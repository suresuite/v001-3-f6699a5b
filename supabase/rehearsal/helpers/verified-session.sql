-- Explicit fixture configuration; artifact reconstruction contains schema, not deployment data.
INSERT INTO public.browser_session_config(singleton,issuer) VALUES(true,'https://wckdrutwkytwcomrlpib.supabase.co/auth/v1') ON CONFLICT DO NOTHING;

-- Isolated test gateway: these claims model a JWT AFTER cryptographic verification.
-- No production function is changed; signature and forged-token tests run in Vitest.
-- GUC poisoning assertions retain their separate app.current_user_id writes.
CREATE FUNCTION pg_temp.browser_session(p_user uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', jsonb_build_object(
    'sub',p_user,'role',CASE WHEN p_user IS NULL THEN 'anon' ELSE 'authenticated' END,
    'aud','authenticated','app_identity','approved_users',
    'iss','https://wckdrutwkytwcomrlpib.supabase.co/auth/v1',
    'exp',extract(epoch from now())+3600)::text,true);
END; $$;

-- Clear HTTP context for fixture setup performed by the actual SQL test owner.
-- This grants no browser authority: SET ROLE authenticated still fails the
-- production security_is_service() role/session-user checks with empty claims.
CREATE FUNCTION pg_temp.database_maintenance()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 PERFORM set_config('request.jwt.claims','{}',true);
 PERFORM set_config('app.current_user_id','',true);
END; $$;

-- Rehearsal schemas do not replay INSERT seeds. Use the same four production
-- capability/default matrices as the focused security and role rehearsals.
DO $seed$ BEGIN
  INSERT INTO public.capabilities (key, kind, label, sort_order) VALUES
    ('simulation_lab', 'feature', 'Run Simulations', 220),
    ('data_edit_inputs', 'feature', 'Edit Input Data', 241),
    ('data_edit_policies', 'feature', 'Edit Policies', 242),
    ('export', 'feature', 'Export', 250)
  ON CONFLICT (key) DO NOTHING;
  INSERT INTO public.project_role_capabilities (project_role, capability_key, allowed) VALUES
    ('owner',   'data_edit_inputs', true),  ('owner',   'data_edit_policies', true),
    ('owner',   'export', true),            ('owner',   'simulation_lab', true),
    ('editor',  'data_edit_inputs', true),  ('editor',  'data_edit_policies', true),
    ('editor',  'export', true),            ('editor',  'simulation_lab', true),
    ('analyst', 'data_edit_inputs', false), ('analyst', 'data_edit_policies', false),
    ('analyst', 'export', false),           ('analyst', 'simulation_lab', true),
    ('viewer',  'data_edit_inputs', false), ('viewer',  'data_edit_policies', false),
    ('viewer',  'export', false),           ('viewer',  'simulation_lab', false)
  ON CONFLICT (project_role, capability_key) DO NOTHING;
  -- Production's account defaults on these keys: 'user' runs simulations and nothing else.
  INSERT INTO public.role_capabilities (role, capability_key, allowed)
  SELECT r.role, k.key, r.role <> 'user' OR k.key = 'simulation_lab'
    FROM (VALUES ('super_admin'), ('admin'), ('modeler'), ('user')) r(role)
    CROSS JOIN (VALUES ('data_edit_inputs'), ('data_edit_policies'), ('export'), ('simulation_lab')) k(key)
  ON CONFLICT (role, capability_key) DO NOTHING;
  UPDATE public.role_capabilities SET allowed = (role <> 'user' OR capability_key = 'simulation_lab')
   WHERE capability_key IN ('data_edit_inputs', 'data_edit_policies', 'export', 'simulation_lab');

END; $seed$;
