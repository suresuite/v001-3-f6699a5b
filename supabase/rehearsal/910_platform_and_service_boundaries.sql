\ir helpers/verified-session.sql
-- Isolated platform policy surfaces, scoped API-key resolution and scheduled SQL
-- callers. Real signed URLs and the Realtime broker still require staging.
GRANT USAGE ON SCHEMA storage, realtime TO authenticated, anon, service_role;
GRANT SELECT ON storage.objects, realtime.messages TO authenticated;
CREATE POLICY fixture_storage_allow ON storage.objects FOR SELECT TO authenticated USING(true);
CREATE POLICY fixture_realtime_allow ON realtime.messages FOR SELECT TO authenticated USING(true);
DO $platform$
DECLARE owner_id uuid:=gen_random_uuid(); outsider_id uuid:=gen_random_uuid();
  org_a uuid:=gen_random_uuid(); org_b uuid:=gen_random_uuid(); project_a uuid:=gen_random_uuid(); project_b uuid:=gen_random_uuid();
  key_id uuid; resolved uuid; scenario_result jsonb; queued_run uuid:=gen_random_uuid(); denied boolean; n integer;
BEGIN
  INSERT INTO public.organizations(id,name,slug) VALUES(org_a,'Platform A','platform-a'),(org_b,'Platform B','platform-b');
  INSERT INTO public.approved_users(id,email,name,password_hash,role,organization_id,is_active) VALUES
    (owner_id,'platform-owner@example.invalid','Owner','x','modeler',org_a,true),
    (outsider_id,'platform-outsider@example.invalid','Outsider','x','admin',org_b,true);
  INSERT INTO public.projects(id,name,plant_name,modeler_id,organization_id) VALUES
    (project_a,'Platform A','PA',owner_id,org_a),(project_b,'Platform B','PB',outsider_id,org_b);
  INSERT INTO storage.objects(bucket_id,name) VALUES('workspace','private-fixture'),('avatars','public-fixture');
  INSERT INTO realtime.messages(topic,extension) VALUES('sim:'||project_a,'broadcast');

  PERFORM pg_temp.browser_session(owner_id);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM storage.objects WHERE name='private-fixture';
  IF n<>0 THEN RAISE EXCEPTION 'Permissive storage policy bypassed private bucket fence'; END IF;
  SELECT count(*) INTO n FROM storage.objects WHERE name='public-fixture';
  IF n<>1 THEN RAISE EXCEPTION 'Private bucket fence revoked public avatars'; END IF;
  PERFORM set_config('realtime.topic','sim:'||project_a,true);
  SELECT count(*) INTO n FROM realtime.messages WHERE topic='sim:'||project_a;
  IF n<>1 THEN RAISE EXCEPTION 'Verified owner lost private simulation broadcast'; END IF;
  PERFORM pg_temp.browser_session(outsider_id);
  SELECT count(*) INTO n FROM realtime.messages WHERE topic='sim:'||project_a;
  IF n<>0 THEN RAISE EXCEPTION 'Permissive realtime policy bypassed project fence'; END IF;
  PERFORM pg_temp.browser_session(owner_id);
  SELECT id INTO key_id FROM public.create_api_key(owner_id,'platform-owner@example.invalid','isolated personal key',
    ARRAY['read:data'],'test',ARRAY[project_a],NULL,NULL,'personal');
  denied:=false;
  BEGIN PERFORM public.sweep_expired_files(); EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
  IF NOT denied THEN RAISE EXCEPTION 'Browser executed scheduled sweep'; END IF;
  -- A forged service claim in an ordinary SQL role is not internal authority.
  PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
  IF public.security_is_service() THEN RAISE EXCEPTION 'Authenticated role inherited service authority'; END IF;
  RESET ROLE;

  SET LOCAL ROLE service_role;
  PERFORM set_config('request.jwt.claims','{"role":"service_role"}',true);
  IF NOT public.security_is_service() THEN RAISE EXCEPTION 'Explicit scheduled service caller lost authority'; END IF;
  resolved:=public.api_personal_key_actor(key_id);
  IF resolved IS DISTINCT FROM owner_id THEN RAISE EXCEPTION 'Scoped personal API key failed owner resolution'; END IF;
  IF NOT public.api_can_access_project(org_a,project_a) OR public.api_can_access_project(org_a,project_b) THEN
    RAISE EXCEPTION 'Service API project tenancy check failed';
  END IF;
  scenario_result:=public.api_create_scenario(project_a,'{"name":"API fixture","horizon_days":42,"replications":3,"seed":7}'::jsonb,owner_id);
  IF (scenario_result->>'horizon_days')::integer<>42 OR (scenario_result->>'replications')::integer<>3 OR (scenario_result->>'seed')::integer<>7 THEN RAISE EXCEPTION 'API scenario changed engine inputs'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.audit_logs WHERE target_type='scenarios' AND actor_user_id=owner_id AND after->>'actor_known'='true') THEN RAISE EXCEPTION 'API scenario lost verified personal-key audit actor'; END IF;
  INSERT INTO public.simulation_runs(id,project_id,scenario_id,policy_hash,graph_hash,status)
    VALUES(queued_run,project_a,(scenario_result->>'id')::uuid,'frozen-api-policy','frozen-api-graph','queued');
  PERFORM public.cancel_authorized_run(project_a,queued_run,owner_id);
  IF NOT EXISTS(SELECT 1 FROM public.simulation_runs WHERE id=queued_run AND status='cancelled' AND policy_hash='frozen-api-policy' AND graph_hash='frozen-api-graph') THEN RAISE EXCEPTION 'Authorized cancellation failed or changed frozen inputs'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.audit_logs WHERE target_id=queued_run::text AND action='run_cancelled' AND actor_user_id=owner_id) THEN RAISE EXCEPTION 'Cancellation lost verified audit actor'; END IF;
  PERFORM public.sweep_expired_files();
  RESET ROLE;
  UPDATE public.approved_users SET is_active=false WHERE id=owner_id;
  IF public.api_personal_key_actor(key_id) IS NOT NULL THEN RAISE EXCEPTION 'Suspended API-key owner remained active'; END IF;
END;
$platform$;
DO $legacy_grants$
BEGIN
 IF to_regprocedure('public.bulk_upsert_customers(uuid,jsonb)') IS NOT NULL THEN
  IF has_function_privilege('anon','public.bulk_upsert_customers(uuid,jsonb)','EXECUTE')
   OR has_function_privilege('authenticated','public.bulk_upsert_customers(uuid,jsonb)','EXECUTE')
   OR NOT has_function_privilege('service_role','public.bulk_upsert_customers(uuid,jsonb)','EXECUTE') THEN
   RAISE EXCEPTION 'Legacy effective-grant adoption did not preserve only the service path';
  END IF;
 END IF;
END;
$legacy_grants$;
