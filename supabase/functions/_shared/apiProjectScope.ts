/** API keys retain their own verified, scoped principal; browser JWTs never enter here. */
export class ApiScopeFailure extends Error {
  constructor(public status: 404 | 503) { super('API project authorization failed'); }
}
export async function authorizeApiProject(
  resolver: { rpc(name: string, args: Record<string, unknown>): PromiseLike<{ data: unknown; error: unknown }> },
  principal: { orgId: string; projectIds: string[] | null; actorUserId?: string | null }, projectId: string,
  capability?: string,
): Promise<void> {
  if (principal.projectIds && !principal.projectIds.includes(projectId)) throw new ApiScopeFailure(404);
  try {
    const { data, error } = await resolver.rpc('api_can_access_project', {
      p_org_id: principal.orgId, p_project_id: projectId,
    });
    if (error) throw new ApiScopeFailure(503);
    if (data !== true) throw new ApiScopeFailure(404);
    if (principal.actorUserId) {
      const { data: rights, error: rightsError } = await resolver.rpc('project_rights_for_user', {
        p_user_id: principal.actorUserId, p_project_id: projectId,
      });
      if (rightsError) throw new ApiScopeFailure(503);
      const r = rights as { visible?: unknown; capabilities?: Record<string, unknown> } | null;
      if (r?.visible !== true || (capability && r.capabilities?.[capability] !== true)) throw new ApiScopeFailure(404);
    }
  } catch (e) {
    if (e instanceof ApiScopeFailure) throw e;
    throw new ApiScopeFailure(503);
  }
}
