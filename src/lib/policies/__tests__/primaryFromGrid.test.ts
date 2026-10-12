/**
 * The pre-run check answers "is there a primary supplier?" the way the grid does.
 *
 * Found on a live project: a material with ONE supplier (M0241 ← S012) showed
 * "Primary ✓" on /policies and counted as resolved on the step track, yet Run
 * checks blocked it with "has no primary supplier — select one". The verifier
 * read the saved override bundle alone, and the stage's single-source decision
 * only reaches that bundle through the auto-seed — which fires once per stage,
 * when the stage has no overrides yet. A lane uploaded after that first seed
 * never got one. The verifier now reads `primary_source` through the grid's own
 * resolver, so the two cannot disagree.
 */
import { describe, expect, it } from "vitest";
import { verifyProjectPolicies } from "../verification";
import { DEFAULT_BUNDLE } from "../schemas";
import type { OverrideRow } from "../resolve";
import type { StageRow } from "@/hooks/useStageRows";

/** A supplier-stage row as `useStageRows` builds it. */
const lane = (supplier: string, material: string, count: number, suggested: boolean): StageRow =>
  ({
    key: `${supplier}::${material}`,
    supplier_id: supplier,
    material_id: material,
    primary_source: count === 1 ? true : suggested,
    __lane_count: count,
    __supplier_count: count,
    __from_data: {},
    __imputed: {},
    __decided: { primary_source: true },
  }) as unknown as StageRow;

const run = (supplierRows: StageRow[], overrides: OverrideRow[] = []) => {
  const res = verifyProjectPolicies({
    defaults: DEFAULT_BUNDLE,
    overrides,
    fulfillmentStrategy: "make_to_stock",
    supplierRows,
    plantRows: [],
    customerRows: [],
    dataReady: true,
  });
  if (res.status !== "ready") throw new Error("expected ready");
  return res.findings.filter((f) => f.stage === "supplier").map((f) => f.id);
};

describe("primary supplier — verifier agrees with the grid", () => {
  it("a single-source material with NO saved override is its own primary", () => {
    // Another row in the stage was seeded earlier; this one arrived later.
    const seeded: OverrideRow = {
      scope: "node", target_key: "S001::M0001", family: "sourcing", patch: { primary_source: true },
    };
    const ids = run([lane("S001", "M0001", 1, true), lane("S012", "M0241", 1, true)], [seeded]);
    expect(ids).not.toContain("s-noprim-M0241");
  });

  it("a user who explicitly un-checks the only supplier is still blocked", () => {
    const unchecked: OverrideRow = {
      scope: "node", target_key: "S012::M0241", family: "sourcing", patch: { primary_source: false },
    };
    expect(run([lane("S012", "M0241", 1, true)], [unchecked])).toContain("s-noprim-M0241");
  });

  it("multi-source: the suggested supplier counts, so exactly one primary", () => {
    const ids = run([lane("S001", "M0002", 2, true), lane("S002", "M0002", 2, false)]);
    expect(ids).not.toContain("s-noprim-M0002");
    expect(ids).not.toContain("s-prim-M0002");
  });

  it("a saved second primary still reads as two", () => {
    const both: OverrideRow = {
      scope: "node", target_key: "S002::M0002", family: "sourcing", patch: { primary_source: true },
    };
    expect(run([lane("S001", "M0002", 2, true), lane("S002", "M0002", 2, false)], [both])).toContain(
      "s-prim-M0002",
    );
  });
});

describe("a sub-assembly made in-house needs no primary supplier (D308)", () => {
  /** The "(made in-house)" line `useStageRows` builds for a BOM intermediate (D175). */
  const inHouse = (material: string): StageRow =>
    ({
      key: `(made in-house)::${material}`,
      supplier_id: "(made in-house)",
      material_id: material,
      __in_house: true,
      __supplier_count: 0,
      __lane_count: 0,
    }) as unknown as StageRow;

  it("an intermediate is not asked for a primary supplier", () => {
    // AA-ver3's shape: 65 of these each blocked the run with
    // "has no primary supplier — select one", which the grid offers no way to do.
    const ids = run([inHouse("E1.061.000.11-SA"), lane("S001", "M0001", 1, true)]);
    expect(ids).not.toContain("s-noprim-E1.061.000.11-SA");
    expect(ids).toEqual([]);
  });

  it("its leaves are still graded — an unsourced leaf still blocks", () => {
    const unassigned = {
      key: "(unassigned supplier)::E2.010.000.00",
      supplier_id: "(unassigned supplier)",
      material_id: "E2.010.000.00",
      __needs_supplier: true,
    } as unknown as StageRow;
    expect(run([inHouse("E1.061.000.11-SA"), unassigned])).toEqual(["s-nosup-E2.010.000.00"]);
  });
});
