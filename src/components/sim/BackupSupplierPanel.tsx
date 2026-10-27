import { useMemo, useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { MONEY_SYMBOL } from "@/lib/sim/money";
import {
  backupLaneProblem,
  backupsForSupplier,
  disruptedSuppliers,
  type BackupLane,
  type InboundLane,
} from "@/lib/sim/recovery";

interface Props {
  schedule: readonly { target: string }[] | null | undefined;
  supplierIds: readonly string[];
  inbound: readonly InboundLane[];
  entered: readonly BackupLane[];
  onChange: (next: BackupLane[]) => void;
}

const fmtLead = (lt?: number | null, unit?: string | null) =>
  lt == null ? "lead time not stated" : `${lt} ${unit || "weeks"}`;
// A unit price keeps its decimals (a resistor costs 0.0054), so it is the declared
// symbol and the number as stated — `formatMoney` rounds to whole units.
const fmtPrice = (p?: number | null) => (p == null ? "price not stated" : `${MONEY_SYMBOL}${p}`);

/**
 * The backup sources P-S.1 can reroute to, for each supplier this scenario disrupts.
 *
 * Per material that supplier ships: the other suppliers already on file for it (the
 * uploaded inbound lanes — what the engine reroutes to), else "no backup supplier on
 * file" and a form to enter one for THIS scenario. An entered backup is saved in the
 * scenario's playbook (`backup_lanes`), never in the item masters, and the engine adds
 * it as a backup-only link: never the primary, used only while the primary is out.
 */
export function BackupSupplierPanel({ schedule, supplierIds, inbound, entered, onChange }: Props) {
  const disrupted = useMemo(() => disruptedSuppliers(schedule, supplierIds), [schedule, supplierIds]);

  if (disrupted.length === 0) {
    return (
      <p className="text-[11px] text-muted-foreground">
        Add a supplier disruption to the schedule to see the backup suppliers its materials have.
      </p>
    );
  }

  return (
    <div className="flex flex-col gap-3">
      {disrupted.map((sup) => (
        <SupplierBackups
          key={sup}
          supplierId={sup}
          rows={backupsForSupplier(sup, inbound, entered, disrupted)}
          inbound={inbound}
          entered={entered}
          onChange={onChange}
        />
      ))}
    </div>
  );
}

function SupplierBackups({
  supplierId, rows, inbound, entered, onChange,
}: {
  supplierId: string;
  rows: ReturnType<typeof backupsForSupplier>;
  inbound: readonly InboundLane[];
  entered: readonly BackupLane[];
  onChange: (next: BackupLane[]) => void;
}) {
  const covered = rows.filter((r) => r.uploaded.some((o) => !o.alsoDisrupted) || r.entered.length > 0).length;
  return (
    <div className="flex flex-col gap-2">
      <div className="text-[11px] font-medium">
        {supplierId} is disrupted — {covered} of {rows.length} material{rows.length === 1 ? "" : "s"} have a backup
      </div>
      {rows.length === 0 && (
        <p className="text-[11px] text-muted-foreground">No inbound lane names this supplier, so it ships no material.</p>
      )}
      {rows.map((r) => (
        <div key={r.material_id} className="rounded-sm border border-border/60 px-2.5 py-2">
          <div className="text-[11px] font-medium">{r.material_id}</div>
          {r.uploaded.length > 0 ? (
            <ul className="mt-1 flex flex-col gap-0.5">
              {r.uploaded.map((o) => (
                <li key={o.supplier_id} className="text-[11px] text-muted-foreground">
                  {o.supplier_id} · {fmtLead(o.lead_time, o.lead_time_unit)} · {fmtPrice(o.unit_price)}
                  {o.alsoDisrupted && (
                    <Badge variant="outline" className="ml-1.5 text-[10px] font-normal">also disrupted</Badge>
                  )}
                </li>
              ))}
            </ul>
          ) : r.entered.length === 0 ? (
            <p className="mt-1 text-[11px] text-muted-foreground">No backup supplier on file.</p>
          ) : null}
          {r.entered.map((b) => (
            <div key={b.supplier_id} className="mt-1 flex items-center justify-between gap-2 text-[11px]">
              <span>
                {b.supplier_name && b.supplier_name !== b.supplier_id ? `${b.supplier_name} (${b.supplier_id})` : b.supplier_id}
                {" · "}{b.lead_time_weeks} weeks · {fmtPrice(b.unit_price)}
                {b.capacity_per_week ? ` · ${b.capacity_per_week}/week` : ""}
                <Badge variant="secondary" className="ml-1.5 text-[10px] font-normal">entered, not uploaded</Badge>
              </span>
              <Button
                type="button"
                variant="ghost"
                size="sm"
                className="h-7 min-h-11 px-2 text-[11px] md:min-h-0"
                onClick={() => onChange(entered.filter((x) => !(x.material_id === b.material_id && x.supplier_id === b.supplier_id)))}
              >
                Remove
              </Button>
            </div>
          ))}
          {r.uploaded.every((o) => o.alsoDisrupted) && (
            <AddBackupForm
              materialId={r.material_id}
              inbound={inbound}
              entered={entered}
              onAdd={(lane) => onChange([...entered, lane])}
            />
          )}
        </div>
      ))}
    </div>
  );
}

function AddBackupForm({
  materialId, inbound, entered, onAdd,
}: {
  materialId: string;
  inbound: readonly InboundLane[];
  entered: readonly BackupLane[];
  onAdd: (lane: BackupLane) => void;
}) {
  const [open, setOpen] = useState(false);
  const [supplier, setSupplier] = useState("");
  const [lead, setLead] = useState("");
  const [price, setPrice] = useState("");
  const [cap, setCap] = useState("");
  const draft: Partial<BackupLane> = {
    material_id: materialId,
    supplier_id: supplier.trim(),
    lead_time_weeks: Number(lead),
    unit_price: Number(price),
  };
  const duplicate = entered.some((b) => b.material_id === materialId && b.supplier_id === draft.supplier_id);
  const problem = duplicate ? "That backup is already entered." : backupLaneProblem(draft, inbound);

  if (!open) {
    return (
      <Button
        type="button"
        variant="outline"
        size="sm"
        className="mt-1.5 h-7 min-h-11 px-2 text-[11px] md:min-h-0"
        onClick={() => setOpen(true)}
      >
        Enter a backup supplier
      </Button>
    );
  }
  return (
    <div className="mt-2 grid grid-cols-1 gap-2 md:grid-cols-4">
      <div className="flex flex-col gap-1">
        <Label className="text-[11px]">Supplier</Label>
        <Input value={supplier} onChange={(e) => setSupplier(e.target.value)} className="h-8 min-h-11 text-xs md:min-h-0" />
      </div>
      <div className="flex flex-col gap-1">
        <Label className="text-[11px]">Lead time <span className="font-normal text-muted-foreground">(weeks)</span></Label>
        <Input type="number" min={1} value={lead} onChange={(e) => setLead(e.target.value)} className="h-8 min-h-11 text-xs md:min-h-0" />
      </div>
      <div className="flex flex-col gap-1">
        <Label className="text-[11px]">Unit price <span className="font-normal text-muted-foreground">({MONEY_SYMBOL})</span></Label>
        <Input type="number" min={0} step="0.01" value={price} onChange={(e) => setPrice(e.target.value)} className="h-8 min-h-11 text-xs md:min-h-0" />
      </div>
      <div className="flex flex-col gap-1">
        <Label className="text-[11px]">Capacity <span className="font-normal text-muted-foreground">(units/week, blank = unlimited)</span></Label>
        <Input type="number" min={0} value={cap} onChange={(e) => setCap(e.target.value)} className="h-8 min-h-11 text-xs md:min-h-0" />
      </div>
      <div className="flex items-center gap-2 md:col-span-4">
        <Button
          type="button"
          size="sm"
          className="h-7 min-h-11 px-2 text-[11px] md:min-h-0"
          disabled={problem != null}
          onClick={() => {
            const capN = Number(cap);
            onAdd({
              material_id: materialId,
              supplier_id: supplier.trim(),
              supplier_name: supplier.trim(),
              lead_time_weeks: Math.round(Number(lead)),
              unit_price: Number(price),
              capacity_per_week: cap !== "" && capN > 0 ? capN : null,
            });
            setOpen(false);
            setSupplier(""); setLead(""); setPrice(""); setCap("");
          }}
        >
          Add backup
        </Button>
        <Button type="button" variant="ghost" size="sm" className="h-7 min-h-11 px-2 text-[11px] md:min-h-0" onClick={() => setOpen(false)}>
          Cancel
        </Button>
        {problem && <span className="text-[11px] text-muted-foreground">{problem}</span>}
      </div>
    </div>
  );
}
