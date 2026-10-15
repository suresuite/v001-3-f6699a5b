/**
 * The search index counts overrides and resolves names from maps built once.
 * Held here to the scans it replaced: `overrides.filter(o => keys.has(...))` per
 * object and `Array.find` per lane, including `find`'s first-match-wins on a
 * duplicated id.
 */
import { describe, expect, it, vi } from "vitest";

vi.mock("react", async (orig) => ({ ...(await orig<typeof import("react")>()), useMemo: (fn: () => unknown) => fn() }));

import { usePolicySearchIndex } from "../usePolicySearchIndex";
import type { OverrideRow } from "@/lib/policies/resolve";

const ov = (target_key: string): OverrideRow =>
  ({ scope: "node", target_key, family: "sourcing", patch: {} }) as unknown as OverrideRow;
const q = (rows: Record<string, unknown>[]) => ({ rows }) as never;

const supplierRows = [
  { key: "S1::M1", supplier_id: "S1", material_id: "M1" },
  { key: "S2::M1", supplier_id: "S2", material_id: "M1" },
  { key: "S1::M2", supplier_id: "S1", material_id: "M2" },
];
const plantRows = [{ key: "P::F1", product_id: "F1" }];
const customerRows = [
  { key: "C1::F1", customer_id: "C1", product_id: "F1" },
  { key: "C2::F1", customer_id: "C2", product_id: "F1" },
];
const overrides = [ov("S1::M1"), ov("S1::M1"), ov("S2::M1"), ov("C1::F1"), ov("P::F1"), ov("nobody")];
const materials = [{ id: "M1", name: "Bolt" }, { id: "M1", name: "Duplicate" }, { id: "M2", name: "Nut" }, { id: "M9", name: "Orphan" }];
const products = [{ id: "F1", name: "Frame" }, { id: "F2", name: "Unused" }];
const suppliers = [{ id: "S1", name: "Acme" }];

// `useMemo` is stubbed to run inline, so the hook is a plain function here.
const build = usePolicySearchIndex;
const run = () =>
  build({
    rowsByStage: { supplier: q(supplierRows), plant: q(plantRows), customer: q(customerRows) } as never,
    overrides, materials, products, suppliers, plantName: "Plant A",
  });
const by = (type: string, id: string) => run().find((r) => r.type === type && r.id === id);

describe("usePolicySearchIndex", () => {
  it("counts the overrides that target an object's rows", () => {
    expect(by("supplier", "S1")?.policyCount).toBe(2); // S1::M1 ×2, S1::M2 has none
    expect(by("supplier", "S2")?.policyCount).toBe(1);
    expect(by("material", "M1")?.policyCount).toBe(3);
    expect(by("material", "M2")?.policyCount).toBe(0);
    expect(by("product", "F1")?.policyCount).toBe(2); // plant row P::F1 + customer row C1::F1
    expect(by("customer", "C1")?.policyCount).toBe(1);
    expect(by("customer", "C2")?.policyCount).toBe(0);
    expect(by("plant", "Plant A")?.policyCount).toBe(1);
    expect(by("lane", "S1::M1")?.policyCount).toBe(2);
  });

  it("leaves out an object that is on no lane or row", () => {
    expect(by("material", "M9")).toBeUndefined();
    expect(by("product", "F2")).toBeUndefined();
  });

  it("names a lane from the FIRST row with that id, as Array.find did", () => {
    expect(by("lane", "S1::M1")?.name).toBe("Acme → Bolt");
    expect(by("lane", "S2::M1")?.name).toBe("S2 → Bolt"); // no supplier name: falls back to the id
    expect(by("lane", "C1::F1")?.name).toBe("Frame → C1");
  });

  it("builds nothing while disabled", () => {
    expect(
      build({
        rowsByStage: { supplier: q(supplierRows), plant: q([]), customer: q([]) } as never,
        overrides, materials, products, suppliers, plantName: null, enabled: false,
      }),
    ).toEqual([]);
  });
});
