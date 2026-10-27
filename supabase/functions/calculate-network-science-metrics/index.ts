import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.57.0';
import {
  applyNodeMetrics, completeRun, failRun, getOrStart,
} from "../_shared/analysisStore.ts";
import { calculateCentralities } from "../_shared/centrality.ts";
import { computeProductMetrics, LANE_COLUMNS } from "../_shared/productMetrics.ts";

/** Part of the store's key. Bump when the metrics change. WP 10.1: the graph read
 *  is now the one the store names (`inputScope`), so the version moves. §4 D313:
 *  the computation moved to `_shared/centrality.ts`; an edge to a node outside the
 *  node list and a self-loop are no longer folded into the adjacency. */
const CODE_VERSION = 'network_metrics@d313.1';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface Node {
  id: string;
  uid: string;
  name: string;
  revenue?: number;
}

interface Edge {
  src_uid: string;
  dst_uid: string;
  relative_revenue?: number;
}

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    const { project_id, uploaded_by, analysis_kind } = await req.json();

    if (!project_id) {
      return new Response(
        JSON.stringify({ error: 'Project ID is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // WP 4.3 · G4 — a tier-3 write names its actor or does not happen.
    if (!uploaded_by) {
      return new Response(JSON.stringify({
        success: false,
        error: 'uploaded_by is required: a tier-3 write must name its actor (invariant audit-actor)',
      }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    // §4 D313 — THE PRODUCT-LEVEL VIEW'S OWN METRICS. `network_metrics` computes on
    // the firm graph (or the lane graph as a fallback) and writes onto
    // `network_nodes`; the Product-level page showed materials by joining that
    // FIRM table to material ids on a bare string (D137), so whenever a deep-tier
    // network existed its table was empty. `product_metrics` computes on the graph
    // the page DRAWS and stores into `analysis_results` only — no entity mirror,
    // because there is no entity table whose rows are this graph's nodes.
    if (analysis_kind === 'product_metrics') {
      const result = await computeProductMetrics(supabase, project_id, uploaded_by, (from, to) =>
        supabase.from('supply_chain_data').select(LANE_COLUMNS)
          .eq('project_id', project_id).order('id', { ascending: true }).range(from, to));
      return new Response(JSON.stringify(result.body), {
        status: result.status, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    if (analysis_kind != null && analysis_kind !== 'network_metrics') {
      return new Response(JSON.stringify({
        success: false, error: `unknown analysis_kind ${analysis_kind}: network_metrics or product_metrics`,
      }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    // WP 10.1 · §4 D235 — keyed on the LEVEL this kind reads. The store resolves
    // it from `analysis_kinds`: the firm level, or the process level when the deep
    // tier has no nodes or no edges — and says which in `inputScope`, so this
    // function reads that graph rather than deciding the fallback a second time.
    const run = await getOrStart(supabase, {
      projectId: project_id,
      analysisKind: 'network_metrics',
      params: { weighted: true },
      codeVersion: CODE_VERSION,
      actorUserId: uploaded_by,
    });

    if (run.cacheHit) {
      console.log(`network_metrics: cache hit on run ${run.runId}`);
      return new Response(JSON.stringify({
        success: true, cache_hit: true, run_id: run.runId,
        input_hash: run.inputHash, input_scope: run.inputScope,
        dataset_version_id: run.datasetVersionId, code_version: run.codeVersion,
        nodes_updated: (run.rowCounts as { nodes?: number } | undefined)?.nodes ?? 0,
      }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    if (run.claimedByOther && run.status === 'running') {
      return new Response(JSON.stringify({
        success: true, cache_hit: false, in_progress: true, run_id: run.runId,
        message: 'another request is already computing this exact analysis',
      }), { status: 202, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }

    console.log(`Calculating network science metrics for project: ${project_id} (${run.inputScope} level)`);

    // §4 D236 — A READ THAT FAILS FAILS THE RUN. These returned 500 without
    // `failRun`, so the claim stayed `running` and owned its key forever: every
    // later request was told "another request is already computing this".
    const readFailed = async (what: string, err: unknown) => {
      console.error(`Error fetching ${what}:`, err);
      await failRun(supabase, run.runId, uploaded_by,
        [{ code: 'read_failed', what, message: String((err as { message?: string })?.message ?? err) }]);
      return new Response(
        JSON.stringify({ error: `Failed to fetch ${what}`, run_id: run.runId }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    };

    let effectiveNodes: Node[] = [];
    let effectiveEdges: Edge[] = [];
    const fallbackWarnings: Array<Record<string, unknown>> = [];

    if (run.inputScope === 'firm') {
      const { data: nodes, error: nodesError } = await supabase
        .rpc('get_network_nodes_for_prominence', { p_project_id: project_id });
      if (nodesError) return await readFailed('nodes', nodesError);
      const { data: edges, error: edgesError } = await supabase
        .rpc('get_network_edges_for_prominence', { p_project_id: project_id });
      if (edgesError) return await readFailed('edges', edgesError);
      effectiveNodes = (nodes ?? []) as Node[];
      effectiveEdges = (edges ?? []) as Edge[];
      console.log(`Processing ${effectiveNodes.length} nodes and ${effectiveEdges.length} edges`);
    }

    // The lane graph — the process level — when the STORE says the deep tier is
    // incomplete (`analysis_kinds.fallback_rule`). The decision is no longer made
    // here; this branch only reads what it was told to read.
    if (run.inputScope === 'process') {
      console.log('No deep-tier network data found. Deriving graph from supply_chain_data as fallback...');
      const { data: scdRows, error: scdError } = await supabase
        .from('supply_chain_data')
        .select('from_location,to_location,weighted,plant_name')
        .eq('project_id', project_id);

      if (scdError) {
        return await readFailed('supply_chain_data', scdError);
      } else if ((scdRows?.length ?? 0) > 0) {
        const nodeSet = new Map<string, { uid: string; name: string; plant_name: string }>();
        const edgeList: Edge[] = [];

        for (const row of scdRows as any[]) {
          const from = row.from_location as string | null;
          const to = row.to_location as string | null;
          if (!from || !to) continue;
          const plant = (row.plant_name as string) ?? '';
          const weight = typeof row.weighted === 'number' ? row.weighted : Number(row.weighted ?? 1);

          if (!nodeSet.has(from)) nodeSet.set(from, { uid: from, name: from, plant_name: plant });
          if (!nodeSet.has(to)) nodeSet.set(to, { uid: to, name: to, plant_name: plant });
          edgeList.push({ src_uid: from, dst_uid: to, relative_revenue: isFinite(weight) ? weight : 1 });
        }

        effectiveNodes = Array.from(nodeSet.values()).map(n => ({ id: n.uid, uid: n.uid, name: n.name }));
        effectiveEdges = edgeList;

        console.log(`Derived fallback graph with ${effectiveNodes.length} nodes and ${effectiveEdges.length} edges from supply_chain_data.`);

        // Ensure nodes exist in network_nodes so metrics can be stored and later
        // queried by RPCs. WP 10.1 · §4 D236: this write used to INVALIDATE ITS OWN
        // RUN — it lands in `network_nodes`, which the anchor hashes, AFTER the key
        // was claimed on that anchor. The run is keyed on the PROCESS level now (the
        // store chose it because the deep tier is incomplete), and the process level
        // does not include `network_nodes`, so the stamp it just took stays true.
        if (effectiveNodes.length > 0) {
          const upsertRows = Array.from(nodeSet.values()).map(n => ({
            project_id,
            uid: n.uid,
            name: n.name,
            plant_name: n.plant_name,
          }));
          // §4 D72 · this upsert named a constraint that did not exist and failed
          // on every run until `network_nodes_natural_key` (project_id, uid) landed
          // in `20260917000007`; it succeeds now. A failure is still not swallowed:
          // it becomes a declared warning on the run (T3).
          const { error: upsertErr } = await supabase
            .from('network_nodes')
            .upsert(upsertRows, { onConflict: 'project_id,uid' });
          if (upsertErr) {
            console.error('Failed to upsert network_nodes for fallback (D72):', upsertErr);
            fallbackWarnings.push({
              code: 'fallback_nodes_not_stored',
              defect: 'D72',
              attempted: upsertRows.length,
              message: upsertErr.message ?? String(upsertErr),
              meaning: 'network_nodes has no unique index on (project_id, uid), so the '
                + 'derived fallback graph could not be stored; metrics below describe '
                + 'nodes that may have no row to be written onto',
            });
          } else {
            console.log(`Upserted ${upsertRows.length} nodes into network_nodes (fallback).`);
          }
        }
      }
    }

    if (run.inputScope !== 'firm' && run.inputScope !== 'process') {
      return await readFailed(`a graph for scope ${run.inputScope}`,
        new Error('analysis_kinds declares network_metrics over firm (fallback process); the store resolved another level'));
    }

    // Calculate network science metrics for each node using effective graph
    // The legacy approximations (sampled betweenness, plain power iteration) are
    // this kind's numbers; `_shared/centrality.ts` says why they stay.
    const metrics = calculateCentralities(
      effectiveNodes,
      effectiveEdges.map((e) => ({ source: e.src_uid, target: e.dst_uid, weight: e.relative_revenue || 1 })),
    );

    // ── WP 4.3 · THE DUAL-WRITE ──────────────────────────────────────────
    //
    // One `.update()` per node stood here, in a serial loop — one statement and
    // one `actor_known: false` audit row each (D36). One statement now, naming
    // the actor, stamping the run's `input_hash` onto every row it writes (I5),
    // and the same numbers into `analysis_results` so WP 5.3 can drop the
    // columns without changing what the product reports.
    const entries = Object.entries(metrics);
    let updatedCount = 0;
    try {
      updatedCount = await applyNodeMetrics(
        supabase, run.runId, uploaded_by,
        entries.map(([uid, m]) => ({
          uid,
          prominence: m.prominence,
          degree_centrality: m.degree_centrality,
          weighted_degree_centrality: m.weighted_degree_centrality,
          eigenvector_centrality: m.eigenvector_centrality,
          betweenness_centrality: m.betweenness_centrality,
          closeness_centrality: m.closeness_centrality,
        })),
      );

      const warnings = [...fallbackWarnings];
      if (updatedCount !== entries.length) {
        warnings.push({
          code: 'nodes_scored_but_not_stored',
          scored: entries.length,
          stored: updatedCount,
          meaning: 'metrics were computed for nodes that have no network_nodes row',
        });
      }

      await completeRun(
        supabase, run.runId, uploaded_by,
        entries.map(([uid, m]) => ({
          entity_type: 'node',
          entity_id: uid,
          metrics: {
            prominence: m.prominence,
            degree_centrality: m.degree_centrality,
            weighted_degree_centrality: m.weighted_degree_centrality,
            eigenvector_centrality: m.eigenvector_centrality,
            betweenness_centrality: m.betweenness_centrality,
            closeness_centrality: m.closeness_centrality,
          },
        })),
        { nodes: updatedCount, nodes_scored: entries.length, edges: effectiveEdges.length },
        warnings,
      );
    } catch (writeError) {
      await failRun(supabase, run.runId, uploaded_by,
        [{ code: 'write_failed', message: String(writeError) }]);
      throw writeError;
    }

    return new Response(
      JSON.stringify({
        success: true,
        cache_hit: false,
        run_id: run.runId,
        input_hash: run.inputHash,
        input_scope: run.inputScope,
        dataset_version_id: run.datasetVersionId,
        code_version: run.codeVersion,
        warnings: fallbackWarnings,
        nodes_processed: effectiveNodes.length,
        edges_processed: effectiveEdges.length,
        nodes_updated: updatedCount,
        metrics_summary: {
          avg_degree: Object.values(metrics).reduce((sum, m) => sum + m.degree_centrality, 0) / Object.keys(metrics).length,
          avg_eigenvector: Object.values(metrics).reduce((sum, m) => sum + m.eigenvector_centrality, 0) / Object.keys(metrics).length,
          avg_betweenness: Object.values(metrics).reduce((sum, m) => sum + m.betweenness_centrality, 0) / Object.keys(metrics).length,
          avg_closeness: Object.values(metrics).reduce((sum, m) => sum + m.closeness_centrality, 0) / Object.keys(metrics).length
        }
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );

  } catch (error) {
    console.error('Error in calculate-network-science-metrics function:', error);
    const errorMessage = error instanceof Error ? error.message : 'Unknown error occurred';
    return new Response(
      JSON.stringify({ error: errorMessage }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
