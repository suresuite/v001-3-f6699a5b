import { supabase } from "@/integrations/supabase/client";
import { setBrowserSession, clearMintedToken } from "./sessionState";
export { currentMintedToken, clearMintedToken } from "./sessionState";

/** Password verification and minting happen together on the server. No anon fallback. */
export async function loginBrowserSession(email: string, password: string): Promise<string | null> {
  clearMintedToken();
  const { data, error } = await supabase.functions.invoke("session-mint", { body: { email, password } });
  if (error || !data || typeof data.access_token !== "string" || typeof data.sub !== "string"
    || typeof data.expires_at !== "number" || data.expires_at <= Date.now() / 1000) return null;
  setBrowserSession(data);
  const { data: resolved, error: resolveError } = await (supabase.rpc as unknown as (name: string) => PromiseLike<{ data: unknown; error: unknown }>)("get_current_user_id");
  if (resolveError || resolved !== data.sub) { clearMintedToken(); return null; }
  await supabase.realtime.setAuth(data.access_token);
  return data.sub;
}
