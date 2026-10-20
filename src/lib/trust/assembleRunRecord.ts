// The reproducibility record (A5 · §5.4 · I8) for one simulation run — ONE
// author for every workbook that ships a run's figures: the run-results export
// (`useVerifiableExports`) and the inventory explorer's workbook. It was written
// inline in the first; a second export that rebuilt it would be a second record
// that could disagree with the first about the same run (`single-source`).
//
// Moved verbatim from `useVerifiableExports.exportRunResults`; the comments
// below are that function's.

import { supabase } from "@/integrations/supabase/client";
import type { SimulationRun } from "@/hooks/useSimulationRun";
import {
  buildReproducibilityRecord,
  type ReproducibilityRecord,
} from "@/lib/trust/reproducibilityRecord";
import { knownLimits, type FreshnessPayload } from "@/lib/trust/trustReport";
import { analysesAtRun, exportTrustInput, ingestHistoryFrom } from "@/lib/trust/exportTrustInputs";
import { resolveRunScenarioBinding, scheduleDigest } from "@/lib/trust/runScenarioBinding";
import { tupleNumbers } from "@/lib/trust/graphLevels";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const sb = supabase as any;

/** The scenario columns the record and the results workbook read. */
export const RUN_SCENARIO_COLUMNS =
  "id,name,seed,replications,crn,horizon_days,warmup_mode,warmup_days,disruption_schedule,updated_at";

export interface RunScenarioRow {
  id?: string;
  name?: string;
  seed?: number;
  disruption_schedule?: unknown[];
  updated_at?: string;
  [k: string]: unknown;
}

/** The registered engine a run was dispatched to, as the run ROW records it:
 *  "slug@code_version" from its `run_spec` (what the RunKey hashed), else the
 *  bare `engine_id`. Null for a run that predates the registry (WP 10.4). */
function engineLabel(run: SimulationRun): string | null {
  const e = (run.run_spec?.engine ?? null) as { slug?: string; code_version?: string | null } | null;
  if (e?.slug) return e.code_version ? `${e.slug}@${e.code_version}` : e.slug;
  return run.engine_id ?? null;
}

export async function assembleRunRecord({
  run,
  scenario,
  projectId,
  projectName,
  userId,
}: {
  run: SimulationRun;
  scenario: RunScenarioRow | null;
  projectId: string;
  projectName?: string | null;
  userId?: string | null;
}): Promise<ReproducibilityRecord> {
  // ── A5 · THE REPRODUCIBILITY RECORD (§5.4, I8) ────────────────────
  //
  // A4's sheets bind this RUN. The record adds what a reader in two years
  // also needs and the run row cannot supply: which ANALYSIS runs produced
  // the network figures — they come from `analysis_runs` and not from a
  // simulation — the hash ALGORITHM version behind `graph_hash`, and the
  // known limits of the whole thing.
  //
  // EVERY QUERY HERE IS ALLOWED TO FAIL, and a failure becomes an absent
  // binding with a stated reason rather than an aborted export. A reviewer
  // holding a workbook with six of nine bindings and three explanations is
  // better served than one holding an error toast.
  const runRow = run as SimulationRun & {
    dataset_version_id?: string | null;
    graph_hash?: string | null;
  };
  const { data: dsv } = await sb
    .from("dataset_versions")
    .select("id,graph_hash,schema_version")
    .eq("id", runRow.dataset_version_id ?? "00000000-0000-0000-0000-000000000000")
    .maybeSingle();
  // WP 11.3 · §4 D263 — the snapshot's tuple: its product, process, firm and
  // simulation-inputs versions, through the one read the browser can reach.
  const { data: tupleRaw } = runRow.dataset_version_id
    ? await sb.rpc("dataset_version_tuple", { p_dataset_version_id: runRow.dataset_version_id })
    : { data: null };
  const tuple = tupleNumbers(tupleRaw);
  const { data: analysisRows } = await sb
    .from("analysis_runs")
    .select("id,analysis_kind,code_version,input_hash,params_hash,finished_at,status")
    .eq("project_id", projectId)
    .eq("status", "succeeded");
  // The analyses that existed when this run was DISPATCHED (audit F-29) —
  // not the latest project-wide, which may have finished after it.
  const analysesBound = analysesAtRun(
    (analysisRows ?? []) as Array<Record<string, unknown>>,
    (run as SimulationRun).created_at, runRow.graph_hash);

  // The seed and schedule that RAN (audit F-11): the dispatch stamp, or the
  // live row only when provably unchanged since dispatch.
  const ran = resolveRunScenarioBinding(
    run as { created_at?: string; seed?: number | null; disruption_schedule?: unknown[] | null },
    (scenario ?? null) as { seed?: number; disruption_schedule?: unknown[]; updated_at?: string } | null,
  );

  // The Trust Report's own inputs (audit F-12): the real freshness payload
  // and ingest history. An empty `tables` map suppressed the two counted limits.
  const { data: freshness } = await sb.rpc("project_freshness", {
    p_project_id: projectId,
    p_user_id: userId ?? null,
  });
  const { data: ingestRows } = await sb
    .from("ingest_runs")
    .select("id,source_kind,applied_at,applied_by_user_id,rows_fetched")
    .eq("project_id", projectId)
    .order("created_at", { ascending: false })
    .limit(10);

  // The browser engine's own version, from the manifest the frontend ships.
  // A separate binding from the worker's `code_version` because the wheels
  // are committed and the two CAN differ (§4 D87).
  let browserEngineVersion: string | null = null;
  try {
    const res = await fetch("/engine/manifest.json");
    if (res.ok) {
      const manifest = (await res.json()) as { engine_version?: string; engine_build?: string };
      // "unknown" is what the build script used to write when its version
      // lookup failed. It is not a version and must not be bound as one.
      // WP 15.1 · §4 D293 — the BUILD (`scsim-0.6.1+<digest>`) when the
      // manifest names one, so it compares with a run's `code_version`.
      const v = manifest.engine_build || manifest.engine_version;
      browserEngineVersion = v && v !== "unknown" ? v : null;
    }
  } catch {
    browserEngineVersion = null;
  }

  return buildReproducibilityRecord({
    projectId,
    // The project's NAME (audit F-29) — it was `"project " + id.slice(0, 8)`.
    projectName: projectName ?? projectId,
    graphHash: runRow.graph_hash ?? (dsv?.graph_hash as string | null) ?? null,
    datasetVersionId: runRow.dataset_version_id ?? (dsv?.id as string | null) ?? null,
    hashSchemaVersion: (dsv?.schema_version as number | null) ?? null,
    policyVersionId: (run as SimulationRun).policy_version_id ?? null,
    policyHash: (run as SimulationRun).policy_hash ?? null,
    scenarioId: (scenario?.id as string | null) ?? (run as SimulationRun).scenario_id ?? null,
    scenarioSeed: ran.seed,
    scenarioSeedSource: ran.seedSource,
    scenarioSeedReason: ran.reason,
    disruptionSchedule: ran.schedule === null ? null : scheduleDigest(ran.schedule),
    engineCodeVersion: (run as SimulationRun).code_version ?? null,
    // WP 10.4 · §4 D245 — read from the RUN ROW, never from a live row.
    scenarioHash: (run as SimulationRun).scenario_hash ?? null,
    validatedModelId: (run as SimulationRun).model_validation_id ?? null,
    engineId: engineLabel((run as SimulationRun)),
    runKey: (run as SimulationRun).run_key ?? null,
    protocolOverrides: (run as SimulationRun).protocol_overrides,
    exploratory: (run as SimulationRun).exploratory ?? null,
    // WP 11.3 — which LEVEL the figure came from, read from the run and its snapshot.
    simulationHash: (run as SimulationRun).hash_simulation ?? null,
    simulationVersionNo: (run as SimulationRun).simulation_version_id ? tuple.simulation ?? null : null,
    levelVersions: { product: tuple.product ?? null, process: tuple.process ?? null, firm: tuple.firm ?? null },
    runKeyVersion: Number((run as SimulationRun).run_spec?.run_key_version ?? 0) || null,
    browserEngineVersion,
    analyses: analysesBound,
    // The Trust Report's own computation over the Trust Report's own inputs
    // — the function was shared before; now the inputs are too (F-12, D-6).
    // A freshness read that failed is not "nothing stale": it is declared.
    limits: freshness
      ? knownLimits(exportTrustInput(projectName ?? projectId,
          freshness as FreshnessPayload,
          ingestHistoryFrom((ingestRows ?? []) as Array<Record<string, unknown>>)))
      : [{
          ref: "T3",
          limit: "Data freshness could not be read when this workbook was exported.",
          consequence: "The counted limits (rows with no input hash, rows from a different " +
            "dataset) are unknown for this export — their absence here is not evidence of none.",
        }],
    measuredAt: new Date().toISOString(),
  });
}
