// The engine's neutral starting point for a new scenario.
//
// A LEAF module on purpose — it imports nothing that touches a client — so the
// /docs manual can render the same values the Lab starts from. `useScenarios`
// re-exports it; every existing importer is unchanged. Same reason as
// `components/shared/frozenCell.ts`.

import type { Scenario } from "@/hooks/useScenarios";

/** The engine's neutral starting point for a new scenario. Exported so the
 *  setup form can mark a field "edited" against ONE source of truth instead of
 *  re-declaring the defaults next to the inputs. */
export const SCENARIO_ENGINE_DEFAULTS = {
  description: "",
  horizon_days: 364,
  time_step: "day",
  warmup_mode: "auto",
  warmup_days: 14,
  replications: 10,
  seed: 42,
  crn: true,
  demand_model: { kind: "poisson", lambda: 50 },
  disruption_schedule: [],
  recovery_overrides: {},
  stopping_rule: { kind: "fixed_horizon", max_wall_seconds: 600 },
  primary_kpi: "fill_rate",
} satisfies Partial<Scenario>;

/** The objectives a scenario can name as its primary KPI — the Setup selector. */
export const KPI_OPTIONS = [
  { value: "fill_rate", label: "Fill rate" },
  { value: "otif", label: "OTIF" },
  { value: "lead_time_days", label: "Lead time" },
  { value: "profit", label: "Profit" },
  { value: "utilization", label: "Utilization" },
];
