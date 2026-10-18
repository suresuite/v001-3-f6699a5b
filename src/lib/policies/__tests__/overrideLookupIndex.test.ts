/**
 * The grid's per-cell lookups are INDEXED (PLAN.md §4 — /policies render cost):
 * `effectivePolicy`, `savedOverrideValue` and `entityOverride` answer from an
 * index built once per override list, and `groupHasPrimary` from a set built
 * once per render. An index is a second way to ask the same question, so each is
 * held here to the plain scan it replaced.
 */
import { describe, expect, it } from "vitest";
import { effectivePolicy, overridesForTarget, type OverrideRow } from "../resolve";
import { entityOverride, type MasterOverrideRule } from "../masterOverrides";
import { groupHasPrimary, lineNeedsInput, primaryGroupKeys, stageNeedsCount } from "../stageGuards";
import type { PolicyBundle } from "../schemas";

const ov = (target_key: string, family: string, patch: Record<string, unknown>, scope = "node"): OverrideRow =>
  ({ scope, target_key, family, patch }) as unknown as OverrideRow;

/** The pre-index `effectivePolicy`, verbatim. */
function scanEffective(defaults: PolicyBundle, overrides: OverrideRow[], scope: "node" | "edge", key: string) {
  const out: Record<string, unknown> = { ...defaults };
  for (const o of overrides) {
    if (o.scope !== scope || o.target_key !== key) continue;
    out[o.family] = { ...(defaults as unknown as Record<string, object>)[o.family], ...o.patch };
  }
  return out;
}

describe("overridesForTarget / effectivePolicy", () => {
  const defaults = { demand: { row_demand_mean: 1, a: 1 }, supplier: { type: "rop" } } as unknown as PolicyBundle;
  const list: OverrideRow[] = [
    ov("C1::P1", "demand", { row_demand_mean: 5 }),
    ov("S1", "supplier", { type: "min_max" }),
    ov("C1::P1", "demand", { a: 9 }),
    ov("C1::P1", "demand", { row_demand_mean: 7 }, "edge"),
    ov("C2::P1", "demand", { row_demand_mean: 2 }),
  ];

  it("matches the scan for every key, scope and merge order", () => {
    for (const key of ["C1::P1", "S1", "C2::P1", "absent"]) {
      for (const scope of ["node", "edge"] as const) {
        expect(effectivePolicy(defaults, list, scope, key)).toEqual(scanEffective(defaults, list, scope, key));
      }
    }
  });

  it("keeps list order within a key", () => {
    expect(overridesForTarget(list, "C1::P1").map((o) => o.scope)).toEqual(["node", "node", "edge"]);
    expect(overridesForTarget(list, "absent")).toEqual([]);
  });

  it("is rebuilt for a new list and for a list grown in place", () => {
    const a = [ov("X", "demand", { a: 1 })];
    expect(overridesForTarget(a, "X")).toHaveLength(1);
    a.push(ov("X", "demand", { a: 2 }));
    expect(overridesForTarget(a, "X")).toHaveLength(2);
    expect(overridesForTarget([...a, ov("X", "demand", { a: 3 })], "X")).toHaveLength(3);
  });
});

describe("entityOverride (cached sort)", () => {
  const rule = { key: "row_demand_mean", family: "demand", domain: "nonnegative", entity: "row" } as unknown as MasterOverrideRule;
  const list = [
    ov("C2::P1", "demand", { row_demand_mean: 3 }),
    ov("C1::P1", "demand", { row_demand_mean: 4 }),
    ov("C1::P1", "demand", { row_demand_mean: 6 }),
  ];

  it("answers a row entity from its own key, first in sorted order", () => {
    expect(entityOverride(list, rule, "C1::P1")?.value).toBe(4);
    expect(entityOverride(list, rule, "C2::P1")?.value).toBe(3);
    expect(entityOverride(list, rule, "C9::P1")).toBeUndefined();
  });

  it("sees a row appended to the same array", () => {
    const l = [...list];
    expect(entityOverride(l, rule, "C3::P1")).toBeUndefined();
    l.push(ov("C3::P1", "demand", { row_demand_mean: 8 }));
    expect(entityOverride(l, rule, "C3::P1")?.value).toBe(8);
  });
});

describe("primaryGroupKeys", () => {
  const rows = [
    { key: "1", customer_id: "C1", product_id: "P1", __lane_count: 2, primary_source: true },
    { key: "2", customer_id: "C1", product_id: "P1", __lane_count: 2, primary_source: false },
    { key: "3", customer_id: "C1", product_id: "P2", __lane_count: 2, primary_source: false },
    { key: "4", customer_id: "C1", product_id: "P2", __lane_count: 2, primary_source: false },
    { key: "5", customer_id: "C2", product_id: "P3", __lane_count: 1, __firms_available: ["F"] },
    { key: "6", product_id: "P4", __lane_count: 3 },
  ] as Record<string, unknown>[];
  const resolve = (r: Record<string, unknown>, f: string) => r[f];

  it("agrees with the scan for every row, with and without the set", () => {
    const primaries = primaryGroupKeys("customer", rows, resolve);
    for (const r of rows) {
      expect(groupHasPrimary("customer", r, rows, resolve, primaries)).toBe(groupHasPrimary("customer", r, rows, resolve));
      expect(lineNeedsInput("customer", r, rows, resolve, primaries)).toBe(lineNeedsInput("customer", r, rows, resolve));
    }
    expect([...primaries]).toEqual(["cp::C1::P1"]);
  });

  it("counts the same lines as the per-row scan", () => {
    const scan = rows.filter((r) => lineNeedsInput("customer", r, rows, resolve)).length;
    expect(stageNeedsCount("customer", rows, resolve)).toBe(scan);
  });

  it("has no groups on a stage that has no primary", () => {
    expect(primaryGroupKeys("plant", rows, resolve).size).toBe(0);
  });
});
