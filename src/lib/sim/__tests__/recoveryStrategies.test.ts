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
import {
  NOT_SIMULATED,
  OFFERED_STRATEGIES,
  RESPONSE_LABELS,
  backupLaneProblem,
  backupsForSupplier,
  disruptedSuppliers,
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
