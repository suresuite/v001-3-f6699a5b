// The Policies root's "search the network, not the catalog" index (v3 §3.1,
// gap-close T6). One computed list of business objects + policy fields, each
// carrying a REAL policy count — never invented (§6: "do not invent
// counts"). Built entirely from data already loaded at the ProjectPolicies
// page level; no new fetch.
//
// What the data model does and doesn't give us (read pass before building
// this): materials/products/suppliers have real names (useItemMasters);
// customers and the plant do not — there is no `customers` table and no
// `plants` table, so a customer's "name" is its uploaded id, and the plant
// is one object per project (`ctx.plant_name`). A "lane" is not its own
// entity either — it's a supplier×material row (inbound) or a
// customer×product row (outbound), so lanes are derived from the same
// stage rows the grid already renders, not a fourth business-object table.
import { useMemo } from "react";
import type { StageRow } from "@/hooks/useStageRows";
import type { StageRowsQuery } from "@/hooks/useStageGuards";
import { specFor } from "@/lib/policies/columnSpecs";
import { stageForFamily, type StageKey } from "@/lib/policies/stages";
import type { OverrideRow } from "@/lib/policies/resolve";
import type { PolicyFamily } from "@/lib/policies/schemas";

export type SearchObjectType =
  | "supplier"
  | "material"
  | "product"
  | "customer"
  | "plant"
  | "lane"
  | "policy";

export interface SearchResult {
  type: SearchObjectType;
  /** Stable id — the target_key for a lane, the item id otherwise. */
  id: string;
  name: string;
  /** Second line: a lane's "supplier → material" shape, a policy's family. */
  sub?: string;
  /** Real override + default-resolved count for a business object; absent
   *  for a "policy" result, which has no count of its own. */
  policyCount?: number;
  /** Set only for a "policy" result matched on a parameter, not its name. */
  matchedField?: string;
  /** Where tapping this result should go. */
  targetStage?: StageKey;
}

interface NamedRow {
  id: string;
  name: string;
}

interface Args {
  rowsByStage: Record<Exclude<StageKey, "run_validate">, StageRowsQuery>;
  overrides: OverrideRow[];
  materials: NamedRow[];
  products: NamedRow[];
  suppliers: NamedRow[];
  plantName: string | null | undefined;
  /** Build the index only while a query is typed. The inputs are fresh arrays
   *  on every page render, so an always-on index was rebuilt on every edit. */
  enabled?: boolean;
}

const str = (row: StageRow, field: string) => String(row[field] ?? "");

/** Overrides per target_key, counted once. A set of keys is then a sum over its
 *  members — the same number `overrides.filter(o => keys.has(o.target_key))`
 *  gave, without a pass over every override for every material and product. */
function overrideCounts(overrides: OverrideRow[]): Map<string, number> {
  const out = new Map<string, number>();
  for (const o of overrides) out.set(o.target_key, (out.get(o.target_key) ?? 0) + 1);
  return out;
}

/** Real override count for a set of target_keys — the same target_key
 *  format `columnSpecs.ts`'s own `targetKey` functions produce, so this
 *  can never disagree with what the grid resolves. */
function countOverrides(counts: Map<string, number>, keys: Iterable<string>): number {
  let n = 0;
  for (const k of keys) n += counts.get(k) ?? 0;
  return n;
}

/** id → first matching row, as `Array.find` returned it. */
function firstById<T extends { id: string }>(rows: T[]): Map<string, T> {
  const out = new Map<string, T>();
  for (const r of rows) if (!out.has(r.id)) out.set(r.id, r);
  return out;
}

/** Group rows' `key` by one of their string fields. */
function keysBy(rows: StageRow[], field: string, into = new Map<string, Set<string>>()): Map<string, Set<string>> {
  for (const r of rows) {
    const id = str(r, field);
    let set = into.get(id);
    if (!set) into.set(id, (set = new Set()));
    set.add(r.key);
  }
  return into;
}

export function usePolicySearchIndex({
  rowsByStage,
  overrides,
  materials,
  products,
  suppliers,
  plantName,
  enabled = true,
}: Args): SearchResult[] {
  return useMemo(() => {
    if (!enabled) return [];
    const supplierRows = rowsByStage.supplier?.rows ?? [];
    const plantRows = rowsByStage.plant?.rows ?? [];
    const customerRows = rowsByStage.customer?.rows ?? [];
    const results: SearchResult[] = [];
    const counts = overrideCounts(overrides);
    const supplierById = firstById(suppliers);
    const materialById = firstById(materials);
    const productById = firstById(products);

    // ── Suppliers (firm) — grouped from the supplier×material rows ───────
    const supplierSpec = specFor("supplier");
    const bySupplier = new Map<string, StageRow[]>();
    for (const row of supplierRows) {
      const id = str(row, "supplier_id");
      if (!id) continue;
      (bySupplier.get(id) ?? bySupplier.set(id, []).get(id)!).push(row);
    }
    for (const [id, rows] of bySupplier) {
      const keys = new Set(rows.map((r) => r.key));
      const materialIds = new Set(rows.map((r) => str(r, "material_id")).filter(Boolean));
      results.push({
        type: "supplier",
        id,
        name: supplierById.get(id)?.name ?? id,
        sub: `${materialIds.size} material${materialIds.size === 1 ? "" : "s"}`,
        policyCount: countOverrides(counts, keys),
        targetStage: "supplier",
      });
    }

    // ── Materials (product) — real names from useItemMasters ─────────────
    const keysByMaterial = keysBy(supplierRows, "material_id");
    for (const material of materials) {
      const keys = keysByMaterial.get(material.id);
      if (!keys || keys.size === 0) continue; // not on any inbound lane this project
      results.push({
        type: "material",
        id: material.id,
        name: material.name,
        policyCount: countOverrides(counts, keys),
        targetStage: "supplier",
      });
    }

    // ── Products (product) — appear on both plant and customer rows ──────
    const keysByProduct = keysBy(customerRows, "product_id", keysBy(plantRows, "product_id"));
    for (const product of products) {
      const keys = keysByProduct.get(product.id);
      if (!keys || keys.size === 0) continue;
      results.push({
        type: "product",
        id: product.id,
        name: product.name,
        policyCount: countOverrides(counts, keys),
        targetStage: "plant",
      });
    }

    // ── Customers (firm) — no name field; the uploaded id is the name ────
    const byCustomer = new Map<string, StageRow[]>();
    for (const row of customerRows) {
      const id = str(row, "customer_id");
      if (!id) continue;
      (byCustomer.get(id) ?? byCustomer.set(id, []).get(id)!).push(row);
    }
    for (const [id, rows] of byCustomer) {
      const keys = new Set(rows.map((r) => r.key));
      results.push({
        type: "customer",
        id,
        name: id,
        policyCount: countOverrides(counts, keys),
        targetStage: "customer",
      });
    }

    // ── Plant (firm) — singular per project ───────────────────────────────
    if (plantName) {
      const keys = new Set(plantRows.map((r) => r.key));
      results.push({
        type: "plant",
        id: plantName,
        name: plantName,
        sub: "focal plant",
        policyCount: countOverrides(counts, keys),
        targetStage: "plant",
      });
    }

    // ── Lanes (process) — one row IS one lane, inbound and outbound ──────
    for (const row of supplierRows) {
      const supplierId = str(row, "supplier_id");
      const materialId = str(row, "material_id");
      if (!supplierId || !materialId) continue;
      const supplierName = supplierById.get(supplierId)?.name ?? supplierId;
      const materialName = materialById.get(materialId)?.name ?? materialId;
      results.push({
        type: "lane",
        id: row.key,
        name: `${supplierName} → ${materialName}`,
        sub: "inbound",
        policyCount: countOverrides(counts, [row.key]),
        targetStage: "supplier",
      });
    }
    for (const row of customerRows) {
      const customerId = str(row, "customer_id");
      const productId = str(row, "product_id");
      if (!customerId || !productId) continue;
      const productName = productById.get(productId)?.name ?? productId;
      results.push({
        type: "lane",
        id: row.key,
        name: `${productName} → ${customerId}`,
        sub: "outbound",
        policyCount: countOverrides(counts, [row.key]),
        targetStage: "customer",
      });
    }

    // ── Policies (no dot) — field labels across the three real stages ────
    const seenFields = new Set<string>();
    for (const stageKey of ["supplier", "plant", "customer"] as const) {
      for (const col of specFor(stageKey).cols) {
        if (col.synthetic || seenFields.has(col.field)) continue;
        seenFields.add(col.field);
        results.push({
          type: "policy",
          id: col.field,
          name: col.label,
          sub: col.family,
          matchedField: col.field,
          targetStage: stageForFamily(col.family as PolicyFamily),
        });
      }
    }

    return results;
  }, [enabled, rowsByStage, overrides, materials, products, suppliers, plantName]);
}
