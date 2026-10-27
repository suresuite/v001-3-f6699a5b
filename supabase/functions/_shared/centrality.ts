/**
 * Node centralities and the prominence composite — written ONCE.
 *
 * Moved out of `calculate-network-science-metrics/index.ts` when the analyzer
 * gained its second graph (kind `product_metrics`, the Product-level view's
 * four-echelon graph). Two analyzers with a copy each would be two definitions of
 * "betweenness" a quarter from now; this is the one.
 *
 * The graph is read UNDIRECTED: a material's betweenness is how often it sits on
 * the shortest path between two other nodes, whichever way the goods flow.
 *
 * TWO MODES, AND WHY THE LEGACY ONE STAYS THE DEFAULT. The firm-level kind
 * (`network_metrics`) has always (a) sampled betweenness from the FIRST 50 nodes
 * and (b) run plain power iteration for the eigenvector. Both are approximations
 * with a known failure: on the product graph the first 50 nodes are all suppliers,
 * and the graph is LAYERED (supplier → material → product → customer), hence
 * bipartite, where plain power iteration oscillates between two vectors and never
 * converges. `exact: true` computes betweenness from every source (Brandes) and
 * iterates on A + I, which has the same leading eigenvector and does converge.
 * The legacy kind keeps its numbers — changing them is a change to that kind's
 * `CODE_VERSION`, owned by whoever takes it — and the product kind is exact.
 */

export interface CentralityNode {
  uid: string;
}

/** One relationship. `weight` is already resolved by the caller (no defaulting here). */
export interface CentralityEdge {
  source: string;
  target: string;
  weight: number;
}

export interface NodeCentrality {
  /** Distinct neighbours. */
  connections: number;
  degree_centrality: number;
  weighted_degree_centrality: number;
  eigenvector_centrality: number;
  betweenness_centrality: number;
  closeness_centrality: number;
  prominence: number;
}

export interface CentralityOptions {
  /** Exact betweenness and a shifted eigenvector iteration — see the header. */
  exact?: boolean;
}

type Adjacency = Map<string, Map<string, number>>;

export function calculateCentralities(
  nodes: readonly CentralityNode[],
  edges: readonly CentralityEdge[],
  options: CentralityOptions = {},
): Record<string, NodeCentrality> {
  const exact = options.exact === true;
  const adjacency: Adjacency = new Map();
  nodes.forEach((n) => adjacency.set(n.uid, new Map()));

  edges.forEach((e) => {
    if (e.source === e.target) return;
    const a = adjacency.get(e.source);
    const b = adjacency.get(e.target);
    if (!a || !b) return;
    if (exact) {
      // Two drawn edges between one pair (a → b and b → a) are one undirected
      // relationship whose weight is their sum.
      a.set(e.target, (a.get(e.target) ?? 0) + e.weight);
      b.set(e.source, (b.get(e.source) ?? 0) + e.weight);
    } else {
      a.set(e.target, e.weight);
      b.set(e.source, e.weight);
    }
  });

  const weightedDegree = new Map<string, number>();
  nodes.forEach((n) => {
    let sum = 0;
    adjacency.get(n.uid)!.forEach((w) => (sum += w));
    weightedDegree.set(n.uid, sum);
  });
  const maxWeightedDegree = Math.max(...weightedDegree.values(), 1);

  const out: Record<string, NodeCentrality> = {};
  nodes.forEach((n) => {
    const degree = adjacency.get(n.uid)!.size;
    const maxPossibleDegree = nodes.length - 1;
    out[n.uid] = {
      connections: degree,
      degree_centrality: maxPossibleDegree > 0 ? degree / maxPossibleDegree : 0,
      weighted_degree_centrality: weightedDegree.get(n.uid)! / maxWeightedDegree,
      eigenvector_centrality: 0,
      betweenness_centrality: 0,
      closeness_centrality: 0,
      prominence: 0,
    };
  });

  const eigen = eigenvectorCentrality(nodes, adjacency, exact);
  const betweenness = exact ? exactBetweenness(nodes, adjacency) : sampledBetweenness(nodes, adjacency);
  const closeness = closenessCentrality(nodes, adjacency);
  nodes.forEach((n) => {
    out[n.uid].eigenvector_centrality = eigen[n.uid] ?? 0;
    out[n.uid].betweenness_centrality = betweenness[n.uid] ?? 0;
    out[n.uid].closeness_centrality = closeness[n.uid] ?? 0;
  });

  // Prominence: a weighted composite, betweenness and closeness normalised to the
  // graph's own maximum (floored at 1, as it always was).
  const all = Object.values(out);
  const maxBetweenness = Math.max(...all.map((m) => m.betweenness_centrality), 1);
  const maxCloseness = Math.max(...all.map((m) => m.closeness_centrality), 1);
  all.forEach((m) => {
    m.prominence =
      0.25 * m.degree_centrality +
      0.35 * m.eigenvector_centrality + // highest weight: neighbour influence
      0.25 * (m.betweenness_centrality / maxBetweenness) + // bottleneck risk
      0.15 * (m.closeness_centrality / maxCloseness); // reachability
  });

  return out;
}

function eigenvectorCentrality(nodes: readonly CentralityNode[], adjacency: Adjacency, shifted: boolean) {
  const centrality: Record<string, number> = {};
  const ids = nodes.map((n) => n.uid);
  ids.forEach((uid) => (centrality[uid] = 1));

  const maxIterations = shifted ? 1000 : 100;
  const tolerance = 1e-6;

  for (let iter = 0; iter < maxIterations; iter++) {
    const next: Record<string, number> = {};
    let norm = 0;
    ids.forEach((uid) => {
      // (A + I)·x when shifted: same leading eigenvector, no oscillation on a
      // bipartite graph.
      let v = shifted ? centrality[uid] : 0;
      adjacency.get(uid)!.forEach((w, nb) => (v += w * centrality[nb]));
      next[uid] = v;
      norm += v * v;
    });
    norm = Math.sqrt(norm);
    if (norm > 0) ids.forEach((uid) => (next[uid] /= norm));

    let converged = true;
    for (const uid of ids) {
      if (Math.abs(next[uid] - centrality[uid]) > tolerance) { converged = false; break; }
    }
    Object.assign(centrality, next);
    if (converged) break;
  }
  return centrality;
}

/** One BFS from `source`, with the shortest-path counts Brandes needs. */
function shortestPaths(nodes: readonly CentralityNode[], adjacency: Adjacency, source: string) {
  const distance = new Map<string, number>();
  const sigma = new Map<string, number>();
  const predecessors = new Map<string, string[]>();
  nodes.forEach((n) => { sigma.set(n.uid, 0); predecessors.set(n.uid, []); });
  distance.set(source, 0);
  sigma.set(source, 1);

  const order: string[] = [];
  const queue = [source];
  for (let head = 0; head < queue.length; head++) {
    const current = queue[head];
    order.push(current);
    const d = distance.get(current)!;
    adjacency.get(current)!.forEach((_w, nb) => {
      if (!distance.has(nb)) {
        distance.set(nb, d + 1);
        queue.push(nb);
      }
      if (distance.get(nb) === d + 1) {
        sigma.set(nb, sigma.get(nb)! + sigma.get(current)!);
        predecessors.get(nb)!.push(current);
      }
    });
  }
  return { distance, sigma, predecessors, order };
}

function accumulate(
  nodes: readonly CentralityNode[],
  adjacency: Adjacency,
  sources: readonly CentralityNode[],
  centrality: Record<string, number>,
) {
  for (const s of sources) {
    const { sigma, predecessors, order } = shortestPaths(nodes, adjacency, s.uid);
    const dependency = new Map<string, number>();
    for (let i = order.length - 1; i >= 0; i--) {
      const w = order[i];
      const dw = dependency.get(w) ?? 0;
      for (const v of predecessors.get(w)!) {
        dependency.set(v, (dependency.get(v) ?? 0) + (sigma.get(v)! / sigma.get(w)!) * (1 + dw));
      }
      if (w !== s.uid) centrality[w] += dw;
    }
  }
}

/** Brandes from every source; undirected, so each pair is counted twice and halved. */
function exactBetweenness(nodes: readonly CentralityNode[], adjacency: Adjacency) {
  const centrality: Record<string, number> = {};
  nodes.forEach((n) => (centrality[n.uid] = 0));
  accumulate(nodes, adjacency, nodes, centrality);
  const n = nodes.length;
  // Halving for the double count, then 2 / ((n−1)(n−2)): together 1 / ((n−1)(n−2)).
  const norm = n > 2 ? 1 / ((n - 1) * (n - 2)) : 1;
  Object.keys(centrality).forEach((uid) => (centrality[uid] *= norm));
  return centrality;
}

/** The legacy approximation: sources are the first 50 nodes in the order given. */
function sampledBetweenness(nodes: readonly CentralityNode[], adjacency: Adjacency) {
  const centrality: Record<string, number> = {};
  nodes.forEach((n) => (centrality[n.uid] = 0));
  accumulate(nodes, adjacency, nodes.slice(0, Math.min(50, nodes.length)), centrality);
  const n = nodes.length;
  const norm = n > 2 ? 2 / ((n - 1) * (n - 2)) : 1;
  Object.keys(centrality).forEach((uid) => (centrality[uid] *= norm));
  return centrality;
}

/** Reachable nodes over total distance to them — per component, as it always was. */
function closenessCentrality(nodes: readonly CentralityNode[], adjacency: Adjacency) {
  const centrality: Record<string, number> = {};
  nodes.forEach((s) => {
    const { distance } = shortestPaths(nodes, adjacency, s.uid);
    let reached = 0;
    let total = 0;
    distance.forEach((d) => { if (d > 0) { reached++; total += d; } });
    centrality[s.uid] = reached > 0 ? reached / total : 0;
  });
  return centrality;
}
