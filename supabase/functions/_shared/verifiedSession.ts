import { decodeTokenPayload } from "./mintSessionToken.ts";

export class AccessDenied extends Error {
  constructor(public status = 403) { super("Access denied"); }
}

export interface Principal { id: string; email: string }
interface Resolver {
  rpc(name: string, args: Record<string, unknown>): PromiseLike<{ data: unknown; error: unknown }>;
}

/** Only the project's signed approved-user sessions are browser credentials. */
export async function verifyBrowserToken(
  token: string, secret: string, url: string, now = Date.now() / 1000,
): Promise<Principal> {
  try {
    const parts = token.split(".");
    if (!secret || parts.length !== 3 || !parts.every(p => /^[\w-]+$/.test(p))) throw new AccessDenied(401);
    const decode = (s: string) => Uint8Array.from(atob(s.replace(/-/g, "+").replace(/_/g, "/")), c => c.charCodeAt(0));
    const header = JSON.parse(new TextDecoder().decode(decode(parts[0])));
    if (header.alg !== "HS256" || header.typ !== "JWT") throw new AccessDenied(401);
    const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["verify"]);
    if (!await crypto.subtle.verify("HMAC", key, decode(parts[2]), new TextEncoder().encode(`${parts[0]}.${parts[1]}`))) throw new AccessDenied(401);
    const p = decodeTokenPayload(token);
    if (!p || p.iss !== `${url.replace(/\/+$/, "")}/auth/v1` || p.aud !== "authenticated"
      || p.role !== "authenticated" || p.app_identity !== "approved_users"
      || typeof p.sub !== "string" || !/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(p.sub)
      || typeof p.email !== "string" || typeof p.exp !== "number" || !Number.isFinite(p.exp) || p.exp <= now
      || typeof p.iat !== "number" || !Number.isFinite(p.iat) || p.iat > now + 30
      || (p.nbf != null && (typeof p.nbf !== "number" || p.nbf > now))) throw new AccessDenied(401);
    return { id: p.sub, email: p.email };
  } catch { throw new AccessDenied(401); }
}

/** Account status is resolved on every request; a valid signature alone is insufficient. */
export async function requireBrowser(
  req: Request, resolver: Resolver, env: { secret: string; url: string },
  asserted?: { id?: unknown; email?: unknown },
): Promise<Principal> {
  const auth = req.headers.get("authorization") ?? "";
  if (!auth.startsWith("Bearer ")) throw new AccessDenied(401);
  const principal = await verifyBrowserToken(auth.slice(7), env.secret, env.url);
  if ((asserted?.id != null && asserted.id !== principal.id)
    || (asserted?.email != null && String(asserted.email).toLowerCase() !== principal.email.toLowerCase())) throw new AccessDenied();
  const { data, error } = await resolver.rpc("get_my_profile", { p_user_id: principal.id });
  const profile = Array.isArray(data) ? data[0] : data;
  if (error || !profile || typeof profile !== "object") throw new AccessDenied();
  const p = profile as Record<string, unknown>;
  if (p.is_active !== true || typeof p.access_expired !== "boolean" || p.access_expired) throw new AccessDenied();
  return principal;
}

export function requireInternal(req: Request, serviceKey: string): void {
  if (!serviceKey || req.headers.get("authorization") !== `Bearer ${serviceKey}`) throw new AccessDenied();
}

export async function requireProject(resolver: Resolver, principal: Principal, projectId: string, capability?: string): Promise<void> {
  const { data, error } = await resolver.rpc("project_rights_for_user", { p_project_id: projectId, p_user_id: principal.id });
  const rights = data as Record<string, unknown> | null;
  if (error || !rights || rights.visible !== true) throw new AccessDenied();
  if (capability) {
    const caps = rights.capabilities as Record<string, unknown> | undefined;
    if (caps?.[capability] !== true) throw new AccessDenied();
  }
}
