/**
 * THE CARD OFFERS ONLY WHAT THE ENGINE RUNS — §4 D114 · D315.
 *
 * Before engine 0.8.2 the Simulation Lab card offered six strategies and two reached no
 * plugin ("Safety stock", "Material reallocation" as `demand_shaping`), a seventh label
 * ("Network rerouting") ran expediting, and nothing compared the card's list with the
 * engine's. This file is that comparison, against `engineBridge.json` — which
 * `scsim/tests/test_recovery_strategies.py` holds equal to what the mapper does.
 *
 * MUTATIONS THAT MUST MAKE THIS FILE FAIL:
 *   * add "reroute" or "demand_shaping" back to OFFERED_STRATEGIES → the first test.
 *   * offer a strategy the bridge does not map without marking it NOT_SIMULATED → same.
 *   * mark a mapped strategy NOT_SIMULATED → the second test.
 */
import { describe, expect, it } from "vitest";
import bridge from "../../../../supabase/functions/_shared/engineBridge.json";
import { activeEnginePolicies } from "../../../../supabase/functions/_shared/grading";
import {
  NOT_SIMULATED,
  OFFERED_STRATEGIES,
  RESPONSE_LABELS,
  backupLaneProblem,
  backupsForSupplier,
  defaultWindow,
  disruptedSuppliers,
  leadTimeWeeks,
  outageWeeks,
  windowProblem,
  type InboundLane,
} from "../recovery";

const MAPS = (bridge as { recovery_response_to_policy: Record<string, string> }).recovery_response_to_policy;

describe("the recovery card and the engine", () => {
  it("every offered strategy reaches an engine plugin, unless the card says it does not", () => {
    for (const s of OFFERED_STRATEGIES) {
      if (NOT_SIMULATED.has(s)) continue;
      expect(MAPS[s], `the card offers "${s}" and the engine maps it to nothing`).toBeTruthy();
    }
  });

  it("a strategy the card marks not simulated really reaches no plugin", () => {
    for (const s of NOT_SIMULATED) expect(MAPS[s], `"${s}" is mapped — drop the "not simulated" mark`).toBeUndefined();
  });

  it("no two offered strategies run the same plugin under different names", () => {
    const plugins = OFFERED_STRATEGIES.map((s) => MAPS[s]).filter(Boolean);
    expect(new Set(plugins).size).toBe(plugins.length);
  });

  it("the retired tokens and early warning are not offered", () => {
    for (const k of ["reroute", "demand_shaping", "early_warning"]) {
      expect((OFFERED_STRATEGIES as readonly string[]).includes(k)).toBe(false);
    }
    expect(RESPONSE_LABELS.reroute).toMatch(/retired/);
  });
});

const LANES: InboundLane[] = [
  { supplier_id: "S1", material_id: "M1", lead_time: 4, lead_time_unit: "weeks", unit_price: 2 },
  { supplier_id: "S1", material_id: "M2", lead_time: 4, lead_time_unit: "weeks", unit_price: 3 },
  { supplier_id: "S2", material_id: "M1", lead_time: 6, lead_time_unit: "weeks", unit_price: 2.5 },
  { supplier_id: "S3", material_id: "M1", lead_time: 2, lead_time_unit: "weeks", unit_price: 4 },
];

describe("backup suppliers for a disrupted supplier", () => {
  it("reads the disrupted suppliers the way the engine resolves targets", () => {
    const sched = [{ target: "supplier:S1" }, { target: "node:plant" }, { target: "supplier:NOPE" }, { target: "S3" }];
    expect(disruptedSuppliers(sched, ["S1", "S2", "S3"])).toEqual(["S1", "S3"]);
  });

  it("lists, per material, the other suppliers on file — and flags one disrupted too", () => {
    const rows = backupsForSupplier("S1", LANES, [], ["S1", "S3"]);
    expect(rows.map((r) => r.material_id)).toEqual(["M1", "M2"]);
    expect(rows[0].uploaded.map((o) => [o.supplier_id, o.alsoDisrupted])).toEqual([["S2", false], ["S3", true]]);
    expect(rows[1].uploaded).toEqual([]); // M2: no backup on file
  });

  it("carries a backup entered on the scenario under its material", () => {
    const entered = [{ material_id: "M2", supplier_id: "NEW", lead_time_weeks: 3, unit_price: 3.5 }];
    expect(backupsForSupplier("S1", LANES, entered, ["S1"])[1].entered).toEqual(entered);
  });

  it("refuses an entered backup the engine would skip, with the engine's reasons", () => {
    expect(backupLaneProblem({ material_id: "M2", supplier_id: "", lead_time_weeks: 3, unit_price: 1 }, LANES)).toMatch(/Name/);
    expect(backupLaneProblem({ material_id: "M2", supplier_id: "X", lead_time_weeks: 0, unit_price: 1 }, LANES)).toMatch(/1 week/);
    expect(backupLaneProblem({ material_id: "M2", supplier_id: "X", lead_time_weeks: 3, unit_price: 0 }, LANES)).toMatch(/above 0/);
    expect(backupLaneProblem({ material_id: "M1", supplier_id: "S2", lead_time_weeks: 3, unit_price: 1 }, LANES)).toMatch(/uploaded lane/);
    expect(backupLaneProblem({ material_id: "M2", supplier_id: "X", lead_time_weeks: 3, unit_price: 1 }, LANES)).toBeNull();
  });
});

describe("safety-stock windows for a disrupted supplier's materials (P-P.3, engine 0.8.3)", () => {
  it("Safety stock now reaches P-P.3", () => {
    expect(MAPS.safety_stock_drawdown).toBe("safety_stock_materials");
    expect(NOT_SIMULATED.has("safety_stock_drawdown")).toBe(false);
  });

  it("reads a lane's lead time in weeks only when its unit says how", () => {
    expect(leadTimeWeeks({ lead_time: 4, lead_time_unit: "weeks" })).toBe(4);
    expect(leadTimeWeeks({ lead_time: 14, lead_time_unit: "days" })).toBe(2);
    expect(leadTimeWeeks({ lead_time: 1, lead_time_unit: "month" })).toBeNull();
    expect(leadTimeWeeks({ lead_time: null, lead_time_unit: "weeks" })).toBeNull();
  });

  it("reads a supplier's outage in the engine's weeks (start_day / 7, rounded)", () => {
    const sched = [{ target: "supplier:S1", start_day: 182, duration_days: 28 }];
    expect(outageWeeks(sched, "S1", ["S1"])).toEqual({ start: 26, end: 30 });
    expect(outageWeeks(sched, "S2", ["S1", "S2"])).toBeNull();
  });

  it("suggests a window built one lead time before the outage, held to its end", () => {
    expect(defaultWindow({ start: 26, end: 30 }, 4)).toEqual({ start_week: 22, end_week: 30 });
    expect(defaultWindow({ start: 2, end: 6 }, 5.5)).toEqual({ start_week: 0, end_week: 6 });
    expect(defaultWindow({ start: 26, end: 30 }, null)).toEqual({ start_week: 26, end_week: 30 });
  });

  it("refuses a window the engine would skip", () => {
    expect(windowProblem({ days: 0, start_week: 1, end_week: 2 })).toMatch(/above 0/);
    expect(windowProblem({ days: 90, start_week: 1, end_week: 2 })).toMatch(/84/);
    expect(windowProblem({ days: 7, start_week: 5, end_week: 5 })).toMatch(/after/);
    expect(windowProblem({ days: 7, start_week: 0, end_week: 4 })).toBeNull();
  });
});

describe("the pre-run grader reads the playbook as the mapper does", () => {
  const b = bridge as unknown as Parameters<typeof activeEnginePolicies>[2];
  it("counts a ticked response's policy only while recovery is enabled", () => {
    const on = activeEnginePolicies({ recovery: { response: ["capacity_flex"] } }, 1, b);
    const off = activeEnginePolicies({ recovery: { enabled: false, response: ["capacity_flex"] } }, 1, b);
    expect(on).toContain("short_term_capacity");
    expect(off).not.toContain("short_term_capacity");
  });
});
