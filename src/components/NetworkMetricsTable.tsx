import React, { useState } from 'react';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Button } from '@/components/ui/button';
import { ToggleGroup, ToggleGroupItem } from '@/components/ui/toggle-group';
import { ArrowUpDown, ArrowUp, ArrowDown } from 'lucide-react';
import { rowFreshnessLabel } from '@/lib/network/storedMetrics';

interface NetworkMetric {
  id: string;
  uid: string;
  name: string;
  /**
   * §4 D313 — the weekly flow through this node on the Product-level graph: for a
   * material, the finished-goods demand propagated down the BOM to it; for a
   * supplier, its deliveries (its share of each material's demand). Neither has a
   * revenue, and the column that stood here read a FIRM's.
   */
  flow: number | null;
  degree_centrality: number | null;
  weighted_degree_centrality: number | null;
  eigenvector_centrality: number | null;
  betweenness_centrality: number | null;
  closeness_centrality: number | null;
  prominence: number | null;
  connection_count: number;
  /**
   * WP 6.3 · §4 D88 — WHICH HALF OF THE DUAL READ ANSWERED.
   *
   * `store`  — `analysis_results`, from a recorded run: reproducible, and it
   *            carries the hash of the dataset it was computed from.
   * `column` — the entity mirror on `network_nodes`, because the store has no row
   *            for this node. Legacy, written before provenance existed, and
   *            nothing can say which data produced it.
   * `none`   — neither half has a number. NOT zero (§4 D17).
   *
   * These arrive from `get_product_level_metrics` (§4 D313), which reads the
   * store only, so `column` no longer occurs on this page; the type keeps it
   * because the sentence below accounts for every value it could be. Optional on the type because the
   * page renders before the columns land and a partial dataset must not crash a
   * table; absent is treated exactly as `none` would be — unknown, said out loud.
   */
  metrics_source?: 'store' | 'column' | 'none' | null;
  run_id?: string | null;
  computed_from_hash?: string | null;
  computed_at?: string | null;
  /** NULL when there is no hash to compare. Unknown is not stale (D70). */
  hash_is_current?: boolean | null;
}

/**
 * The one-line account of where this table's numbers came from — §5 T2, at the
 * point of display.
 *
 * A screen that showed reproducible figures and legacy ones in the same font
 * would be T1 with the source silently removed, and that is the state every
 * project is in right now: 439 of 1 824 rows carry a hash and the rest predate
 * provenance (§15 run 35399391429). The columns cannot be dropped until every
 * project has been re-run, and the rows cannot be backfilled — inventing a hash is
 * the fabricated provenance I6 forbids — so the honest move is to SAY which.
 */
function provenanceSummary(metrics: NetworkMetric[]): string | null {
  if (metrics.length === 0) return null;
  const n = (k: NetworkMetric['metrics_source']) =>
    metrics.filter((m) => (m.metrics_source ?? 'none') === k).length;
  const store = n('store');
  const column = n('column');
  const none = n('none');
  // The stale count is only meaningful for rows that HAVE a hash, which is why it
  // is counted separately rather than folded into `store`.
  const stale = metrics.filter((m) => m.hash_is_current === false).length;
  const unknown = metrics.filter(
    (m) => (m.metrics_source ?? 'none') !== 'none' && m.hash_is_current == null,
  ).length;

  const parts: string[] = [];
  if (store > 0) parts.push(`${store} from a recorded analysis run`);
  if (column > 0) {
    parts.push(
      `${column} from values stored before this project tracked provenance — ` +
        `nothing can say which data produced them`,
    );
  }
  if (none > 0) parts.push(`${none} not computed yet`);
  if (parts.length === 0) return null;

  let out = `Where these numbers come from: ${parts.join('; ')}.`;
  if (stale > 0) {
    out +=
      ` ${stale} were computed from a different version of this dataset than the ` +
      `one loaded now — re-run the analysis before quoting them.`;
  }
  if (unknown > 0 && column > 0) {
    out += ` For ${unknown} of them we cannot tell, which is not the same as up to date.`;
  }
  return out;
}

/** Which echelon of the Product-level graph the table lists — the words differ, the measures do not. */
type TableEchelon = 'material' | 'supplier';

const WORDS: Record<TableEchelon, {
  title: string; plural: string; nameHeader: string; flow: string; empty: string;
}> = {
  material: {
    title: 'Nexus Materials',
    plural: 'purchased materials',
    nameHeader: 'Material Name',
    flow: 'Demand propagated to the material',
    empty: 'No purchased material',
  },
  supplier: {
    title: 'Nexus Suppliers',
    plural: 'suppliers',
    nameHeader: 'Supplier Name',
    flow: "The supplier's share of its materials' demand",
    empty: 'No supplier',
  },
};

interface NetworkMetricsTableProps {
  metrics: NetworkMetric[];
  loading?: boolean;
  /** Defaults to `material`, the table this page always had. */
  echelon?: TableEchelon;
}

type SortField = keyof NetworkMetric;

/** Rows a table shows at once; `all` shows every row. Default 10. */
export const PAGE_SIZES = ['10', '20', '50', 'all'] as const;
type PageSize = (typeof PAGE_SIZES)[number];

/** How each sortable column is named in the sentence above the table. */
const SORT_LABEL: Partial<Record<SortField, string>> = {
  name: 'name',
  connection_count: 'connections',
  flow: 'weekly flow',
  degree_centrality: 'degree',
  weighted_degree_centrality: 'weighted degree',
  eigenvector_centrality: 'eigenvector centrality',
  betweenness_centrality: 'betweenness centrality',
  closeness_centrality: 'closeness centrality',
  prominence: 'prominence',
};
type SortDirection = 'asc' | 'desc' | null;

export function NetworkMetricsTable({ metrics, loading = false, echelon = 'material' }: NetworkMetricsTableProps) {
  const words = WORDS[echelon];
  const [sortField, setSortField] = useState<SortField>('betweenness_centrality');
  const [sortDirection, setSortDirection] = useState<SortDirection>('desc');
  const [pageSize, setPageSize] = useState<PageSize>('10');
  
  const displayLimit = pageSize === 'all' ? Infinity : Number(pageSize);

  const handleSort = (field: SortField) => {
    if (sortField === field) {
      setSortDirection(sortDirection === 'asc' ? 'desc' : sortDirection === 'desc' ? null : 'asc');
    } else {
      setSortField(field);
      setSortDirection('desc');
    }
  };

  const sortedMetrics = React.useMemo(() => {
    if (!sortField || !sortDirection) return metrics.slice(0, displayLimit);

    const sorted = [...metrics].sort((a, b) => {
      const aVal = a[sortField];
      const bVal = b[sortField];
      
      // Handle null values
      if (aVal === null && bVal === null) return 0;
      if (aVal === null) return 1;
      if (bVal === null) return -1;
      
      const comparison = aVal < bVal ? -1 : aVal > bVal ? 1 : 0;
      return sortDirection === 'asc' ? comparison : -comparison;
    });
    
    return sorted.slice(0, displayLimit);
  }, [metrics, sortField, sortDirection, displayLimit]);

  const formatNumber = (value: number | null, decimals = 3) => {
    if (value === null) return '-';
    return value.toFixed(decimals);
  };

  const formatFlow = (value: number | null) => {
    if (value === null) return '-';
    if (value > 0 && value < 1) return '<1';
    return Math.round(value).toLocaleString('en-US');
  };

  const getSortIcon = (field: SortField) => {
    if (sortField !== field) return <ArrowUpDown className="h-4 w-4" />;
    if (sortDirection === 'asc') return <ArrowUp className="h-4 w-4" />;
    if (sortDirection === 'desc') return <ArrowDown className="h-4 w-4" />;
    return <ArrowUpDown className="h-4 w-4" />;
  };

  const getProminenceColor = (prominence: number | null) => {
    if (prominence === null) return '';
    if (prominence >= 0.8) return 'text-destructive font-semibold';
    if (prominence >= 0.6) return 'text-warning font-medium';
    if (prominence >= 0.4) return 'text-primary';
    return 'text-muted-foreground';
  };

  if (loading) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Network Science Metrics - {words.title}</CardTitle>
          <CardDescription>Computing network centrality on the product-level graph…</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="flex items-center justify-center h-32">
            <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary"></div>
          </div>
        </CardContent>
      </Card>
    );
  }

  if (metrics.length === 0) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Network Science Metrics - {words.title}</CardTitle>
          <CardDescription>No network metrics are stored for this graph's {words.plural}.</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="text-center text-muted-foreground py-8">
            {words.empty} on the product-level graph has computed metrics yet. Use
            Recalculate to compute them; a project whose lanes are empty must be combined first.
          </div>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Network Science Metrics - {words.title}</CardTitle>
        <CardDescription>
          {sortedMetrics.length >= metrics.length
            ? `Network centrality of ${metrics.length} ${words.plural} on the product-level graph.`
            : `${sortedMetrics.length} of ${metrics.length} ${words.plural}` +
              (sortField && sortDirection
                ? `, ${sortDirection === 'desc' ? 'highest' : 'lowest'} ${SORT_LABEL[sortField] ?? String(sortField)} first.`
                : '.')
          } Computed on the graph drawn above — suppliers, materials, finished products and customers, the BOM collapsed. Higher values indicate more critical positions.
        </CardDescription>
        {/* §4 D88 · T2 — the substitution is visible where the numbers are, not in
            a log. `provenanceSummary` returns null only when the table is empty,
            so a populated table always accounts for itself. */}
        {provenanceSummary(metrics) && (
          <p className="mt-1.5 text-[12px] leading-snug text-muted-foreground">
            {provenanceSummary(metrics)}
          </p>
        )}
      </CardHeader>
      <CardContent>
        <div className="rounded-md border overflow-x-auto">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead className="min-w-[120px]">
                  <Button
                    variant="ghost"
                    size="sm"
                    className="h-auto p-0 font-semibold text-white hover:bg-transparent hover:text-white"
                    onClick={() => handleSort('name')}
                  >
                    {words.nameHeader}
                    {getSortIcon('name')}
                  </Button>
                </TableHead>
                <TableHead className="text-right">
                  <Button
                    variant="ghost"
                    size="sm"
                    className="h-auto p-0 font-semibold text-white hover:bg-transparent hover:text-white"
                    onClick={() => handleSort('connection_count')}
                  >
                    Connections
                    {getSortIcon('connection_count')}
                  </Button>
                </TableHead>
                <TableHead className="text-right">
                  <Button
                    variant="ghost"
                    size="sm"
                    className="h-auto p-0 font-semibold text-white hover:bg-transparent hover:text-white"
                    onClick={() => handleSort('flow')}
                  >
                    Weekly flow
                    {getSortIcon('flow')}
                  </Button>
                </TableHead>
                <TableHead className="text-right">
                  <Button
                    variant="ghost"
                    size="sm"
                    className="h-auto p-0 font-semibold text-white hover:bg-transparent hover:text-white"
                    onClick={() => handleSort('degree_centrality')}
                  >
                    Degree
                    {getSortIcon('degree_centrality')}
                  </Button>
                </TableHead>
                <TableHead className="text-right">
                  <Button
                    variant="ghost"
                    size="sm"
                    className="h-auto p-0 font-semibold text-white hover:bg-transparent hover:text-white"
                    onClick={() => handleSort('weighted_degree_centrality')}
                  >
                    Wtd. Degree
                    {getSortIcon('weighted_degree_centrality')}
                  </Button>
                </TableHead>
                <TableHead className="text-right">
                  <Button
                    variant="ghost"
                    size="sm"
                    className="h-auto p-0 font-semibold text-white hover:bg-transparent hover:text-white"
                    onClick={() => handleSort('eigenvector_centrality')}
                  >
                    Eigenvector
                    {getSortIcon('eigenvector_centrality')}
                  </Button>
                </TableHead>
                <TableHead className="text-right">
                  <Button
                    variant="ghost"
                    size="sm"
                    className="h-auto p-0 font-semibold text-white hover:bg-transparent hover:text-white"
                    onClick={() => handleSort('betweenness_centrality')}
                  >
                    Betweenness
                    {getSortIcon('betweenness_centrality')}
                  </Button>
                </TableHead>
                <TableHead className="text-right">
                  <Button
                    variant="ghost"
                    size="sm"
                    className="h-auto p-0 font-semibold text-white hover:bg-transparent hover:text-white"
                    onClick={() => handleSort('closeness_centrality')}
                  >
                    Closeness
                    {getSortIcon('closeness_centrality')}
                  </Button>
                </TableHead>
                <TableHead className="text-right">
                  <Button
                    variant="ghost"
                    size="sm"
                    className="h-auto p-0 font-semibold text-white hover:bg-transparent hover:text-white"
                    onClick={() => handleSort('prominence')}
                  >
                    Prominence
                    {getSortIcon('prominence')}
                  </Button>
                </TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {sortedMetrics.map((metric) => (
                <TableRow key={metric.id}>
                  <TableCell className="font-medium">
                    {metric.name || metric.uid}
                    {/* WP 10.1 · freshness PER ROW, beside the number (T2): only a
                        current stored figure goes unmarked. */}
                    {rowFreshnessLabel(metric) !== 'current' && (
                      <span className="ml-1.5 font-mono text-[10.5px] font-normal text-muted-foreground">
                        {rowFreshnessLabel(metric)}
                      </span>
                    )}
                  </TableCell>
                  <TableCell className="text-right">
                    {metric.connection_count}
                  </TableCell>
                  <TableCell className="text-right">
                    {formatFlow(metric.flow)}
                  </TableCell>
                  <TableCell className="text-right font-mono text-sm">
                    {formatNumber(metric.degree_centrality)}
                  </TableCell>
                  <TableCell className="text-right font-mono text-sm">
                    {formatNumber(metric.weighted_degree_centrality)}
                  </TableCell>
                  <TableCell className="text-right font-mono text-sm">
                    {formatNumber(metric.eigenvector_centrality)}
                  </TableCell>
                  <TableCell className="text-right font-mono text-sm">
                    {formatNumber(metric.betweenness_centrality)}
                  </TableCell>
                  <TableCell className="text-right font-mono text-sm">
                    {formatNumber(metric.closeness_centrality)}
                  </TableCell>
                  <TableCell className={`text-right font-mono text-sm ${getProminenceColor(metric.prominence)}`}>
                    {formatNumber(metric.prominence)}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
        
        {metrics.length > Number(PAGE_SIZES[0]) && (
          <div className="mt-4 flex flex-wrap items-center justify-end gap-2 text-sm text-muted-foreground">
            <span>Rows</span>
            <ToggleGroup
              type="single"
              value={pageSize}
              onValueChange={(v) => v && setPageSize(v as PageSize)}
              aria-label={`Rows of ${words.plural} to show`}
            >
              {PAGE_SIZES.map((size) => (
                <ToggleGroupItem key={size} value={size} className="h-7 min-h-11 px-2 text-xs md:min-h-0">
                  {size === 'all' ? `All (${metrics.length})` : size}
                </ToggleGroupItem>
              ))}
            </ToggleGroup>
          </div>
        )}
        
        <div className="mt-4 text-sm text-muted-foreground">
          <div className="flex flex-wrap gap-4">
            <span><strong>Degree:</strong> Connection ratio to max possible</span>
            <span><strong>Weekly flow:</strong> {words.flow}</span>
            <span><strong>Wtd. degree:</strong> Flow-weighted connections</span>
            <span><strong>Eigenvector:</strong> Connected to important nodes</span>
            <span><strong>Betweenness:</strong> Bridge between network clusters</span>
            <span><strong>Closeness:</strong> Reachable nodes over total distance to them</span>
            <span><strong>Prominence:</strong> Overall network importance</span>
          </div>
        </div>
      </CardContent>
    </Card>
  );
}