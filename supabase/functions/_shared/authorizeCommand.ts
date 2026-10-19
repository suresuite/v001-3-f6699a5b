import { AccessDenied, requireBrowser, requireProject, type Principal } from "./verifiedSession.ts";

type Resolver = Parameters<typeof requireBrowser>[1];
export interface SecuredCommand { project_id: string; scenario_id?: string; kind: string; payload: Record<string, unknown> }

/** Runs before service-role dispatch, queueing, cancellation or signing. */
export async function authorizeCommand(
  req: Request, cmd: SecuredCommand, resolver: Resolver,
  env: { secret: string; url: string },
  resourceProject: (table: "scenarios" | "simulation_runs", id: string) => Promise<string | null>,
): Promise<Principal> {
  const who = await requireBrowser(req, resolver, env, { id: cmd.payload.actor_user_id });
  const rights: Record<string, string | null> = {
    'experiment.run': 'simulation_lab', 'experiment.cancel': 'simulation_lab', 'experiment.add_reps': 'simulation_lab',
    'scenario.changed': 'simulation_lab', 'scenario.reset': 'simulation_lab',
    'simulation.snapshot': 'simulation_lab', 'simulation.fork': 'simulation_lab',
    'policy.changed': 'data_edit_policies', 'run.series_url': null,
  };
  if (!Object.prototype.hasOwnProperty.call(rights, cmd.kind)) throw new AccessDenied();
  const capability = rights[cmd.kind] ?? undefined;
  await requireProject(resolver, who, cmd.project_id, capability);
  if (cmd.scenario_id && await resourceProject("scenarios", cmd.scenario_id) !== cmd.project_id) throw new AccessDenied();
  if (["experiment.cancel", "experiment.add_reps", "run.series_url"].includes(cmd.kind)) {
    if (typeof cmd.payload.run_id !== "string" || await resourceProject("simulation_runs", cmd.payload.run_id) !== cmd.project_id) throw new AccessDenied();
  }
  return who;
}
