// The inventory explorer's ranked table (G17 / §9.5.1) — notebook 04's
// `material_table`, and its finished-goods twin. Rows arrive already ranked
// (`materialTable` / `productTable`); this only draws them, with a checkbox per
// row. Mobile keeps the table and scrolls it sideways with the identifying
// column frozen (docs/mobile-ui-spec.md §2.7) — the column set is the information.

import { Checkbox } from "@/components/ui/checkbox";
import { cn } from "@/lib/utils";
import { NOT_STOCKED, type MaterialRow, type ProductRow } from "@/lib/sim/inventoryExplorer";

const DASH = "\u2014";

const num = (v: number | null, digits = 1): string =>
  v === null || !Number.isFinite(v)
    ? DASH
    : v.toLocaleString(undefined, { maximumFractionDigits: digits, minimumFractionDigits: 0 });
const pct = (v: number | null): string => (v === null ? DASH : `${(v * 100).toFixed(1)}%`);

const TH = "px-2 py-1.5 text-left font-mono text-[10px] font-medium uppercase tracking-[0.04em] text-muted-foreground";
const TD = "px-2 py-1 text-right tabular-nums";
const STICKY = "sticky left-0 z-[1] bg-card";

interface Common {
  selected: Set<string>;
  onToggle: (id: string) => void;
}

function SelectCell({ id, label, sub, checked, onToggle }: {
  id: string; label: string | null; sub?: string; checked: boolean; onToggle: (id: string) => void;
}) {
  return (
    <td className={cn(STICKY, "max-w-[11rem] px-2 py-1 text-left")}>
      <label className="-my-[11px] flex min-h-11 cursor-pointer items-center gap-2 py-[11px] md:my-0 md:min-h-0 md:py-0">
        <Checkbox
          checked={checked}
          onCheckedChange={() => onToggle(id)}
          aria-label={`Select ${id}`}
          className="shrink-0"
        />
        <span className="min-w-0">
          <span className="block truncate font-mono text-[11px]" title={id}>{id}</span>
          {(label || sub) && (
            <span className="block truncate text-[10px] text-muted-foreground" title={label ?? sub}>
              {label ?? sub}
            </span>
          )}
        </span>
      </label>
    </td>
  );
}

function Frame({ head, children, count }: { head: string[]; children: React.ReactNode; count: number }) {
  return (
    <>
      <div className="max-h-[360px] overflow-auto rounded border">
        <table className="w-full border-collapse whitespace-nowrap text-[11px]">
          <thead className="sticky top-0 z-[2] bg-muted/60 backdrop-blur">
            <tr>
              {head.map((h, i) => (
                <th key={h} className={cn(TH, i === 0 && cn(STICKY, "bg-muted"), i > 0 && "text-right")}>{h}</th>
              ))}
            </tr>
          </thead>
          <tbody className="divide-y divide-border">{children}</tbody>
        </table>
      </div>
      {count > 0 && (
        <p className="mt-1 text-[10px] text-muted-foreground md:hidden">
          swipe the table sideways for the remaining columns
        </p>
      )}
    </>
  );
}

export function MaterialTable({ rows, selected, onToggle }: Common & { rows: MaterialRow[] }) {
  return (
    <Frame
      count={rows.length}
      head={["Material", "Suppliers", "Avg on hand", "Min on hand", "Weeks at zero", "First stockout",
        "Avg in transit", "Avg use / wk (derived)", "Min cover (wk)", "Ordered"]}
    >
      {rows.map((r) => (
        <tr key={r.id} className={cn(selected.has(r.id) && "bg-primary/5")} data-testid="material-row">
          <SelectCell id={r.id} label={r.name} checked={selected.has(r.id)} onToggle={onToggle} />
          <td className="max-w-[10rem] truncate px-2 py-1 text-left" title={r.suppliers.join(", ")}>
            {r.suppliers.join(", ") || DASH}
          </td>
          <td className={TD}>{num(r.avgOnHand)}</td>
          <td className={TD}>{num(r.minOnHand)}</td>
          <td className={cn(TD, r.weeksAtZero > 0 && "font-semibold text-destructive")}>{r.weeksAtZero}</td>
          <td className={TD}>{r.firstStockout === null ? DASH : `wk ${r.firstStockout}`}</td>
          <td className={TD}>{num(r.avgInTransit)}</td>
          <td className={TD}>{num(r.avgUsePerWeek)}</td>
          <td className={TD}>{num(r.minCoverWeeks)}</td>
          <td className={TD}>{num(r.ordered, 0)}</td>
        </tr>
      ))}
    </Frame>
  );
}

export function ProductTable({ rows, selected, onToggle }: Common & { rows: ProductRow[] }) {
  return (
    <Frame
      count={rows.length}
      head={["Finished good", "Mode", "Avg FG on hand", "Min FG on hand", "Avg FG target",
        "Weeks at zero (demand > 0)", "First stockout", "Weeks of cover", "Fill rate", "Avg backlog", "Lost units"]}
    >
      {rows.map((r) => (
        <tr key={r.id} className={cn(selected.has(r.id) && "bg-primary/5")} data-testid="product-row">
          <SelectCell id={r.id} label={r.name} checked={selected.has(r.id)} onToggle={onToggle} />
          <td className="px-2 py-1 text-left">
            {r.mode === "mts" ? "Make-to-stock" : r.mode === "mto" ? "Make-to-order" : DASH}
          </td>
          {r.mode === "mts" ? (
            <>
              <td className={TD}>{num(r.avgFgOnHand)}</td>
              <td className={TD}>{num(r.minFgOnHand)}</td>
              <td className={TD}>{num(r.avgFgTarget)}</td>
              <td className={cn(TD, (r.weeksAtZero ?? 0) > 0 && "font-semibold text-destructive")}>
                {r.weeksAtZero ?? DASH}
              </td>
              <td className={TD}>{r.firstStockout === null ? DASH : `wk ${r.firstStockout}`}</td>
              <td className={TD}>{num(r.weeksOfCover)}</td>
            </>
          ) : (
            // A make-to-order product holds no FG stock BY DESIGN: one cell says
            // so across the six stock columns, rather than six zeros claiming a
            // measured stockout. A run that predates the record says that instead.
            <td colSpan={6} className="px-2 py-1 text-center italic text-muted-foreground">
              {r.mode === "mto" ? NOT_STOCKED : "not recorded by this run"}
            </td>
          )}
          <td className={TD}>{pct(r.fillRate)}</td>
          <td className={TD}>{num(r.avgBacklog)}</td>
          <td className={cn(TD, r.lostUnits > 0 && "font-semibold text-destructive")}>{num(r.lostUnits, 0)}</td>
        </tr>
      ))}
    </Frame>
  );
}
