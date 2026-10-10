/**
 * D230 — the signed-in account's rights on ONE project, as the app applies them.
 *
 * `get_my_project_rights` returns `project_rights_for_user`, the same answer /profile's
 * "My organization" tab and both admin pages list for every person — so a button this
 * app enables and the right a page shows cannot disagree. The account-wide set
 * (`get_my_capabilities`, `useCapabilities`) has no project layer: a Viewer member whose
 * account is a modeler holds `simulation_lab` there and not here.
 *
 * The user is NAMED on the call: the browser calls as `anon` (PLAN.md §4 D155).
 */
import { supabase } from '@/integrations/supabase/client';
import type { ProjectRights } from './projectRightsText';

export * from './projectRightsText';

type RpcClient = {
  rpc: (fn: string, args: Record<string, unknown>) => Promise<{ data: unknown; error: { message: string } | null }>;
};
const db = supabase as unknown as RpcClient;

/** Why the read failed: a refusal the page must honour, or a read that did not happen. */
export type RightsReadFailure = 'refused' | 'unavailable';

export async function getMyProjectRights(
  userId: string,
  projectId: string,
): Promise<{ data: ProjectRights | null; failure: RightsReadFailure | null; error: string | null }> {
  const { data, error } = await db.rpc('get_my_project_rights', { p_project_id: projectId, p_user_id: userId });
  if (error) {
    const m = error.message ?? '';
    const refused = /forbidden|account_inactive|not_authenticated/.test(m);
    return { data: null, failure: refused ? 'refused' : 'unavailable', error: m };
  }
  return { data: data as ProjectRights, failure: null, error: null };
}

/** A write this account may not make on this project (D230). The hook that refused it
 *  has already said why, so a caller's catch should not say it again. */
export class ProjectRightRefused extends Error {}

