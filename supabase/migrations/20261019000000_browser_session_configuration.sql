-- D309: the issuer is deployment configuration owned by database maintenance,
-- never a caller-set GUC. Staging configures its own URL before accepting users.
CREATE TABLE public.browser_session_config (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  issuer text NOT NULL CHECK (issuer ~ '^https://[^/]+/auth/v1$')
);
ALTER TABLE public.browser_session_config ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.browser_session_config FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.browser_session_config TO service_role;
INSERT INTO public.browser_session_config(singleton,issuer)
VALUES(true,'https://wckdrutwkytwcomrlpib.supabase.co/auth/v1');
