import { describe, expect, it } from 'vitest';
import {
  DEFAULT_SORT,
  baselineLine,
  durationsOf,
  eur,
  scenarioLine,
  sortRows,
  staleNotes,
  zeroReasonText,
  type StressResult,
  type StressRow,
} from '../stressResults';

const cells = (vals: number[]) =>
  Object.fromEntries(vals.map((v, i) => [String(i + 2), { mean: v }]));

const rows: StressRow[] = [
  { id: 'M1', rank: 1, average_eur: 9000, by_duration: cells([0, 0, 1000, 5000, 9000, 14000, 18000, 25000]), zero_reason: null },
  { id: 'M2', rank: 2, average_eur: 5400, by_duration: cells([500, 900, 2000, 3000, 5000, 7000, 9000, 15800]), zero_reason: null },
  { id: 'M3', rank: 3, average_eur: 0, by_duration: cells([0, 0, 0, 0, 0, 0, 0, 0]), zero_reason: 'absorbed' },
];

const result: StressResult = {
  run_id: 'r1',
  code_version: 'scsim-0.8.1+abc',
  scenario: { durations_weeks: [9, 2, 3, 4, 5, 6, 7, 8], start_week: 26 },
  summary: { start_week: 31, replications: 10 },
  baseline: { model_name: 'Baseline', model_code: 'M-3', policy_version_code: 'P-2', dataset_version_no: 4 },
  data_is_current: true,
  model_is_active: true,
  materials: rows,
};

describe('the stored battery, read for the Nexus card (§27 WP 17.5)', () => {
  it('takes its columns from the run, in order', () => {
    expect(durationsOf(result)).toEqual([2, 3, 4, 5, 6, 7, 8, 9]);
  });

  it('opens sorted by Average, highest first — the stored rank', () => {
    expect(sortRows(rows, DEFAULT_SORT.key, DEFAULT_SORT.dir).map((r) => r.id)).toEqual(['M1', 'M2', 'M3']);
  });

  it('sorts by any duration, and a duration can reorder the table', () => {
    // At 2 weeks M2 is the one that hurts: it has the thinner cover.
    expect(sortRows(rows, { kind: 'duration', weeks: 2 }, 'desc').map((r) => r.id)).toEqual(['M2', 'M1', 'M3']);
    expect(sortRows(rows, { kind: 'duration', weeks: 9 }, 'asc').map((r) => r.id)).toEqual(['M3', 'M2', 'M1']);
  });

  it('breaks ties by the battery rank, never arbitrarily', () => {
    // M1 and M3 both lose €0 at 2 weeks.
    expect(sortRows(rows, { kind: 'duration', weeks: 2 }, 'asc').map((r) => r.id)).toEqual(['M1', 'M3', 'M2']);
  });

  it('states the baseline and the scenario that ran (the run\'s start week wins)', () => {
    expect(baselineLine(result)).toBe('Baseline (M-3) · data v4 · policies P-2 · engine scsim-0.8.1+abc');
    expect(scenarioLine(result)).toBe(
      'Each supplier and supplied material disrupted alone · full outage from week 31 · 2–9 weeks · 10 replications');
  });

  it('a single-duration, single-replication battery names its seed', () => {
    const one = { ...result, scenario: { durations_weeks: [5], start_week: 30 },
                  summary: { ...result.summary, start_week: 30, replications: 1, seed: 7 } };
    expect(scenarioLine(one)).toBe(
      'Each supplier and supplied material disrupted alone · full outage from week 30 · 5 weeks · 1 replication · seed 7');
  });

  it('says why a row lost nothing, and when the result is stale', () => {
    expect(zeroReasonText('absorbed')).toMatch(/covered/);
    expect(zeroReasonText('backordered')).toMatch(/backorder/);
    expect(zeroReasonText(null)).toBeNull();
    expect(staleNotes(result)).toEqual([]);
    expect(staleNotes({ ...result, data_is_current: false, model_is_active: false })).toHaveLength(2);
  });

  it('prints whole euros, unabbreviated', () => {
    expect(eur(1234567)).toBe('€1,234,567');
    expect(eur(null)).toBe('—');
  });
});
