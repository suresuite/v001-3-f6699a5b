// One item's weekly charts in the inventory explorer (G17 / §9.5.1) — the
// in-app form of notebook 04's `plot_material`, plus its finished-goods twin.
// Every line is the engine's own weekly record except "Use", which is the
// named derived rule (`USE_RULE`) and is labelled as derived on the chart.

import {
  Area,
  Bar,
  CartesianGrid,
  ComposedChart,
  Legend,
  Line,
  ReferenceLine,
  ResponsiveContainer,
  Scatter,
  Tooltip as RTooltip,
  XAxis,
  YAxis,
} from "recharts";
import { STOCK_EPS, NOT_STOCKED, type ItemSeriesRow } from "@/lib/sim/inventoryExplorer";

const C = {
  stock: "hsl(215 80% 50%)",
  transit: "hsl(190 70% 40%)",
  target: "hsl(280 60% 55%)",
  zero: "hsl(0 75% 50%)",
  orders: "hsl(35 90% 55%)",
  use: "hsl(150 65% 35%)",
  demand: "hsl(220 15% 35%)",
  production: "hsl(150 65% 35%)",
  fulfillment: "hsl(215 80% 50%)",
  backlog: "hsl(0 70% 60%)",
  plan: "hsl(280 60% 55%)",
  mrp: ["hsl(25 95% 50%)", "hsl(215 80% 50%)", "hsl(190 70% 40%)", "hsl(150 65% 35%)"],
};

interface Props {
  row: ItemSeriesRow;
  title: string;
  warmupWeeks: number | null;
  /** A material's derived weekly use. */
  use?: number[];
  /** Whether this run recorded per-product FG stock at all. */
  fgRecorded: boolean;
  /** The legend name of an engine measure — the explorer's `SERIES_LABEL`, the
   *  one place those names are authored (`deriveItemSeries` reads it). */
  label: (key: string) => string;
}

const axis = { tick: { fontSize: 9 } };

/** "Use" is not an engine measure, so it has no `SERIES_LABEL` entry: the
 *  derived rule names itself. */
export const USE_LABEL = "Used (derived)";

function frame(series: Record<string, Array<number | null> | undefined>): Array<Record<string, number | null>> {
  const weeks = Math.max(0, ...Object.values(series).map((v) => v?.length ?? 0));
  return Array.from({ length: weeks }, (_, week) => {
    const row: Record<string, number | null> = { week };
    for (const [k, v] of Object.entries(series)) row[k] = v?.[week] ?? null;
    return row;
  });
}

function WarmUp({ weeks }: { weeks: number | null }) {
  if (weeks == null || weeks <= 0) return null;
  return (
    <ReferenceLine
      x={weeks}
      stroke="hsl(var(--destructive))"
      strokeDasharray="4 3"
      label={{ value: "warm-up", fontSize: 9, fill: "hsl(var(--destructive))" }}
    />
  );
}

function Chart({ data, height, children }: { data: object[]; height: number; children: React.ReactNode }) {
  // The x-axis is the run's weeks, pinned: a series with points in a few weeks
  // only (the stockout markers) must not narrow it to those weeks.
  const last = Math.max(0, data.length - 1);
  return (
    <ResponsiveContainer width="100%" height={height}>
      <ComposedChart data={data} margin={{ top: 6, right: 10, bottom: 0, left: 0 }}>
        <CartesianGrid strokeOpacity={0.15} />
        <XAxis dataKey="week" type="number" domain={[0, last]} allowDataOverflow {...axis} />
        <YAxis width={48} {...axis} />
        <RTooltip contentStyle={{ fontSize: 10 }} />
        <Legend wrapperStyle={{ fontSize: 10 }} />
        {children}
      </ComposedChart>
    </ResponsiveContainer>
  );
}

const line = (key: string, name: string, color: string, dashed = false) => (
  <Line
    key={key}
    type="monotone"
    dataKey={key}
    name={name}
    stroke={color}
    strokeWidth={dashed ? 1.2 : 1.6}
    strokeDasharray={dashed ? "5 3" : undefined}
    dot={false}
    isAnimationActive={false}
    connectNulls
  />
);

/** A week's marker: 0 (drawn at the axis) after warm-up where the stock was
 *  empty — and, for a product, demand was waiting — else no point. */
function stockouts(stock: number[], w0: number, demand?: number[]): Array<number | null> {
  return stock.map((v, t) => (t >= w0 && v <= STOCK_EPS && (!demand || (demand[t] ?? 0) > 0) ? 0 : null));
}

const markers = (weeks: Array<number | null>) =>
  weeks.some((v) => v !== null) ? (
    <Scatter dataKey="stockout" name="Stockout" fill={C.zero} shape="triangle" isAnimationActive={false} />
  ) : null;

function Note({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex min-h-[80px] items-center justify-center rounded border border-dashed px-3 py-4 text-center text-[11px] text-muted-foreground">
      {children}
    </div>
  );
}

export function ItemCharts({ row, title, warmupWeeks, use, fgRecorded, label }: Props) {
  const s = row.series;
  const w0 = Math.max(0, warmupWeeks ?? 0);

  if (row.kind === "material") {
    const mrpKeys = ["mrp_need", "mrp_on_hand", "mrp_on_the_way", "mrp_net"].filter(
      (k) => Array.isArray(s[k]) && s[k].some((v) => v !== 0),
    );
    const out = stockouts(s.on_hand ?? [], w0);
    const data = frame({
      on_hand: s.on_hand, in_transit: s.in_transit, orders: s.orders, use, stockout: out,
      ...Object.fromEntries(mrpKeys.map((k) => [k, s[k]])),
    });
    return (
      <figure className="min-w-0 rounded-md border bg-card p-2" data-testid="item-chart">
        <figcaption className="mb-1 min-w-0 break-words text-[11px] font-semibold">{title}</figcaption>
        <Chart data={data} height={190}>
          {line("on_hand", label("on_hand"), C.stock)}
          {line("in_transit", label("in_transit"), C.transit, true)}
          {markers(out)}
          <WarmUp weeks={warmupWeeks} />
        </Chart>
        <Chart data={data} height={140}>
          <Bar dataKey="orders" name={label("orders")} fill={C.orders} isAnimationActive={false} />
          {use && line("use", USE_LABEL, C.use)}
          <WarmUp weeks={warmupWeeks} />
        </Chart>
        {mrpKeys.length > 0 && (
          <Chart data={data} height={140}>
            {mrpKeys.map((k, i) => line(k, label(k), C.mrp[i % C.mrp.length]))}
            <WarmUp weeks={warmupWeeks} />
          </Chart>
        )}
      </figure>
    );
  }

  const mode = Array.isArray(s.make_to_stock) ? ((s.make_to_stock[0] ?? 0) >= 0.5 ? "mts" : "mto") : null;
  const out = stockouts(s.fg_on_hand ?? [], w0, s.demand);
  const data = frame({
    stockout: out,
    fg_on_hand: s.fg_on_hand, fg_target: s.fg_target, demand: s.demand, production: s.production,
    fulfillment: s.fulfillment, backlog: s.backlog, projected_demand: s.projected_demand, planned: s.planned,
  });
  return (
    <figure className="min-w-0 rounded-md border bg-card p-2" data-testid="item-chart">
      <figcaption className="mb-1 min-w-0 break-words text-[11px] font-semibold">{title}</figcaption>
      {!fgRecorded ? (
        <Note>
          This run predates per-product finished-goods stock; run a new inspection to see it.
        </Note>
      ) : mode === "mto" ? (
        <Note>
          <span>
            <strong className="text-foreground">{NOT_STOCKED[0].toUpperCase() + NOT_STOCKED.slice(1)}.</strong>{" "}
            This product is made to order and holds no finished-goods stock by design; its service
            is the backlog and lost units below.
          </span>
        </Note>
      ) : (
        <Chart data={data} height={190}>
          {line("fg_on_hand", label("fg_on_hand"), C.stock)}
          {line("fg_target", label("fg_target"), C.target, true)}
          {markers(out)}
          <WarmUp weeks={warmupWeeks} />
        </Chart>
      )}
      <Chart data={data} height={160}>
        <Area
          type="monotone"
          dataKey="backlog"
          name={label("backlog")}
          stroke={C.backlog}
          fill={C.backlog}
          fillOpacity={0.2}
          isAnimationActive={false}
        />
        {line("demand", label("demand"), C.demand)}
        {line("production", label("production"), C.production)}
        {line("fulfillment", label("fulfillment"), C.fulfillment)}
        {Array.isArray(s.projected_demand) && line("projected_demand", label("projected_demand"), C.plan, true)}
        {Array.isArray(s.planned) && line("planned", label("planned"), C.production, true)}
        <WarmUp weeks={warmupWeeks} />
      </Chart>
    </figure>
  );
}

