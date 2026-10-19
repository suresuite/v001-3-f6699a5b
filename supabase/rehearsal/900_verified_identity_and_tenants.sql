-- D309/D310. Isolated PostgREST-claim simulation: PostgreSQL sees claims only AFTER
-- the gateway has verified a token. Signature failures are exercised by Vitest.
-- No production endpoint or row is touched. The rehearsal rolls back this file.
CREATE FUNCTION pg_temp.security_session(p_user uuid, p_exp numeric DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', jsonb_build_object(
    'sub',p_user,'role','authenticated','aud','authenticated','app_identity','approved_users',
    'iss','https://wckdrutwkytwcomrlpib.supabase.co/auth/v1',
    'exp',COALESCE(p_exp,extract(epoch from now())+3600))::text,true);
END; $$;

DO $test$
DECLARE
  org_a uuid:=gen_random_uuid(); org_b uuid:=gen_random_uuid();
  owner_id uuid:=gen_random_uuid(); viewer_id uuid:=gen_random_uuid(); outsider_id uuid:=gen_random_uuid(); super_id uuid:=gen_random_uuid();
  project_a uuid:=gen_random_uuid(); project_b uuid:=gen_random_uuid(); scenario_id uuid:=gen_random_uuid(); run_id uuid:=gen_random_uuid();
  n integer; denied boolean; actual uuid;
BEGIN
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

  INSERT INTO public.organizations(id,name,slug) VALUES
    (org_a,'Security fixture A','security-fixture-a'),(org_b,'Security fixture B','security-fixture-b');
  INSERT INTO public.approved_users(id,email,name,password_hash,role,organization_id,organization,is_active) VALUES
    (owner_id,'security-owner@example.invalid','Owner','x','modeler',org_a,'Security fixture A',true),
    (viewer_id,'security-viewer@example.invalid','Viewer','x','modeler',org_a,'Security fixture A',true),
    (outsider_id,'security-outsider@example.invalid','Outsider','x','admin',org_b,'Security fixture B',true),
    (super_id,'security-super@example.invalid','Super','x','super_admin',org_a,'Security fixture A',true);
  PERFORM pg_temp.security_session(owner_id);
  INSERT INTO public.projects(id,name,plant_name,modeler_id,organization_id,organization)
    VALUES(project_a,'Security A','SEC-A',owner_id,org_a,'Security fixture A');
  PERFORM pg_temp.security_session(outsider_id);
  INSERT INTO public.projects(id,name,plant_name,modeler_id,organization_id,organization)
    VALUES(project_b,'Security B','SEC-B',outsider_id,org_b,'Security fixture B');
  INSERT INTO public.project_members(project_id,user_id,project_role) VALUES(project_a,viewer_id,'viewer');
  PERFORM pg_temp.security_session(owner_id);
  INSERT INTO public.materials(project_id,material_id) VALUES(project_a,'SEC-M');

  -- A local GUC naming a powerful user never changes the signed subject.
  PERFORM pg_temp.security_session(viewer_id);
  PERFORM set_config('app.current_user_id',super_id::text,true);
  IF public.get_current_user_id() IS DISTINCT FROM viewer_id THEN RAISE EXCEPTION 'GUC impersonation succeeded'; END IF;
  denied:=false;
  BEGIN PERFORM public._assert_super_admin(super_id,'security-super@example.invalid');
  EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'Forged admin actor accepted'; END IF;

  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM public.materials WHERE project_id=project_a;
  IF n<>1 THEN RAISE EXCEPTION 'Viewer lost legitimate read'; END IF;
  denied:=false;
  BEGIN INSERT INTO public.materials(project_id,material_id) VALUES(project_a,'VIEWER-WRITE');
  EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'Viewer wrote input data'; END IF;
  RESET ROLE;

  PERFORM pg_temp.security_session(outsider_id);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM public.materials WHERE project_id=project_a;
  IF n<>0 THEN RAISE EXCEPTION 'Cross-organization input read succeeded'; END IF;
  denied:=false;
  BEGIN PERFORM public.bulk_upsert_materials(project_a,'[]',outsider_id);
  EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'Cross-organization admin wrote input data'; END IF;
  RESET ROLE;

  -- Approved owner and super admin positives are necessary: deny-all would fail them.
  PERFORM pg_temp.security_session(owner_id);
  SET LOCAL ROLE authenticated;
  PERFORM public.bulk_upsert_materials(project_a,'[{"material_id":"EDITOR-WRITE"}]',owner_id);
  RESET ROLE;
  PERFORM pg_temp.security_session(super_id);
  PERFORM public._assert_super_admin(super_id,'security-super@example.invalid');

  -- Anonymous callers cannot use asserted actors, even with a populated GUC.
  PERFORM set_config('request.jwt.claims','{"role":"anon"}',true);
  PERFORM set_config('app.current_user_id',owner_id::text,true);
  IF public.get_current_user_id() IS NOT NULL THEN RAISE EXCEPTION 'Anonymous GUC authenticated'; END IF;
  denied:=false;
  BEGIN PERFORM public.bulk_upsert_materials(project_a,'[]',owner_id);
  EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'Anonymous RPC accepted'; END IF;

  PERFORM pg_temp.security_session(owner_id,extract(epoch from now())-1);
  IF public.get_current_user_id() IS NOT NULL THEN RAISE EXCEPTION 'Expired token accepted'; END IF;
  PERFORM pg_temp.security_session(owner_id);
  UPDATE public.approved_users SET is_active=false WHERE id=owner_id;
  IF public.get_current_user_id() IS NOT NULL THEN RAISE EXCEPTION 'Suspended subject accepted'; END IF;
  UPDATE public.approved_users SET is_active=true WHERE id=owner_id;
  PERFORM pg_temp.security_session(owner_id);

  INSERT INTO public.scenarios(id,project_id,name) VALUES(scenario_id,project_a,'Security scenario');
  INSERT INTO public.simulation_runs(id,project_id,scenario_id,policy_hash,graph_hash)
    VALUES(run_id,project_a,scenario_id,'frozen-policy','frozen-graph');
  denied:=false;
  BEGIN PERFORM public.persist_browser_result(run_id,project_b);
  EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'Mismatched project/run accepted'; END IF;
  denied:=false;
  BEGIN PERFORM public.persist_browser_result(run_id,project_a,'[]','[]','{"policy_hash":"forged"}');
  EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'Result persistence altered frozen inputs'; END IF;
  PERFORM public.persist_browser_result(run_id,project_a,'[]','[]','{"status":"done","aggregate_kpis":{"fill_rate":1}}');
  IF NOT EXISTS(SELECT 1 FROM public.simulation_runs WHERE id=run_id AND status='done' AND policy_hash='frozen-policy' AND graph_hash='frozen-graph') THEN
    RAISE EXCEPTION 'Authorized result persistence changed bindings or failed';
  END IF;
END; $test$;
