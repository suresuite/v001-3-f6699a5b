/**
 * The Nexus card's reading of a stored stress battery — PLAN.md §27 WP 17.5 (§4 D310).
 *
 * `get_nexus_stress_results` returns the project's newest published battery: its
 * baseline (Validated Model, policy version, data version, engine build), the
 * scenario it ran (read from the RUN, never retyped here) and the materials and
 * suppliers it disrupted, each with its lost sales in € per outage duration and
 * the Average the battery ranks by. Nothing here computes a figure: it orders the
 * stored cells and words the baseline.
 */

/** One duration's cell: mean Δ lost sales in € vs the undisrupted run. */
export interface StressCell {
  mean: number | null;
  ci_halfwidth?: number | null;
  n?: number;
}

export interface StressRow {
  id: string;
  rank: number;
  average_eur: number;
  by_duration: Record<string, StressCell>;
  backlog_by_duration?: Record<string, number | null>;
  fill_rate_drop_by_duration?: Record<string, number | null>;
  /** Why a row lost nothing: covered by stock or policy, or the demand waited. */
  zero_reason: 'absorbed' | 'backordered' | null;
}

export interface StressResult {
  run_id: string | null;
  finished_at?: string | null;
  code_version?: string | null;
  scenario?: { durations_weeks?: number[]; start_week?: number; measure_unit?: string } | null;
  summary?: {
    warmup_week?: number;
    start_week?: number;
    replications?: number;
    /** The root seed; replication k draws from (seed, k), so more replications later extend this run. */
    seed?: number | null;
    window_weeks?: number;
    clean_lost_sales_eur?: { mean: number | null } | null;
  } | null;
  baseline?: {
    model_name?: string | null;
    model_code?: string | null;
    policy_version_no?: number | null;
    policy_version_code?: string | null;
    dataset_version_no?: number | null;
  } | null;
  data_is_current?: boolean;
  model_is_active?: boolean;
  materials?: StressRow[];
  suppliers?: StressRow[];
}

/** A sortable column: one duration (in weeks), the Average, or the rank. */
export type SortKey = { kind: 'duration'; weeks: number } | { kind: 'average' } | { kind: 'rank' };
export type SortDir = 'asc' | 'desc';

/** The order the table OPENS in (§27.2 rule 5): Average, highest first. */
export const DEFAULT_SORT: { key: SortKey; dir: SortDir } = { key: { kind: 'average' }, dir: 'desc' };

/** The run's own durations — the column set comes from what was stored. */
export function durationsOf(r: StressResult): number[] {
  const d = r.scenario?.durations_weeks;
  if (d && d.length) return [...d].sort((a, b) => a - b);
  const first = (r.materials ?? r.suppliers ?? [])[0];
  return first ? Object.keys(first.by_duration).map(Number).sort((a, b) => a - b) : [];
}

function value(row: StressRow, key: SortKey): number {
  if (key.kind === 'average') return row.average_eur;
  if (key.kind === 'rank') return row.rank;
  return row.by_duration[String(key.weeks)]?.mean ?? Number.NEGATIVE_INFINITY;
}

/**
 * Rows ordered by a column. Ties fall back to the battery's own rank, so an
 * order is never arbitrary and re-sorting by Average restores the stored one.
 */
export function sortRows(rows: StressRow[], key: SortKey, dir: SortDir): StressRow[] {
  const sign = dir === 'asc' ? 1 : -1;
  return [...rows].sort((a, b) => {
    const d = (value(a, key) - value(b, key)) * sign;
    return d !== 0 ? d : a.rank - b.rank;
  });
}

const EUR = new Intl.NumberFormat('en-GB', { style: 'currency', currency: 'EUR', maximumFractionDigits: 0 });
/** Whole euros, never abbreviated (mobile-ui-spec §6: numbers are load-bearing). */
export const eur = (x: number | null | undefined) => (x == null ? '—' : EUR.format(x));

/** "Model M-3 · data v4 · policies v2 · engine scsim-0.8.1+…". */
export function baselineLine(r: StressResult): string {
  const b = r.baseline ?? {};
  const model = b.model_name ? `${b.model_name}${b.model_code ? ` (${b.model_code})` : ''}` : 'Validated Model';
  const pv = b.policy_version_code ?? (b.policy_version_no != null ? `v${b.policy_version_no}` : '—');
  const dv = b.dataset_version_no != null ? `v${b.dataset_version_no}` : '—';
  return `${model} · data ${dv} · policies ${pv} · engine ${r.code_version ?? '—'}`;
}

/** "Each supplier and material disrupted alone · full outage from week 26 · 2–9 weeks · 10 replications · seed 42". */
export function scenarioLine(r: StressResult): string {
  const d = durationsOf(r);
  const span = d.length === 0 ? '' : d.length === 1 ? `${d[0]} weeks` : `${d[0]}–${d[d.length - 1]} weeks`;
  const start = r.summary?.start_week ?? r.scenario?.start_week;
  const reps = r.summary?.replications;
  const seed = r.summary?.seed;
  return [
    'Each supplier and supplied material disrupted alone',
    start != null ? `full outage from week ${start}` : 'full outage',
    span,
    reps != null ? `${reps} ${reps === 1 ? 'replication' : 'replications'}` : '',
    seed != null ? `seed ${seed}` : '',
  ].filter(Boolean).join(' · ');
}

/** What a zero row means, in words the reader can act on. */
export function zeroReasonText(z: StressRow['zero_reason']): string | null {
  if (z === 'absorbed') return 'no sales lost — stock or a policy covered the outage';
  if (z === 'backordered') return 'no sales lost — demand waited (backorder) instead';
  return null;
}

/** The notes the card must show beside a stored result (§27.2 rule 6). */
export function staleNotes(r: StressResult): string[] {
  const out: string[] = [];
  if (r.data_is_current === false) {
    out.push("The project's data has changed since this was prepared — the figures describe the data version above.");
  }
  if (r.model_is_active === false) {
    out.push('The Validated Model this ran on is no longer active.');
  }
  return out;
}
