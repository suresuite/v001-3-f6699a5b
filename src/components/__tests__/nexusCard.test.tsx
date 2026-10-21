/**
 * PLAN.md §27 WP 17.5 — the Nexus card reads a prepared battery and has no Run
 * button. Rendered to static markup (vitest runs in node with no DOM), as the
 * other card tests do; ordering itself is `stressResults.test.ts`'s.
 */
import { describe, expect, it, vi } from 'vitest';
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';

vi.mock('@/integrations/supabase/client', () => ({ supabase: { rpc: vi.fn() } }));
vi.mock('@/hooks/useAuth', () => ({ useAuth: () => ({ user: { id: 'u1' } }) }));
vi.mock('@/hooks/useGlobalProject', () => ({ useGlobalProject: () => ({ globalSelectedProjectId: null }) }));

import MLPrediction, { StressTable } from '../MLPrediction';
import type { StressRow } from '@/lib/nexus/stressResults';

const cells = (vals: number[]) => Object.fromEntries(vals.map((v, i) => [String(i + 2), { mean: v }]));
const rows: StressRow[] = [
  { id: 'S9', rank: 2, average_eur: 1200, by_duration: cells([0, 0, 0, 600, 1200, 1800, 2400, 3600]), zero_reason: null },
  { id: 'M1', rank: 1, average_eur: 9000, by_duration: cells([0, 0, 1000, 5000, 9000, 14000, 18000, 25000]), zero_reason: null },
  { id: 'S3', rank: 3, average_eur: 0, by_duration: cells([0, 0, 0, 0, 0, 0, 0, 0]), zero_reason: 'absorbed' },
];
const DURATIONS = [2, 3, 4, 5, 6, 7, 8, 9];

describe('Nexus node prediction (§27 WP 17.5)', () => {
  for (const skin of [false, true]) {
    it(`has no Run button and computes nothing (${skin ? 'mobile' : 'desktop'})`, () => {
      const html = renderToStaticMarkup(createElement(MLPrediction, { selectedPlant: null, skin }));
      expect(html).toContain('Nexus node prediction');
      expect(html).not.toMatch(/Run prediction/i);
      expect(html).toContain('Select a project first');
    });
  }

  it('the table: one column per duration, then Average; opened sorted by Average', () => {
    const html = renderToStaticMarkup(createElement(StressTable, { rows, durations: DURATIONS, idLabel: 'Material' }));
    const heads = [...html.matchAll(/<th[^>]*>(.*?)<\/th>/g)].map((m) => m[1].replace(/<[^>]+>/g, ''));
    expect(heads[0]).toContain('Material');
    expect(heads.slice(1)).toEqual([...DURATIONS.map((w) => `${w} wk`), 'Average ▼']);
    expect(html).toContain('aria-sort="descending"');
    const order = [...html.matchAll(/font-medium">([A-Z]\d)</g)].map((m) => m[1]);
    expect(order).toEqual(['M1', 'S9', 'S3']);
    expect(html).toContain('€25,000');
    expect(html).toContain('stock or a policy covered the outage');
  });
});
