import { useMemo } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  defaultWindow,
  disruptedSuppliers,
  leadTimeWeeks,
  outageWeeks,
  windowProblem,
  type InboundLane,
  type SafetyStockWindow,
} from "@/lib/sim/recovery";

interface Props {
  schedule: readonly { target: string; start_day?: number; duration_days?: number }[] | null | undefined;
  supplierIds: readonly string[];
  inbound: readonly InboundLane[];
  windows: readonly SafetyStockWindow[];
  onChange: (next: SafetyStockWindow[]) => void;
}

/**
 * Extra safety stock for the materials a disrupted supplier ships (P-P.3 windows,
 * engine 0.8.3). Per material: days of cover above its /policies safety stock, held
 * from a start week to an end week. The engine raises the material's reorder levels
 * only in those weeks — orders released at the start arrive a lead time later, which
 * is why the suggested start is one lead time before the outage — and books the
 * holding cost at the material's own holding rate for those weeks only.
 */
export function SafetyStockPanel({ schedule, supplierIds, inbound, windows, onChange }: Props) {
  const disrupted = useMemo(() => disruptedSuppliers(schedule, supplierIds), [schedule, supplierIds]);

  if (disrupted.length === 0) {
    return (
      <p className="text-[11px] text-muted-foreground">
        Add a supplier disruption to the schedule to set a buffer for the materials it ships.
      </p>
    );
  }

  const byMat = new Map(windows.map((w) => [w.material_id, w]));
  const put = (material_id: string, patch: Partial<SafetyStockWindow> | null, seed?: SafetyStockWindow) => {
    const rest = windows.filter((w) => w.material_id !== material_id);
    if (patch === null) return onChange(rest);
    const base = byMat.get(material_id) ?? seed;
    if (!base) return;
    onChange([...rest, { ...base, ...patch, material_id }]);
  };

  return (
    <div className="flex flex-col gap-3">
      <p className="text-[11px] text-muted-foreground">
        Extra cover on top of the /policies safety stock, held only between the start and end week. Holding
        cost is charged at each material's /policies holding rate for those weeks. Blank days = no buffer.
      </p>
      {disrupted.map((sup) => {
        const outage = outageWeeks(schedule, sup, supplierIds);
        const lanes = inbound.filter((l) => l.supplier_id === sup);
        const mats = [...new Map(lanes.map((l) => [l.material_id, l])).values()]
          .sort((a, b) => a.material_id.localeCompare(b.material_id));
        return (
          <div key={sup} className="flex flex-col gap-1.5">
            <div className="text-[11px] font-medium">
              {sup} is disrupted{outage ? ` in weeks ${outage.start}–${outage.end - 1}` : ""} — {mats.length} material
              {mats.length === 1 ? "" : "s"}
            </div>
            {mats.map((lane) => {
              const lead = leadTimeWeeks(lane);
              const seed: SafetyStockWindow | undefined = outage
                ? { material_id: lane.material_id, days: 0, ...defaultWindow(outage, lead) }
                : undefined;
              const w = byMat.get(lane.material_id);
              const problem = w ? windowProblem(w) : null;
              return (
                <div key={lane.material_id} className="grid grid-cols-2 items-end gap-2 rounded-sm border border-border/60 px-2.5 py-2 md:grid-cols-5">
                  <div className="col-span-2 text-[11px] md:col-span-1">
                    <div className="font-medium">{lane.material_id}</div>
                    <div className="text-muted-foreground">
                      lead time {lead == null ? "not stated" : `${Math.round(lead * 10) / 10} weeks`}
                    </div>
                  </div>
                  <NumField
                    label="Days of cover"
                    blankZero
                    value={w?.days ?? null}
                    onCommit={(v) => (v == null ? put(lane.material_id, null) : put(lane.material_id, { days: v }, seed))}
                    disabled={!seed && !w}
                  />
                  <NumField label="Start week" value={w?.start_week ?? null} disabled={!w}
                    onCommit={(v) => v != null && put(lane.material_id, { start_week: Math.round(v) })} />
                  <NumField label="End week (excl.)" value={w?.end_week ?? null} disabled={!w}
                    onCommit={(v) => v != null && put(lane.material_id, { end_week: Math.round(v) })} />
                  <div className="flex items-center gap-2 text-[11px] text-muted-foreground">
                    {w && (
                      <Button type="button" variant="ghost" size="sm" className="h-7 min-h-11 px-2 text-[11px] md:min-h-0"
                        onClick={() => put(lane.material_id, null)}>
                        Clear
                      </Button>
                    )}
                    {problem && <span>{problem}</span>}
                  </div>
                </div>
              );
            })}
          </div>
        );
      })}
    </div>
  );
}

function NumField({
  label, value, onCommit, disabled, blankZero,
}: {
  label: string;
  value: number | null;
  onCommit: (v: number | null) => void;
  disabled?: boolean;
  /** Show 0 as blank (days of cover: 0 is "no buffer"); a week 0 is a real week. */
  blankZero?: boolean;
}) {
  return (
    <label className="flex flex-col gap-1 text-[11px]">
      <span>{label}</span>
      <Input
        type="number"
        value={value == null || (blankZero && value === 0) ? "" : String(value)}
        disabled={disabled}
        onChange={(e) => {
          const raw = e.target.value;
          if (raw === "") return onCommit(null);
          const v = parseFloat(raw);
          if (Number.isFinite(v)) onCommit(v);
        }}
        className="h-8 min-h-11 text-xs md:min-h-0"
      />
    </label>
  );
}
