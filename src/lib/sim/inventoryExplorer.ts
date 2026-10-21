// Inventory explorer — the two ranked tables of an inspection run (blueprint
// G17 / §9.5.1; the in-app form of notebook 04's step 5).
//
// Everything here is computed FROM the engine's per-item weekly series
// (`run_item_series`) and the run's frozen dataset snapshot. Nothing here
// re-derives what the engine already measured:
//
//   · finished-goods stock and its target are the engine's own
//     `product.fg_on_hand` / `product.fg_target` — not rebuilt from
//     production minus fulfillment, which would be wrong twice (fulfillment
//     includes backlog served, and completions lag starts under a production
//     lead time);
//   · a product's fulfillment mode is `product.make_to_stock`, the mode the
//     engine RESOLVED (row → master → project → MTO) — not re-resolved here;
//   · the BOM is the engine's: multi-level rows win when the snapshot has any
//     (`sim_worker/local.py`), flattened by `normalizeBomRows`, the browser port
//     of `_flatten_multi_level_bom`.
//
// ONE rule here is derived rather than measured, and it is NAMED wherever it is
// shown: a material's USE is each product's production (units started) times
// its flattened BOM rate. The engine consumes materials at production start, so
// this is the consumption it booked — but it is computed in the browser.

import { normalizeBomRows } from "../../../supabase/functions/_shared/grading";
import type { KnownLimit } from "@/lib/trust/trustReport";

export type ItemKind = "material" | "product";

/** One `run_item_series` row. */
export interface ItemSeriesRow {
  kind: ItemKind;
  item_id: string;
  series: Record<string, number[]>;
}

/** A flattened product → leaf-material rate. */
export interface FlatBomRow {
  product_id: string;
  material_id: string;
  rate: number;
}

type Row = Record<string, unknown>;

/** A stock at or below this is zero (the notebook's tolerance). */
export const STOCK_EPS = 1e-6;

/** The named derived rule, verbatim, for every place that shows "use". */
export const USE_RULE =
  "Use is derived, not measured by the engine: each product's production (units started) " +
  "times its flattened bill of materials.";

/** The dataset snapshot's tables, from either shape (v1 top level, v2 `inputs`). */
export function snapshotInputs(snapshot: unknown): Record<string, Row[] | undefined> {
  const s = (snapshot ?? {}) as { inputs?: Record<string, Row[]> } & Record<string, Row[]>;
  return (s.inputs ?? s) as Record<string, Row[] | undefined>;
}

/** The BOM the engine read: multi-level rows when there are any, else the
 *  single-level rows — flattened through sub-assemblies to leaf materials. */
export function flatBom(single: Row[], multi: Row[]): FlatBomRow[] {
  const out: FlatBomRow[] = [];
  for (const r of normalizeBomRows(multi.length > 0 ? multi : single)) {
    if (r.product_id == null || r.material_id == null) continue;
    const rate = Number(r.consumption_rate);
    out.push({
      product_id: String(r.product_id),
      material_id: String(r.material_id),
      rate: Number.isFinite(rate) && rate !== 0 ? rate : 1,
    });
  }
  return out;
}

/** Each material's weekly use — the named derived rule (`USE_RULE`). */
export function materialUse(rows: ItemSeriesRow[], bom: FlatBomRow[]): Map<string, number[]> {
  const production = new Map<string, number[]>();
  let weeks = 0;
  for (const r of rows) {
    if (r.kind === "product" && Array.isArray(r.series.production)) {
      production.set(r.item_id, r.series.production);
    }
    if (r.kind === "material") weeks = Math.max(weeks, (r.series.on_hand ?? []).length);
  }
  const use = new Map<string, number[]>();
  for (const r of rows) if (r.kind === "material") use.set(r.item_id, new Array(weeks).fill(0));
  for (const { product_id, material_id, rate } of bom) {
    const q = production.get(product_id);
    const u = use.get(material_id);
    if (!q || !u) continue;
    for (let t = 0; t < u.length; t++) u[t] += (q[t] ?? 0) * rate;
  }
  return use;
}

/** material → its suppliers, from the snapshot's inbound lanes. */
export function suppliersByMaterial(inbound: Row[]): Map<string, string[]> {
  const m = new Map<string, Set<string>>();
  for (const r of inbound) {
    if (r.material_id == null || r.supplier_id == null) continue;
    const k = String(r.material_id);
    if (!m.has(k)) m.set(k, new Set());
    m.get(k)!.add(String(r.supplier_id));
  }
  return new Map([...m].map(([k, v]) => [k, [...v].sort()]));
}

/** material → the products that use it (directly or through a sub-assembly). */
export function usersByMaterial(bom: FlatBomRow[]): Map<string, string[]> {
  const m = new Map<string, Set<string>>();
  for (const { product_id, material_id } of bom) {
    if (!m.has(material_id)) m.set(material_id, new Set());
    m.get(material_id)!.add(product_id);
  }
  return new Map([...m].map(([k, v]) => [k, [...v].sort()]));
}

/** Whether the run carries per-product finished-goods stock at all. A run
 *  recorded before the engine wrote `product.fg_on_hand` has product rows
 *  without it — the panel says so rather than showing zeros. */
export function hasFgStock(rows: ItemSeriesRow[]): boolean {
  return rows.some((r) => r.kind === "product" && Array.isArray(r.series.fg_on_hand));
}

const post = (a: number[] | undefined, w0: number): number[] => (a ?? []).slice(Math.max(0, w0));
const sum = (a: number[]) => a.reduce((s, v) => s + v, 0);
const mean = (a: number[]) => (a.length ? sum(a) / a.length : 0);
const min = (a: number[]) => (a.length ? Math.min(...a) : 0);

export interface MaterialRow {
  id: string;
  name: string | null;
  suppliers: string[];
  users: string[];
  avgOnHand: number;
  minOnHand: number;
  weeksAtZero: number;
  /** The first week (run week, not offset) on hand was zero, after warm-up. */
  firstStockout: number | null;
  avgInTransit: number;
  avgUsePerWeek: number;
  /** Min on hand ÷ average use; null when the material is not used. */
  minCoverWeeks: number | null;
  ordered: number;
}

/** Every material, riskiest first: most weeks at zero, then the thinnest
 *  cover — notebook 04's order. Weeks before `w0` (warm-up) are left out. */
export function materialTable(
  rows: ItemSeriesRow[],
  use: Map<string, number[]>,
  w0: number,
  ctx: { suppliers: Map<string, string[]>; users: Map<string, string[]>; names?: Map<string, string> },
): MaterialRow[] {
  const out: MaterialRow[] = [];
  for (const r of rows) {
    if (r.kind !== "material") continue;
    const oh = post(r.series.on_hand, w0);
    const u = post(use.get(r.item_id), w0);
    const zeroAt = oh.findIndex((v) => v <= STOCK_EPS);
    const avgUse = mean(u);
    out.push({
      id: r.item_id,
      name: ctx.names?.get(r.item_id) ?? null,
      suppliers: ctx.suppliers.get(r.item_id) ?? [],
      users: ctx.users.get(r.item_id) ?? [],
      avgOnHand: mean(oh),
      minOnHand: min(oh),
      weeksAtZero: oh.filter((v) => v <= STOCK_EPS).length,
      firstStockout: zeroAt < 0 ? null : zeroAt + Math.max(0, w0),
      avgInTransit: mean(post(r.series.in_transit, w0)),
      avgUsePerWeek: avgUse,
      minCoverWeeks: avgUse > 0 ? min(oh) / avgUse : null,
      ordered: sum(post(r.series.orders, w0)),
    });
  }
  return out.sort(
    (a, b) =>
      b.weeksAtZero - a.weeksAtZero ||
      (a.minCoverWeeks ?? Infinity) - (b.minCoverWeeks ?? Infinity) ||
      a.id.localeCompare(b.id),
  );
}

export type FulfillmentMode = "mts" | "mto";

export interface ProductRow {
  id: string;
  name: string | null;
  /** The mode the engine resolved; null when the run predates the record. */
  mode: FulfillmentMode | null;
  // Stock columns are null for a make-to-order product (it holds no FG stock
  // BY DESIGN — "not stocked", never 0) and for a run that predates them.
  avgFgOnHand: number | null;
  minFgOnHand: number | null;
  avgFgTarget: number | null;
  /** Weeks with no FG stock while demand was positive. */
  weeksAtZero: number | null;
  firstStockout: number | null;
  weeksOfCover: number | null;
  /** Σ fulfillment ÷ Σ demand (fulfillment includes backlog served). */
  fillRate: number | null;
  avgBacklog: number;
  lostUnits: number;
}

/** Every finished good, riskiest first: the largest shortfall (lost units +
 *  average backlog) — comparable for MTS and MTO alike — then the most weeks
 *  out of stock while demand was positive, then the lowest fill rate. */
export function productTable(
  rows: ItemSeriesRow[],
  w0: number,
  ctx: { names?: Map<string, string> } = {},
): ProductRow[] {
  const out: ProductRow[] = [];
  for (const r of rows) {
    if (r.kind !== "product") continue;
    const s = r.series;
    const mts = Array.isArray(s.make_to_stock) ? (s.make_to_stock[0] ?? 0) >= 0.5 : null;
    const stocked = mts === true && Array.isArray(s.fg_on_hand);
    const d = post(s.demand, w0);
    const f = post(s.fulfillment, w0);
    const fg = stocked ? post(s.fg_on_hand, w0) : [];
    let weeksAtZero: number | null = null;
    let firstStockout: number | null = null;
    if (stocked) {
      weeksAtZero = 0;
      fg.forEach((v, i) => {
        if (v <= STOCK_EPS && (d[i] ?? 0) > 0) {
          weeksAtZero! += 1;
          if (firstStockout === null) firstStockout = i + Math.max(0, w0);
        }
      });
    }
    const avgDemand = mean(d);
    const totalDemand = sum(d);
    out.push({
      id: r.item_id,
      name: ctx.names?.get(r.item_id) ?? null,
      mode: mts === null ? null : mts ? "mts" : "mto",
      avgFgOnHand: stocked ? mean(fg) : null,
      minFgOnHand: stocked ? min(fg) : null,
      avgFgTarget: stocked && Array.isArray(s.fg_target) ? mean(post(s.fg_target, w0)) : null,
      weeksAtZero,
      firstStockout,
      weeksOfCover: stocked && avgDemand > 0 ? mean(fg) / avgDemand : null,
      fillRate: totalDemand > 0 ? sum(f) / totalDemand : null,
      avgBacklog: mean(post(s.backlog, w0)),
      lostUnits: sum(post(s.lost_units, w0)),
    });
  }
  return out.sort(
    (a, b) =>
      b.lostUnits + b.avgBacklog - (a.lostUnits + a.avgBacklog) ||
      (b.weeksAtZero ?? 0) - (a.weeksAtZero ?? 0) ||
      (a.fillRate ?? 1) - (b.fillRate ?? 1) ||
      a.id.localeCompare(b.id),
  );
}

/** What the explorer reads besides the item series: the run's frozen dataset
 *  snapshot, or — for a dataset version frozen before the deep BOM was in it —
 *  the project's live BOM and lanes, and the items' display names. */
export interface ExplorerInputs {
  snapshot: unknown;
  source: "snapshot" | "live" | "none";
  names: Map<string, string>;
  liveBom?: Row[];
  liveInbound?: Row[];
}

/** The tables and their inputs, from the run's rows and its frozen inputs. */
export function deriveInventory(rows: ItemSeriesRow[], ctx: ExplorerInputs | null, w0: number) {
  const inputs = snapshotInputs(ctx?.snapshot);
  const live = ctx?.source === "live";
  const liveBom = ctx?.liveBom ?? [];
  const bom = live
    ? flatBom(liveBom.filter((b) => b.product_id != null), liveBom.filter((b) => b.product_id == null))
    : flatBom(inputs.bom ?? [], inputs.bom_multi_level ?? []);
  const use = materialUse(rows, bom);
  const suppliers = suppliersByMaterial(live ? ctx?.liveInbound ?? [] : inputs.inbound ?? []);
  const users = usersByMaterial(bom);
  const names = ctx?.names ?? new Map<string, string>();
  return {
    use,
    suppliers,
    users,
    names,
    materials: materialTable(rows, use, w0, { suppliers, users, names }),
    products: productTable(rows, w0, { names }),
    fgRecorded: hasFgStock(rows),
  };
}

export type DerivedInventory = ReturnType<typeof deriveInventory>;

/** What a make-to-order product's stock cells say instead of a number. */
export const NOT_STOCKED = "not stocked (make-to-order)";

/** The limits of these tables, stated wherever they are shown (T2/T3) and
 *  appended to the workbook's record. */
export const EXPLORER_LIMITS: KnownLimit[] = [
  {
    ref: "T3",
    limit: "One seed: an inspection run is one replication.",
    consequence:
      "These weeks are one possible world. The run's KPIs average every replication of a " +
      "multi-replication run; these do not, and a spike here may be the seed rather than the chain.",
  },
  {
    ref: "T3",
    limit: "A sub-assembly has no stock line of its own.",
    consequence:
      "The engine holds stock per leaf material and per finished good; an intermediate " +
      "component is flattened into the materials beneath it, so it has no row here.",
  },
  {
    ref: "T2",
    limit: USE_RULE,
    consequence:
      "\"Use\" and \"min cover\" rest on it; every other column is the engine's own weekly record.",
  },
];
