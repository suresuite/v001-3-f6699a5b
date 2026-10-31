/**
 * §9.3 comparison semantics, as a pure rule (WP 9.4 slice 5, closes §4 D221).
 *
 * Two runs are comparable iff they are CRN-paired (same seed spec) and they
 * differ in EXACTLY ONE component. There are three components, not two:
 *
 *   · policies — the policy version the run was dispatched under;
 *   · world    — the baseline fingerprint stamped on the run (`scenario_hash`:
 *                horizon, time step, demand model — B0 §2.3);
 *   · events   — the disruption schedule the run was dispatched with.
 *
 * The rule used to know only the first two. But `scenario_hash` EXCLUDES the
 * disruption schedule by design — so a baseline run and a stress run of the
 * same model read "the same policies and the same world — nothing to compare",
 * which is precisely the disruption-impact comparison §9.3 names as valid.
 *
 * Seed and schedule are read from the RUN (stamped at dispatch since audit
 * WP 8); the live scenario row is the fallback only for runs older than that.
 *
 * A FOURTH component, data (§4 D316): §9.3 names "different graphs under the
 * same policies" as a valid experiment, and the rule never read the graph — so
 * a run on last month's upload and a run on this month's read "same world", and
 * a data change rode inside a policy or disruption comparison unseen. Read from
 * what the run RECORDED: the simulation-scope hash, else the dataset version,
 * else the RunKey's composite graph hash; unknown when neither side has the same
 * kind of binding.
 *
 * WHAT A FAILURE MEANS since §4 D316: not "refused". A pair that fails is still
 * compared — the user may compare across engine, data and policy versions — but
 * as a DESCRIPTIVE comparison: an independent interval rather than a paired one
 * (`compareRows(…, paired = false)`), no "best" mark, and every reason here shown
 * beside it, so a difference that cannot be attributed to one change says so.
 */

import { engineEvent } from "./startAnchor";
import { isCalendarDate } from "./calendarWeeks";
import { engineDifference } from "./engineBuild";
import { engineChangeSummary, resultsUnchangedBetween } from "./engineChanges";

export interface ComparableSide {
  scenario: { crn: boolean; seed: number; disruption_schedule?: unknown[] | null };
  run: {
    policy_version_id: string | null;
    scenario_hash?: string | null;
    /** What data the run read (§4 D316): the simulation scope's hash (WP 11.2),
     *  the frozen dataset version (WP 13.2), the RunKey spec's `graph_hash`. */
    hash_simulation?: string | null;
    dataset_version_id?: string | null;
    code_version?: string | null;
    seed?: number | null;
    disruption_schedule?: unknown[] | null;
    /** The RunKey's spec; its `scenario` carries the world fields the run read. */
    run_spec?: Record<string, unknown> | null;
    /** §4 D318 — run week 0's date as the run recorded it, and how it was recorded. */
    calendar_start?: string | null;
    calendar_start_source?: string | null;
  };
}

export type Component = "data" | "policies" | "world" | "events";

const specGraphHash = (x: ComparableSide): string | null => {
  const g = (x.run.run_spec as { graph_hash?: unknown } | null | undefined)?.graph_hash;
  return typeof g === "string" && g ? g : null;
};

/** Whether the two runs read the same data, from the strongest binding BOTH
 *  recorded. "unknown" when they share no kind of binding (a run that predates
 *  them) — never assumed the same. */
export function dataDifference(a: ComparableSide, b: ComparableSide): "same" | "differs" | "unknown" {
  const pairs: [string | null | undefined, string | null | undefined][] = [
    [a.run.hash_simulation, b.run.hash_simulation],
    [a.run.dataset_version_id, b.run.dataset_version_id],
    [specGraphHash(a), specGraphHash(b)],
  ];
  for (const [x, y] of pairs) if (x && y) return x === y ? "same" : "differs";
  return "unknown";
}

/** Order-independent, key-order-independent text of a schedule. */
export function canonicalSchedule(schedule: unknown[] | null | undefined): string {
  const canon = (v: unknown): unknown =>
    Array.isArray(v)
      ? v.map(canon)
      : v && typeof v === "object"
        ? Object.fromEntries(
            Object.keys(v as Record<string, unknown>)
              .sort()
              .map((k) => [k, canon((v as Record<string, unknown>)[k])]),
          )
        : v;
  // `start_anchor` is what the user typed (an ISO week or a date) and the
  // engine never reads it (PLAN.md §4 D318): two runs whose events differ only
  // in how their start was entered ran the same events.
  const engineOnly = (e: unknown) =>
    e && typeof e === "object" && !Array.isArray(e) ? engineEvent(e as Record<string, unknown>) : e;
  return JSON.stringify(((schedule ?? []) as unknown[]).map(engineOnly).map(canon).map((e) => JSON.stringify(e)).sort());
}

export function differingComponents(a: ComparableSide, b: ComparableSide): Component[] {
  const events = (x: ComparableSide) =>
    canonicalSchedule(x.run.disruption_schedule ?? x.scenario.disruption_schedule ?? []);
  return [
    dataDifference(a, b) === "differs" && "data",
    a.run.policy_version_id !== b.run.policy_version_id && "policies",
    (a.run.scenario_hash ?? null) !== (b.run.scenario_hash ?? null) && "world",
    events(a) !== events(b) && "events",
  ].filter(Boolean) as Component[];
}

export function comparabilityFailures(a: ComparableSide, b: ComparableSide): string[] {
  const failures: string[] = [];
  const seedA = a.run.seed ?? a.scenario.seed;
  const seedB = b.run.seed ?? b.scenario.seed;
  if (!a.scenario.crn || !b.scenario.crn) {
    failures.push("common random numbers are off — the runs are not CRN-paired");
  } else if (seedA !== seedB) {
    failures.push(`seed spec differs (${seedA} vs ${seedB}) — the runs are not CRN-paired`);
  }

  if (dataDifference(a, b) === "unknown") {
    failures.push("one run records no data binding, so whether the two read the same data is unknown");
  }
  const differing = differingComponents(a, b);
  if (differing.length === 0) {
    failures.push("both runs share the same data, policies, world and disruptions — nothing to compare");
  } else if (differing.length > 1) {
    const world = differing.includes("world") ? worldDifference(a, b) : null;
    failures.push(
      `${differing.join(" AND ")} differ${world ? ` (world: ${world})` : ""} — ` +
        "the difference cannot be attributed to one of them; isolate one component for a paired experiment",
    );
  }

  // WP 15.1 · §4 D293 — says HOW the engines differ: version, build, or unknowable;
  // WP 15.6 · §4 D297 — and what the change record says lies between them.
  // Versions whose record says "results unchanged" are not a failure: that is
  // what `comparable: identical` means (comparabilityNotes says it instead).
  const engines = engineDifference(a.run.code_version, b.run.code_version);
  if (engines && !resultsUnchangedBetween(a.run.code_version, b.run.code_version)) {
    const between = engineChangeSummary(a.run.code_version, b.run.code_version);
    failures.push(`${engines}${between ? ` — ${between}` : ""} — re-run one side for a paired experiment`);
  } else if (!a.run.code_version || !b.run.code_version) {
    // engineDifference reads a missing version as "no difference"; it is unknown.
    failures.push("one run records no engine version, so whether the same engine ran both is unknown");
  }
  return failures;
}

/** Short labels for what one run used — the "what each run used" table, so the
 *  reason a pair is or is not like-for-like is visible rather than inferred. */
export function runVersions(
  run: ComparableSide["run"],
): { data: string; policies: string; engine: string; seed: string; calendar: string } {
  const short = (v: string | null | undefined) => (v ? v.slice(0, 8) : null);
  const g = (run.run_spec as { graph_hash?: unknown } | null | undefined)?.graph_hash;
  const data =
    (run.hash_simulation && `data ${short(run.hash_simulation)}`) ||
    (run.dataset_version_id && `version ${short(run.dataset_version_id)}`) ||
    (typeof g === "string" && g && `graph ${short(g)}`) ||
    "not recorded";
  const engine = run.code_version ? run.code_version.replace(/^scsim-/, "").replace(/\+.*/, "") : "not recorded";
  return {
    data,
    policies: run.policy_version_id ? `version ${short(run.policy_version_id)}` : "not recorded",
    engine,
    seed: run.seed == null ? "not recorded" : String(run.seed),
    // The calendar dates a week; it is not an engine input, so it never makes a
    // pair "not like-for-like" — it is shown so a date is read against the right start.
    calendar: isCalendarDate(run.calendar_start)
      ? `week 0 = ${run.calendar_start}${run.calendar_start_source === "backfill" ? " (filled later)" : ""}`
      : "not recorded",
  };
}

/** What a reader of a VALID pair should still be told: two engine versions the
 *  change record says give the same results. Never a reason to refuse. */
export function comparabilityNotes(a: ComparableSide, b: ComparableSide): string[] {
  const engines = engineDifference(a.run.code_version, b.run.code_version);
  if (!engines || !resultsUnchangedBetween(a.run.code_version, b.run.code_version)) return [];
  const between = engineChangeSummary(a.run.code_version, b.run.code_version);
  return [`${engines}${between ? ` — ${between}` : ""}`];
}

const WORLD_FIELDS = ["horizon_days", "time_step", "demand_model"] as const;

/** Which world fields differ, from what each run recorded in its RunKey spec —
 *  never from the live scenario row, which may have been edited since. Null when
 *  either run predates the spec or the spec shows no difference. */
export function worldDifference(a: ComparableSide, b: ComparableSide): string | null {
  const worldOf = (x: ComparableSide) => {
    const sc = (x.run.run_spec as { scenario?: Record<string, unknown> } | null | undefined)?.scenario;
    return sc && typeof sc === "object" ? sc : null;
  };
  const wa = worldOf(a);
  const wb = worldOf(b);
  if (!wa || !wb) return null;
  const parts: string[] = [];
  for (const k of WORLD_FIELDS) {
    const va = canonicalSchedule([wa[k]]);
    const vb = canonicalSchedule([wb[k]]);
    if (va === vb) continue;
    if (k === "horizon_days" && typeof wa[k] === "number" && typeof wb[k] === "number") {
      const wk = (d: number) => `${Math.round((d / 7) * 10) / 10} wk`;
      parts.push(`horizon ${wk(wa[k] as number)} vs ${wk(wb[k] as number)}`);
    } else if (k === "time_step") {
      parts.push(`time step ${String(wa[k])} vs ${String(wb[k])}`);
    } else {
      parts.push("demand model");
    }
  }
  return parts.length ? parts.join(", ") : null;
}
