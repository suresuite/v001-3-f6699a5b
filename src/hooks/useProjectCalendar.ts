/**
 * The project's calendar: run week 0 and the window that sets the run's length
 * (PLAN.md §4 D318, WP 18.1). Read once by the page that has it — the Lab
 * provides it from the project row and the demand forecasts it already loaded —
 * and fetched from `projects` by any surface outside a provider (the network
 * pages' disruption dialog).
 */
import { createContext, createElement, useContext, useEffect, useState, type ReactNode } from "react";
import { supabase } from "@/integrations/supabase/client";

export interface ProjectCalendar {
  /** `projects.simulation_start` — run week 0 */
  projectStart: string | null;
  /** `projects.simulation_end` */
  projectEnd: string | null;
  /** the earliest `demand_forecasts.period_start` — the engine's demand week 0
   *  (`sim-worker/sim_worker/datamap.py` `forecast_series`), when known */
  demandStart?: string | null;
}

const Ctx = createContext<ProjectCalendar | null>(null);

export function ProjectCalendarProvider({ value, children }: { value: ProjectCalendar; children: ReactNode }) {
  return createElement(Ctx.Provider, { value }, children);
}

export function useProjectCalendar(projectId: string | null | undefined): ProjectCalendar {
  const provided = useContext(Ctx);
  const [read, setRead] = useState<ProjectCalendar>({ projectStart: null, projectEnd: null });
  useEffect(() => {
    if (provided || !projectId) return;
    let live = true;
    // The generated client types predate these columns (as for `scenarios`).
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    void (supabase as any)
      .from("projects")
      .select("simulation_start, simulation_end")
      .eq("id", projectId)
      .maybeSingle()
      .then(({ data }: { data: unknown }) => {
        const row = data as { simulation_start?: string | null; simulation_end?: string | null } | null;
        if (live) setRead({ projectStart: row?.simulation_start ?? null, projectEnd: row?.simulation_end ?? null });
      });
    return () => {
      live = false;
    };
  }, [provided, projectId]);
  return provided ?? read;
}
