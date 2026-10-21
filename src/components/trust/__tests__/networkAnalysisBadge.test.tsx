import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { storedMetricsDecision } from '@/lib/network/storedMetrics';
import { NetworkAnalysisBadge } from '../NetworkAnalysisBadge';

const { readVersion } = vi.hoisted(() => ({ readVersion: vi.fn() }));
vi.mock('@/hooks/useDatasetVersion', () => ({ useDatasetVersion: readVersion }));
// If the network chip ever reads the project roll-up again, fail immediately.
vi.mock('../FreshnessBadge', () => ({ FreshnessBadge: () => { throw new Error('Wrong scope'); } }));
import { GraphVersionChip } from '../GraphVersionChip';

beforeEach(() => {
  readVersion.mockReset();
  readVersion.mockReturnValue({
    loading: false, currentHash: 'composite-hash',
    currentVersion: { version_no: 9 },
    levels: { process: { hash: 'process-hash', currentVersion: { version_no: 3 } } },
  });
});

describe('a network badge describes its own analysis', () => {
  it('a current stored analysis stays current even though the composite hash differs', () => {
    const html = renderToStaticMarkup(createElement(GraphVersionChip, {
      projectId: 'AA', level: 'process', analysisState: 'current',
      analysisHash: 'process-hash', refreshKey: 2,
    }));
    expect(html).toContain('Process graph v3');
    expect(html).toContain('Analysis current');
    expect(html).not.toContain('composite-hash');
    expect(html).not.toContain('Dataset');
    expect(readVersion).toHaveBeenCalledWith('AA', 2);
  });

  it('a process result for a different process hash still needs recalculation', () => {
    const html = renderToStaticMarkup(createElement(GraphVersionChip, {
      projectId: 'AA', level: 'process', analysisState: 'current', analysisHash: 'old-process',
    }));
    expect(html).toContain('Analysis needs recalculation');
    expect(html).not.toContain('Analysis current');
  });

  it('newly read metrics change the verdict from stale to current, including cached results', () => {
    const row = { metrics_source: 'store' as const, hash_is_current: false, run_id: 'r1' };
    const render = (current: boolean) => renderToStaticMarkup(createElement(NetworkAnalysisBadge, {
      state: storedMetricsDecision([{ ...row, hash_is_current: current }]).state,
    }));
    expect(render(false)).toContain('Analysis needs recalculation');
    expect(render(true)).toContain('Analysis current');
  });

  it.each([
    ['loading', 'Checking analysis…'],
    ['unavailable', 'Analysis status unavailable'],
    ['in progress', 'Analysis in progress'],
    ['unknown', 'Analysis provenance unknown'],
    ['missing', 'No stored analysis'],
  ] as const)('never claims current when %s', (state, label) => {
    const html = renderToStaticMarkup(createElement(NetworkAnalysisBadge, { state }));
    expect(html).toContain(label);
    expect(html).not.toContain('Analysis current');
  });

  it('missing process provenance is unknown and a pending version read is checking', () => {
    const props = { projectId: 'AA', level: 'process' as const, analysisState: 'current' as const, analysisHash: null };
    expect(renderToStaticMarkup(createElement(GraphVersionChip, props))).toContain('Analysis provenance unknown');
    readVersion.mockReturnValue({ loading: true, currentHash: null, levels: {} });
    expect(renderToStaticMarkup(createElement(GraphVersionChip, props))).toContain('Checking analysis…');
  });

  it('all three pages pass their own status and refresh revision', () => {
    for (const page of ['Product', 'Process', 'Firm']) {
      const source = readFileSync(join(__dirname, '../../../pages', `${page}LevelNetwork.tsx`), 'utf8');
      expect(source).toMatch(/analysisState=/);
      expect(source).toMatch(/refreshKey=/);
      if (page !== 'Firm') expect(source).toMatch(/\}, \[[^\]]*loadNonce\]\);/);
    }
  });
});
