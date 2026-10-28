import { describe, expect, it } from "vitest";
import {
  comparabilityFailures,
  comparabilityNotes,
  dataDifference,
  differingComponents,
  runVersions,
  type ComparableSide,
} from "../comparability";

const ev = { target: "supplier:S1", target_type: "node", start_day: 140, duration_days: 28, magnitude_pct: 100 };
const side = (o: Partial<ComparableSide["run"]> = {}, sched: unknown[] = []): ComparableSide => ({
  scenario: { crn: true, seed: 42, disruption_schedule: sched },
  run: {
    policy_version_id: "v1", scenario_hash: "w1", code_version: "0.2.8", seed: 42,
    disruption_schedule: sched, hash_simulation: "d1", ...o,
  },
});

describe("§9.3 comparability knows disruptions are a component (§4 D221)", () => {
  it("baseline vs a stress run of the same model is a valid pair", () => {
    const base = side();
    const stress = side({ disruption_schedule: [ev] }, [ev]);
    expect(differingComponents(base, stress)).toEqual(["events"]);
    expect(comparabilityFailures(base, stress)).toEqual([]);
  });

  it("identical inputs say so (still shown, as a descriptive comparison)", () => {
    expect(comparabilityFailures(side(), side())[0]).toMatch(/nothing to compare/);
  });

  it("policies and disruptions both differing is refused", () => {
    const f = comparabilityFailures(side(), side({ policy_version_id: "v2", disruption_schedule: [ev] }, [ev]));
    expect(f.join(" ")).toMatch(/policies AND events differ — the difference cannot be attributed/);
  });

  it("schedule order and key order do not make a difference", () => {
    const e2 = { ...ev, target: "plant:P" };
    const reordered = { magnitude_pct: 100, duration_days: 28, start_day: 140, target_type: "node", target: "supplier:S1" };
    expect(differingComponents(side({ disruption_schedule: [ev, e2] }), side({ disruption_schedule: [e2, reordered] }))).toEqual([]);
  });

  it("the seed is read from the run, not the live scenario", () => {
    const a = side();
    const b = side({ seed: 7, disruption_schedule: [ev] });
    expect(comparabilityFailures(a, b).join(" ")).toMatch(/seed spec differs \(42 vs 7\)/);
  });
});

describe("engine versions the change record says give the same results compare", () => {
  const stress = (cv: string) => side({ code_version: cv, disruption_schedule: [ev] }, [ev]);
  it("0.8.0 vs 0.8.1 (comparable: identical) is a valid pair, with a note saying so", () => {
    const base = side({ code_version: "scsim-0.8.0" });
    const b = stress("scsim-0.8.1+6483d4e3f6f6");
    expect(comparabilityFailures(base, b)).toEqual([]);
    expect(comparabilityNotes(base, b).join(" ")).toMatch(
      /engine versions differ \(0\.8\.0 vs 0\.8\.1\) — 1 version between them, none of which changes results/,
    );
  });
  it("a span with a version that changes results is still refused", () => {
    const f = comparabilityFailures(side({ code_version: "scsim-0.7.0" }), stress("scsim-0.8.1+6483d4e3f6f6"));
    expect(f.join(" ")).toMatch(/0\.8\.0 changes results for some projects.*re-run one side/);
  });
});

describe("a world difference names the fields the runs recorded", () => {
  const spec = (horizon_days: number) => ({
    scenario: { horizon_days, time_step: "week", demand_model: { kind: "poisson" } },
  });
  it("horizon in weeks, from the RunKey spec", () => {
    const f = comparabilityFailures(
      side({ run_spec: spec(364) }),
      side({ scenario_hash: "w2", run_spec: spec(525), disruption_schedule: [ev] }, [ev]),
    );
    expect(f.join(" ")).toMatch(/world AND events differ \(world: horizon 52 wk vs 75 wk\)/);
  });
  it("says nothing extra for a run without a spec", () => {
    const f = comparabilityFailures(side(), side({ scenario_hash: "w2", disruption_schedule: [ev] }, [ev]));
    expect(f.join(" ")).toMatch(/world AND events differ — the difference cannot be attributed/);
  });
});

// §4 D316 — data is the fourth component, and a missing binding is unknown, not "same".
describe("data is a component, read from what the run recorded (§4 D316)", () => {
  it("different data alone is a paired experiment (network redesign, §9.3)", () => {
    const b = side({ hash_simulation: "d2" });
    expect(differingComponents(side(), b)).toEqual(["data"]);
    expect(comparabilityFailures(side(), b)).toEqual([]);
  });

  it("different data AND policies is named, not hidden inside a policy comparison", () => {
    const f = comparabilityFailures(side(), side({ hash_simulation: "d2", policy_version_id: "v2" }));
    expect(f.join(" ")).toMatch(/data AND policies differ/);
  });

  it("falls back to the dataset version, then the RunKey's graph hash", () => {
    const dv = (id: string) => side({ hash_simulation: null, dataset_version_id: id });
    expect(dataDifference(dv("x"), dv("y"))).toBe("differs");
    const gh = (h: string) => side({ hash_simulation: null, run_spec: { graph_hash: h } });
    expect(dataDifference(gh("g"), gh("g"))).toBe("same");
  });

  it("a run with no data binding is unknown — never assumed the same", () => {
    const old = side({ hash_simulation: null, policy_version_id: "v2" });
    expect(dataDifference(side(), old)).toBe("unknown");
    expect(comparabilityFailures(side(), old).join(" ")).toMatch(/same data is unknown/);
  });
});

describe("a missing engine version is unknown, not the same engine (§4 D316)", () => {
  it("names it", () => {
    const f = comparabilityFailures(side(), side({ code_version: null, policy_version_id: "v2" }));
    expect(f.join(" ")).toMatch(/no engine version/);
  });
});

describe("runVersions labels what each run used", () => {
  it("short labels, and says when nothing was recorded", () => {
    const v = runVersions({ ...side().run, hash_simulation: "abcdef0123456789", code_version: "scsim-0.8.3+6483d4e3f6f6" });
    expect(v).toEqual({ data: "data abcdef01", policies: "version v1", engine: "0.8.3", seed: "42" });
    const none = runVersions({ policy_version_id: null });
    expect(none).toEqual({ data: "not recorded", policies: "not recorded", engine: "not recorded", seed: "not recorded" });
  });
});
