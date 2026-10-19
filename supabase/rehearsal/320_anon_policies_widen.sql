\ir helpers/verified-session.sql
-- D309/D310 supersede the stage-1 widening: authenticated access is project
-- scoped, anon has no tenant grant, and a permissive allow cannot bypass a fence.
DO $scope$
DECLARE owner_id uuid:=gen_random_uuid(); outsider_id uuid:=gen_random_uuid();
  org_a uuid:=gen_random_uuid(); org_b uuid:=gen_random_uuid(); fixture_project uuid:=gen_random_uuid(); n integer;
BEGIN
  INSERT INTO public.organizations(id,name,slug) VALUES(org_a,'Scope A','scope-a'),(org_b,'Scope B','scope-b');
  INSERT INTO public.approved_users(id,email,name,password_hash,role,organization_id,is_active) VALUES
    (owner_id,'scope-owner@example.invalid','Owner','x','modeler',org_a,true),
    (outsider_id,'scope-outsider@example.invalid','Outsider','x','admin',org_b,true);
  INSERT INTO public.projects(id,name,plant_name,modeler_id,organization_id) VALUES(fixture_project,'Scope','SCOPE',owner_id,org_a);
  INSERT INTO public.materials(project_id,material_id) VALUES(fixture_project,'SCOPE-M');
  PERFORM pg_temp.browser_session(owner_id);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM public.materials WHERE materials.project_id=fixture_project;
  RESET ROLE;
  IF n<>1 THEN RAISE EXCEPTION 'Verified owner lost scoped read'; END IF;

  -- Reproduce permissive OR semantics. The restrictive fence must still refuse.
  CREATE POLICY fixture_permissive_allow ON public.materials FOR SELECT TO authenticated USING(true);
  PERFORM pg_temp.browser_session(outsider_id);
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM public.materials WHERE materials.project_id=fixture_project;
  RESET ROLE;
  IF n<>0 THEN RAISE EXCEPTION 'Permissive allow bypassed project fence'; END IF;
  IF has_table_privilege('anon','public.materials','SELECT') THEN RAISE EXCEPTION 'Anon retained tenant SELECT grant'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='materials'
    AND permissive='RESTRICTIVE' AND cmd='SELECT') THEN RAISE EXCEPTION 'Missing restrictive fence'; END IF;
END;
$scope$;
