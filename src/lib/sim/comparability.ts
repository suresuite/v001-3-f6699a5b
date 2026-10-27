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
 */

import { engineDifference } from "./engineBuild";
import { engineChangeSummary, resultsUnchangedBetween } from "./engineChanges";

export interface ComparableSide {
  scenario: { crn: boolean; seed: number; disruption_schedule?: unknown[] | null };
  run: {
    policy_version_id: string | null;
    scenario_hash?: string | null;
    code_version?: string | null;
    seed?: number | null;
    disruption_schedule?: unknown[] | null;
    /** The RunKey's spec; its `scenario` carries the world fields the run read. */
    run_spec?: Record<string, unknown> | null;
  };
}

export type Component = "policies" | "world" | "events";

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
  return JSON.stringify(((schedule ?? []) as unknown[]).map(canon).map((e) => JSON.stringify(e)).sort());
}

export function differingComponents(a: ComparableSide, b: ComparableSide): Component[] {
  const events = (x: ComparableSide) =>
    canonicalSchedule(x.run.disruption_schedule ?? x.scenario.disruption_schedule ?? []);
  return [
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

  const differing = differingComponents(a, b);
  if (differing.length === 0) {
    failures.push("both runs share the same policies, world and disruptions — nothing to compare");
  } else if (differing.length > 1) {
    const world = differing.includes("world") ? worldDifference(a, b) : null;
    failures.push(
      `${differing.join(" AND ")} differ${world ? ` (world: ${world})` : ""} — ` +
        "isolate one component to get a valid paired experiment",
    );
  }

  // WP 15.1 · §4 D293 — says HOW the engines differ: version, build, or unknowable;
  // WP 15.6 · §4 D297 — and what the change record says lies between them.
  // Versions whose record says "results unchanged" are not a failure: that is
  // what `comparable: identical` means (comparabilityNotes says it instead).
  const engines = engineDifference(a.run.code_version, b.run.code_version);
  if (engines && !resultsUnchangedBetween(a.run.code_version, b.run.code_version)) {
    const between = engineChangeSummary(a.run.code_version, b.run.code_version);
    failures.push(`${engines}${between ? ` — ${between}` : ""} — re-run one side`);
  }
  return failures;
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
