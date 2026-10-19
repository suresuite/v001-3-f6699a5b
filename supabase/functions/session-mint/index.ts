// D28: password verification, throttling and session issuance are one server operation.
import { allowLogin } from "../_shared/loginThrottle.ts";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  DEFAULT_TTL_SECONDS,
  mintSessionToken,
  verifySessionToken,
} from "../_shared/mintSessionToken.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
  const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const JWT_SECRET = Deno.env.get("APP_SESSION_JWT_SECRET") ?? "";

  if (!JWT_SECRET || !SUPABASE_URL || !SERVICE_ROLE) return json({ error: "service_unavailable" }, 503);

  let email = "";
  let password = "";
  try {
    const body = await req.json();
    email = typeof body?.email === "string" ? body.email : "";
    password = typeof body?.password === "string" ? body.password : "";
  } catch {
    return json({ error: "bad_request" }, 400);
  }
  if (!email || !password || email.length > 320 || password.length > 1024) return json({ error: "bad_request" }, 400);

  try {
    const allowed = await allowLogin(email, req.headers.get("x-forwarded-for") ?? "unknown", {
      url: Deno.env.get("UPSTASH_REDIS_REST_URL") ?? "",
      token: Deno.env.get("UPSTASH_REDIS_REST_TOKEN") ?? "",
    });
    if (!allowed) return json({ error: "Please try again later" }, 429);
  } catch { return json({ error: "service_unavailable" }, 503); }
  const svc = createClient(SUPABASE_URL, SERVICE_ROLE);
  const { data, error } = await svc.rpc("authenticate_approved_user", {
    user_email: email,
    user_password: password,
  });

  if (error) return json({ error: "auth_failed" }, 500);
  if (!Array.isArray(data) || data.length === 0) {
    // Deliberately identical to a wrong password: this endpoint must not say whether an
    // address is registered.
    return json({ error: "invalid_credentials" }, 401);
  }

  const row = data[0] as { user_id?: string };
  if (!row?.user_id) return json({ error: "auth_failed" }, 500);

  const token = await mintSessionToken({
    userId: row.user_id,
    email,
    secret: JWT_SECRET,
    supabaseUrl: SUPABASE_URL,
    ttlSeconds: DEFAULT_TTL_SECONDS,
  });

  // A token this function cannot verify is one it should not hand out. Cheap, and it turns
  // a silent signing bug into a 500 here rather than an unexplained 401 at PostgREST.
  if (!(await verifySessionToken(token.access_token, JWT_SECRET))) {
    return json({ error: "mint_failed" }, 500);
  }

  return json(token);
});
