// A scenario's recovery playbook: the strategies the Simulation Lab card offers, what
// each reaches in the engine, and the backup sources a disrupted supplier has.
//
// §4 D114. Every strategy offered here reaches an engine plugin through
// `scsim/scsim/io/project_map.py` (`_map_policies`), and `engineBridge.json` names
// which — `recoveryStrategies.test.ts` fails if the card offers one the bridge does
// not map. The exception is said on the card rather than hidden: Safety stock has no
// recovery model in the engine yet (the buffer itself is the /policies safety stock).
//
// This module replaced `recoveryScore.ts`, whose "with vs without recovery" KPIs were
// computed from hand-set weights (a fill rate of 0.94, revenue of €1,000,000) and
// shown on the results page as if a run had produced them.

import { judgeTarget } from "./disruptionEvents";

/** Every response token a stored playbook may still carry (old ones included). */
export type RecoveryResponseKey =
  | "dual_source_activate"
  | "safety_stock_drawdown"
  | "capacity_flex"
  | "allocate_materials"
  | "mode_shift"
  // Retired by migration 20261027000003: `reroute` ran P-T.2 expediting under a
  // second name, `demand_shaping` reached no plugin. Kept so frozen versions parse.
  | "reroute"
  | "demand_shaping";

/** The strategies the card offers, in order. Early warning (P-S.4) is not offered. */
export const OFFERED_STRATEGIES = [
  "dual_source_activate",
  "safety_stock_drawdown",
  "capacity_flex",
  "allocate_materials",
  "mode_shift",
] as const satisfies readonly RecoveryResponseKey[];

/** Offered, saved, and not yet modelled by the engine — said on the card. */
export const NOT_SIMULATED: ReadonlySet<RecoveryResponseKey> = new Set(["safety_stock_drawdown"]);

export const RESPONSE_LABELS: Record<RecoveryResponseKey, string> = {
  dual_source_activate: "Backup supplier",
  safety_stock_drawdown: "Safety stock",
  capacity_flex: "Overtime production",
  allocate_materials: "Material reallocation",
  mode_shift: "Expedite shipments",
  reroute: "Network rerouting (retired)",
  demand_shaping: "Material reallocation (retired)",
};

/** A backup source the planner enters for one scenario because no uploaded lane
 *  offers one. The engine adds it as a backup-only link (engine 0.8.2): never the
 *  material's primary, used only while P-S.1 reroutes. */
export interface BackupLane {
  material_id: string;
  supplier_id: string;
  supplier_name?: string;
  lead_time_weeks: number;
  unit_price: number;
  /** Blank = unlimited. Read only for a supplier no uploaded lane names. */
  capacity_per_week?: number | null;
}

export interface RecoveryConfig {
  enabled: boolean;
  response: RecoveryResponseKey[];
  detection_lag_days?: number;
  trigger_magnitude_pct?: number;
  trigger_duration_days?: number;
  recovery_target_days?: number;
  cost_cap?: number;
  // Per-strategy parameters — each reaches its plugin (project_map `_map_policies`).
  /** P-S.1. Blank = each backup lane's own lead time. */
  backup_lead_time_weeks?: number | null;
  holding_cost_pct?: number;
  /** P-P.5 overtime_premium_pct_of_price. */
  overtime_cost_pct?: number;
  /** P-P.9 window_weeks. */
  allocation_horizon_weeks?: number;
  /** P-P.9 annual_cost. */
  annual_labor_cost?: number;
  /** P-T.2 premium_pct_of_cost. */
  expedite_cost_pct?: number;
  backup_lanes?: BackupLane[];
}

export interface DisruptionEvent {
  start_day?: number;
  duration_days?: number;
  magnitude_pct?: number;
  node?: string;
}

/** An inbound lane as the project's data holds it (raw, never converted here). */
export interface InboundLane {
  supplier_id: string;
  material_id: string;
  lead_time?: number | null;
  lead_time_unit?: string | null;
  unit_price?: number | null;
}

/** The suppliers a schedule disrupts — the targets the engine resolves to a supplier. */
export function disruptedSuppliers(
  schedule: readonly { target: string }[] | null | undefined,
  supplierIds: readonly string[],
): string[] {
  const out = new Set<string>();
  for (const e of schedule ?? []) {
    const t = judgeTarget(e.target, supplierIds).target;
    if (t.kind === "supplier") out.add(t.id);
  }
  return [...out].sort();
}

export interface BackupOption {
  supplier_id: string;
  lead_time?: number | null;
  lead_time_unit?: string | null;
  unit_price?: number | null;
  /** That supplier is disrupted too in this scenario, so it cannot take the orders. */
  alsoDisrupted: boolean;
}

export interface MaterialBackups {
  material_id: string;
  /** Uploaded lanes from other suppliers — what P-S.1 can reroute to. */
  uploaded: BackupOption[];
  /** Backups entered on this scenario for the material. */
  entered: BackupLane[];
}

/**
 * For each material a disrupted supplier ships: the other suppliers already on file
 * for it, and any backup entered on the scenario. A material with neither has no
 * backup — the card says so and offers to enter one.
 */
export function backupsForSupplier(
  supplierId: string,
  inbound: readonly InboundLane[],
  entered: readonly BackupLane[],
  disrupted: readonly string[],
): MaterialBackups[] {
  const hit = new Set(disrupted);
  const mats = [...new Set(inbound.filter((l) => l.supplier_id === supplierId).map((l) => l.material_id))].sort();
  return mats.map((material_id) => {
    const seen = new Set<string>();
    const uploaded: BackupOption[] = [];
    for (const l of inbound) {
      if (l.material_id !== material_id || l.supplier_id === supplierId || seen.has(l.supplier_id)) continue;
      seen.add(l.supplier_id);
      uploaded.push({
        supplier_id: l.supplier_id,
        lead_time: l.lead_time ?? null,
        lead_time_unit: l.lead_time_unit ?? null,
        unit_price: l.unit_price ?? null,
        alsoDisrupted: hit.has(l.supplier_id),
      });
    }
    uploaded.sort((a, b) => a.supplier_id.localeCompare(b.supplier_id));
    return {
      material_id,
      uploaded,
      entered: entered.filter((b) => b.material_id === material_id),
    };
  });
}

/** Why an entered backup would be skipped by the engine, or null when it is usable —
 *  the same rules `_scenario_backup_links` applies. */
export function backupLaneProblem(
  lane: Partial<BackupLane>,
  inbound: readonly InboundLane[],
): string | null {
  const sup = (lane.supplier_id ?? "").trim();
  if (!sup) return "Name the backup supplier.";
  if (!(Number(lane.lead_time_weeks) >= 1)) return "Lead time must be at least 1 week.";
  if (!(Number(lane.unit_price) > 0)) return "Unit price must be above 0.";
  if (inbound.some((l) => l.supplier_id === sup && l.material_id === lane.material_id)) {
    return `${sup} already supplies this material through an uploaded lane — it is listed above.`;
  }
  return null;
}
