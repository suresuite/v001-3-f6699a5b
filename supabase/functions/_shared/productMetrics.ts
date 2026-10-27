/**
 * §4 D313 · the Product-level view's network metrics — computed on the graph the
 * page DRAWS, stored once, read by `get_product_level_metrics`.
 *
 * WHY A KIND OF ITS OWN. `network_metrics` reads the FIRM graph (or, when the deep
 * tier is incomplete, the raw lane rows) and mirrors onto `network_nodes`. The
 * Product-level page then showed "materials" by joining that firm table to material
 * ids on a bare string (D137): whenever a project held a deep-tier network the table
 * was empty, and the analyzer answered "reused" for a run about another graph. This
 * kind's nodes are the four echelons the page draws — supplier, purchased material,
 * finished product, customer — built by the SAME function the page calls
 * (`buildProductLevelGraph`), from the same rows (`supply_chain_data`, every plant,
 * the multi-tier lane excluded), so a node in the table is a node on the canvas.
 *
 * WHY ITS KEY IS THE PROCESS LEVEL, NOT THE PRODUCT LEVEL. `supply_chain_data` is
 * rebuilt by `rebuild_supply_chain_lanes`, which reads `bom_multi_level` — and the
 * product-level hash does not cover `bom_multi_level`. The process-level hash covers
 * exactly the columns that rebuild reads (`20261001000007` §1), so it is the hash
 * that moves whenever this graph can. `critical_nodes` reads the same lanes and keys
 * on the same level for the same reason.
 *
 * STORE ONLY. Results land in `analysis_results` with `entity_type` = the node's
 * echelon and `entity_id` = its id. There is no entity mirror: no table's rows are
 * this graph's nodes, and a mirror is the thing WP 6.5 (b) exists to drop.
 */
import { buildProductLevelGraph, type FlatLaneRow } from "./productGraph.ts";
import { calculateCentralities } from "./centrality.ts";
import { completeRun, failRun, getOrStart, type StoreClient } from "./analysisStore.ts";

/** Part of the store's key. Bump when the graph rule or the metrics change. */
export const PRODUCT_METRICS_CODE_VERSION = "product_metrics@d313.1";

const PAGE = 1000;

/**
 * One page of the project's `supply_chain_data`, rows `from`…`to` inclusive in a
 * stable order. The caller owns the client, so this module needs no query-builder
 * type of its own.
 */
export type LanePageReader = (
  from: number,
  to: number,
) => PromiseLike<{ data: unknown; error: { message?: string } | null }>;

/** The columns `readPage` must select. */
export const LANE_COLUMNS =
  "id,data_source,plant_name,from_location,to_location,material_consumption_rate,sourcing_ratio,weighted";

export interface ProductMetricsResult {
  status: number;
  body: Record<string, unknown>;
}

/** Every lane row of the project, paged so `max_rows` cannot truncate it (§4 D200). */
async function readLanes(readPage: LanePageReader): Promise<FlatLaneRow[]> {
  const rows: FlatLaneRow[] = [];
  for (let from = 0; ; from += PAGE) {
    const { data, error } = await readPage(from, from + PAGE - 1);
    if (error) throw new Error(error.message ?? String(error));
    const page = (data ?? []) as Array<FlatLaneRow & { id: string }>;
    for (const r of page) {
      if ((r.data_source ?? "").toLowerCase() === "multi_tier") continue;
      rows.push({ ...r, weighted: r.weighted == null ? null : Number(r.weighted),
        material_consumption_rate: r.material_consumption_rate == null ? null : Number(r.material_consumption_rate) });
    }
    if (page.length < PAGE) break;
  }
  return rows;
}

/** The graph and its metrics — pure, so the test suite runs exactly what the analyzer does. */
export function productLevelMetrics(rows: readonly FlatLaneRow[]) {
  const graph = buildProductLevelGraph(rows);
  // The page hides a node no edge touches; so does the analysis, or a disconnected
  // node would enter every normalisation the drawn ones are measured against.
  const touched = new Set<string>();
  graph.edges.forEach((e) => { touched.add(e.source); touched.add(e.target); });
  const nodes = [...graph.nodes.keys()].filter((uid) => touched.has(uid)).map((uid) => ({ uid }));

  // Flow is the propagated weekly demand; normalised to the graph's largest edge so
  // the weighted measures do not depend on the unit. A zero-flow edge carries no
  // demand and weighs 0 — it still counts for degree, betweenness and closeness,
  // which are topological.
  const maxFlow = Math.max(0, ...graph.edges.map((e) => e.flow));
  const metrics = calculateCentralities(
    nodes,
    graph.edges.map((e) => ({ source: e.source, target: e.target, weight: maxFlow > 0 ? e.flow / maxFlow : 0 })),
    { exact: true },
  );

  // A node's flow per week, read on the edges it SENDS: a supplier's deliveries, a
  // material's demand propagated from every product it ends up in (the sum of its
  // material → product edges, 0 when it reaches none), a product's outbound volume.
  // A customer sends nothing, so its flow is what it receives. Inflow is not used for
  // a product: it sums quantities of different materials, which have no common unit.
  const inflow = new Map<string, number>();
  const outflow = new Map<string, number>();
  graph.edges.forEach((e) => {
    inflow.set(e.target, (inflow.get(e.target) ?? 0) + e.flow);
    outflow.set(e.source, (outflow.get(e.source) ?? 0) + e.flow);
  });

  const results = nodes.map(({ uid }) => {
    const echelon = graph.nodes.get(uid)!.echelon;
    return {
      entity_type: echelon,
      entity_id: uid,
      metrics: {
        ...metrics[uid],
        flow: echelon === "customer" ? (inflow.get(uid) ?? 0) : (outflow.get(uid) ?? 0),
      },
    };
  });
  return { graph, results, edgeCount: graph.edges.length };
}

export async function computeProductMetrics(
  client: StoreClient,
  projectId: string,
  actorUserId: string,
  readPage: LanePageReader,
): Promise<ProductMetricsResult> {
  const run = await getOrStart(client, {
    projectId,
    analysisKind: "product_metrics",
    params: { graph: "product_level", weighted: "flow", exact: true },
    codeVersion: PRODUCT_METRICS_CODE_VERSION,
    actorUserId,
  });

  const stamp = {
    run_id: run.runId, input_hash: run.inputHash, input_scope: run.inputScope,
    dataset_version_id: run.datasetVersionId, code_version: run.codeVersion,
  };

  if (run.cacheHit) {
    return { status: 200, body: { success: true, cache_hit: true, ...stamp,
      nodes_stored: (run.rowCounts as { nodes?: number } | undefined)?.nodes ?? 0 } };
  }
  if (run.claimedByOther && run.status === "running") {
    return { status: 202, body: { success: true, cache_hit: false, in_progress: true, run_id: run.runId,
      message: "another request is already computing this exact analysis" } };
  }

  try {
    if (run.inputScope !== "process") {
      throw new Error(`analysis_kinds declares product_metrics over the process level; the store resolved ${run.inputScope}`);
    }
    const rows = await readLanes(readPage);
    const { graph, results, edgeCount } = productLevelMetrics(rows);

    // T3 — the limits of this computation travel with the run.
    const warnings: Array<Record<string, unknown>> = [];
    if (graph.unreachedMaterials.length > 0) {
      warnings.push({
        code: "materials_reach_no_product",
        count: graph.unreachedMaterials.length,
        sample: graph.unreachedMaterials.slice(0, 10),
        meaning: "these purchased materials reach no finished product through the BOM, so they have no "
          + "material → product edge; their metrics describe their supplier edges only",
      });
    }
    if (results.length === 0) {
      warnings.push({ code: "empty_graph", lane_rows: rows.length,
        meaning: "the product-level graph has no edges — combine the project to rebuild its lanes" });
    }

    const count = (e: string) => results.filter((r) => r.entity_type === e).length;
    await completeRun(client, run.runId, actorUserId, results, {
      nodes: results.length, edges: edgeCount, lane_rows: rows.length,
      suppliers: count("supplier"), materials: count("material"),
      products: count("product"), customers: count("customer"),
      collapsed_intermediates: graph.collapsedIntermediates,
    }, warnings);

    return { status: 200, body: { success: true, cache_hit: false, ...stamp,
      nodes_stored: results.length, edges_processed: edgeCount, warnings } };
  } catch (err) {
    await failRun(client, run.runId, actorUserId,
      [{ code: "product_metrics_failed", message: String((err as { message?: string })?.message ?? err) }]);
    return { status: 500, body: { success: false, run_id: run.runId,
      error: `product_metrics failed: ${String((err as { message?: string })?.message ?? err)}` } };
  }
}
