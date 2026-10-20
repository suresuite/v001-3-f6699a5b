/**
 * The inventory explorer's tables (G17 / §9.5.1) — over a REAL inspection run
 * (`fixtures/inventoryInspectionRun.json`, from the committed engine wheels) and
 * over small hand-built rows where a rule needs isolating.
 */
import { describe, expect, it } from "vitest";
import RUN from "./fixtures/inventoryInspectionRun.json";
import {
  flatBom,
  hasFgStock,
  materialTable,
  materialUse,
  productTable,
  snapshotInputs,
  suppliersByMaterial,
  usersByMaterial,
  type ItemSeriesRow,
} from "../inventoryExplorer";

const rows = RUN.item_series as unknown as ItemSeriesRow[];
const W0 = RUN.warmup_detected_at as number;
const inputs = snapshotInputs(RUN.snapshot);
const bom = flatBom(inputs.bom ?? [], inputs.bom_multi_level ?? []);
const use = materialUse(rows, bom);
const ctx = { suppliers: suppliersByMaterial(inputs.inbound ?? []), users: usersByMaterial(bom) };

const mat = (id: string, on_hand: number[], extra: Record<string, number[]> = {}): ItemSeriesRow => ({
  kind: "material", item_id: id, series: { on_hand, in_transit: on_hand.map(() => 0), orders: on_hand.map(() => 0), ...extra },
});
const prod = (id: string, series: Record<string, number[]>): ItemSeriesRow => ({ kind: "product", item_id: id, series });

describe("the BOM is the engine's", () => {
  it("multi-level rows win over single-level ones when there are any", () => {
    const single = [{ product_id: "P", material_id: "X", consumption_rate: 9 }];
    const multi = [{ material_id: "M", higher_level_component_id: "P", consumption_rate: 2 }];
    expect(flatBom(single, multi)).toEqual([{ product_id: "P", material_id: "M", rate: 2 }]);
    expect(flatBom(single, [])).toEqual([{ product_id: "P", material_id: "X", rate: 9 }]);
  });

  it("walks through a sub-assembly, multiplying rates (P_F = 2 SA, SA = 1 M2 + 0.5 M3)", () => {
    const pf = bom.filter((b) => b.product_id === "P_F").sort((a, b) => a.material_id.localeCompare(b.material_id));
    expect(pf).toEqual([
      { product_id: "P_F", material_id: "M2", rate: 2 },
      { product_id: "P_F", material_id: "M3", rate: 1 },
    ]);
    expect(bom.some((b) => b.material_id === "SA")).toBe(false);
  });
});

describe("use — the named derived rule", () => {
  it("is production × flattened rate, summed over products", () => {
    const q = (id: string) => rows.find((r) => r.kind === "product" && r.item_id === id)!.series.production;
    const m3 = use.get("M3")!;
    for (const t of [0, 10, 30]) expect(m3[t]).toBeCloseTo(q("P_F")[t] * 1 + q("P_O")[t] * 1, 6);
    expect(use.get("M1")![30]).toBeCloseTo(q("P_S")[30], 6);
  });
});

describe("materials table", () => {
  const table = materialTable(rows, use, W0, ctx);

  it("has one row per material, with suppliers and users from the run's snapshot", () => {
    expect(table.map((r) => r.id).sort()).toEqual(["M1", "M2", "M3"]);
    const m3 = table.find((r) => r.id === "M3")!;
    expect(m3.suppliers).toEqual(["S1", "S2"]);
    expect(m3.users).toEqual(["P_F", "P_O"]);
  });

  it("ranks the material that ran out first (the outage starved M1)", () => {
    expect(table[0].id).toBe("M1");
    expect(table[0].weeksAtZero).toBeGreaterThan(0);
    expect(table[0].firstStockout).toBeGreaterThanOrEqual(W0);
  });

  it("leaves warm-up weeks out", () => {
    const r = materialTable([mat("A", [0, 0, 5, 7])], new Map([["A", [1, 1, 2, 2]]]), 2, ctx)[0];
    expect(r).toMatchObject({ weeksAtZero: 0, firstStockout: null, minOnHand: 5, avgOnHand: 6, avgUsePerWeek: 2 });
    const all = materialTable([mat("A", [0, 0, 5, 7])], new Map([["A", [1, 1, 2, 2]]]), 0, ctx)[0];
    expect(all).toMatchObject({ weeksAtZero: 2, firstStockout: 0 });
  });

  it("first stockout is a run week, and cover is min ÷ average use (null when unused)", () => {
    const r = materialTable([mat("A", [9, 9, 4, 0, 3])], new Map([["A", [0, 0, 2, 2, 2]]]), 2, ctx)[0];
    expect(r.firstStockout).toBe(3);
    expect(r.minCoverWeeks).toBeCloseTo(0 / 2);
    const unused = materialTable([mat("B", [5, 5])], new Map(), 0, ctx)[0];
    expect(unused.minCoverWeeks).toBeNull();
  });

  it("sorts by weeks at zero, then by the thinnest cover", () => {
    const u = new Map([["A", [1, 1]], ["B", [1, 1]], ["C", [1, 1]]]);
    const t = materialTable([mat("A", [5, 5]), mat("B", [2, 2]), mat("C", [0, 3])], u, 0, ctx);
    expect(t.map((r) => r.id)).toEqual(["C", "B", "A"]);
    // Two materials that both ran out have the same (zero) cover: the one out
    // for more weeks ranks first, whatever its id.
    const z = materialTable([mat("A", [0, 3]), mat("Z", [0, 0])], new Map([["A", [1, 1]], ["Z", [1, 1]]]), 0, ctx);
    expect(z.map((r) => r.id)).toEqual(["Z", "A"]);
  });
});

describe("products table", () => {
  const table = productTable(rows, W0);
  const row = (id: string) => table.find((r) => r.id === id)!;

  it("reads the mode the engine resolved", () => {
    expect(row("P_S").mode).toBe("mts");
    expect(row("P_F").mode).toBe("mts");
    expect(row("P_O").mode).toBe("mto");
  });

  it("a make-to-order product's stock columns are null — not stocked, never 0", () => {
    const o = row("P_O");
    for (const k of ["avgFgOnHand", "minFgOnHand", "avgFgTarget", "weeksAtZero", "firstStockout", "weeksOfCover"] as const) {
      expect(o[k], k).toBeNull();
    }
    expect(o.fillRate).not.toBeNull();
  });

  it("a base-stock product's average target is its S, and the outage shows as FG stockouts", () => {
    expect(row("P_S").avgFgTarget).toBeCloseTo(400, 6);
    expect(row("P_S").weeksAtZero).toBeGreaterThan(0);
  });

  it("fill rate is Σ fulfillment ÷ Σ demand after warm-up", () => {
    const r = productTable([prod("X", { demand: [100, 10, 10], fulfillment: [0, 5, 10], backlog: [0, 0, 0], lost_units: [0, 5, 0] })], 1)[0];
    expect(r.fillRate).toBeCloseTo(15 / 20);
    expect(r.lostUnits).toBe(5);
  });

  it("counts a week at zero only while demand is positive", () => {
    const r = productTable([prod("X", {
      demand: [0, 5, 5], fulfillment: [0, 5, 5], backlog: [0, 0, 0], lost_units: [0, 0, 0],
      fg_on_hand: [0, 0, 4], fg_target: [4, 4, 4], make_to_stock: [1, 1, 1],
    })], 0)[0];
    expect(r.weeksAtZero).toBe(1);
    expect(r.firstStockout).toBe(1);
    expect(r.weeksOfCover).toBeCloseTo((4 / 3) / (10 / 3));
  });

  it("ranks shortfall first (lost + average backlog), then weeks at zero, then fill rate", () => {
    const base = { demand: [10, 10], fulfillment: [10, 10], backlog: [0, 0], lost_units: [0, 0], make_to_stock: [1, 1], fg_target: [5, 5] };
    const t = productTable([
      prod("calm", { ...base, fg_on_hand: [5, 5] }),
      prod("empty", { ...base, fg_on_hand: [0, 0] }),
      prod("short", { ...base, fulfillment: [5, 5], lost_units: [5, 5], fg_on_hand: [5, 5] }),
    ], 0);
    expect(t.map((r) => r.id)).toEqual(["short", "empty", "calm"]);
    expect(table[0].id).toBe("P_F"); // the run's largest loser
  });

  it("a run without per-product FG stock is recognised, and reads null rather than 0", () => {
    expect(hasFgStock(rows)).toBe(true);
    const old = rows.map((r) => {
      if (r.kind !== "product") return r;
      const { fg_on_hand, fg_target, make_to_stock, ...rest } = r.series;
      void fg_on_hand; void fg_target; void make_to_stock;
      return { ...r, series: rest };
    });
    expect(hasFgStock(old)).toBe(false);
    const p = productTable(old, W0).find((r) => r.id === "P_S")!;
    expect(p.mode).toBeNull();
    expect(p.avgFgOnHand).toBeNull();
  });
});
