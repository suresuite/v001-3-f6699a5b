import { act, create, type ReactTestRenderer } from 'react-test-renderer';
import { createElement } from 'react';
import { afterEach, describe, expect, it, vi } from 'vitest';

const { rpc } = vi.hoisted(() => ({ rpc: vi.fn() }));
vi.mock('@/integrations/supabase/client', () => ({ supabase: { rpc } }));
import { useDatasetVersion } from '../useDatasetVersion';

let view: ReactTestRenderer;
let result: ReturnType<typeof useDatasetVersion>;
function Probe({ projectId, revision }: { projectId: string | null; revision: number }) {
  result = useDatasetVersion(projectId, revision);
  return null;
}
const response = (hash: string, version: number) => ({ data: {
  current: { graph_hash: hash }, current_version: { id: hash, version_no: version },
  levels: { firm: { hash, current_version: { id: hash, version_no: version, created_at: '2026-10-21T10:00:00Z' } } },
}, error: null });

afterEach(() => {
  if (view) act(() => view.unmount());
  rpc.mockReset();
});

describe('refreshing a mounted graph version', () => {
  it('re-reads when the page reloads or recalculation completes without changing project', async () => {
    rpc.mockResolvedValueOnce(response('old', 1));
    await act(async () => { view = create(createElement(Probe, { projectId: 'AA', revision: 0 })); });
    expect(result.currentVersion?.version_no).toBe(1);

    rpc.mockResolvedValueOnce(response('new', 2));
    await act(async () => { view.update(createElement(Probe, { projectId: 'AA', revision: 1 })); });
    expect(result.currentHash).toBe('new');
    expect(result.levels.firm?.currentVersion?.version_no).toBe(2);
    expect(rpc).toHaveBeenCalledTimes(2);
    await act(async () => { view.update(createElement(Probe, { projectId: 'AA', revision: 1 })); });
    expect(rpc).toHaveBeenCalledTimes(2);
  });

  it('an older response cannot overwrite the refreshed version', async () => {
    let finishOld: (value: ReturnType<typeof response>) => void;
    rpc.mockReturnValueOnce(new Promise((resolve) => { finishOld = resolve; }));
    await act(async () => { view = create(createElement(Probe, { projectId: 'AA', revision: 0 })); });
    rpc.mockResolvedValueOnce(response('new', 2));
    await act(async () => { view.update(createElement(Probe, { projectId: 'AA', revision: 1 })); });
    await act(async () => { finishOld(response('old', 1)); });
    expect(result.currentHash).toBe('new');
    expect(result.loading).toBe(false);
  });

  it('switching projects discards the previous project response and clearing selection clears the version', async () => {
    let finishOld: (value: ReturnType<typeof response>) => void;
    rpc.mockReturnValueOnce(new Promise((resolve) => { finishOld = resolve; }));
    await act(async () => { view = create(createElement(Probe, { projectId: 'AA', revision: 0 })); });
    rpc.mockResolvedValueOnce(response('BB-hash', 7));
    await act(async () => { view.update(createElement(Probe, { projectId: 'BB', revision: 0 })); });
    await act(async () => { finishOld(response('AA-hash', 1)); });
    expect(result.currentHash).toBe('BB-hash');
    await act(async () => { view.update(createElement(Probe, { projectId: null, revision: 0 })); });
    expect(result.currentHash).toBeNull();
    expect(result.levels).toEqual({});
  });
});
