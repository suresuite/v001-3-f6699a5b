import { AccessDenied, requireBrowser, requireProject, type Principal } from "./verifiedSession.ts";

export { requireProject, requireInternal, AccessDenied } from "./verifiedSession.ts";

export async function browserIdentity(
  req: Request, resolver: Parameters<typeof requireBrowser>[1],
  asserted?: { id?: unknown; email?: unknown }, projectId?: string, capability?: string,
): Promise<Principal | Response> {
  try {
    const who = await requireBrowser(req, resolver, {
      secret: Deno.env.get("APP_SESSION_JWT_SECRET") ?? "",
      url: Deno.env.get("SUPABASE_URL") ?? "",
    }, asserted);
    if (projectId) await requireProject(resolver, who, projectId, capability);
    return who;
  } catch (e) {
    return new Response(JSON.stringify({ error: "Access denied" }), { status: e instanceof AccessDenied ? e.status : 503,
      headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" } });
  }
}
