/**
 * §4 D313 — the Product-level page's metrics are computed on the graph the page
 * draws. These run the analyzer's own pure core (`_shared/productMetrics.ts`), so a
 * divergence between what is drawn and what is measured fails here.
 */
import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { buildProductLevelGraph, type FlatLaneRow } from '../productGraph';
import { productLevelMetrics } from '../../../../supabase/functions/_shared/productMetrics';
import { calculateCentralities } from '../../../../supabase/functions/_shared/centrality';

/**
 *   S1 ─┐            ┌─ P1 ── C1
 *       ├─ M1 ───────┤
 *   S2 ─┘            └─ P2 ── C2
 *   S3 ── M2 ── P2
 *   S4 ── M3            (reaches no product — drawn with its supplier edge only)
 *
 * M1 is the only material shared by both products, so it is the bridge.
 */
const ROWS: FlatLaneRow[] = [
  { data_source: 'inbound', from_location: 'S1', to_location: 'M1', weighted: 30 },
  { data_source: 'inbound', from_location: 'S2', to_location: 'M1', weighted: 10 },
  { data_source: 'inbound', from_location: 'S3', to_location: 'M2', weighted: 5 },
  { data_source: 'inbound', from_location: 'S4', to_location: 'M3', weighted: 0 },
  { data_source: 'bom', from_location: 'M1', to_location: 'P1', material_consumption_rate: 2 },
  { data_source: 'bom', from_location: 'M1', to_location: 'P2', material_consumption_rate: 1 },
  { data_source: 'bom', from_location: 'M2', to_location: 'P2', material_consumption_rate: 1 },
  { data_source: 'outbound', from_location: 'P1', to_location: 'C1', weighted: 10 },
  { data_source: 'outbound', from_location: 'P2', to_location: 'C2', weighted: 20 },
];

describe('product_metrics — the analyzer measures the graph the page draws', () => {
  const { graph, results } = productLevelMetrics(ROWS);
  const by = new Map(results.map((r) => [r.entity_id, r]));

  it('stores one result per drawn node, typed by its echelon', () => {
    const drawn = buildProductLevelGraph(ROWS);
    const touched = new Set(drawn.edges.flatMap((e) => [e.source, e.target]));
    expect([...by.keys()].sort()).toEqual([...touched].sort());
    expect(by.get('M1')!.entity_type).toBe('material');
    expect(by.get('S1')!.entity_type).toBe('supplier');
    expect(by.get('P2')!.entity_type).toBe('product');
    expect(by.get('C2')!.entity_type).toBe('customer');
    expect(graph.unreachedMaterials).toEqual(['M3']);
  });

  it("a material's flow is the demand propagated to it", () => {
    // P1 needs 10 × 2 = 20 of M1; P2 needs 20 × 1 = 20 of M1 and 20 of M2.
    expect(by.get('M1')!.metrics.flow).toBe(40);
    expect(by.get('M2')!.metrics.flow).toBe(20);
    expect(by.get('M3')!.metrics.flow).toBe(0);
  });

  it("a supplier's flow is what it delivers, and it is stored beside the materials", () => {
    expect(by.get('S1')!.metrics.flow).toBe(30);
    expect(by.get('S2')!.metrics.flow).toBe(10);
    expect(results.filter((r) => r.entity_type === 'supplier').map((r) => r.entity_id).sort())
      .toEqual(['S1', 'S2', 'S3', 'S4']);
  });

  it('the shared material is the bridge — highest betweenness among materials', () => {
    const b = (id: string) => by.get(id)!.metrics.betweenness_centrality;
    expect(b('M1')).toBeGreaterThan(b('M2'));
    expect(b('M2')).toBeGreaterThan(0);
    expect(b('M3')).toBe(0);
    expect(by.get('M1')!.metrics.connections).toBe(4);
  });

  it('every metric is a finite number in [0, 1]', () => {
    for (const r of results) {
      for (const k of ['degree_centrality', 'weighted_degree_centrality', 'eigenvector_centrality',
        'betweenness_centrality', 'closeness_centrality', 'prominence'] as const) {
        const v = r.metrics[k];
        expect(Number.isFinite(v), `${r.entity_id}.${k}`).toBe(true);
        expect(v).toBeGreaterThanOrEqual(0);
        expect(v).toBeLessThanOrEqual(1);
      }
    }
  });
});

describe('calculateCentralities — exact mode', () => {
  it('betweenness on a path a–b–c is 1 for the middle node (normalised, undirected)', () => {
    const m = calculateCentralities(
      [{ uid: 'a' }, { uid: 'b' }, { uid: 'c' }],
      [{ source: 'a', target: 'b', weight: 1 }, { source: 'b', target: 'c', weight: 1 }],
      { exact: true },
    );
    expect(m.b.betweenness_centrality).toBeCloseTo(1);
    expect(m.a.betweenness_centrality).toBe(0);
  });

  it('the eigenvector converges on a bipartite graph (a star), centre highest', () => {
    const m = calculateCentralities(
      [{ uid: 'hub' }, { uid: 'x' }, { uid: 'y' }, { uid: 'z' }],
      ['x', 'y', 'z'].map((t) => ({ source: 'hub', target: t, weight: 1 })),
      { exact: true },
    );
    // Perron vector of K1,3: hub = 1/√2, leaves = 1/√6.
    expect(m.hub.eigenvector_centrality).toBeCloseTo(Math.SQRT1_2, 4);
    expect(m.x.eigenvector_centrality).toBeCloseTo(1 / Math.sqrt(6), 4);
  });
});

describe('the page reads the product-level store, not the firm table (D137)', () => {
  const page = readFileSync(join(process.cwd(), 'src/pages/ProductLevelNetwork.tsx'), 'utf8');
  it('calls get_product_level_metrics and asks for product_metrics', () => {
    expect(page).toContain("supabase.rpc('get_product_level_metrics'");
    expect(page).toContain("analysis_kind: 'product_metrics'");
    expect(page).not.toContain("rpc('get_network_metrics_for_materials'");
  });

  it('shows the same run twice: a material table and a supplier table', () => {
    expect(page).toContain("r.echelon === 'material'");
    expect(page).toContain("r.echelon === 'supplier'");
    expect(page).toMatch(/<NetworkMetricsTable\s+echelon="supplier"/);
  });
});
