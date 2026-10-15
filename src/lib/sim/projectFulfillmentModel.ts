// The project's default fulfillment mode — read ONE way, by every engine.
//
// A product that states no MTS / MTO of its own takes `projects.supply_chain_model`
// (row override → products.fulfillment_mode → this → MTO). The worker reads that
// column at dispatch (`sim_worker/worker.py::_fetch_project_model`, with the
// service role; a failed read becomes "not set", i.e. MTO).
//
// TWO CLIENT READS DISAGREED WITH IT (§4 D197):
//   · the browser engine was handed the POLICY's `fulfillment_strategy` string,
//     so one saved policy ran MTS in the browser and MTO on the server whenever
//     a product carried no mode of its own;
//   · the simulation-input export selected the `projects` table directly. This
//     application authenticates against `approved_users`, not Supabase Auth, so
//     a direct table read can return NO ROW — and the file then printed
//     "(not set — make-to-order)" for a project the grid, which reads the same
//     column through `list_projects`, showed as make-to-stock.
//
// This reads it the way the grid does: the `list_projects` RPC (SECURITY DEFINER,
// sets the caller's context), falling back to the table only when no user is
// known. Unreadable stays null — the worker's own "not set" — and callers say so.

export interface ProjectModelReader {
  from: (table: string) => any; // eslint-disable-line @typescript-eslint/no-explicit-any
  rpc: (fn: string, args?: Record<string, unknown>) => any; // eslint-disable-line @typescript-eslint/no-explicit-any
}

export interface ReadingUser {
  id?: string | null;
  email?: string | null;
}

const clean = (v: unknown): string | null =>
  v == null || String(v).trim() === "" ? null : String(v);

/** `projects.supply_chain_model`, or null when unset or unreadable. */
export async function readProjectFulfillmentModel(
  sb: ProjectModelReader,
  projectId: string | null | undefined,
  user?: ReadingUser | null,
): Promise<string | null> {
  if (!projectId) return null;
  try {
    if (user?.id) {
      const { data, error } = await sb.rpc("list_projects", {
        p_user_id: user.id,
        p_user_email: user.email ?? null,
      });
      if (!error && Array.isArray(data)) {
        const row = (data as Array<{ id?: string; supply_chain_model?: string | null }>).find(
          (p) => String(p.id) === String(projectId),
        );
        if (row) return clean(row.supply_chain_model);
      }
    }
    const { data, error } = await sb
      .from("projects")
      .select("supply_chain_model")
      .eq("id", projectId)
      .maybeSingle();
    if (error) return null;
    return clean((data as { supply_chain_model?: string | null } | null)?.supply_chain_model);
  } catch {
    return null;
  }
}
