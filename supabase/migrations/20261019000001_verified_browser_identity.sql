-- Phase 7 / WP 7.1 / G15: verified identity boundary (D309–D312).
-- PostgREST verifies signatures before supplying request.jwt.claims. No caller-set
-- app.* value authenticates a browser. Service requests are a separate, signed role.
CREATE OR REPLACE FUNCTION public.security_is_service()
RETURNS boolean LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT
    (COALESCE(NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '') = 'service_role'
      AND current_setting('role', true) IN ('none', 'service_role'))
    OR (
      -- Management migrations/jobs authenticate as an actual database superuser,
      -- not as PostgREST's authenticator. This is never an HTTP/GUC identity path.
      COALESCE(NULLIF(current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb) = '{}'::jsonb
      AND current_setting('role', true) = 'none'
      AND EXISTS (SELECT 1 FROM pg_roles WHERE rolname = session_user AND rolsuper)
    );
$$;

CREATE OR REPLACE FUNCTION public.get_current_user_id()
RETURNS uuid LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE c jsonb := COALESCE(NULLIF(current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb); v_id uuid;
BEGIN
  IF public.security_is_service() THEN
    v_id := NULLIF(current_setting('app.current_user_id', true), '')::uuid;
  ELSE
    IF c->>'role' IS DISTINCT FROM 'authenticated' OR c->>'aud' IS DISTINCT FROM 'authenticated'
      OR c->>'iss' IS DISTINCT FROM 'https://wckdrutwkytwcomrlpib.supabase.co/auth/v1'
      OR c->>'app_identity' IS DISTINCT FROM 'approved_users'
      OR jsonb_typeof(c->'exp') IS DISTINCT FROM 'number'
      OR (c->>'exp')::numeric <= extract(epoch from now()) THEN RETURN NULL; END IF;
    v_id := auth.uid();
  END IF;
  RETURN (SELECT u.id FROM public.approved_users u LEFT JOIN public.organizations o ON o.id = u.organization_id
    WHERE u.id = v_id AND u.is_active AND (u.role = 'super_admin' OR o.access_valid_until IS NULL OR o.access_valid_until > now()));
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN RETURN NULL;
END; $$;

CREATE OR REPLACE FUNCTION public.security_actor(p_asserted uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := public.get_current_user_id();
BEGIN
  IF public.security_is_service() THEN RETURN COALESCE(p_asserted, v_uid); END IF;
  IF v_uid IS NULL OR (p_asserted IS NOT NULL AND p_asserted <> v_uid) THEN
    RAISE EXCEPTION 'not_authenticated: verified session required' USING ERRCODE = '42501';
  END IF;
  RETURN v_uid;
END; $$;

CREATE OR REPLACE FUNCTION public.set_current_user_context(user_id uuid, user_email text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := public.security_actor(user_id);
BEGIN
  IF NOT public.security_is_service() AND user_email IS NOT NULL AND NOT EXISTS
    (SELECT 1 FROM public.approved_users u WHERE u.id = v_uid AND lower(u.email) = lower(user_email)) THEN
    RAISE EXCEPTION 'not_authenticated: mismatched email' USING ERRCODE = '42501';
  END IF;
  PERFORM set_config('app.current_user_id', v_uid::text, true);
END; $$;

CREATE OR REPLACE FUNCTION public.account_self_resolve(p_user_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := public.security_actor(p_user_id);
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501'; END IF;
  PERFORM set_config('app.current_user_id', v_uid::text, true);
  RETURN v_uid;
END; $$;

CREATE OR REPLACE FUNCTION public.get_current_approved_user()
RETURNS TABLE(user_id uuid, user_email text, user_role text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT u.id, u.email, u.role::text FROM public.approved_users u WHERE u.id = public.get_current_user_id();
$$;

CREATE OR REPLACE FUNCTION public.get_current_user_org()
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT u.organization FROM public.approved_users u WHERE u.id = public.get_current_user_id();
$$;

CREATE OR REPLACE FUNCTION public.security_project_allowed(p_project_id uuid, p_capability text DEFAULT NULL)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := public.get_current_user_id(); r jsonb;
BEGIN
  IF v_uid IS NULL OR p_project_id IS NULL THEN RETURN false; END IF;
  r := public.project_rights_for_user(v_uid, p_project_id);
  RETURN COALESCE((r->>'visible')::boolean, false) AND
    (p_capability IS NULL OR COALESCE((r->'capabilities'->>p_capability)::boolean, false));
END; $$;

CREATE OR REPLACE FUNCTION public.security_assert_project(p_project_id uuid, p_capability text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.security_is_service() AND NOT public.security_project_allowed(p_project_id, p_capability) THEN
    RAISE EXCEPTION 'forbidden: project capability required' USING ERRCODE = '42501';
  END IF;
END; $$;

-- Privileged resolvers used by verified edge front doors, never callable as anon.
GRANT EXECUTE ON FUNCTION public.project_rights_for_user(uuid,uuid) TO service_role;
REVOKE EXECUTE ON FUNCTION public.authenticate_approved_user(text,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.authenticate_approved_user(text,text) TO service_role;
REVOKE EXECUTE ON FUNCTION public.authenticate_user(text,text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.sweep_expired_files(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.sweep_expired_files(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public._assert_super_admin(p_actor_id uuid, p_actor_email text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);

  PERFORM public.set_current_user_context(p_actor_id, p_actor_email);
  IF p_actor_id IS NULL OR NOT EXISTS (
       SELECT 1 FROM public.approved_users
        WHERE id = p_actor_id
          AND role = 'super_admin'::public.app_role
          AND is_active) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
END; $$;

CREATE OR REPLACE FUNCTION public._insert_validated_model(
  p_project_id         uuid,
  p_policy_version_id  uuid,
  p_dataset_version_id uuid,
  p_scenario_id        uuid,
  p_name               text,
  p_protocol           jsonb,
  p_warmup_method      text,
  p_replication_basis  jsonb,
  p_validation_tests   jsonb,
  p_findings           jsonb,
  p_verdict            text,
  p_basis              text,
  p_face_validation    text,
  p_evidence_run_id    uuid,
  p_evidence           jsonb,
  p_actor              uuid,
  p_actor_email        text
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  v_id             uuid := gen_random_uuid();
  v_prev_id        uuid;
  v_policy_hash    text;
  v_graph_hash     text;
  v_sim_hash       text;
  v_sim_version    uuid;
  v_fingerprint    jsonb;
  v_scenario_hash  text;
  v_engine         text;
  v_ver_project    uuid;
  v_scen_project   uuid;
  v_ds_project     uuid;
  v_probs          text[];
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor := public.security_actor(p_actor);
  PERFORM public.security_assert_project(p_project_id, 'simulation_lab');

  IF p_actor IS NOT NULL THEN
    PERFORM set_config('app.current_user_id', p_actor::text, true);
  END IF;

  IF p_dataset_version_id IS NULL THEN
    RAISE EXCEPTION 'a Validated Model names the graph version it was validated on (dataset_version_id)'
      USING ERRCODE = 'null_value_not_allowed';
  END IF;
  v_probs := public.validated_model_protocol_problems(p_protocol);
  IF cardinality(v_probs) > 0 OR (p_protocol ? 'backfilled') THEN
    RAISE EXCEPTION 'the run protocol is incomplete: %', array_to_string(
      CASE WHEN cardinality(v_probs) > 0 THEN v_probs ELSE ARRAY['a new model may not carry a backfilled protocol'] END, '; ')
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT project_id INTO v_ver_project FROM public.policy_versions WHERE id = p_policy_version_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'policy version % not found', p_policy_version_id; END IF;
  IF v_ver_project <> p_project_id THEN
    RAISE EXCEPTION 'policy version does not belong to project %', p_project_id;
  END IF;
  v_policy_hash := public._policy_version_hash(p_policy_version_id);

  -- WP 11.2 · §4 D259 — the model binds the scope the engine READS (the snapshot's
  -- `inputs` domain) and that scope's version, beside the snapshot it was validated on.
  SELECT project_id, graph_hash, hash_inputs, simulation_version_id
    INTO v_ds_project, v_graph_hash, v_sim_hash, v_sim_version
    FROM public.dataset_versions WHERE id = p_dataset_version_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'dataset version % not found', p_dataset_version_id; END IF;
  IF v_ds_project <> p_project_id THEN
    RAISE EXCEPTION 'dataset version does not belong to project %', p_project_id;
  END IF;

  SELECT project_id INTO v_scen_project FROM public.scenarios WHERE id = p_scenario_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'scenario % not found', p_scenario_id; END IF;
  IF v_scen_project <> p_project_id THEN
    RAISE EXCEPTION 'scenario does not belong to project %', p_project_id;
  END IF;

  v_fingerprint   := public._build_scenario_fingerprint(p_scenario_id);
  v_scenario_hash := encode(extensions.digest(v_fingerprint::text, 'sha256'), 'hex');

  IF p_evidence_run_id IS NOT NULL THEN
    SELECT NULLIF(code_version, '') INTO v_engine FROM public.simulation_runs WHERE id = p_evidence_run_id;
  END IF;

  UPDATE public.model_validations
     SET status = 'superseded'
   WHERE project_id = p_project_id AND policy_hash = v_policy_hash
     AND COALESCE(hash_simulation, graph_hash) = COALESCE(v_sim_hash, v_graph_hash)
     AND scenario_hash = v_scenario_hash
     AND status = 'active'
  RETURNING id INTO v_prev_id;

  INSERT INTO public.model_validations (
    id, project_id, name, protocol, protocol_hash, model_hash, face_validation,
    policy_version_id, policy_hash, dataset_version_id, graph_hash,
    hash_simulation, simulation_version_id,
    scenario_hash, scenario_fingerprint, engine_fingerprint,
    adopted_warmup_days, warmup_method, recommended_replications, replication_basis,
    validation_tests, findings_snapshot, verdict, basis, evidence_run_id,
    author_user_id, author_email
  ) VALUES (
    v_id, p_project_id,
    COALESCE(NULLIF(btrim(p_name), ''), 'Validated model'),
    p_protocol,
    encode(extensions.digest(p_protocol::text, 'sha256'), 'hex'),
    public._validated_model_hash(v_policy_hash, COALESCE(v_sim_hash, v_graph_hash), v_scenario_hash, p_protocol, v_engine),
    NULLIF(btrim(COALESCE(p_face_validation, '')), ''),
    p_policy_version_id, v_policy_hash, p_dataset_version_id, v_graph_hash,
    v_sim_hash, v_sim_version,
    v_scenario_hash, v_fingerprint, v_engine,
    (p_protocol ->> 'warmup_week')::int * 7,
    COALESCE(p_warmup_method, 'engine'),
    (p_protocol ->> 'replications')::int,
    COALESCE(p_replication_basis, '{}'::jsonb),
    COALESCE(p_validation_tests, '[]'::jsonb), COALESCE(p_findings, '[]'::jsonb),
    p_verdict, p_basis, p_evidence_run_id,
    p_actor, p_actor_email
  );

  IF v_prev_id IS NOT NULL THEN
    UPDATE public.model_validations SET superseded_by = v_id WHERE id = v_prev_id;
  END IF;

  INSERT INTO public.model_validation_evidence (
    validation_id, project_id, warmup, replication_analysis, kpi_tests, face_validation,
    evidence_run_ids, author_user_id
  ) VALUES (
    v_id, p_project_id,
    COALESCE(p_evidence -> 'warmup', '{}'::jsonb),
    COALESCE(p_evidence -> 'replication_analysis', p_replication_basis, '{}'::jsonb),
    COALESCE(p_validation_tests, '[]'::jsonb),
    CASE WHEN NULLIF(btrim(COALESCE(p_face_validation, '')), '') IS NULL THEN NULL
         ELSE jsonb_build_object('statement', btrim(p_face_validation), 'by', p_actor, 'at', now()) END,
    COALESCE(ARRAY(SELECT x::uuid FROM jsonb_array_elements_text(p_evidence -> 'run_ids') x),
             CASE WHEN p_evidence_run_id IS NULL THEN '{}'::uuid[] ELSE ARRAY[p_evidence_run_id] END),
    p_actor
  );

  RETURN v_id;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.admin_add_org_member(
  p_actor_id uuid, p_actor_email text, p_target_user_id uuid, p_org_id uuid,
  p_org_role text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text;
  v_org_role text;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);

  PERFORM public._assert_super_admin(p_actor_id, p_actor_email);
  PERFORM public.set_current_user_context(p_actor_id, p_actor_email);
  IF p_org_role IS NOT NULL AND p_org_role NOT IN ('owner', 'admin', 'member') THEN
    RAISE EXCEPTION 'invalid organization role %', p_org_role;
  END IF;
  SELECT role::text INTO v_role FROM public.approved_users WHERE id = p_target_user_id;
  IF v_role IS NULL THEN RAISE EXCEPTION 'user not found'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.organizations WHERE id = p_org_id) THEN
    RAISE EXCEPTION 'organization not found';
  END IF;
  IF EXISTS (SELECT 1 FROM public.organization_members
              WHERE org_id = p_org_id AND user_id = p_target_user_id) THEN
    RAISE EXCEPTION 'already_a_member: the account already belongs to that organization';
  END IF;

  v_org_role := COALESCE(p_org_role, CASE WHEN v_role = 'admin' THEN 'admin' ELSE 'member' END);
  INSERT INTO public.organization_members (org_id, user_id, org_role)
  VALUES (p_org_id, p_target_user_id, v_org_role);

  PERFORM public.log_admin_action('org.member_add', 'organization_members', p_target_user_id::text, NULL,
    jsonb_build_object('org_id', p_org_id, 'org_role', v_org_role));
END; $$;

CREATE OR REPLACE FUNCTION public.admin_audit_log_read(
  p_actor_id    uuid,
  p_actor_email text,
  p_since       timestamptz,
  p_plane       text    DEFAULT NULL,
  p_limit       integer DEFAULT 1000
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 1000), 1), 5000);
  v_out   jsonb;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);

  PERFORM public._assert_super_admin(p_actor_id, p_actor_email);
  IF p_since IS NULL THEN
    RAISE EXCEPTION 'admin_audit_log_read: a window must name its start' USING ERRCODE = '22023';
  END IF;
  IF p_plane IS NOT NULL AND p_plane NOT IN ('admin','data','access') THEN
    RAISE EXCEPTION 'admin_audit_log_read: unknown plane %', p_plane USING ERRCODE = '22023';
  END IF;

  PERFORM public.audit_log_seal(false);

  WITH w AS (
    SELECT l.* FROM public.audit_logs l
     WHERE l.created_at >= p_since
       AND (p_plane IS NULL OR l.plane = p_plane)
  ),
  people AS (
    SELECT u.id, u.name, u.email, COALESCE(o.name, u.organization) AS org
      FROM public.approved_users u
      LEFT JOIN public.organizations o ON o.id = u.organization_id
     WHERE u.id IN (SELECT w.actor_user_id FROM w
                    UNION SELECT (w.target_id)::uuid FROM w
                     WHERE w.action LIKE 'auth.%' AND w.target_id ~ '^[0-9a-f-]{36}$')
  ),
  newest AS (
    SELECT w.* FROM w ORDER BY w.created_at DESC, w.seq DESC NULLS FIRST LIMIT v_limit
  )
  SELECT jsonb_build_object(
    'since',    p_since,
    'plane',    p_plane,
    'total',    (SELECT count(*) FROM w),
    'returned', (SELECT count(*) FROM newest),
    'rows', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'id', n.id, 'seq', n.seq, 'plane', n.plane,
               'actor_user_id', n.actor_user_id,
               'actor_name',  COALESCE(p.name, p.email),
               'actor_email', p.email,
               'actor_deleted', n.actor_user_id IS NOT NULL AND p.id IS NULL,
               'action', n.action, 'target_type', n.target_type, 'target_id', n.target_id,
               'target_name', CASE WHEN n.target_type = 'approved_users' THEN
                                (SELECT COALESCE(u.name, u.email) FROM public.approved_users u
                                  WHERE u.id::text = n.target_id) END,
               'before', n.before, 'after', n.after, 'created_at', n.created_at,
               'sealed', n.seq IS NOT NULL,
               'projects', (SELECT jsonb_agg(jsonb_build_object('id', pr.id, 'name', pr.name))
                              FROM public.projects pr
                             WHERE pr.id::text IN (SELECT jsonb_array_elements_text(
                                     CASE WHEN jsonb_typeof(n.after -> 'projects') = 'array'
                                          THEN n.after -> 'projects' ELSE '[]'::jsonb END))))
             ORDER BY n.created_at DESC, n.seq DESC NULLS FIRST)
        FROM newest n LEFT JOIN people p ON p.id = n.actor_user_id), '[]'::jsonb),
    'by_actor', COALESCE((
      SELECT jsonb_agg(a ORDER BY (a ->> 'total')::int DESC) FROM (
        SELECT jsonb_build_object(
                 'actor_user_id', w.actor_user_id,
                 'actor_name',  COALESCE(p.name, p.email),
                 'actor_email', p.email,
                 'actor_org',   p.org,
                 'actor_deleted', w.actor_user_id IS NOT NULL AND p.id IS NULL,
                 'total',     count(*),
                 'sign_ins',  count(*) FILTER (WHERE w.action = 'auth.sign_in'),
                 'data_writes', count(*) FILTER (WHERE w.plane = 'data'),
                 'rows_written', COALESCE(sum(GREATEST((w.after ->> 'rows_after')::bigint,
                                                       (w.after ->> 'rows_before')::bigint))
                                          FILTER (WHERE w.plane = 'data'), 0),
                 'admin_actions', count(*) FILTER (WHERE w.plane = 'admin'),
                 'exports',   count(*) FILTER (WHERE w.action LIKE 'export.%'),
                 'first_at',  min(w.created_at),
                 'last_at',   max(w.created_at)) AS a
          FROM w LEFT JOIN people p ON p.id = w.actor_user_id
         GROUP BY w.actor_user_id, p.id, p.name, p.email, p.org) s), '[]'::jsonb),
    'by_action', COALESCE((
      SELECT jsonb_agg(a ORDER BY (a ->> 'n')::int DESC) FROM (
        SELECT jsonb_build_object(
                 'plane', w.plane, 'action', w.action, 'target_type', w.target_type,
                 'n', count(*), 'people', count(DISTINCT w.actor_user_id),
                 'last_at', max(w.created_at)) AS a
          FROM w GROUP BY w.plane, w.action, w.target_type
         ORDER BY count(*) DESC LIMIT 50) s), '[]'::jsonb),
    'failed_sign_ins', COALESCE((
      SELECT jsonb_agg(a ORDER BY (a ->> 'n')::int DESC) FROM (
        SELECT jsonb_build_object(
                 'account_id', w.target_id,
                 'account', COALESCE(p.name, p.email, 'deleted user'),
                 'n', count(*), 'last_at', max(w.created_at)) AS a
          FROM w LEFT JOIN people p ON p.id::text = w.target_id
         WHERE w.action = 'auth.sign_in_failed'
         GROUP BY w.target_id, p.name, p.email) s), '[]'::jsonb)
  ) INTO v_out;

  RETURN v_out;
END; $$;

CREATE OR REPLACE FUNCTION public.admin_audit_log_verify(p_actor_id uuid, p_actor_email text)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  r        public.audit_logs;
  v_seq    bigint := 0;
  v_hash   text   := repeat('0', 64);
  v_n      bigint := 0;
  v_break  jsonb;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);

  PERFORM public._assert_super_admin(p_actor_id, p_actor_email);
  PERFORM public.audit_log_seal(false);

  FOR r IN SELECT * FROM public.audit_logs l WHERE l.seq IS NOT NULL ORDER BY l.seq LOOP
    IF r.seq <> v_seq + 1 THEN
      v_break := jsonb_build_object('seq', v_seq + 1, 'id', NULL,
        'reason', format('rows %s to %s are missing — deleted after they were sealed',
                         v_seq + 1, r.seq - 1));
      EXIT;
    END IF;
    IF r.prev_hash IS DISTINCT FROM v_hash THEN
      v_break := jsonb_build_object('seq', r.seq, 'id', r.id,
        'reason', 'this row does not follow the one before it — a row was removed or replaced');
      EXIT;
    END IF;
    IF r.row_hash IS DISTINCT FROM public.audit_log_digest(r) THEN
      v_break := jsonb_build_object('seq', r.seq, 'id', r.id,
        'reason', 'this row''s content no longer matches its seal — it was edited');
      EXIT;
    END IF;
    v_seq := r.seq;
    v_hash := r.row_hash;
    v_n := v_n + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'ok',          v_break IS NULL,
    'checked',     v_n,
    'head_seq',    CASE WHEN v_break IS NULL THEN v_seq END,
    'head_hash',   CASE WHEN v_break IS NULL THEN v_hash END,
    'unsealed',    (SELECT count(*) FROM public.audit_logs WHERE seq IS NULL),
    'first_break', v_break,
    'verified_at', now());
END; $$;

CREATE OR REPLACE FUNCTION public.admin_copy_project(
  p_actor_id uuid, p_actor_email text, p_project_id uuid, p_new_name text,
  p_target_org_id uuid DEFAULT NULL, p_new_owner_id uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_src public.projects%ROWTYPE;
  v_new_id uuid;
  v_org_id uuid; v_org_name text;
  v_owner_id uuid; v_owner_name text;
  v_tbl text; v_cols text;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_inputs');

  PERFORM public._assert_super_admin(p_actor_id, p_actor_email);
  IF p_new_name IS NULL OR btrim(p_new_name) = '' THEN RAISE EXCEPTION 'name required'; END IF;
  SELECT * INTO v_src FROM public.projects WHERE id = p_project_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'project not found'; END IF;

  v_org_id := COALESCE(p_target_org_id, v_src.organization_id);
  IF p_target_org_id IS NOT NULL THEN
    SELECT name INTO v_org_name FROM public.organizations WHERE id = p_target_org_id;
    IF v_org_name IS NULL THEN RAISE EXCEPTION 'organization not found'; END IF;
  ELSE
    v_org_name := v_src.organization;
  END IF;

  v_owner_id := COALESCE(p_new_owner_id, v_src.modeler_id);
  IF p_new_owner_id IS NOT NULL THEN
    SELECT COALESCE(name, email) INTO v_owner_name FROM public.approved_users WHERE id = p_new_owner_id;
    IF v_owner_name IS NULL THEN RAISE EXCEPTION 'new owner not found'; END IF;
  ELSE
    v_owner_name := v_src.modeler_name;
  END IF;

  BEGIN
    INSERT INTO public.projects
      (name, modeler_id, modeler_name, plant_name, supply_chain_model, bom_level,
       data_type, completed, simulation_start, simulation_end,
       plant_latitude, plant_longitude, plant_location_text, deep_tier_enabled,
       organization, organization_id)
    VALUES
      (btrim(p_new_name), v_owner_id, v_owner_name, v_src.plant_name,
       v_src.supply_chain_model, v_src.bom_level, v_src.data_type, v_src.completed,
       v_src.simulation_start, v_src.simulation_end,
       v_src.plant_latitude, v_src.plant_longitude, v_src.plant_location_text,
       v_src.deep_tier_enabled, COALESCE(v_org_name, 'default_org'), v_org_id)
    RETURNING id INTO v_new_id;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'the owner already has a project named "%" for plant "%"',
      btrim(p_new_name), v_src.plant_name;
  END;

  FOREACH v_tbl IN ARRAY ARRAY[
    'suppliers','materials','products',
    'inbound_logistics','outbound_logistics',
    'bom_single_level','bom_multi_level',
    'multi_tier_supply_chain','tier2_suppliers','tier3_suppliers',
    'node_list','network_nodes','network_edges','network_summary',
    'policy_defaults','policy_overrides']
  LOOP
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema = 'public' AND table_name = v_tbl
                      AND column_name = 'project_id') THEN
      CONTINUE;
    END IF;
    SELECT string_agg(quote_ident(column_name), ',' ORDER BY ordinal_position) INTO v_cols
    FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = v_tbl
      AND column_name NOT IN ('id', 'project_id')
      AND is_generated = 'NEVER';
    IF v_cols IS NULL THEN CONTINUE; END IF;
    EXECUTE format(
      'INSERT INTO public.%I (project_id, %s) SELECT $1, %s FROM public.%I WHERE project_id = $2',
      v_tbl, v_cols, v_cols, v_tbl)
    USING v_new_id, p_project_id;
  END LOOP;

  PERFORM public.log_admin_action('project.copy', 'projects', v_new_id::text,
    jsonb_build_object('source_project_id', p_project_id),
    jsonb_build_object('name', btrim(p_new_name), 'org_id', v_org_id, 'owner_id', v_owner_id));
  RETURN v_new_id;
END; $$;

CREATE OR REPLACE FUNCTION public.admin_create_organization(
  p_actor_id uuid, p_actor_email text, p_name text, p_slug text,
  p_access_period text DEFAULT NULL, p_project_limit integer DEFAULT NULL,
  p_user_limit integer DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid; v_slug text;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);

  PERFORM public._assert_super_admin(p_actor_id, p_actor_email);
  IF p_name IS NULL OR btrim(p_name) = '' THEN RAISE EXCEPTION 'name required'; END IF;
  IF p_access_period IS NOT NULL AND p_access_period NOT IN ('week', 'month', 'quarter', 'year') THEN
    RAISE EXCEPTION 'invalid access period %', p_access_period;
  END IF;
  IF p_project_limit IS NOT NULL AND p_project_limit NOT IN (1, 2, 3, 5, 10, 20, 50, 100) THEN
    RAISE EXCEPTION 'invalid project limit %', p_project_limit;
  END IF;
  IF p_user_limit IS NOT NULL AND p_user_limit NOT IN (1, 2, 3, 5, 10, 20, 50, 100) THEN
    RAISE EXCEPTION 'invalid user limit %', p_user_limit;
  END IF;
  v_slug := lower(regexp_replace(COALESCE(NULLIF(btrim(p_slug), ''), p_name), '[^a-zA-Z0-9]+', '-', 'g'));
  v_slug := btrim(v_slug, '-');
  IF EXISTS (SELECT 1 FROM public.organizations WHERE slug = v_slug) THEN
    RAISE EXCEPTION 'an organization with slug "%" already exists', v_slug;
  END IF;
  INSERT INTO public.organizations
    (name, slug, status, access_period, access_valid_from, project_limit, user_limit)
  VALUES (btrim(p_name), v_slug, 'active',
          p_access_period, CASE WHEN p_access_period IS NULL THEN NULL ELSE now() END,
          p_project_limit, p_user_limit)
  RETURNING id INTO v_id;
  PERFORM public.log_admin_action('org.create', 'organizations', v_id::text, NULL,
    jsonb_build_object('name', btrim(p_name), 'slug', v_slug, 'access_period', p_access_period,
                       'project_limit', p_project_limit, 'user_limit', p_user_limit));
  RETURN v_id;
END; $$;

CREATE OR REPLACE FUNCTION public.admin_create_user(
  p_actor_id uuid, p_actor_email text,
  p_name text, p_email text, p_password text, p_role text, p_org_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid; v_org_name text;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);

  PERFORM public._assert_super_admin(p_actor_id, p_actor_email);

  IF p_email IS NULL OR btrim(p_email) = '' THEN RAISE EXCEPTION 'email required'; END IF;
  IF p_role NOT IN ('super_admin','admin','modeler','user') THEN RAISE EXCEPTION 'invalid role %', p_role; END IF;
  IF p_password IS NULL OR length(p_password) < 8 THEN RAISE EXCEPTION 'password_too_short'; END IF;
  IF EXISTS (SELECT 1 FROM public.approved_users WHERE lower(email) = lower(btrim(p_email))) THEN
    RAISE EXCEPTION 'email already in use';
  END IF;

  IF p_org_id IS NOT NULL THEN
    SELECT name INTO v_org_name FROM public.organizations WHERE id = p_org_id;
  END IF;

  INSERT INTO public.approved_users
    (name, email, role, organization, organization_id, password_hash, is_active, force_password_change)
  VALUES (
    NULLIF(btrim(coalesce(p_name, '')), ''), lower(btrim(p_email)), p_role::public.app_role,
    v_org_name, p_org_id,
    extensions.crypt(p_password, extensions.gen_salt('bf')), true, true)
  RETURNING id INTO v_id;

  IF p_org_id IS NOT NULL THEN
    INSERT INTO public.organization_members (org_id, user_id, org_role)
    VALUES (p_org_id, v_id, CASE WHEN p_role = 'admin' THEN 'admin' ELSE 'member' END)
    ON CONFLICT (org_id, user_id) DO NOTHING;
  END IF;

  PERFORM public.log_admin_action('user.create', 'approved_users', v_id::text, NULL,
    jsonb_build_object('name', p_name, 'email', lower(btrim(p_email)), 'role', p_role, 'org_id', p_org_id));
  RETURN v_id;
END; $$;

CREATE OR REPLACE FUNCTION public.admin_delete_docs_faq(p_actor_id uuid, p_actor_email text, p_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_before public.docs_faq;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);

  PERFORM public._assert_super_admin(p_actor_id, p_actor_email);
  DELETE FROM public.docs_faq WHERE id = p_id RETURNING * INTO v_before;
  IF v_before.id IS NULL THEN RAISE EXCEPTION 'question not found' USING ERRCODE = '42704'; END IF;
  PERFORM public.log_admin_action('docs.faq_delete', 'docs_faq', p_id::text,
    jsonb_build_object('question', v_before.question, 'is_published', v_before.is_published), NULL);
END; $$;

CREATE OR REPLACE FUNCTION public.admin_delete_organization(
  p_actor_id     uuid,
  p_actor_email  text,
  p_org_id       uuid,
  p_confirm_slug text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org      public.organizations%ROWTYPE;
  v_users    uuid[];
  v_detached uuid[];
  v_projects uuid[];
  v_pid      uuid;
  v_blocker  text;
  v_before   jsonb;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);

  PERFORM public._assert_super_admin(p_actor_id, p_actor_email);
  -- Said again in this body: `_assert_super_admin` sets it, but the attribution scan
  -- in `dataPlaneAudit.test.ts` reads text and cannot follow a call.
  PERFORM public.set_current_user_context(p_actor_id, p_actor_email);

  SELECT * INTO v_org FROM public.organizations WHERE id = p_org_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'organization not found' USING ERRCODE = 'no_data_found';
  END IF;

  IF p_confirm_slug IS DISTINCT FROM v_org.slug THEN
    RAISE EXCEPTION 'confirmation does not match: type the slug "%" to delete this organization', v_org.slug
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  IF EXISTS (SELECT 1 FROM public.organization_members WHERE user_id = p_actor_id AND org_id = p_org_id)
     OR EXISTS (SELECT 1 FROM public.approved_users WHERE id = p_actor_id AND organization_id = p_org_id) THEN
    RAISE EXCEPTION 'you cannot delete your own organization (you belong to it — remove yourself from it first)'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Every account in it, locked so none can be moved in or out while this runs.
  PERFORM 1 FROM public.approved_users au
   WHERE au.organization_id = p_org_id
      OR EXISTS (SELECT 1 FROM public.organization_members m WHERE m.user_id = au.id AND m.org_id = p_org_id)
   ORDER BY au.id FOR UPDATE;

  -- Deleted: the accounts that belong to NO other organization. Detached: the rest.
  SELECT COALESCE(array_agg(au.id ORDER BY au.id) FILTER (WHERE NOT elsewhere), '{}'),
         COALESCE(array_agg(au.id ORDER BY au.id) FILTER (WHERE elsewhere), '{}')
    INTO v_users, v_detached
    FROM (SELECT au.id,
                 EXISTS (SELECT 1 FROM public.organization_members x
                          WHERE x.user_id = au.id AND x.org_id <> p_org_id) AS elsewhere
            FROM public.approved_users au
           WHERE au.organization_id = p_org_id
              OR EXISTS (SELECT 1 FROM public.organization_members m
                          WHERE m.user_id = au.id AND m.org_id = p_org_id)) au;

  SELECT string_agg(email, ', ' ORDER BY email) INTO v_blocker
    FROM public.approved_users
   WHERE id = ANY (v_users) AND role = 'super_admin'::public.app_role;
  IF v_blocker IS NOT NULL THEN
    RAISE EXCEPTION 'this organization holds super admin account(s) (%): move them to another organization or change their role first', v_blocker
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT COALESCE(array_agg(id ORDER BY id), '{}') INTO v_projects
    FROM public.projects
   WHERE organization_id = p_org_id
      OR (organization_id IS NULL AND modeler_id = ANY (v_users));

  -- Work a deleted account recorded in a project that is NOT being deleted stays, with
  -- its actor anonymised by the keys' ON DELETE SET NULL (WP 7.2 (a), §4 D213).

  v_before := to_jsonb(v_org) || jsonb_build_object(
    'users', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', u.id, 'email', u.email, 'role', u.role) ORDER BY u.email)
                         FROM public.approved_users u WHERE u.id = ANY (v_users)), '[]'::jsonb),
    'detached', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', u.id, 'email', u.email) ORDER BY u.email)
                            FROM public.approved_users u WHERE u.id = ANY (v_detached)), '[]'::jsonb),
    'projects', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name) ORDER BY p.name)
                            FROM public.projects p WHERE p.id = ANY (v_projects)), '[]'::jsonb));

  -- Projects first: each through THE sweep, so a project leaves exactly as D170 says.
  FOREACH v_pid IN ARRAY v_projects LOOP
    PERFORM public._delete_project_rows(v_pid, p_actor_id, p_actor_email);
  END LOOP;

  DELETE FROM public.ai_budgets
   WHERE (scope = 'org'     AND scope_id = p_org_id)
      OR (scope = 'user'    AND scope_id = ANY (v_users))
      OR (scope = 'project' AND scope_id = ANY (v_projects));

  -- The memberships go BEFORE the organization, so each detached account re-points to
  -- its next organization through `trg_organization_members_repoint_active` rather than
  -- through the `ON DELETE SET NULL`, which cannot refresh the text copy.
  DELETE FROM public.organization_members WHERE org_id = p_org_id;
  DELETE FROM public.approved_users WHERE id = ANY (v_users);
  DELETE FROM public.organizations  WHERE id = p_org_id;

  PERFORM public.log_admin_action('org.delete', 'organizations', p_org_id::text, v_before,
    jsonb_build_object('deleted', true,
                       'projects', cardinality(v_projects),
                       'users', cardinality(v_users),
                       'detached', cardinality(v_detached)));

  RETURN jsonb_build_object(
    'organization', v_org.name,
    'projects', cardinality(v_projects),
    'users', cardinality(v_users),
    'detached', cardinality(v_detached));
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_delete_project(
  p_actor_id uuid, p_actor_email text, p_project_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_before jsonb;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_inputs');

  PERFORM public._assert_super_admin(p_actor_id, p_actor_email);
  SELECT to_jsonb(p) INTO v_before FROM public.projects p WHERE p.id = p_project_id;
  IF v_before IS NULL THEN RAISE EXCEPTION 'project not found'; END IF;
  DELETE FROM public.projects WHERE id = p_project_id;
  PERFORM public.log_admin_action('project.delete', 'projects', p_project_id::text, v_before, NULL);
END; $$;

CREATE OR REPLACE FUNCTION public.admin_delete_user(
  p_actor_id       uuid,
  p_actor_email    text,
  p_target_user_id uuid,
  p_confirm_email  text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user     public.approved_users%ROWTYPE;
  v_owned    text;
  v_n_owned  integer;
  v_before   jsonb;
  v_anon     jsonb;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);

  PERFORM public._assert_super_admin(p_actor_id, p_actor_email);
  -- Said again in this body: `_assert_super_admin` sets it, but the attribution scan
  -- in `dataPlaneAudit.test.ts` reads text and cannot follow a call.
  PERFORM public.set_current_user_context(p_actor_id, p_actor_email);

  SELECT * INTO v_user FROM public.approved_users WHERE id = p_target_user_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'user not found' USING ERRCODE = 'no_data_found';
  END IF;

  IF p_confirm_email IS NULL OR lower(btrim(p_confirm_email)) IS DISTINCT FROM lower(v_user.email) THEN
    RAISE EXCEPTION 'confirmation does not match: type the email "%" to delete this account', v_user.email
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  IF p_target_user_id = p_actor_id THEN
    RAISE EXCEPTION 'you cannot delete your own account' USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_user.role = 'super_admin'::public.app_role THEN
    RAISE EXCEPTION '% is a super admin: change their role first, then delete the account', v_user.email
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT count(*)::int,
         string_agg(format('"%s"', name), ', ' ORDER BY name) FILTER (WHERE rn <= 5)
    INTO v_n_owned, v_owned
    FROM (SELECT name, row_number() OVER (ORDER BY name) AS rn
            FROM public.projects WHERE modeler_id = p_target_user_id) p;
  IF v_n_owned > 0 THEN
    RAISE EXCEPTION '% owns % project(s) (%): transfer them to another owner or delete them first',
      v_user.email, v_n_owned, v_owned || CASE WHEN v_n_owned > 5 THEN ', …' ELSE '' END
      USING ERRCODE = 'dependent_objects_still_exist';
  END IF;

  -- What the delete will anonymise, counted BEFORE it happens (the rows keep no trace
  -- of whose they were afterwards, which is the point).
  v_anon := jsonb_build_object(
    'files_uploaded',    (SELECT count(*) FROM public.ingest_files      WHERE uploaded_by = p_target_user_id),
    'ingest_runs',       (SELECT count(*) FROM public.ingest_runs       WHERE p_target_user_id IN (triggered_by_user_id, applied_by_user_id)),
    'analysis_runs',     (SELECT count(*) FROM public.analysis_runs     WHERE actor_user_id = p_target_user_id),
    'supply_chain_rows', (SELECT count(*) FROM public.supply_chain_data WHERE uploaded_by = p_target_user_id));

  -- No name and no email: the log keeps the uuid, as the audit log does (header §3).
  v_before := jsonb_build_object(
    'id', v_user.id,
    'role', v_user.role,
    'organization_ids', COALESCE((SELECT jsonb_agg(m.org_id ORDER BY m.org_id)
                                    FROM public.organization_members m
                                   WHERE m.user_id = p_target_user_id), '[]'::jsonb),
    'project_memberships', (SELECT count(*) FROM public.project_members WHERE user_id = p_target_user_id));

  DELETE FROM public.ai_budgets WHERE scope = 'user' AND scope_id = p_target_user_id;
  DELETE FROM public.approved_users WHERE id = p_target_user_id;

  PERFORM public.log_admin_action('user.delete', 'approved_users', p_target_user_id::text, v_before,
    jsonb_build_object('deleted', true, 'anonymised', v_anon));

  RETURN jsonb_build_object('email', v_user.email, 'anonymised', v_anon);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_dismiss_password_reset_request(
  p_actor_id uuid, p_actor_email text, p_request_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_user uuid;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);

  PERFORM public._assert_super_admin(p_actor_id, p_actor_email);
  UPDATE public.password_reset_requests
     SET status = 'dismissed', closed_at = now(), closed_by = p_actor_id
   WHERE id = p_request_id AND status = 'open'
  RETURNING user_id INTO v_user;
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'request not found or already closed' USING ERRCODE = '42704';
  END IF;
  PERFORM public.log_admin_action('user.reset_request_dismissed', 'approved_users', v_user::text,
    NULL, jsonb_build_object('request_id', p_request_id));
END; $$;

CREATE OR REPLACE FUNCTION public.admin_get_project_access(
  p_actor_id uuid, p_actor_email text, p_project_id uuid)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_inputs');

  PERFORM public._assert_super_admin(p_actor_id, p_actor_email);
  RETURN public.project_access_read(p_project_id);
END; $$;

CREATE OR REPLACE FUNCTION public.admin_get_user_memberships(
  p_actor_id uuid, p_actor_email text, p_target_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user     public.approved_users%ROWTYPE;
  v_is_super boolean;
  v_default  uuid;
  v_orgs     jsonb;
  v_projects jsonb;
  v_keys     jsonb;
  v_matrix   jsonb;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);

  PERFORM public._assert_super_admin(p_actor_id, p_actor_email);
  SELECT * INTO v_user FROM public.approved_users WHERE id = p_target_user_id;
  IF v_user.id IS NULL THEN RAISE EXCEPTION 'user not found'; END IF;
  v_is_super := (v_user.role = 'super_admin'::public.app_role);
  SELECT m.org_id INTO v_default FROM public.organization_members m
   WHERE m.user_id = v_user.id AND m.is_default;

  -- Every organization the account belongs to (D210), the active one first.
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'id', o.id, 'name', o.name, 'slug', o.slug, 'status', o.status,
           'access_valid_until', o.access_valid_until,
           'org_role', m.org_role,
           'is_active', o.id = v_user.organization_id,
           'is_default', m.is_default,
           'members', (SELECT count(*) FROM public.organization_members mm WHERE mm.org_id = o.id),
           'projects', (SELECT count(*) FROM public.projects p WHERE p.organization_id = o.id))
           ORDER BY (o.id = v_user.organization_id) DESC, lower(o.name), o.id), '[]'::jsonb)
    INTO v_orgs
    FROM public.organization_members m
    JOIN public.organizations o ON o.id = m.org_id
   WHERE m.user_id = v_user.id;

  -- The project-scoped capabilities: the keys the project layer of the resolver has an
  -- opinion on. Read from `project_role_capabilities`, so a key added there appears here.
  SELECT COALESCE(jsonb_agg(jsonb_build_object('key', c.key, 'label', c.label)
                            ORDER BY c.sort_order, c.key), '[]'::jsonb)
    INTO v_keys
    FROM public.capabilities c
   WHERE c.key IN (SELECT DISTINCT capability_key FROM public.project_role_capabilities);

  SELECT COALESCE(jsonb_object_agg(r.project_role, r.caps), '{}'::jsonb) INTO v_matrix
    FROM (SELECT prc.project_role, jsonb_object_agg(prc.capability_key, prc.allowed) AS caps
            FROM public.project_role_capabilities prc
           GROUP BY prc.project_role) r;

  -- Every project the account can reach or is recorded on: the projects of any of its
  -- organizations, projects it owns, and projects it holds a membership or a live
  -- delegation on — expired memberships included, so an admin can see and clear them.
  WITH my_orgs AS (
    SELECT m.org_id FROM public.organization_members m WHERE m.user_id = v_user.id
  ), reach AS (
    SELECT p.id FROM public.projects p
     WHERE p.organization_id IN (SELECT org_id FROM my_orgs)
        OR p.modeler_id = v_user.id
    UNION
    SELECT pm.project_id FROM public.project_members pm WHERE pm.user_id = v_user.id
    UNION
    SELECT dg.project_id FROM public.delegation_grants dg
     WHERE dg.grantee_user_id = v_user.id AND dg.revoked_at IS NULL AND dg.expires_at > now()
  )
  SELECT COALESCE(jsonb_agg(x.j ORDER BY x.sort_key), '[]'::jsonb) INTO v_projects
  FROM (
    SELECT lower(p.name) AS sort_key, jsonb_build_object(
      'project_id',        p.id,
      'name',              p.name,
      'plant_name',        p.plant_name,
      'organization_id',   p.organization_id,
      'organization_name', po.name,
      -- "Projects: org-wide view" reads the ACTIVE organization and nothing else (D210).
      'in_active_org',     p.organization_id IS NOT NULL AND p.organization_id = v_user.organization_id,
      'in_member_org',     p.organization_id IN (SELECT org_id FROM my_orgs),
      'is_modeler',        p.modeler_id = v_user.id,
      'owner_name',        COALESCE(ow.name, ow.email),
      -- D230 — the rights are `project_rights_for_user`'s, the answer the app's gates read.
      'visible',           (r.rights ->> 'visible')::boolean,
      'can_edit_project',  (r.rights ->> 'can_edit_project')::boolean,
      'may_land_uploads',  (r.rights ->> 'may_land_uploads')::boolean,
      'member', CASE WHEN pm.project_id IS NULL THEN NULL ELSE jsonb_build_object(
                  'project_role',   pm.project_role,
                  'expires_at',     pm.expires_at,
                  'expired',        pm.expires_at IS NOT NULL AND pm.expires_at <= now(),
                  'rationale',      pm.rationale,
                  'granted_by',     COALESCE(gb.name, gb.email),
                  'updated_at',     pm.updated_at) END,
      'delegations', COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
                   'id', dg.id, 'project_role', dg.project_role, 'expires_at', dg.expires_at,
                   'rationale', dg.rationale, 'grantor', COALESCE(g.name, g.email))
                   ORDER BY dg.expires_at)
            FROM public.delegation_grants dg
            LEFT JOIN public.approved_users g ON g.id = dg.grantor_user_id
           WHERE dg.grantee_user_id = v_user.id AND dg.project_id = p.id
             AND dg.revoked_at IS NULL AND dg.expires_at > now()), '[]'::jsonb),
      'effective_role',    public.effective_project_role(v_user.id, p.id),
      -- What the account may do (D230), and what the resolver's four layers alone would say.
      'capabilities',          r.rights -> 'capabilities',
      'resolved_capabilities', r.rights -> 'resolved_capabilities'
    ) AS j
      FROM reach
      JOIN public.projects p ON p.id = reach.id
      LEFT JOIN public.organizations po ON po.id = p.organization_id
      LEFT JOIN public.approved_users ow ON ow.id = p.modeler_id
      LEFT JOIN public.project_members pm ON pm.project_id = p.id AND pm.user_id = v_user.id
      LEFT JOIN public.approved_users gb ON gb.id = pm.granted_by
      CROSS JOIN LATERAL (SELECT public.project_rights_for_user(v_user.id, p.id) AS rights) r
  ) x;

  RETURN jsonb_build_object(
    'user_id', v_user.id,
    'role', v_user.role::text,
    'is_super_admin', v_is_super,
    'active_organization_id', v_user.organization_id,
    'default_organization_id', v_default,
    'organizations', v_orgs,
    'projects', v_projects,
    'project_capabilities', v_keys,
    'role_matrix', v_matrix);
END; $$;

CREATE OR REPLACE FUNCTION public.admin_list_account_role_gaps(p_actor_id uuid, p_actor_email text)
RETURNS TABLE (user_id uuid, org_id uuid, org_name text, role text, org_role text)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);

  PERFORM public._assert_super_admin(p_actor_id, p_actor_email);
  RETURN QUERY
  SELECT u.id, m.org_id, o.name, u.role::text, m.org_role
    FROM public.approved_users u
    JOIN public.organization_members m ON m.user_id = u.id AND m.org_id = u.organization_id
    JOIN public.organizations o ON o.id = m.org_id
   WHERE u.role = 'admin'::public.app_role
     AND m.org_role = 'member'
   ORDER BY lower(o.name), u.id;
END; $$;

CREATE OR REPLACE FUNCTION public.admin_list_docs_faq(p_actor_id uuid, p_actor_email text)
RETURNS SETOF public.docs_faq
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);

  PERFORM public._assert_super_admin(p_actor_id, p_actor_email);
  RETURN QUERY SELECT * FROM public.docs_faq ORDER BY sort_order, question;
END; $$;

CREATE OR REPLACE FUNCTION public.admin_list_organizations(p_actor_id uuid, p_actor_email text)
RETURNS TABLE (
  id uuid, name text, slug text, status text, created_at timestamptz,
  members bigint, projects bigint, cost_mtd numeric,
  access_period text, access_valid_from timestamptz, access_valid_until timestamptz,
  access_expired boolean, project_limit integer, user_limit integer,
  members_only_here bigint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);

  PERFORM public._assert_super_admin(p_actor_id, p_actor_email);
  RETURN QUERY
  SELECT o.id, o.name, o.slug, o.status, o.created_at,
         (SELECT count(*) FROM public.organization_members m WHERE m.org_id = o.id),
         (SELECT count(*) FROM public.projects p WHERE p.organization_id = o.id),
         COALESCE((SELECT sum(l.cost_usd) FROM public.ai_usage_logs l
                    WHERE l.org_id = o.id
                      AND l.created_at >= date_trunc('month', now())), 0),
         o.access_period, o.access_valid_from, o.access_valid_until,
         COALESCE(o.access_valid_until <= now(), false),
         o.project_limit, o.user_limit,
         (SELECT count(*) FROM public.organization_members m
           WHERE m.org_id = o.id
             AND NOT EXISTS (SELECT 1 FROM public.organization_members x
                              WHERE x.user_id = m.user_id AND x.org_id <> o.id))
  FROM public.organizations o
  ORDER BY o.name;
END; $$;

CREATE OR REPLACE FUNCTION public.admin_list_password_reset_requests(p_actor_id uuid, p_actor_email text)
RETURNS TABLE (
  id uuid, user_id uuid, email text, name text, role text, is_active boolean,
  organization text, requested_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);

  PERFORM public._assert_super_admin(p_actor_id, p_actor_email);
  RETURN QUERY
    SELECT r.id, r.user_id, au.email, au.name, au.role::text, au.is_active,
           o.name, r.requested_at
      FROM public.password_reset_requests r
      JOIN public.approved_users au ON au.id = r.user_id
      LEFT JOIN public.organizations o ON o.id = au.organization_id
     WHERE r.status = 'open'
     ORDER BY r.requested_at;
END; $$;

CREATE OR REPLACE FUNCTION public.admin_list_projects(p_actor_id uuid, p_actor_email text)
RETURNS TABLE (
  id uuid, name text, organization_id uuid, organization text,
  modeler_id uuid, owner_name text, owner_email text,
  plant_name text, supply_chain_model text, bom_level text, data_type text,
  completed boolean, simulation_start date, simulation_end date,
  created_at timestamptz, updated_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);

  PERFORM public._assert_super_admin(p_actor_id, p_actor_email);
  RETURN QUERY
  SELECT p.id, p.name, p.organization_id,
         COALESCE(o.name, p.organization),
         p.modeler_id,
         COALESCE(u.name, p.modeler_name),
         u.email,
         p.plant_name, p.supply_chain_model, p.bom_level, p.data_type,
         p.completed, p.simulation_start, p.simulation_end,
         p.created_at, p.updated_at
  FROM public.projects p
  LEFT JOIN public.organizations o ON o.id = p.organization_id
  LEFT JOIN public.approved_users u ON u.id = p.modeler_id
  ORDER BY p.updated_at DESC;
END; $$;

CREATE OR REPLACE FUNCTION public.admin_list_users_basic(p_actor_id uuid, p_actor_email text)
RETURNS TABLE (id uuid, name text, email text, role text, organization_id uuid,
               is_active boolean, org_ids uuid[])
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);

  PERFORM public._assert_super_admin(p_actor_id, p_actor_email);
  RETURN QUERY
  SELECT u.id, u.name, u.email, u.role::text, u.organization_id, u.is_active,
         COALESCE((SELECT array_agg(m.org_id ORDER BY m.org_id)
                     FROM public.organization_members m WHERE m.user_id = u.id),
                  ARRAY[]::uuid[])
  FROM public.approved_users u
  ORDER BY COALESCE(u.name, u.email);
END; $$;

CREATE OR REPLACE FUNCTION public.admin_list_users(p_actor_id uuid, p_actor_email text)
RETURNS TABLE (
  user_id uuid, name text, email text, role text, is_active boolean,
  organization_id uuid, organization text, organization_status text, org_role text,
  mtd_requests bigint, mtd_tokens bigint, mtd_cost_usd numeric,
  monthly_budget_usd numeric, created_at timestamptz,
  memberships jsonb)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);

  PERFORM public._assert_super_admin(p_actor_id, p_actor_email);
  RETURN QUERY
  SELECT au.id, au.name, au.email, au.role::text, au.is_active,
         au.organization_id, o.name, o.status, m.org_role,
         COALESCE(mtd.requests, 0)::bigint,
         COALESCE(mtd.tokens, 0)::bigint,
         COALESCE(mtd.cost_usd, 0)::numeric,
         (SELECT b.budget_usd FROM public.ai_budgets b
           WHERE b.scope = 'user' AND b.scope_id = au.id AND b.period = 'monthly' LIMIT 1),
         au.created_at,
         COALESCE((SELECT jsonb_agg(jsonb_build_object(
                             'org_id', mo.id, 'name', mo.name, 'status', mo.status,
                             'org_role', mm.org_role, 'is_current', mo.id = au.organization_id,
                             'is_default', mm.is_default)
                           ORDER BY lower(mo.name), mo.id)
                     FROM public.organization_members mm
                     JOIN public.organizations mo ON mo.id = mm.org_id
                    WHERE mm.user_id = au.id), '[]'::jsonb)
    FROM public.approved_users au
    LEFT JOIN public.organizations o ON o.id = au.organization_id
    LEFT JOIN public.organization_members m ON m.user_id = au.id AND m.org_id = au.organization_id
    LEFT JOIN LATERAL (
      SELECT count(*) AS requests, SUM(l.total_tokens) AS tokens, SUM(l.cost_usd) AS cost_usd
        FROM public.ai_usage_logs l
       WHERE l.user_id = au.id AND l.created_at >= date_trunc('month', now())
    ) mtd ON true
   ORDER BY COALESCE(mtd.cost_usd, 0) DESC, lower(COALESCE(au.name, au.email));
END; $$;

CREATE OR REPLACE FUNCTION public.admin_org_capacity_usage(p_actor_id uuid, p_actor_email text)
RETURNS TABLE (org_id uuid, org_name text, compute_used_rep_weeks bigint, compute_quota_rep_weeks_month bigint,
               storage_used_bytes bigint, storage_quota_bytes bigint, active_runs bigint,
               max_concurrent_runs integer, series_retention_days integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);

  PERFORM public._assert_super_admin(p_actor_id, p_actor_email);
  RETURN QUERY
  SELECT o.id, o.name, public._compute_used(o.id), o.compute_quota_rep_weeks_month,
         public._storage_used(o.id), o.storage_quota_bytes,
         (SELECT count(*) FROM public.simulation_runs r JOIN public.projects p ON p.id = r.project_id
           WHERE p.organization_id = o.id AND r.status IN ('queued','running')),
         o.max_concurrent_runs, o.series_retention_days
    FROM public.organizations o ORDER BY o.name;
END; $$;

CREATE OR REPLACE FUNCTION public.admin_platform_overview(p_actor_id uuid, p_actor_email text)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_month timestamptz := date_trunc('month', now());
  v_day   timestamptz := date_trunc('day', now());
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);

  PERFORM public._assert_super_admin(p_actor_id, p_actor_email);
  RETURN jsonb_build_object(
    'month_start', v_month,
    'day_start',   v_day,
    'organizations', (SELECT count(*) FROM public.organizations),
    'projects',      (SELECT count(*) FROM public.projects),
    'users',         (SELECT count(*) FROM public.approved_users),
    'users_suspended', (SELECT count(*) FROM public.approved_users WHERE NOT is_active),
    'requests',      (SELECT count(*) FROM public.ai_usage_logs),
    'cost_today',    (SELECT COALESCE(sum(cost_usd), 0) FROM public.ai_usage_logs WHERE created_at >= v_day),
    'cost_mtd',      (SELECT COALESCE(sum(cost_usd), 0) FROM public.ai_usage_logs WHERE created_at >= v_month),
    'requests_mtd',  (SELECT count(*) FROM public.ai_usage_logs WHERE created_at >= v_month),
    'active_users_7d', (SELECT count(DISTINCT user_id) FROM public.ai_usage_logs
                         WHERE created_at >= now() - interval '7 days' AND user_id IS NOT NULL),
    'top_users', COALESCE((
      SELECT jsonb_agg(t ORDER BY (t ->> 'cost')::numeric DESC, (t ->> 'requests')::bigint DESC)
        FROM (SELECT jsonb_build_object(
                       'user_id', l.user_id,
                       'label', COALESCE(u.name, u.email, 'Deleted account'),
                       'requests', count(*),
                       'cost', COALESCE(sum(l.cost_usd), 0)) AS t
                FROM public.ai_usage_logs l
                LEFT JOIN public.approved_users u ON u.id = l.user_id
               WHERE l.created_at >= v_month AND l.user_id IS NOT NULL
               GROUP BY l.user_id, u.name, u.email
               ORDER BY COALESCE(sum(l.cost_usd), 0) DESC, count(*) DESC
               LIMIT 10) s), '[]'::jsonb),
    'top_orgs', COALESCE((
      SELECT jsonb_agg(t ORDER BY (t ->> 'cost')::numeric DESC, (t ->> 'requests')::bigint DESC)
        FROM (SELECT jsonb_build_object(
                       'org_id', l.org_id,
                       'label', CASE WHEN l.org_id IS NULL THEN 'Unassigned'
                                     ELSE COALESCE(o.name, 'Deleted organization') END,
                       'requests', count(*),
                       'cost', COALESCE(sum(l.cost_usd), 0)) AS t
                FROM public.ai_usage_logs l
                LEFT JOIN public.organizations o ON o.id = l.org_id
               WHERE l.created_at >= v_month
               GROUP BY l.org_id, o.name
               ORDER BY COALESCE(sum(l.cost_usd), 0) DESC, count(*) DESC
               LIMIT 10) s), '[]'::jsonb));
END; $$;

CREATE OR REPLACE FUNCTION public.admin_preview_role_capability(
  p_actor_id uuid, p_actor_email text, p_role text, p_capability_key text, p_allowed boolean)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_changes jsonb;
  v_scoped  boolean;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);

  PERFORM public.set_current_user_context(p_actor_id, p_actor_email);
  IF NOT public.is_super_admin(p_actor_id) THEN RAISE EXCEPTION 'forbidden'; END IF;
  v_scoped := EXISTS (SELECT 1 FROM public.project_role_capabilities WHERE capability_key = p_capability_key);
  IF NOT v_scoped THEN
    RETURN jsonb_build_object('project_scoped', false, 'changes', '[]'::jsonb);
  END IF;

  -- Each membership whose account role is p_role, re-decided with the switch flipped. Only a
  -- right whose account answer comes from the account role moves: an organization or person
  -- override already decides it.
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'user_id', h.user_id, 'name', COALESCE(u.name, u.email), 'project_id', h.project_id,
           'project_name', p.name, 'project_role', h.project_role,
           'before', (d.value ->> 'allowed')::boolean, 'after', (n.v ->> 'allowed')::boolean)
           ORDER BY lower(COALESCE(u.name, u.email, '')), p.name), '[]'::jsonb)
    INTO v_changes
    FROM public.project_role_holdings() h
    JOIN public.approved_users u ON u.id = h.user_id
    JOIN public.projects p ON p.id = h.project_id
    CROSS JOIN LATERAL (SELECT public.project_right_decisions(h.user_id, h.project_id) -> p_capability_key AS value) d
    CROSS JOIN LATERAL (SELECT public.project_right_decide(
                          false, (d.value ->> 'person_override')::boolean, h.project_role,
                          (d.value ->> 'project_grant')::boolean,
                          CASE WHEN d.value ->> 'account_source' = 'organization'
                               THEN (d.value ->> 'account_allows')::boolean
                               ELSE COALESCE(p_allowed, false) END) AS v) n
   WHERE h.account_role = p_role
     AND (d.value ->> 'allowed')::boolean IS DISTINCT FROM (n.v ->> 'allowed')::boolean;

  RETURN jsonb_build_object('project_scoped', true, 'changes', v_changes);
END; $$;

CREATE OR REPLACE FUNCTION public.admin_remove_org_member(
  p_actor_id uuid, p_actor_email text, p_target_user_id uuid, p_org_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_before jsonb;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);

  PERFORM public._assert_super_admin(p_actor_id, p_actor_email);
  PERFORM public.set_current_user_context(p_actor_id, p_actor_email);
  SELECT to_jsonb(m) INTO v_before FROM public.organization_members m
   WHERE m.org_id = p_org_id AND m.user_id = p_target_user_id;
  IF v_before IS NULL THEN
    RAISE EXCEPTION 'not_a_member: the account does not belong to that organization';
  END IF;

  DELETE FROM public.organization_members WHERE org_id = p_org_id AND user_id = p_target_user_id;

  PERFORM public.log_admin_action('org.member_remove', 'organization_members', p_target_user_id::text, v_before,
    jsonb_build_object('organization_id',
      (SELECT organization_id FROM public.approved_users WHERE id = p_target_user_id)));
END; $$;

CREATE OR REPLACE FUNCTION public.admin_remove_project_member(
  p_actor_id uuid, p_actor_email text, p_target_user_id uuid, p_project_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_before jsonb;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_inputs');

  PERFORM public._assert_super_admin(p_actor_id, p_actor_email);
  IF EXISTS (SELECT 1 FROM public.projects WHERE id = p_project_id AND modeler_id = p_target_user_id) THEN
    RAISE EXCEPTION 'this user owns the project (its modeler) and stays a standing owner — transfer the project on /admin/projects first';
  END IF;
  DELETE FROM public.project_members pm
   WHERE pm.project_id = p_project_id AND pm.user_id = p_target_user_id
  RETURNING to_jsonb(pm) INTO v_before;
  IF v_before IS NULL THEN RAISE EXCEPTION 'no membership to remove'; END IF;
  PERFORM public.log_admin_action('project.member_remove', 'project_members',
    p_project_id::text || ':' || p_target_user_id::text, v_before, NULL);
END; $$;

CREATE OR REPLACE FUNCTION public.admin_rename_project(
  p_actor_id uuid, p_actor_email text, p_project_id uuid, p_name text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_before jsonb;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_inputs');

  PERFORM public._assert_super_admin(p_actor_id, p_actor_email);
  IF p_name IS NULL OR btrim(p_name) = '' THEN RAISE EXCEPTION 'name required'; END IF;
  SELECT to_jsonb(p) INTO v_before FROM public.projects p WHERE p.id = p_project_id;
  IF v_before IS NULL THEN RAISE EXCEPTION 'project not found'; END IF;
  BEGIN
    UPDATE public.projects SET name = btrim(p_name), updated_at = now() WHERE id = p_project_id;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'the owner already has a project named "%" for this plant', btrim(p_name);
  END;
  PERFORM public.log_admin_action('project.rename', 'projects', p_project_id::text,
    v_before, jsonb_build_object('name', btrim(p_name)));
END; $$;

CREATE OR REPLACE FUNCTION public.admin_reset_user_password(
  p_actor_id uuid, p_actor_email text, p_target_user_id uuid, p_new_password text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_closed uuid[];
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);

  PERFORM public._assert_super_admin(p_actor_id, p_actor_email);
  IF p_new_password IS NULL OR length(p_new_password) < 8 THEN RAISE EXCEPTION 'password_too_short'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.approved_users WHERE id = p_target_user_id) THEN
    RAISE EXCEPTION 'user not found';
  END IF;
  UPDATE public.approved_users
     SET password_hash = extensions.crypt(p_new_password, extensions.gen_salt('bf')),
         password_changed_at = now(),
         password_expires_at = now() + public.password_max_age(),
         force_password_change = true,
         updated_at = now()
   WHERE id = p_target_user_id;
  WITH closed AS (
    UPDATE public.password_reset_requests
       SET status = 'resolved', closed_at = now(), closed_by = p_actor_id
     WHERE user_id = p_target_user_id AND status = 'open'
    RETURNING id
  )
  SELECT array_agg(id) INTO v_closed FROM closed;
  PERFORM public.log_admin_action('user.reset_password', 'approved_users', p_target_user_id::text, NULL,
    CASE WHEN v_closed IS NULL THEN NULL
         ELSE jsonb_build_object('resolved_request_id', v_closed[1]) END);
END; $$;

CREATE OR REPLACE FUNCTION public.admin_save_docs_faq(
  p_actor_id uuid, p_actor_email text, p_id uuid,
  p_question text, p_answer text, p_section_key text,
  p_related_slugs text[], p_sort_order integer, p_is_published boolean)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_before public.docs_faq; v_id uuid;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);

  PERFORM public._assert_super_admin(p_actor_id, p_actor_email);
  IF p_id IS NULL THEN
    INSERT INTO public.docs_faq
      (question, answer, section_key, related_slugs, sort_order, is_published, created_by, updated_by)
    VALUES (btrim(p_question), p_answer, NULLIF(btrim(p_section_key), ''),
            COALESCE(p_related_slugs, '{}'), COALESCE(p_sort_order, 0),
            COALESCE(p_is_published, false), p_actor_id, p_actor_id)
    RETURNING id INTO v_id;
    PERFORM public.log_admin_action('docs.faq_create', 'docs_faq', v_id::text, NULL,
      jsonb_build_object('question', btrim(p_question), 'is_published', COALESCE(p_is_published, false)));
  ELSE
    SELECT * INTO v_before FROM public.docs_faq WHERE id = p_id FOR UPDATE;
    IF v_before.id IS NULL THEN RAISE EXCEPTION 'question not found' USING ERRCODE = '42704'; END IF;
    UPDATE public.docs_faq
       SET question = btrim(p_question), answer = p_answer,
           section_key = NULLIF(btrim(p_section_key), ''),
           related_slugs = COALESCE(p_related_slugs, '{}'),
           sort_order = COALESCE(p_sort_order, 0),
           is_published = COALESCE(p_is_published, false),
           updated_at = now(), updated_by = p_actor_id
     WHERE id = p_id;
    v_id := p_id;
    PERFORM public.log_admin_action('docs.faq_update', 'docs_faq', v_id::text,
      jsonb_build_object('question', v_before.question, 'is_published', v_before.is_published),
      jsonb_build_object('question', btrim(p_question), 'is_published', COALESCE(p_is_published, false)));
  END IF;
  RETURN v_id;
END; $$;

CREATE OR REPLACE FUNCTION public.admin_set_capability(
  p_actor_id uuid, p_actor_email text,
  p_scope text, p_scope_id text, p_capability_key text, p_allowed boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_before boolean;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);

  PERFORM public.set_current_user_context(p_actor_id, p_actor_email);
  IF NOT public.is_super_admin(p_actor_id) THEN RAISE EXCEPTION 'forbidden'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.capabilities WHERE key = p_capability_key) THEN
    RAISE EXCEPTION 'unknown capability %', p_capability_key;
  END IF;

  IF p_scope = 'user' THEN
    SELECT allowed INTO v_before FROM public.user_capabilities
      WHERE user_id = p_scope_id::uuid AND capability_key = p_capability_key;
    IF p_allowed IS NULL THEN
      DELETE FROM public.user_capabilities WHERE user_id = p_scope_id::uuid AND capability_key = p_capability_key;
    ELSE
      INSERT INTO public.user_capabilities (user_id, capability_key, allowed)
      VALUES (p_scope_id::uuid, p_capability_key, p_allowed)
      ON CONFLICT (user_id, capability_key) DO UPDATE SET allowed = EXCLUDED.allowed, updated_at = now();
    END IF;
  ELSIF p_scope = 'org' THEN
    SELECT allowed INTO v_before FROM public.org_capabilities
      WHERE org_id = p_scope_id::uuid AND capability_key = p_capability_key;
    IF p_allowed IS NULL THEN
      DELETE FROM public.org_capabilities WHERE org_id = p_scope_id::uuid AND capability_key = p_capability_key;
    ELSE
      INSERT INTO public.org_capabilities (org_id, capability_key, allowed)
      VALUES (p_scope_id::uuid, p_capability_key, p_allowed)
      ON CONFLICT (org_id, capability_key) DO UPDATE SET allowed = EXCLUDED.allowed, updated_at = now();
    END IF;
  ELSIF p_scope = 'role' THEN
    IF p_scope_id NOT IN ('super_admin','admin','modeler','user') THEN RAISE EXCEPTION 'unknown role %', p_scope_id; END IF;
    SELECT allowed INTO v_before FROM public.role_capabilities
      WHERE role = p_scope_id AND capability_key = p_capability_key;
    INSERT INTO public.role_capabilities (role, capability_key, allowed)
    VALUES (p_scope_id, p_capability_key, COALESCE(p_allowed, false))
    ON CONFLICT (role, capability_key) DO UPDATE SET allowed = EXCLUDED.allowed, updated_at = now();
  ELSE
    RAISE EXCEPTION 'unknown scope %', p_scope;
  END IF;

  PERFORM public.log_admin_action(
    'access.capability_set', p_scope, p_scope_id,
    jsonb_build_object('capability', p_capability_key, 'allowed', v_before),
    jsonb_build_object('capability', p_capability_key, 'allowed', p_allowed));
END; $$;

CREATE OR REPLACE FUNCTION public.admin_set_default_org(
  p_actor_id uuid, p_actor_email text, p_target_user_id uuid, p_org_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_before uuid;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);

  PERFORM public._assert_super_admin(p_actor_id, p_actor_email);
  PERFORM public.set_current_user_context(p_actor_id, p_actor_email);
  IF NOT EXISTS (SELECT 1 FROM public.approved_users WHERE id = p_target_user_id) THEN
    RAISE EXCEPTION 'user not found';
  END IF;
  IF p_org_id IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM public.organization_members
        WHERE org_id = p_org_id AND user_id = p_target_user_id) THEN
    RAISE EXCEPTION 'not_a_member: the default organization must be one the account belongs to — add it first'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT org_id INTO v_before FROM public.organization_members
   WHERE user_id = p_target_user_id AND is_default;
  IF v_before IS NOT DISTINCT FROM p_org_id THEN
    RETURN;
  END IF;

  -- Clear first: the partial unique index admits one default per account at any moment.
  UPDATE public.organization_members SET is_default = false
   WHERE user_id = p_target_user_id AND is_default;
  IF p_org_id IS NOT NULL THEN
    UPDATE public.organization_members SET is_default = true
     WHERE user_id = p_target_user_id AND org_id = p_org_id;
  END IF;

  PERFORM public.log_admin_action('org.default_set', 'approved_users', p_target_user_id::text,
    jsonb_build_object('default_org_id', v_before),
    jsonb_build_object('default_org_id', p_org_id));
END; $$;

CREATE OR REPLACE FUNCTION public.admin_set_docs_section_audience(
  p_actor_id uuid, p_actor_email text, p_section_key text, p_audience text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_before text;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);

  PERFORM public._assert_super_admin(p_actor_id, p_actor_email);
  IF p_audience IS NULL OR p_audience NOT IN ('public','internal','confidential') THEN
    RAISE EXCEPTION 'invalid audience %', p_audience USING ERRCODE = '22023';
  END IF;
  IF p_section_key IS NULL OR p_section_key !~ '^[a-z][a-z0-9-]*$' THEN
    RAISE EXCEPTION 'invalid section key %', p_section_key USING ERRCODE = '22023';
  END IF;
  SELECT audience INTO v_before FROM public.docs_section_releases WHERE section_key = p_section_key;
  IF v_before IS NOT DISTINCT FROM p_audience THEN RETURN; END IF;
  INSERT INTO public.docs_section_releases (section_key, audience, updated_at, updated_by)
  VALUES (p_section_key, p_audience, now(), p_actor_id)
  ON CONFLICT (section_key) DO UPDATE
    SET audience = EXCLUDED.audience, updated_at = now(), updated_by = EXCLUDED.updated_by;
  PERFORM public.log_admin_action('docs.section_audience', 'docs_section_releases', p_section_key,
    jsonb_build_object('audience', COALESCE(v_before, 'confidential')),
    jsonb_build_object('audience', p_audience));
END; $$;

CREATE OR REPLACE FUNCTION public.admin_set_org_access_period(
  p_actor_id uuid, p_actor_email text, p_org_id uuid, p_period text)
RETURNS timestamptz LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_before jsonb; v_until timestamptz;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);

  PERFORM public._assert_super_admin(p_actor_id, p_actor_email);
  IF p_period IS NOT NULL AND p_period NOT IN ('week', 'month', 'quarter', 'year') THEN
    RAISE EXCEPTION 'invalid access period %', p_period;
  END IF;
  SELECT jsonb_build_object('access_period', access_period,
                            'access_valid_from', access_valid_from,
                            'access_valid_until', access_valid_until)
    INTO v_before FROM public.organizations WHERE id = p_org_id;
  IF v_before IS NULL THEN RAISE EXCEPTION 'organization not found'; END IF;

  UPDATE public.organizations
     SET access_period     = p_period,
         access_valid_from = CASE WHEN p_period IS NULL THEN NULL ELSE now() END,
         updated_at        = now()
   WHERE id = p_org_id
  RETURNING access_valid_until INTO v_until;

  PERFORM public.log_admin_action('org.access_period', 'organizations', p_org_id::text, v_before,
    jsonb_build_object('access_period', p_period, 'access_valid_until', v_until));
  RETURN v_until;
END; $$;

CREATE OR REPLACE FUNCTION public.admin_set_org_capacity(
  p_actor_id uuid, p_actor_email text, p_org_id uuid,
  p_storage_quota_bytes bigint, p_compute_quota_rep_weeks_month bigint,
  p_max_replications_per_run integer, p_max_concurrent_runs integer,
  p_series_retention_days integer)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_before jsonb;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);

  PERFORM public._assert_super_admin(p_actor_id, p_actor_email);
  SELECT jsonb_build_object('storage_quota_bytes', storage_quota_bytes,
           'compute_quota_rep_weeks_month', compute_quota_rep_weeks_month,
           'max_replications_per_run', max_replications_per_run,
           'max_concurrent_runs', max_concurrent_runs, 'series_retention_days', series_retention_days)
    INTO v_before FROM public.organizations WHERE id = p_org_id;
  IF v_before IS NULL THEN RAISE EXCEPTION 'organization not found'; END IF;
  UPDATE public.organizations
     SET storage_quota_bytes = p_storage_quota_bytes,
         compute_quota_rep_weeks_month = p_compute_quota_rep_weeks_month,
         max_replications_per_run = p_max_replications_per_run,
         max_concurrent_runs = p_max_concurrent_runs,
         series_retention_days = p_series_retention_days,
         updated_at = now()
   WHERE id = p_org_id;
  -- A new retention period re-dates the organization's standard runs from when
  -- each ended (never into the past: a shortened period expires at the next
  -- sweep, not retroactively mid-read); NULL keeps their series without limit.
  IF (v_before ->> 'series_retention_days') IS DISTINCT FROM p_series_retention_days::text THEN
    UPDATE public.simulation_runs r
       SET series_expires_at = CASE WHEN p_series_retention_days IS NULL THEN NULL
             ELSE GREATEST(COALESCE(r.ended_at, r.created_at) + make_interval(days => p_series_retention_days), now()) END
      FROM public.projects p
     WHERE p.id = r.project_id AND p.organization_id = p_org_id
       AND r.status = 'done' AND r.retention = 'standard' AND r.series_expired_at IS NULL;
  END IF;
  PERFORM public.log_admin_action('org.capacity', 'organizations', p_org_id::text, v_before,
    jsonb_build_object('storage_quota_bytes', p_storage_quota_bytes,
      'compute_quota_rep_weeks_month', p_compute_quota_rep_weeks_month,
      'max_replications_per_run', p_max_replications_per_run,
      'max_concurrent_runs', p_max_concurrent_runs, 'series_retention_days', p_series_retention_days));
END; $$;

CREATE OR REPLACE FUNCTION public.admin_set_org_limits(
  p_actor_id uuid, p_actor_email text, p_org_id uuid,
  p_project_limit integer, p_user_limit integer)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_before jsonb;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);

  PERFORM public._assert_super_admin(p_actor_id, p_actor_email);
  IF p_project_limit IS NOT NULL AND p_project_limit NOT IN (1, 2, 3, 5, 10, 20, 50, 100) THEN
    RAISE EXCEPTION 'invalid project limit %', p_project_limit;
  END IF;
  IF p_user_limit IS NOT NULL AND p_user_limit NOT IN (1, 2, 3, 5, 10, 20, 50, 100) THEN
    RAISE EXCEPTION 'invalid user limit %', p_user_limit;
  END IF;
  SELECT jsonb_build_object('project_limit', project_limit, 'user_limit', user_limit)
    INTO v_before FROM public.organizations WHERE id = p_org_id;
  IF v_before IS NULL THEN RAISE EXCEPTION 'organization not found'; END IF;

  UPDATE public.organizations
     SET project_limit = p_project_limit, user_limit = p_user_limit, updated_at = now()
   WHERE id = p_org_id;

  PERFORM public.log_admin_action('org.limits', 'organizations', p_org_id::text, v_before,
    jsonb_build_object('project_limit', p_project_limit, 'user_limit', p_user_limit));
END; $$;

CREATE OR REPLACE FUNCTION public.admin_set_org_status(
  p_actor_id uuid, p_actor_email text, p_org_id uuid, p_status text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_before text;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);

  PERFORM public._assert_super_admin(p_actor_id, p_actor_email);
  IF p_status NOT IN ('active','suspended') THEN RAISE EXCEPTION 'invalid status %', p_status; END IF;
  SELECT status INTO v_before FROM public.organizations WHERE id = p_org_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'organization not found'; END IF;
  UPDATE public.organizations SET status = p_status WHERE id = p_org_id;
  PERFORM public.log_admin_action('org.set_status', 'organizations', p_org_id::text,
    jsonb_build_object('status', v_before), jsonb_build_object('status', p_status));
END; $$;

CREATE OR REPLACE FUNCTION public.admin_set_project_member(
  p_actor_id uuid, p_actor_email text, p_target_user_id uuid, p_project_id uuid,
  p_project_role text, p_expires_at timestamptz DEFAULT NULL, p_rationale text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_modeler uuid; v_found boolean; v_before jsonb;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_inputs');

  PERFORM public._assert_super_admin(p_actor_id, p_actor_email);
  IF p_project_role IS NULL OR public.project_role_rank(p_project_role) = 0 THEN
    RAISE EXCEPTION 'invalid project role %', p_project_role;
  END IF;
  IF p_expires_at IS NOT NULL AND p_expires_at <= now() THEN
    RAISE EXCEPTION 'expires_at % is already in the past', p_expires_at;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.approved_users WHERE id = p_target_user_id) THEN
    RAISE EXCEPTION 'user not found';
  END IF;
  SELECT modeler_id, true INTO v_modeler, v_found FROM public.projects WHERE id = p_project_id;
  IF v_found IS NULL THEN RAISE EXCEPTION 'project not found'; END IF;
  IF v_modeler = p_target_user_id AND (p_project_role <> 'owner' OR p_expires_at IS NOT NULL) THEN
    RAISE EXCEPTION 'this user owns the project (its modeler) and stays a standing owner — transfer the project on /admin/projects first';
  END IF;

  SELECT to_jsonb(pm) INTO v_before FROM public.project_members pm
   WHERE pm.project_id = p_project_id AND pm.user_id = p_target_user_id;
  INSERT INTO public.project_members (project_id, user_id, project_role, granted_by, expires_at, rationale)
  VALUES (p_project_id, p_target_user_id, p_project_role, p_actor_id, p_expires_at,
          NULLIF(btrim(COALESCE(p_rationale, '')), ''))
  ON CONFLICT (project_id, user_id) DO UPDATE
    SET project_role = EXCLUDED.project_role,
        granted_by   = EXCLUDED.granted_by,
        expires_at   = EXCLUDED.expires_at,
        rationale    = COALESCE(EXCLUDED.rationale, project_members.rationale),
        updated_at   = now();
  PERFORM public.log_admin_action('project.member_set', 'project_members',
    p_project_id::text || ':' || p_target_user_id::text, v_before,
    jsonb_build_object('project_id', p_project_id, 'user_id', p_target_user_id,
                       'project_role', p_project_role, 'expires_at', p_expires_at));
END; $$;

CREATE OR REPLACE FUNCTION public.admin_set_role_allowance(
  p_actor_id uuid, p_actor_email text, p_org_id uuid, p_project_role text,
  p_compute_share_pct numeric, p_storage_share_pct numeric, p_max_concurrent integer)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);

  PERFORM public._assert_super_admin(p_actor_id, p_actor_email);
  PERFORM set_config('app.current_user_id', p_actor_id::text, true);
  INSERT INTO public.plan_role_allowances (org_id, project_role, compute_share_pct, storage_share_pct, max_concurrent)
  VALUES (p_org_id, p_project_role, p_compute_share_pct, p_storage_share_pct, p_max_concurrent)
  ON CONFLICT ON CONSTRAINT plan_role_allowances_org_role_key DO UPDATE
     SET compute_share_pct = EXCLUDED.compute_share_pct, storage_share_pct = EXCLUDED.storage_share_pct,
         max_concurrent = EXCLUDED.max_concurrent, updated_at = now();
  PERFORM public.log_admin_action('org.role_allowance', 'plan_role_allowances',
    COALESCE(p_org_id::text, 'default') || ':' || p_project_role, NULL,
    jsonb_build_object('compute_share_pct', p_compute_share_pct, 'storage_share_pct', p_storage_share_pct,
                       'max_concurrent', p_max_concurrent));
END; $$;

CREATE OR REPLACE FUNCTION public.admin_set_user_active(
  p_actor_id uuid, p_actor_email text, p_target_user_id uuid, p_is_active boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_before boolean; v_role text;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);

  PERFORM public._assert_super_admin(p_actor_id, p_actor_email);
  IF p_is_active IS NULL THEN RAISE EXCEPTION 'is_active must be true or false'; END IF;
  SELECT is_active, role::text INTO v_before, v_role FROM public.approved_users WHERE id = p_target_user_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'user not found'; END IF;
  IF NOT p_is_active THEN
    IF p_target_user_id = p_actor_id THEN
      RAISE EXCEPTION 'you cannot suspend your own account';
    END IF;
    PERFORM public._lock_active_super_admins();
    IF v_role = 'super_admin' AND v_before AND public._active_super_admin_count() <= 1 THEN
      RAISE EXCEPTION 'cannot suspend the last active super admin';
    END IF;
  END IF;
  UPDATE public.approved_users SET is_active = p_is_active WHERE id = p_target_user_id;
  PERFORM public.log_admin_action('user.set_active', 'approved_users', p_target_user_id::text,
    jsonb_build_object('is_active', v_before), jsonb_build_object('is_active', p_is_active));
END; $$;

CREATE OR REPLACE FUNCTION public.admin_set_user_budget(
  p_actor_id uuid, p_actor_email text, p_target_user_id uuid, p_period text,
  p_budget_usd numeric, p_token_limit bigint, p_rpm integer, p_rpd integer)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_before jsonb;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);

  PERFORM public.set_current_user_context(p_actor_id, p_actor_email);
  IF NOT public.is_super_admin(p_actor_id) THEN RAISE EXCEPTION 'forbidden'; END IF;
  IF p_period NOT IN ('daily','monthly') THEN RAISE EXCEPTION 'bad period %', p_period; END IF;

  SELECT to_jsonb(b) INTO v_before FROM public.ai_budgets b
   WHERE b.scope='user' AND b.scope_id=p_target_user_id AND b.period=p_period;

  IF p_budget_usd IS NULL AND p_token_limit IS NULL AND p_rpm IS NULL AND p_rpd IS NULL THEN
    DELETE FROM public.ai_budgets WHERE scope='user' AND scope_id=p_target_user_id AND period=p_period;
  ELSE
    INSERT INTO public.ai_budgets (scope, scope_id, period, budget_usd, token_limit, rpm, rpd)
    VALUES ('user', p_target_user_id, p_period, p_budget_usd, p_token_limit, p_rpm, p_rpd)
    ON CONFLICT (scope, scope_id, period) DO UPDATE
      SET budget_usd = EXCLUDED.budget_usd, token_limit = EXCLUDED.token_limit,
          rpm = EXCLUDED.rpm, rpd = EXCLUDED.rpd, updated_at = now();
  END IF;

  PERFORM public.log_admin_action(
    'access.budget_set', 'approved_users', p_target_user_id::text, v_before,
    jsonb_build_object('period', p_period, 'budget_usd', p_budget_usd,
                       'token_limit', p_token_limit, 'rpm', p_rpm, 'rpd', p_rpd));
END; $$;

CREATE OR REPLACE FUNCTION public.admin_set_user_models(
  p_actor_id uuid, p_actor_email text, p_target_user_id uuid,
  p_allowed_model_ids uuid[], p_default_model_id uuid, p_fallback_model_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_before jsonb;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);

  PERFORM public.set_current_user_context(p_actor_id, p_actor_email);
  IF NOT public.is_super_admin(p_actor_id) THEN RAISE EXCEPTION 'forbidden'; END IF;

  SELECT to_jsonb(u) INTO v_before FROM public.user_ai_permissions u WHERE u.user_id = p_target_user_id;

  INSERT INTO public.user_ai_permissions (user_id, allowed_model_ids, default_model_id, fallback_model_id)
  VALUES (p_target_user_id, COALESCE(p_allowed_model_ids, '{}'), p_default_model_id, p_fallback_model_id)
  ON CONFLICT (user_id) DO UPDATE
    SET allowed_model_ids = EXCLUDED.allowed_model_ids,
        default_model_id  = EXCLUDED.default_model_id,
        fallback_model_id = EXCLUDED.fallback_model_id,
        updated_at = now();

  PERFORM public.log_admin_action(
    'access.models_set', 'approved_users', p_target_user_id::text, v_before,
    jsonb_build_object('allowed_model_ids', to_jsonb(COALESCE(p_allowed_model_ids, '{}')),
                       'default_model_id', p_default_model_id, 'fallback_model_id', p_fallback_model_id));
END; $$;

CREATE OR REPLACE FUNCTION public.admin_set_user_org_role(
  p_actor_id uuid, p_actor_email text, p_target_user_id uuid, p_org_id uuid, p_org_role text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_before text;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);

  PERFORM public._assert_super_admin(p_actor_id, p_actor_email);
  IF p_org_role IS NULL OR p_org_role NOT IN ('owner','admin','member') THEN
    RAISE EXCEPTION 'invalid organization role %', p_org_role;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.approved_users WHERE id = p_target_user_id) THEN
    RAISE EXCEPTION 'user not found';
  END IF;
  SELECT org_role INTO v_before FROM public.organization_members
   WHERE org_id = p_org_id AND user_id = p_target_user_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_a_member: the account does not belong to that organization';
  END IF;
  IF v_before = p_org_role THEN RETURN; END IF;
  UPDATE public.organization_members SET org_role = p_org_role
   WHERE org_id = p_org_id AND user_id = p_target_user_id;
  PERFORM public.log_admin_action('user.org_role_change', 'organization_members', p_target_user_id::text,
    jsonb_build_object('org_id', p_org_id, 'org_role', v_before),
    jsonb_build_object('org_id', p_org_id, 'org_role', p_org_role));
END; $$;

CREATE OR REPLACE FUNCTION public.admin_set_user_role(
  p_actor_id uuid, p_actor_email text, p_target_user_id uuid, p_role text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_before     text;
  v_active     boolean;
  v_org        uuid;
  v_org_name   text;
  v_org_before text;
  v_org_after  text;
  v_overrides  jsonb;
  v_narrowed   jsonb;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);

  PERFORM public._assert_super_admin(p_actor_id, p_actor_email);
  IF p_role NOT IN ('super_admin','admin','modeler','user') THEN RAISE EXCEPTION 'invalid role %', p_role; END IF;
  SELECT role::text, is_active INTO v_before, v_active FROM public.approved_users WHERE id = p_target_user_id;
  IF v_before IS NULL THEN RAISE EXCEPTION 'user not found'; END IF;
  IF v_before = 'super_admin' AND p_role <> 'super_admin' THEN
    IF p_target_user_id = p_actor_id THEN
      RAISE EXCEPTION 'you cannot remove your own super_admin role — ask another super admin';
    END IF;
    PERFORM public._lock_active_super_admins();
    IF v_active AND public._active_super_admin_count() <= 1 THEN
      RAISE EXCEPTION 'cannot demote the last active super admin';
    END IF;
  END IF;
  UPDATE public.approved_users SET role = p_role::public.app_role WHERE id = p_target_user_id;
  PERFORM public.log_admin_action('user.role_change', 'approved_users', p_target_user_id::text,
    jsonb_build_object('role', v_before), jsonb_build_object('role', p_role));

  -- D278 — the ACTIVE organization's member/admin role follows; owner and every other
  -- membership are not this verb's (D210).
  SELECT u.organization_id, o.name INTO v_org, v_org_name
    FROM public.approved_users u
    LEFT JOIN public.organizations o ON o.id = u.organization_id
   WHERE u.id = p_target_user_id;
  IF v_org IS NOT NULL THEN
    SELECT m.org_role INTO v_org_before FROM public.organization_members m
     WHERE m.org_id = v_org AND m.user_id = p_target_user_id
       FOR UPDATE;
    v_org_after := CASE
      WHEN v_org_before = 'member' AND p_role = 'admin'                        THEN 'admin'
      WHEN v_org_before = 'admin'  AND v_before = 'admin' AND p_role <> 'admin' THEN 'member'
      ELSE v_org_before END;
    IF v_org_after IS DISTINCT FROM v_org_before THEN
      UPDATE public.organization_members SET org_role = v_org_after
       WHERE org_id = v_org AND user_id = p_target_user_id;
      PERFORM public.log_admin_action('user.org_role_change', 'organization_members', p_target_user_id::text,
        jsonb_build_object('org_id', v_org, 'org_role', v_org_before),
        jsonb_build_object('org_id', v_org, 'org_role', v_org_after));
    END IF;
  END IF;

  -- What still decides instead: the override that decides each key, where it now differs
  -- from the new role's default. A super admin skips every layer, so none decides.
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'key', c.key, 'label', c.label, 'kind', c.kind,
           'layer', CASE WHEN y.user_ IS NOT NULL THEN 'person' ELSE 'organization' END,
           'allowed', COALESCE(y.user_, y.org_),
           'role_default', y.default_)
           ORDER BY c.sort_order, c.key), '[]'::jsonb)
    INTO v_overrides
    FROM public.capabilities c
    CROSS JOIN LATERAL (SELECT
      (SELECT uc.allowed FROM public.user_capabilities uc
        WHERE uc.user_id = p_target_user_id AND uc.capability_key = c.key) AS user_,
      (SELECT oc.allowed FROM public.org_capabilities oc
        WHERE oc.org_id = v_org AND oc.capability_key = c.key)            AS org_,
      COALESCE((SELECT rc.allowed FROM public.role_capabilities rc
        WHERE rc.role = p_role AND rc.capability_key = c.key), false)     AS default_) y
   WHERE p_role <> 'super_admin'
     AND c.key <> '/profile'
     AND COALESCE(y.user_, y.org_) IS NOT NULL
     AND COALESCE(y.user_, y.org_) IS DISTINCT FROM y.default_;

  -- …and every project whose ROLE refuses a right the account now allows, as D276's rule
  -- answers it (`project_right_decisions`), not as this function would guess it.
  WITH reach AS (
    SELECT pm.project_id AS id FROM public.project_members pm WHERE pm.user_id = p_target_user_id
    UNION
    SELECT dg.project_id FROM public.delegation_grants dg
     WHERE dg.grantee_user_id = p_target_user_id AND dg.revoked_at IS NULL AND dg.expires_at > now()
    UNION
    SELECT p.id FROM public.projects p WHERE p.modeler_id = p_target_user_id
  ), narrowed AS (
    SELECT p.id, p.name, d.value ->> 'project_role' AS project_role,
           jsonb_agg(jsonb_build_object('key', d.key, 'label', COALESCE(c.label, d.key))
                     ORDER BY c.sort_order, d.key) AS keys
      FROM reach
      JOIN public.projects p ON p.id = reach.id
      CROSS JOIN LATERAL jsonb_each(public.project_right_decisions(p_target_user_id, p.id)) d
      LEFT JOIN public.capabilities c ON c.key = d.key
     WHERE d.value ->> 'decided_by' = 'project_role'
       AND (d.value ->> 'allowed')::boolean IS FALSE
       AND (d.value ->> 'account_allows')::boolean IS TRUE
     GROUP BY p.id, p.name, d.value ->> 'project_role'
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'project_id', n.id, 'name', n.name, 'project_role', n.project_role, 'keys', n.keys)
           ORDER BY lower(n.name), n.id), '[]'::jsonb)
    INTO v_narrowed
    FROM narrowed n;

  RETURN jsonb_build_object(
    'role_before', v_before,
    'role_after',  p_role,
    'org', CASE WHEN v_org IS NULL THEN NULL ELSE jsonb_build_object(
             'org_id', v_org, 'name', v_org_name,
             'org_role_before', v_org_before, 'org_role_after', v_org_after) END,
    'overrides', v_overrides,
    'narrowed_projects', v_narrowed);
END; $$;

CREATE OR REPLACE FUNCTION public.admin_transfer_project(
  p_actor_id uuid, p_actor_email text, p_project_id uuid,
  p_org_id uuid, p_new_owner_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_project     public.projects%ROWTYPE;
  v_before      jsonb;
  v_org_name    text;
  v_owner       public.approved_users%ROWTYPE;
  v_owner_id    uuid;
  v_owner_name  text;
  v_org_changed boolean;
  v_own_changed boolean;
  v_removed     jsonb := '[]'::jsonb;
  v_revoked     jsonb := '[]'::jsonb;
  v_rows        jsonb;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_inputs');

  PERFORM public._assert_super_admin(p_actor_id, p_actor_email);

  SELECT * INTO v_project FROM public.projects WHERE id = p_project_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'project not found'; END IF;
  v_before := to_jsonb(v_project);

  SELECT name INTO v_org_name FROM public.organizations WHERE id = p_org_id;
  IF v_org_name IS NULL THEN RAISE EXCEPTION 'organization not found'; END IF;

  -- (1) the owner: named, or the current one kept
  v_owner_id := COALESCE(p_new_owner_id, v_project.modeler_id);
  IF v_owner_id IS NULL THEN
    RAISE EXCEPTION 'owner_required: the project has no owner — pick a new owner from %', v_org_name;
  END IF;
  SELECT * INTO v_owner FROM public.approved_users WHERE id = v_owner_id;
  IF NOT FOUND THEN
    IF p_new_owner_id IS NOT NULL THEN RAISE EXCEPTION 'new owner not found'; END IF;
    RAISE EXCEPTION 'owner_required: the current owner is not a user account — pick a new owner from %', v_org_name;
  END IF;
  v_owner_name := COALESCE(NULLIF(btrim(COALESCE(v_owner.name, '')), ''), v_owner.email);
  IF NOT COALESCE(v_owner.is_active, false) THEN
    RAISE EXCEPTION 'owner_suspended: % is suspended and cannot own a project — reactivate the account or pick another owner', v_owner_name;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.organization_members m
                  WHERE m.org_id = p_org_id AND m.user_id = v_owner_id) THEN
    RAISE EXCEPTION 'owner_not_in_organization: % does not belong to % and would never see the project — add them to % on /admin/users first, or pick an owner who belongs to it',
      v_owner_name, v_org_name, v_org_name;
  END IF;

  v_org_changed := v_project.organization_id IS DISTINCT FROM p_org_id;
  v_own_changed := v_project.modeler_id IS DISTINCT FROM v_owner_id;
  IF NOT v_org_changed AND NOT v_own_changed THEN
    RAISE EXCEPTION 'nothing_to_change: the project is already in % and owned by %', v_org_name, v_owner_name;
  END IF;

  -- (2) the project row — `trg_tenant_allowance` refuses a full or ended organization
  BEGIN
    UPDATE public.projects SET
      organization_id = p_org_id,
      organization    = v_org_name,
      modeler_id      = v_owner_id,
      modeler_name    = v_owner_name,
      updated_at      = now()
    WHERE id = p_project_id;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'the new owner already has a project named "%" for plant "%"',
      v_project.name, v_project.plant_name;
  END;

  -- (4) the previous owner's standing, and what they delegated
  IF v_own_changed AND v_project.modeler_id IS NOT NULL THEN
    WITH d AS (
      DELETE FROM public.project_members pm
       WHERE pm.project_id = p_project_id AND pm.user_id = v_project.modeler_id
      RETURNING pm.user_id, pm.project_role)
    SELECT COALESCE(jsonb_agg(jsonb_build_object('user_id', user_id, 'project_role', project_role,
                                                 'reason', 'previous owner')), '[]'::jsonb)
      INTO v_rows FROM d;
    v_removed := v_removed || v_rows;

    WITH r AS (
      UPDATE public.delegation_grants dg SET revoked_at = now()
       WHERE dg.project_id = p_project_id AND dg.grantor_user_id = v_project.modeler_id
         AND dg.revoked_at IS NULL AND dg.expires_at > now()
      RETURNING dg.id, dg.grantee_user_id, dg.project_role)
    SELECT COALESCE(jsonb_agg(jsonb_build_object('id', id, 'grantee_user_id', grantee_user_id,
                                                 'project_role', project_role,
                                                 'reason', 'granted by the previous owner')), '[]'::jsonb)
      INTO v_rows FROM r;
    v_revoked := v_revoked || v_rows;
  END IF;

  -- (5) the organization the project left
  IF v_org_changed THEN
    WITH d AS (
      DELETE FROM public.project_members pm
       WHERE pm.project_id = p_project_id
         AND pm.user_id <> v_owner_id
         AND NOT EXISTS (SELECT 1 FROM public.organization_members m
                          WHERE m.org_id = p_org_id AND m.user_id = pm.user_id)
      RETURNING pm.user_id, pm.project_role)
    SELECT COALESCE(jsonb_agg(jsonb_build_object('user_id', user_id, 'project_role', project_role,
                                                 'reason', 'not in the target organization')), '[]'::jsonb)
      INTO v_rows FROM d;
    v_removed := v_removed || v_rows;

    WITH r AS (
      UPDATE public.delegation_grants dg SET revoked_at = now()
       WHERE dg.project_id = p_project_id
         AND dg.revoked_at IS NULL AND dg.expires_at > now()
         AND NOT EXISTS (SELECT 1 FROM public.organization_members m
                          WHERE m.org_id = p_org_id AND m.user_id = dg.grantee_user_id)
      RETURNING dg.id, dg.grantee_user_id, dg.project_role)
    SELECT COALESCE(jsonb_agg(jsonb_build_object('id', id, 'grantee_user_id', grantee_user_id,
                                                 'project_role', project_role,
                                                 'reason', 'grantee not in the target organization')), '[]'::jsonb)
      INTO v_rows FROM r;
    v_revoked := v_revoked || v_rows;
  END IF;

  -- (3) the owner is a standing owner — after the removals, so no rule above can take it
  INSERT INTO public.project_members (project_id, user_id, project_role, granted_by, expires_at, rationale)
  VALUES (p_project_id, v_owner_id, 'owner', p_actor_id, NULL,
          'the project''s owner, by admin_transfer_project (D212)')
  ON CONFLICT (project_id, user_id) DO UPDATE
    SET project_role = 'owner',
        granted_by   = EXCLUDED.granted_by,
        expires_at   = NULL,
        rationale    = EXCLUDED.rationale,
        updated_at   = now();

  v_rows := jsonb_build_object(
    'org_id', p_org_id, 'org_name', v_org_name,
    'organization_changed', v_org_changed,
    'owner_id', v_owner_id, 'owner_name', v_owner_name,
    'owner_changed', v_own_changed,
    'previous_owner_id', v_project.modeler_id,
    'owner_active_org_is_target', v_owner.organization_id IS NOT DISTINCT FROM p_org_id,
    'memberships_removed', v_removed,
    'delegations_revoked', v_revoked);
  PERFORM public.log_admin_action('project.transfer', 'projects', p_project_id::text, v_before, v_rows);
  RETURN v_rows;
END; $$;

CREATE OR REPLACE FUNCTION public.admin_update_organization(
  p_actor_id uuid, p_actor_email text, p_org_id uuid, p_name text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_before jsonb;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);

  PERFORM public._assert_super_admin(p_actor_id, p_actor_email);
  SELECT to_jsonb(o) INTO v_before FROM public.organizations o WHERE o.id = p_org_id;
  IF v_before IS NULL THEN RAISE EXCEPTION 'organization not found'; END IF;
  IF p_name IS NULL OR btrim(p_name) = '' THEN RAISE EXCEPTION 'name required'; END IF;
  UPDATE public.organizations SET name = btrim(p_name) WHERE id = p_org_id;
  PERFORM public.log_admin_action('org.update', 'organizations', p_org_id::text, v_before,
    jsonb_build_object('name', btrim(p_name)));
END; $$;

CREATE OR REPLACE FUNCTION public.admin_update_project_meta(
  p_actor_id uuid, p_actor_email text, p_project_id uuid,
  p_plant text, p_model text, p_bom_level text, p_data_type text,
  p_simulation_start date, p_simulation_end date, p_completed boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_before jsonb;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_inputs');

  PERFORM public._assert_super_admin(p_actor_id, p_actor_email);
  SELECT to_jsonb(p) INTO v_before FROM public.projects p WHERE p.id = p_project_id;
  IF v_before IS NULL THEN RAISE EXCEPTION 'project not found'; END IF;
  IF p_model IS NOT NULL AND p_model NOT IN ('Make-To-Stock','Make-To-Order') THEN
    RAISE EXCEPTION 'invalid supply chain model %', p_model;
  END IF;
  IF p_data_type IS NOT NULL AND p_data_type NOT IN ('curated','uncurated') THEN
    RAISE EXCEPTION 'invalid data type %', p_data_type;
  END IF;
  UPDATE public.projects SET
    plant_name         = COALESCE(NULLIF(btrim(coalesce(p_plant, '')), ''), plant_name),
    supply_chain_model = COALESCE(p_model, supply_chain_model),
    bom_level          = COALESCE(p_bom_level, bom_level),
    data_type          = COALESCE(p_data_type, data_type),
    simulation_start   = p_simulation_start,
    simulation_end     = p_simulation_end,
    completed          = COALESCE(p_completed, completed),
    updated_at         = now()
  WHERE id = p_project_id;
  PERFORM public.log_admin_action('project.update_meta', 'projects', p_project_id::text,
    v_before, jsonb_build_object(
      'plant_name', p_plant, 'supply_chain_model', p_model, 'bom_level', p_bom_level,
      'data_type', p_data_type, 'simulation_start', p_simulation_start,
      'simulation_end', p_simulation_end, 'completed', p_completed));
END; $$;

CREATE OR REPLACE FUNCTION public.admin_update_user(
  p_actor_id uuid, p_actor_email text, p_target_user_id uuid, p_name text, p_org_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_before jsonb; v_org_name text;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);

  PERFORM public._assert_super_admin(p_actor_id, p_actor_email);
  SELECT to_jsonb(u) INTO v_before FROM public.approved_users u WHERE u.id = p_target_user_id;
  IF v_before IS NULL THEN RAISE EXCEPTION 'user not found'; END IF;

  IF p_org_id IS NOT NULL THEN
    SELECT name INTO v_org_name FROM public.organizations WHERE id = p_org_id;
  END IF;

  UPDATE public.approved_users
     SET name = NULLIF(btrim(coalesce(p_name, '')), ''),
         organization = COALESCE(v_org_name, organization),
         organization_id = COALESCE(p_org_id, organization_id)
   WHERE id = p_target_user_id;

  IF p_org_id IS NOT NULL THEN
    INSERT INTO public.organization_members (org_id, user_id, org_role)
    VALUES (p_org_id, p_target_user_id, 'member') ON CONFLICT (org_id, user_id) DO NOTHING;
  END IF;

  PERFORM public.log_admin_action('user.update', 'approved_users', p_target_user_id::text, v_before,
    jsonb_build_object('name', p_name, 'org_id', p_org_id));
END; $$;

CREATE OR REPLACE FUNCTION public.admin_usage_log_read(
  p_actor_id uuid, p_actor_email text, p_limit integer DEFAULT 500)
RETURNS TABLE (
  id uuid, user_id uuid, user_name text, model_code text, provider_code text,
  prompt_tokens integer, completion_tokens integer, total_tokens integer,
  cost_usd numeric, latency_ms integer, status text, created_at timestamptz)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);

  PERFORM public._assert_super_admin(p_actor_id, p_actor_email);
  RETURN QUERY
  SELECT l.id, l.user_id,
         CASE WHEN l.user_id IS NULL THEN NULL
              ELSE COALESCE(u.name, u.email, 'Deleted account') END,
         l.model_code, l.provider_code,
         l.prompt_tokens, l.completion_tokens, l.total_tokens,
         l.cost_usd::numeric, l.latency_ms, l.status, l.created_at
    FROM public.ai_usage_logs l
    LEFT JOIN public.approved_users u ON u.id = l.user_id
   ORDER BY l.created_at DESC
   LIMIT LEAST(GREATEST(COALESCE(p_limit, 500), 1), 5000);
END; $$;

CREATE OR REPLACE FUNCTION public.advance_chat_plan_step(
  p_plan_id uuid,
  p_step_id text,
  p_status  text,
  p_user_id uuid,
  p_note    text DEFAULT NULL,
  p_run_id  uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_row   public.chat_plans;
  v_steps jsonb := '[]'::jsonb;
  v_step  jsonb;
  v_found boolean := false;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);

  IF p_status NOT IN ('awaiting_run','failed') THEN
    RAISE EXCEPTION 'invalid_params: advance_chat_plan_step allows only awaiting_run or failed';
  END IF;
  IF p_status = 'awaiting_run' AND p_run_id IS NULL THEN
    RAISE EXCEPTION 'invalid_params: awaiting_run requires p_run_id (§21.1 rule 4)';
  END IF;
  SELECT * INTO v_row FROM public.chat_plans WHERE id = p_plan_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'plan % not found', p_plan_id; END IF;
  IF v_row.user_id IS DISTINCT FROM p_user_id THEN RAISE EXCEPTION 'forbidden'; END IF;
  IF v_row.status <> 'active' THEN RAISE EXCEPTION 'plan % is not active (is %)', p_plan_id, v_row.status; END IF;

  FOR v_step IN SELECT * FROM jsonb_array_elements(v_row.steps) LOOP
    IF (v_step->>'id') = p_step_id THEN
      v_found := true;
      IF (v_step->>'status') <> 'awaiting_approval' THEN
        RAISE EXCEPTION 'invalid_params: step % is % — only awaiting_approval steps advance here', p_step_id, v_step->>'status';
      END IF;
      v_step := jsonb_set(v_step, '{status}', to_jsonb(p_status));
      IF p_note IS NOT NULL THEN
        v_step := jsonb_set(v_step, '{note}', to_jsonb(left(p_note, 200)));
      END IF;
      IF p_run_id IS NOT NULL THEN
        v_step := jsonb_set(v_step, '{ref}',
          COALESCE(v_step->'ref', '{}'::jsonb) || jsonb_build_object('run_id', p_run_id));
      END IF;
    END IF;
    v_steps := v_steps || v_step;
  END LOOP;
  IF NOT v_found THEN RAISE EXCEPTION 'step % not found on plan %', p_step_id, p_plan_id; END IF;

  UPDATE public.chat_plans SET steps = v_steps WHERE id = p_plan_id;
  SELECT * INTO v_row FROM public.chat_plans WHERE id = p_plan_id;
  RETURN to_jsonb(v_row);
END; $$;

CREATE OR REPLACE FUNCTION public.agent_project_right_refusal(
  p_user_id uuid, p_project_id uuid, p_artifact_type text)
RETURNS text
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_map    jsonb := public.agent_artifact_project_rights();
  v_key    text;
  v_rights jsonb;
  v_label  text;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_inputs');

  IF NOT (v_map ? p_artifact_type) THEN
    RETURN format('forbidden: no project right is declared for artifact %s', p_artifact_type);
  END IF;
  v_key := v_map ->> p_artifact_type;
  IF v_key IS NULL THEN RETURN NULL; END IF;
  IF p_project_id IS NULL THEN
    RETURN format('forbidden: this proposal names no project, so %s cannot be checked', v_key);
  END IF;
  v_rights := public.project_rights_for_user(p_user_id, p_project_id);
  IF COALESCE((v_rights -> 'capabilities' ->> v_key)::boolean, false) THEN RETURN NULL; END IF;
  SELECT label INTO v_label FROM public.capabilities WHERE key = v_key;
  RETURN format('forbidden: approving this proposal needs %s on its project (decided by %s)',
                COALESCE(v_label, v_key),
                COALESCE(v_rights -> 'decisions' -> v_key ->> 'decided_by', 'no project access'));
END; $$;

CREATE OR REPLACE FUNCTION public.ai_can_access_project(
  p_user_id uuid,
  p_user_email text,
  p_project_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org text;
  v_org_id uuid;
  v_modeler uuid;
  v_plant_name text;
  v_role text;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_inputs');

  -- Establish the user context the get_current_* helpers read from.
  PERFORM public.set_current_user_context(p_user_id, p_user_email);

  SELECT organization, organization_id, modeler_id, plant_name
    INTO v_org, v_org_id, v_modeler, v_plant_name
  FROM public.projects
  WHERE id = p_project_id;

  -- Unknown project -> no access.
  IF v_org IS NULL THEN
    RETURN false;
  END IF;

  -- Must be in the same organization.
  IF NOT public.org_is_current_user_org(v_org_id, v_org) THEN
    RETURN false;
  END IF;

  SELECT user_role INTO v_role
  FROM public.get_current_approved_user()
  LIMIT 1;

  -- Owner, admin, or plant-granted viewer (mirrors the projects SELECT policy).
  RETURN (
    v_modeler = public.get_current_user_id()
    OR v_role IN ('admin', 'super_admin')
    OR v_plant_name IN (
      SELECT upa.plant
      FROM public.user_plant_access upa
      WHERE upa.user_id = public.get_current_user_id()
        AND upa.can_view = true
    )
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.analysis_apply_critical_nodes(
  _run_id        uuid,
  _scores        jsonb,
  _actor_user_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_run     public.analysis_runs;
  v_updated integer := 0;
  v_cleared integer := 0;
BEGIN
  -- D309: bind caller assertions before the original operation.
  _actor_user_id := public.security_actor(_actor_user_id);

  IF jsonb_typeof(_scores) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'analysis_apply_critical_nodes: _scores must be a json array'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  SELECT * INTO v_run FROM public.analysis_runs WHERE id = _run_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'analysis_apply_critical_nodes: no run %', _run_id
      USING ERRCODE = 'no_data_found';
  END IF;
  IF v_run.analysis_kind <> 'critical_nodes' THEN
    RAISE EXCEPTION 'analysis_apply_critical_nodes: run % is a % run', _run_id, v_run.analysis_kind
      USING ERRCODE = 'invalid_parameter_value';
  END IF;
  -- The entity mirror is written while the run is running or not at all (WP 4.3):
  -- a finished run's answer is frozen, and stamping rows from it afterwards would
  -- let the store and its mirror drift with the run claiming to describe both.
  IF v_run.status <> 'running' THEN
    RAISE EXCEPTION
      'analysis_apply_critical_nodes: run % is %, and the entity mirror is written '
      'while the run is running or not at all', _run_id, v_run.status
      USING ERRCODE = 'P0A01';
  END IF;

  -- Names WHO and decides nothing (`20260917000005`).
  PERFORM public.assert_writer_may_act('analysis_apply_critical_nodes', v_run.project_id, _actor_user_id);

  -- ONE statement, scoped by the RUN's project — the scope is not a parameter a
  -- caller can get wrong, and the hash is read off the run, not passed in.
  UPDATE public.node_list nl
     SET is_critical_node     = s.is_critical,
         critical_node_score  = s.score,
         prediction_timestamp = now(),
         computed_from_hash   = v_run.input_hash,
         computed_at          = now(),
         updated_at           = now()
    FROM jsonb_to_recordset(_scores) AS s(node_id text, is_critical boolean, score numeric)
   WHERE nl.project_id = v_run.project_id AND nl.node_id = s.node_id;
  GET DIAGNOSTICS v_updated = ROW_COUNT;

  -- A node this run did not score carries no score from an earlier one. It is
  -- not on the lane graph any more (a supplier dropped from the inbound file), and
  -- leaving its old flag would show a nexus that no longer exists.
  UPDATE public.node_list nl
     SET is_critical_node     = NULL,
         critical_node_score  = NULL,
         prediction_timestamp = now(),
         computed_from_hash   = v_run.input_hash,
         computed_at          = now(),
         updated_at           = now()
   WHERE nl.project_id = v_run.project_id
     AND (nl.is_critical_node IS NOT NULL OR nl.critical_node_score IS NOT NULL)
     AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(_scores) e
                      WHERE e ->> 'node_id' = nl.node_id);
  GET DIAGNOSTICS v_cleared = ROW_COUNT;

  RETURN jsonb_build_object(
    'rows_updated', v_updated,
    'rows_cleared', v_cleared,
    'scores_supplied', jsonb_array_length(_scores),
    'computed_from_hash', v_run.input_hash);
END; $fn$;

CREATE OR REPLACE FUNCTION public.analysis_apply_node_metrics(
  _run_id        uuid,
  _metrics       jsonb,
  _actor_user_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_run     public.analysis_runs;
  v_updated integer := 0;
  v_seen    integer := 0;
BEGIN
  -- D309: bind caller assertions before the original operation.
  _actor_user_id := public.security_actor(_actor_user_id);

  IF jsonb_typeof(_metrics) <> 'array' THEN
    RAISE EXCEPTION 'analysis_apply_node_metrics: _metrics must be a json array'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  SELECT * INTO v_run FROM public.analysis_runs WHERE id = _run_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'analysis_apply_node_metrics: no run %', _run_id
      USING ERRCODE = 'no_data_found';
  END IF;

  -- A finished run's answer is frozen (WP 4.2). Stamping entity rows from it
  -- afterwards would let a stored result and its mirror drift apart with the
  -- run still claiming to describe both.
  IF v_run.status <> 'running' THEN
    RAISE EXCEPTION
      'analysis_apply_node_metrics: run % is %, and the entity mirror is written '
      'while the run is running or not at all (WP 4.3)', _run_id, v_run.status
      USING ERRCODE = 'P0A01';
  END IF;

  -- Authenticates and sets `app.current_user_id` LOCAL, so the tier-3 audit
  -- trigger names a person. It does not authorize — see `20260917000005`.
  PERFORM public.assert_writer_may_act('analysis_apply_node_metrics', v_run.project_id, _actor_user_id);

  v_seen := jsonb_array_length(_metrics);
  IF v_seen = 0 THEN
    RETURN jsonb_build_object('rows_updated', 0, 'metrics_supplied', 0,
                              'computed_from_hash', v_run.input_hash);
  END IF;

  -- ONE statement, and it is scoped by the RUN's project rather than by a
  -- parameter: `analysis_mark_critical_nodes` had to DERIVE its project from the
  -- scored rows because its caller filtered by `plant_name`, which is not scoped
  -- to a project at all. Here the run already knows, so the scope is not
  -- something a caller can get wrong.
  --
  -- COALESCE on each metric: a partial update is legitimate —
  -- `calculate-node-prominence` computes `prominence` and nothing else, and must
  -- not blank the five centralities another run wrote.
  UPDATE public.network_nodes n
     SET prominence                 = COALESCE(m.prominence, n.prominence),
         degree_centrality          = COALESCE(m.degree_centrality, n.degree_centrality),
         weighted_degree_centrality = COALESCE(m.weighted_degree_centrality, n.weighted_degree_centrality),
         eigenvector_centrality     = COALESCE(m.eigenvector_centrality, n.eigenvector_centrality),
         betweenness_centrality     = COALESCE(m.betweenness_centrality, n.betweenness_centrality),
         closeness_centrality       = COALESCE(m.closeness_centrality, n.closeness_centrality),
         prominence_updated_at      = CASE WHEN m.prominence IS NOT NULL
                                           THEN now() ELSE n.prominence_updated_at END,
         network_metrics_updated_at = CASE WHEN m.degree_centrality IS NOT NULL
                                           THEN now() ELSE n.network_metrics_updated_at END,
         computed_from_hash         = v_run.input_hash,
         computed_at                = now(),
         updated_at                 = now()
    FROM jsonb_to_recordset(_metrics) AS m(
           uid                        text,
           prominence                 numeric,
           degree_centrality          numeric,
           weighted_degree_centrality numeric,
           eigenvector_centrality     numeric,
           betweenness_centrality     numeric,
           closeness_centrality       numeric)
   WHERE n.project_id = v_run.project_id AND n.uid = m.uid;
  GET DIAGNOSTICS v_updated = ROW_COUNT;

  RETURN jsonb_build_object(
    'rows_updated', v_updated,
    'metrics_supplied', v_seen,
    'computed_from_hash', v_run.input_hash);
END; $fn$;

CREATE OR REPLACE FUNCTION public.analysis_complete_run(
  _run_id        uuid,
  _results       jsonb,
  _row_counts    jsonb,
  _warnings      jsonb,
  _actor_user_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_run public.analysis_runs;
  v_n   integer := 0;
BEGIN
  -- D309: bind caller assertions before the original operation.
  _actor_user_id := public.security_actor(_actor_user_id);

  SELECT * INTO v_run FROM public.analysis_runs WHERE id = _run_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'analysis_complete_run: no run %', _run_id USING ERRCODE = 'no_data_found';
  END IF;

  PERFORM public.assert_writer_may_act('analysis_complete_run', v_run.project_id, _actor_user_id);

  IF v_run.status <> 'running' THEN
    RAISE EXCEPTION
      'analysis_complete_run: run % is already %, and a finished run is never rewritten (WP 4.2)',
      _run_id, v_run.status USING ERRCODE = 'P0A01';
  END IF;

  IF _results IS NOT NULL AND jsonb_typeof(_results) = 'array' THEN
    INSERT INTO public.analysis_results (run_id, entity_type, entity_id, metrics)
    SELECT _run_id,
           r ->> 'entity_type',
           r ->> 'entity_id',
           COALESCE(r -> 'metrics', '{}'::jsonb)
      FROM jsonb_array_elements(_results) r;
    GET DIAGNOSTICS v_n = ROW_COUNT;
  END IF;

  UPDATE public.analysis_runs
     SET status      = 'succeeded',
         finished_at = now(),
         duration_ms = GREATEST(0, (EXTRACT(EPOCH FROM (now() - started_at)) * 1000)::integer),
         row_counts  = COALESCE(_row_counts, '{}'::jsonb),
         warnings    = COALESCE(_warnings, '[]'::jsonb)
   WHERE id = _run_id;

  RETURN jsonb_build_object('run_id', _run_id, 'status', 'succeeded', 'results_written', v_n);
END; $fn$;

CREATE OR REPLACE FUNCTION public.analysis_fail_run(
  _run_id        uuid,
  _warnings      jsonb,
  _actor_user_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE v_run public.analysis_runs;
BEGIN
  -- D309: bind caller assertions before the original operation.
  _actor_user_id := public.security_actor(_actor_user_id);

  SELECT * INTO v_run FROM public.analysis_runs WHERE id = _run_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'analysis_fail_run: no run %', _run_id USING ERRCODE = 'no_data_found';
  END IF;

  PERFORM public.assert_writer_may_act('analysis_fail_run', v_run.project_id, _actor_user_id);

  IF v_run.status <> 'running' THEN
    RAISE EXCEPTION 'analysis_fail_run: run % is already %', _run_id, v_run.status
      USING ERRCODE = 'P0A01';
  END IF;

  UPDATE public.analysis_runs
     SET status      = 'failed',
         finished_at = now(),
         duration_ms = GREATEST(0, (EXTRACT(EPOCH FROM (now() - started_at)) * 1000)::integer),
         warnings    = COALESCE(_warnings, '[]'::jsonb)
   WHERE id = _run_id;

  RETURN jsonb_build_object('run_id', _run_id, 'status', 'failed');
END; $fn$;

CREATE OR REPLACE FUNCTION public.analysis_get_or_start(
  _project_id     uuid,
  _analysis_kind  text,
  _params         jsonb,
  _code_version   text,
  _actor_user_id  uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_scope       text;
  v_hashes      jsonb;
  v_input_hash  text;
  v_dsv         uuid;
  v_lvl         uuid;
  v_params      jsonb := COALESCE(_params, '{}'::jsonb);
  v_params_hash text;
  v_run         public.analysis_runs;
BEGIN
  -- D309: bind caller assertions before the original operation.
  _actor_user_id := public.security_actor(_actor_user_id);
  PERFORM public.security_assert_project(_project_id, 'data_edit_inputs');

  PERFORM public.assert_writer_may_act('analysis_get_or_start', _project_id, _actor_user_id);

  IF _analysis_kind IS NULL OR _code_version IS NULL THEN
    RAISE EXCEPTION 'analysis_get_or_start: analysis_kind and code_version are part of the key and may not be NULL'
      USING ERRCODE = 'null_value_not_allowed';
  END IF;

  -- §4 D235: the level this kind reads, from the ONE place it is stated. A kind
  -- the catalog does not declare keys on EVERYTHING ('all', the composite) — the
  -- conservative answer, which keeps WP 4.2's open enum open (a new kind costs no
  -- migration) without ever serving a stale hit.
  v_scope := COALESCE(public.analysis_scope_now(_project_id, _analysis_kind), 'all');

  v_hashes := public.project_graph_hashes(_project_id);
  -- WP 11.2 · the ONE scope → hash mapping (`simulation` is the `inputs` domain).
  v_input_hash := v_hashes ->> public._scope_hash_key(v_scope);
  IF v_input_hash IS NULL THEN
    RAISE EXCEPTION 'analysis_get_or_start: project % has no % hash, so a run could not name its inputs (I5)', _project_id, v_scope
      USING ERRCODE = 'null_value_not_allowed';
  END IF;

  v_params_hash := encode(extensions.digest(v_params::text, 'sha256'), 'hex');

  SELECT * INTO v_run FROM public.analysis_runs
   WHERE project_id = _project_id AND analysis_kind = _analysis_kind
     AND input_hash = v_input_hash AND params_hash = v_params_hash
     AND code_version = _code_version AND status = 'succeeded'
   LIMIT 1;

  IF FOUND THEN
    RETURN jsonb_build_object(
      'run_id', v_run.id, 'cache_hit', true, 'status', v_run.status,
      'input_hash', v_run.input_hash, 'input_scope', v_run.input_scope,
      'dataset_version_id', v_run.dataset_version_id,
      'level_version_id', v_run.level_version_id,
      'params_hash', v_run.params_hash,
      'code_version', v_run.code_version, 'row_counts', v_run.row_counts,
      'warnings', v_run.warnings, 'started_at', v_run.started_at,
      'finished_at', v_run.finished_at);
  END IF;

  -- The graph version this run computes over (created if the world has none yet).
  v_dsv := public.snapshot_dataset(_project_id, NULL, _actor_user_id, NULL);
  -- WP 11.2 · §4 D261 — and the VERSION of the level it keys on, which that snapshot
  -- has just registered. NULL for scope `all`, whose version is the snapshot itself.
  SELECT id INTO v_lvl FROM public.graph_level_versions
   WHERE project_id = _project_id AND level = v_scope AND level_hash = v_input_hash;

  INSERT INTO public.analysis_runs
    (project_id, analysis_kind, input_hash, input_scope, dataset_version_id, level_version_id,
     params_hash, params, code_version, actor_user_id)
  VALUES
    (_project_id, _analysis_kind, v_input_hash, v_scope, v_dsv, v_lvl,
     v_params_hash, v_params, _code_version, _actor_user_id)
  ON CONFLICT DO NOTHING
  RETURNING * INTO v_run;

  IF FOUND THEN
    RETURN jsonb_build_object(
      'run_id', v_run.id, 'cache_hit', false, 'status', v_run.status,
      'input_hash', v_run.input_hash, 'input_scope', v_run.input_scope,
      'dataset_version_id', v_run.dataset_version_id,
      'level_version_id', v_run.level_version_id,
      'params_hash', v_run.params_hash,
      'code_version', v_run.code_version, 'started_at', v_run.started_at);
  END IF;

  SELECT * INTO v_run FROM public.analysis_runs
   WHERE project_id = _project_id AND analysis_kind = _analysis_kind
     AND input_hash = v_input_hash AND params_hash = v_params_hash
     AND code_version = _code_version AND status <> 'failed'
   LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'analysis_get_or_start: lost the key race for project %/% and then could not find the winner', _project_id, _analysis_kind;
  END IF;

  RETURN jsonb_build_object(
    'run_id', v_run.id, 'cache_hit', v_run.status = 'succeeded', 'status', v_run.status,
    'input_hash', v_run.input_hash, 'input_scope', v_run.input_scope,
    'dataset_version_id', v_run.dataset_version_id,
    'params_hash', v_run.params_hash,
    'code_version', v_run.code_version, 'row_counts', v_run.row_counts,
    'warnings', v_run.warnings, 'started_at', v_run.started_at,
    'finished_at', v_run.finished_at, 'claimed_by_other', true);
END; $fn$;

CREATE OR REPLACE FUNCTION public.analysis_mark_critical_nodes(
  _actor_user_id uuid,
  _scores        jsonb,
  _run_id        uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_project  uuid;
  v_projects integer;
  v_updated  integer;
  v_hash     text;
  v_run      public.analysis_runs;
BEGIN
  -- D309: bind caller assertions before the original operation.
  _actor_user_id := public.security_actor(_actor_user_id);

  IF jsonb_typeof(_scores) <> 'array' THEN
    RAISE EXCEPTION 'analysis_mark_critical_nodes: scores must be a json array'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF jsonb_array_length(_scores) = 0 THEN
    RETURN jsonb_build_object('rows_updated', 0);
  END IF;

  SELECT count(*), (array_agg(p))[1]
    INTO v_projects, v_project
    FROM (SELECT DISTINCT d.project_id AS p
            FROM public.supply_chain_data d
           WHERE d.id IN (SELECT (e ->> 'id')::uuid FROM jsonb_array_elements(_scores) e)) q;

  IF COALESCE(v_projects, 0) = 0 THEN
    RAISE EXCEPTION 'analysis_mark_critical_nodes: none of the % scored id(s) exists',
      jsonb_array_length(_scores) USING ERRCODE = 'no_data_found';
  END IF;
  IF v_projects > 1 THEN
    RAISE EXCEPTION
      'analysis_mark_critical_nodes: the scored rows span % projects. One call writes '
      'under one project''s authority or it writes nothing.', v_projects
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- A run given must BELONG to the rows being written. Without this check a
  -- caller could stamp project A's rows with project B's run and the provenance
  -- column would be worse than absent — it would be confidently wrong.
  IF _run_id IS NOT NULL THEN
    SELECT * INTO v_run FROM public.analysis_runs WHERE id = _run_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'analysis_mark_critical_nodes: no run %', _run_id
        USING ERRCODE = 'no_data_found';
    END IF;
    IF v_run.project_id <> v_project THEN
      RAISE EXCEPTION
        'analysis_mark_critical_nodes: run % belongs to project %, the scored rows to %',
        _run_id, v_run.project_id, v_project USING ERRCODE = 'invalid_parameter_value';
    END IF;
    v_hash := v_run.input_hash;
  END IF;

  PERFORM public.assert_writer_may_act('analysis_mark_critical_nodes', v_project, _actor_user_id);

  UPDATE public.supply_chain_data d
     SET is_critical_node      = s.is_critical,
         critical_node_score   = s.score,
         prediction_timestamp  = now(),
         computed_from_hash    = v_hash,
         computed_at           = now(),
         updated_at            = now()
    FROM jsonb_to_recordset(_scores) AS s(id uuid, is_critical boolean, score numeric)
   WHERE d.id = s.id AND d.project_id = v_project;
  GET DIAGNOSTICS v_updated = ROW_COUNT;

  RETURN jsonb_build_object('project_id', v_project, 'rows_updated', v_updated,
                            'computed_from_hash', v_hash);
END; $fn$;

CREATE OR REPLACE FUNCTION public.api_key_caller(p_user_id uuid, p_user_email text)
RETURNS TABLE (org_id uuid, can_manage boolean, self_service_scopes text[])
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);

  PERFORM public.set_current_user_context(p_user_id, p_user_email);
  RETURN QUERY SELECT c.org_id, c.can_manage, public.api_key_self_service_scopes()
                 FROM public._api_key_caller(p_user_id, NULL) c;
END;
$$;

CREATE OR REPLACE FUNCTION public.api_key_usage(p_user_id uuid, p_user_email text)
RETURNS TABLE (
  api_key_id uuid, requests_24h bigint, requests_30d bigint,
  errors_30d bigint, last_request_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_super  boolean;
  v_org    uuid;
  v_manage boolean := true;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);

  PERFORM public.set_current_user_context(p_user_id, p_user_email);
  v_super := public.is_super_admin(p_user_id);
  IF NOT v_super THEN
    SELECT c.org_id, c.can_manage INTO v_org, v_manage FROM public._api_key_caller(p_user_id, NULL) c;
  END IF;
  RETURN QUERY
  SELECT l.api_key_id,
         count(*) FILTER (WHERE l.created_at >= now() - interval '24 hours'),
         count(*),
         count(*) FILTER (WHERE l.status >= 400),
         max(l.created_at)
  FROM public.api_request_logs l
  JOIN public.api_keys k ON k.id = l.api_key_id
  WHERE l.created_at >= now() - interval '30 days'
    AND (v_super OR k.org_id = v_org)
    AND (v_manage OR (k.principal = 'personal' AND k.created_by = p_user_id))
  GROUP BY l.api_key_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.append_chat_message(
  p_user_id     uuid,
  p_thread_id   uuid,
  p_role        text,
  p_content     text,
  p_parts       jsonb DEFAULT '[]'::jsonb,
  p_tool_calls  jsonb DEFAULT '[]'::jsonb,
  p_proposal_id uuid DEFAULT NULL,
  p_model_code  text DEFAULT NULL,
  p_created_at  timestamptz DEFAULT NULL
) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_seq integer;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);

  PERFORM public._chat_assert_thread_owner(p_thread_id, p_user_id);
  PERFORM 1 FROM public.chat_threads WHERE id = p_thread_id FOR UPDATE;
  SELECT COALESCE(MAX(seq), 0) + 1 INTO v_seq
    FROM public.chat_messages WHERE thread_id = p_thread_id;
  INSERT INTO public.chat_messages
    (thread_id, seq, role, content, parts, tool_calls, proposal_id, model_code, created_at)
  VALUES
    (p_thread_id, v_seq, p_role, left(COALESCE(p_content, ''), 32000),
     COALESCE(p_parts, '[]'::jsonb), COALESCE(p_tool_calls, '[]'::jsonb),
     p_proposal_id, p_model_code, COALESCE(p_created_at, now()));
  UPDATE public.chat_threads
     SET last_message_at = COALESCE(p_created_at, now())
   WHERE id = p_thread_id;
  RETURN v_seq;
END; $$;

CREATE OR REPLACE FUNCTION public.apply_policy_bundle(
  p_project_id           uuid,
  p_defaults             jsonb DEFAULT '{}'::jsonb,  -- {family: patch-object}
  p_overrides            jsonb DEFAULT '[]'::jsonb,  -- [{scope,target_key,family,patch}]
  p_label                text  DEFAULT NULL,
  p_parent_version_id    uuid  DEFAULT NULL,
  p_expected_policy_hash text  DEFAULT NULL,
  p_user_id              uuid  DEFAULT NULL,
  p_user_email           text  DEFAULT NULL,
  p_user_name            text  DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_families   text[] := ARRAY['sourcing','inventory','transport','fulfillment',
                               'production','recovery','demand'];
  v_family     text;
  v_patch      jsonb;
  v_row        jsonb;
  v_current    text;
  v_version_id uuid;
  v_hash       text;
  v_n_overrides integer := 0;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_policies');


  -- D71, closed for this path (WP 6.2 slice 11). LOCAL to this transaction and
  -- set BEFORE any tier-2/3 write, so `audit_tier_write`'s `get_current_user_id()`
  -- resolves and the audit rows below name the person who acted instead of
  -- recording `actor_known: false`. The actor was always a parameter here; only
  -- the one line telling the trigger about it was missing — the same shape
  -- `assign_material_supplier` had before `20260916000021`.
  IF p_user_id IS NOT NULL THEN
    PERFORM set_config('app.current_user_id', p_user_id::text, true);
  END IF;
  -- D275 · a named actor must hold Edit Policies on the project.
  PERFORM public.assert_may_edit_policies(p_project_id, p_user_id);
  IF NOT EXISTS (SELECT 1 FROM public.projects WHERE id = p_project_id) THEN
    RAISE EXCEPTION 'project % not found', p_project_id;
  END IF;

  -- §8 T8 / pc-08: grounding freshness inside the transaction.
  IF p_expected_policy_hash IS NOT NULL THEN
    v_current := public.current_policy_hash(p_project_id);
    IF v_current IS DISTINCT FROM p_expected_policy_hash THEN
      RAISE EXCEPTION 'stale_values: the policy configuration changed since this proposal was drafted (expected hash %, current %)',
        left(p_expected_policy_hash, 12), left(COALESCE(v_current, 'none'), 12);
    END IF;
  END IF;

  -- Validate every family key before touching anything (dynamic SQL below
  -- interpolates the family as an identifier — whitelist first).
  FOR v_family IN SELECT jsonb_object_keys(COALESCE(p_defaults, '{}'::jsonb)) LOOP
    IF NOT v_family = ANY (v_families) THEN
      RAISE EXCEPTION 'unknown policy family %', v_family;
    END IF;
    IF jsonb_typeof(p_defaults -> v_family) <> 'object' THEN
      RAISE EXCEPTION 'defaults.% must be a patch object', v_family;
    END IF;
  END LOOP;
  FOR v_row IN SELECT * FROM jsonb_array_elements(COALESCE(p_overrides, '[]'::jsonb)) LOOP
    IF NOT (v_row ->> 'family') = ANY (v_families) THEN
      RAISE EXCEPTION 'unknown policy family % on override %',
        v_row ->> 'family', v_row ->> 'target_key';
    END IF;
    IF COALESCE(v_row ->> 'scope', '') = '' OR COALESCE(v_row ->> 'target_key', '') = '' THEN
      RAISE EXCEPTION 'override rows need scope and target_key';
    END IF;
    IF jsonb_typeof(v_row -> 'patch') <> 'object' THEN
      RAISE EXCEPTION 'override % needs a patch object', v_row ->> 'target_key';
    END IF;
  END LOOP;

  -- Step 2a: family-default patches, merged (jsonb ||) onto the live row.
  INSERT INTO public.policy_defaults (project_id, updated_at)
  VALUES (p_project_id, now())
  ON CONFLICT (project_id) DO NOTHING;

  FOR v_family IN SELECT jsonb_object_keys(COALESCE(p_defaults, '{}'::jsonb)) LOOP
    v_patch := p_defaults -> v_family;
    EXECUTE format(
      'UPDATE public.policy_defaults
          SET %I = COALESCE(%I, ''{}''::jsonb) || $1, updated_at = now()
        WHERE project_id = $2',
      v_family, v_family
    ) USING v_patch, p_project_id;
  END LOOP;

  -- Step 2b: override patches, merged onto any existing row's patch.
  FOR v_row IN SELECT * FROM jsonb_array_elements(COALESCE(p_overrides, '[]'::jsonb)) LOOP
    INSERT INTO public.policy_overrides
      (project_id, scope, target_key, family, patch, updated_at)
    VALUES
      (p_project_id, v_row ->> 'scope', v_row ->> 'target_key',
       v_row ->> 'family', COALESCE(v_row -> 'patch', '{}'::jsonb), now())
    ON CONFLICT (project_id, scope, target_key, family)
    DO UPDATE SET
      patch = COALESCE(public.policy_overrides.patch, '{}'::jsonb) || EXCLUDED.patch,
      updated_at = now();
    v_n_overrides := v_n_overrides + 1;
  END LOOP;

  -- Step 3: snapshot with the agent label + parent lineage (§4.4; pc-09).
  v_version_id := public.snapshot_policy(
    p_project_id,
    COALESCE(p_label, 'agent: policy bundle'),
    p_user_id, p_user_email, p_user_name,
    p_parent_version_id
  );

  SELECT policy_hash INTO v_hash FROM public.policy_versions WHERE id = v_version_id;

  RETURN jsonb_build_object(
    'policy_version_id', v_version_id,
    'policy_hash', v_hash,
    'overrides_applied', v_n_overrides
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.apply_validation_to_scenario(
  p_scenario_id   uuid,
  p_validation_id uuid,
  _actor_user_id  uuid DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_card public.model_validations%ROWTYPE;
  v_scen_project uuid;
BEGIN
  -- D309: bind caller assertions before the original operation.
  _actor_user_id := public.security_actor(_actor_user_id);

  IF _actor_user_id IS NOT NULL THEN
    PERFORM set_config('app.current_user_id', _actor_user_id::text, true);
  END IF;

  SELECT * INTO v_card FROM public.model_validations WHERE id = p_validation_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'validation % not found', p_validation_id; END IF;

  SELECT project_id INTO v_scen_project FROM public.scenarios WHERE id = p_scenario_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'scenario % not found', p_scenario_id; END IF;
  IF v_scen_project <> v_card.project_id THEN
    RAISE EXCEPTION 'validation and scenario belong to different projects';
  END IF;

  IF v_card.status <> 'active' OR v_card.verdict <> 'validated' THEN
    RAISE EXCEPTION 'validation % is not an active validated model', p_validation_id
      USING ERRCODE = 'check_violation';
  END IF;
  IF public.scenario_fingerprint_hash(p_scenario_id) IS DISTINCT FROM v_card.scenario_hash THEN
    RAISE EXCEPTION 'scenario % is not in the validated model''s world (scenario fingerprint differs)', p_scenario_id
      USING ERRCODE = 'check_violation';
  END IF;
  IF public.current_policy_hash(v_card.project_id) IS DISTINCT FROM v_card.policy_hash THEN
    RAISE EXCEPTION 'the project''s policies are not the validated model''s (policy content differs)'
      USING ERRCODE = 'check_violation';
  END IF;
  -- WP 11.2 · §4 D259 — the model's world is the SIMULATION'S inputs; a deep-tier
  -- change the engine never reads does not make it a different model. A card that
  -- could not learn its simulation hash (no snapshot) keeps the composite rule.
  IF v_card.hash_simulation IS NOT NULL THEN
    IF public.current_level_hash(v_card.project_id, 'simulation') IS DISTINCT FROM v_card.hash_simulation THEN
      RAISE EXCEPTION 'the project''s simulation inputs are not the validated model''s (inputs differ)'
        USING ERRCODE = 'check_violation';
    END IF;
  ELSIF public.current_graph_hash(v_card.project_id) IS DISTINCT FROM v_card.graph_hash THEN
    RAISE EXCEPTION 'the project''s data is not the validated model''s (graph differs)'
      USING ERRCODE = 'check_violation';
  END IF;

  UPDATE public.scenarios SET
    warmup_mode             = 'manual',
    warmup_days             = v_card.adopted_warmup_days,
    replications            = v_card.recommended_replications,
    inherited_validation_id = v_card.id
  WHERE id = p_scenario_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.assert_may_edit_policies(p_project_id uuid, p_actor uuid)
RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_rights jsonb;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor := public.security_actor(p_actor);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_inputs');

  -- No actor: the unattributed path, unchanged (above, (2)). No project: the caller raises
  -- its own "not found", which is the better error.
  IF p_actor IS NULL OR p_project_id IS NULL
     OR NOT EXISTS (SELECT 1 FROM public.projects WHERE id = p_project_id) THEN
    RETURN;
  END IF;
  v_rights := public.project_rights_for_user(p_actor, p_project_id);
  IF COALESCE((v_rights -> 'capabilities' ->> 'data_edit_policies')::boolean, false) THEN
    RETURN;
  END IF;
  RAISE EXCEPTION 'forbidden: your role on this project does not include Edit Policies'
    USING ERRCODE = 'insufficient_privilege',
          HINT = 'D275 — policy writes need Edit Policies; an Analyst runs simulations from the Simulation Lab.';
END; $$;

CREATE OR REPLACE FUNCTION public.assert_writer_may_act(
  _fn            text,
  _project_id    uuid,
  _actor_user_id uuid
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
BEGIN
  -- D309: bind caller assertions before the original operation.
  _actor_user_id := public.security_actor(_actor_user_id);
  PERFORM public.security_assert_project(_project_id, 'data_edit_inputs');

  -- `audit-actor` (G4) as a CONSTRAINT rather than an intention. A write that
  -- cannot name who made it is refused here rather than recorded as
  -- `actor_known: false` downstream.
  IF _actor_user_id IS NULL THEN
    RAISE EXCEPTION '%: this write must name its actor (invariant audit-actor)', _fn
      USING ERRCODE = 'null_value_not_allowed';
  END IF;
  IF _project_id IS NULL THEN
    RAISE EXCEPTION '%: this write must name its project', _fn
      USING ERRCODE = 'null_value_not_allowed';
  END IF;

  -- LOCAL — `true` — so it belongs to THIS transaction and cannot leak onto the
  -- next caller of a pooled connection. It is also what makes
  -- `has_project_access()` answer for the named actor rather than for whoever
  -- the connection last belonged to, so the RLS the callers already rely on is
  -- evaluated against the right person.
  PERFORM set_config('app.current_user_id', _actor_user_id::text, true);
END; $fn$;

CREATE OR REPLACE FUNCTION public.assign_bom_line(
  p_project_id  uuid,
  p_product_id  text,
  p_material_id text,
  p_rate        numeric,
  p_user_id     uuid,
  p_user_email  text
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_plant text;
  v_org   text;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_inputs');


  -- D71, closed for this path (WP 6.2 slice 11). LOCAL to this transaction and
  -- set BEFORE any tier-2/3 write, so `audit_tier_write`'s `get_current_user_id()`
  -- resolves and the audit rows below name the person who acted instead of
  -- recording `actor_known: false`. The actor was always a parameter here; only
  -- the one line telling the trigger about it was missing — the same shape
  -- `assign_material_supplier` had before `20260916000021`.
  IF p_user_id IS NOT NULL THEN
    PERFORM set_config('app.current_user_id', p_user_id::text, true);
  END IF;
  IF NULLIF(p_product_id, '') IS NULL OR NULLIF(p_material_id, '') IS NULL THEN
    RAISE EXCEPTION 'product_id and material_id are required';
  END IF;
  IF p_rate IS NULL OR p_rate <= 0 THEN
    RAISE EXCEPTION 'consumption rate must be > 0 (BomLine.rate is a hard engine constraint)';
  END IF;

  SELECT plant_name, organization INTO v_plant, v_org
  FROM public.projects WHERE id = p_project_id;
  IF v_plant IS NULL THEN
    RAISE EXCEPTION 'project_not_found';
  END IF;

  -- 1) BOM row (the engine + grader source).
  INSERT INTO public.bom_single_level
    (project_id, plant_name, product_id, material_id, consumption_rate)
  SELECT p_project_id, v_plant, p_product_id, p_material_id, p_rate
  WHERE NOT EXISTS (
    SELECT 1 FROM public.bom_single_level
    WHERE project_id = p_project_id
      AND product_id = p_product_id
      AND material_id = p_material_id
  );

  -- 2) Edge row so get_supply_chain_data reflects the pair immediately
  --    (combine-project's 'bom' shape: from = material, to = product).
  INSERT INTO public.supply_chain_data
    (project_id, plant_name, data_source, from_location, to_location,
     material_consumption_rate, sourcing_ratio, weighted, uploaded_by, organization)
  SELECT p_project_id, v_plant, 'bom', p_material_id, p_product_id,
         p_rate, 1.0, 0, p_user_id, v_org
  WHERE NOT EXISTS (
    SELECT 1 FROM public.supply_chain_data
    WHERE project_id = p_project_id
      AND data_source = 'bom'
      AND from_location = p_material_id
      AND to_location = p_product_id
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.assign_material_supplier(
  p_project_id  uuid,
  p_material_id text,
  p_supplier_id text,
  p_user_id     uuid,
  p_user_email  text
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_plant text;
  v_org   text;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_policies');

  IF NULLIF(p_material_id, '') IS NULL OR NULLIF(p_supplier_id, '') IS NULL THEN
    RAISE EXCEPTION 'material_id and supplier_id are required';
  END IF;

  -- D36 (WP 3.3): LOCAL to this transaction, set BEFORE any tier-2 write, so the
  -- audit rows name the person who clicked.
  IF p_user_id IS NOT NULL THEN
    PERFORM set_config('app.current_user_id', p_user_id::text, true);
  END IF;

  SELECT plant_name, organization INTO v_plant, v_org
  FROM public.projects WHERE id = p_project_id;
  IF v_plant IS NULL THEN
    RAISE EXCEPTION 'project_not_found';
  END IF;

  -- 1) Lane row (the engine + grid enrichment source). Guarded rather than
  --    ON CONFLICT so assigning an assigned supplier is a no-op (WP 3.3).
  INSERT INTO public.inbound_logistics
    (project_id, plant_name, supplier_id, material_id)
  SELECT p_project_id, v_plant, p_supplier_id, p_material_id
  WHERE NOT EXISTS (
    SELECT 1 FROM public.inbound_logistics
    WHERE project_id = p_project_id
      AND supplier_id = p_supplier_id
      AND material_id = p_material_id
  );

  -- 2) Edge row so get_supply_chain_data reflects the pair immediately.
  INSERT INTO public.supply_chain_data
    (project_id, plant_name, data_source, from_location, to_location,
     material_consumption_rate, sourcing_ratio, weighted, uploaded_by, organization)
  SELECT p_project_id, v_plant, 'inbound', p_supplier_id, p_material_id,
         0, 1.0, 0, p_user_id, v_org
  WHERE NOT EXISTS (
    SELECT 1 FROM public.supply_chain_data
    WHERE project_id = p_project_id
      AND data_source = 'inbound'
      AND from_location = p_supplier_id
      AND to_location = p_material_id
  );

  -- 3) NO SUPPLIER MASTER ROW (§23 WP 13.1). /policies never writes the masters.
END;
$$;

CREATE OR REPLACE FUNCTION public.assign_outbound_customer(
  p_project_id  uuid,
  p_product_id  text,
  p_customer_id text,
  p_user_id     uuid,
  p_user_email  text
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_plant text;
  v_org   text;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_inputs');


  -- D71, closed for this path (WP 6.2 slice 11). LOCAL to this transaction and
  -- set BEFORE any tier-2/3 write, so `audit_tier_write`'s `get_current_user_id()`
  -- resolves and the audit rows below name the person who acted instead of
  -- recording `actor_known: false`. The actor was always a parameter here; only
  -- the one line telling the trigger about it was missing — the same shape
  -- `assign_material_supplier` had before `20260916000021`.
  IF p_user_id IS NOT NULL THEN
    PERFORM set_config('app.current_user_id', p_user_id::text, true);
  END IF;
  IF NULLIF(p_product_id, '') IS NULL OR NULLIF(p_customer_id, '') IS NULL THEN
    RAISE EXCEPTION 'product_id and customer_id are required';
  END IF;

  SELECT plant_name, organization INTO v_plant, v_org
  FROM public.projects WHERE id = p_project_id;
  IF v_plant IS NULL THEN
    RAISE EXCEPTION 'project_not_found';
  END IF;

  -- 1) Lane row (economics NULL — never estimated).
  INSERT INTO public.outbound_logistics
    (project_id, plant_name, product_id, customer_id)
  SELECT p_project_id, v_plant, p_product_id, p_customer_id
  WHERE NOT EXISTS (
    SELECT 1 FROM public.outbound_logistics
    WHERE project_id = p_project_id
      AND product_id = p_product_id
      AND customer_id = p_customer_id
  );

  -- 2) Edge row (combine-project's 'outbound' shape: rate carries the
  --    volume, 0 until one exists).
  INSERT INTO public.supply_chain_data
    (project_id, plant_name, data_source, from_location, to_location,
     material_consumption_rate, sourcing_ratio, weighted, uploaded_by, organization)
  SELECT p_project_id, v_plant, 'outbound', p_product_id, p_customer_id,
         0, 1.0, 0, p_user_id, v_org
  WHERE NOT EXISTS (
    SELECT 1 FROM public.supply_chain_data
    WHERE project_id = p_project_id
      AND data_source = 'outbound'
      AND from_location = p_product_id
      AND to_location = p_customer_id
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.bulk_delete_chat_threads(
  p_thread_ids uuid[], p_user_id uuid
) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_count integer;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);

  IF p_user_id IS NULL THEN RAISE EXCEPTION 'forbidden'; END IF;
  DELETE FROM public.chat_threads
   WHERE id = ANY (COALESCE(p_thread_ids, '{}'::uuid[]))
     AND user_id = p_user_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END; $$;

CREATE OR REPLACE FUNCTION public.bulk_insert_bom_multi_level(p_rows jsonb, p_user_id uuid, p_user_email text)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_org text;
  v_org_id uuid;
  v_modeler uuid;
  v_role text;
  v_project_id uuid;
  r jsonb;
  inserted_count integer := 0;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);

  PERFORM public.set_current_user_context(p_user_id, p_user_email);

  SELECT (value->>'project_id')::uuid INTO v_project_id
  FROM jsonb_array_elements(COALESCE(p_rows, '[]'::jsonb))
  LIMIT 1;

  IF v_project_id IS NULL THEN
    RAISE EXCEPTION 'project_id_required';
  END IF;

  SELECT organization, organization_id, modeler_id INTO v_org, v_org_id, v_modeler
  FROM public.projects
  WHERE id = v_project_id;

  IF v_org IS NULL THEN
    RAISE EXCEPTION 'project_not_found';
  END IF;

  SELECT user_role INTO v_role FROM public.get_current_approved_user() LIMIT 1;
  IF NOT public.org_is_current_user_org(v_org_id, v_org) OR NOT (v_modeler = public.get_current_user_id() OR v_role IN ('admin', 'super_admin')) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  FOR r IN SELECT value FROM jsonb_array_elements(COALESCE(p_rows, '[]'::jsonb)) LOOP
    INSERT INTO public.bom_multi_level (
      material_id,
      level,
      higher_level_component_id,
      consumption_rate,
      plant_name,
      project_id
    ) VALUES (
      r->>'material_id',
      CASE WHEN r ? 'level' AND NULLIF(r->>'level','') IS NOT NULL THEN (r->>'level')::int ELSE 0 END,
      NULLIF(r->>'higher_level_component_id',''),
      CASE WHEN r ? 'consumption_rate' AND NULLIF(r->>'consumption_rate','') IS NOT NULL THEN (r->>'consumption_rate')::numeric ELSE NULL END,
      r->>'plant_name',
      (r->>'project_id')::uuid
    );
    inserted_count := inserted_count + 1;
  END LOOP;

  RETURN inserted_count;
END;
$function$;

CREATE OR REPLACE FUNCTION public.bulk_insert_bom_single_level(p_rows jsonb, p_user_id uuid, p_user_email text)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_org text;
  v_org_id uuid;
  v_modeler uuid;
  v_role text;
  v_project_id uuid;
  r jsonb;
  inserted_count integer := 0;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);

  PERFORM public.set_current_user_context(p_user_id, p_user_email);

  SELECT (value->>'project_id')::uuid INTO v_project_id
  FROM jsonb_array_elements(COALESCE(p_rows, '[]'::jsonb))
  LIMIT 1;

  IF v_project_id IS NULL THEN
    RAISE EXCEPTION 'project_id_required';
  END IF;

  SELECT organization, organization_id, modeler_id INTO v_org, v_org_id, v_modeler
  FROM public.projects
  WHERE id = v_project_id;

  IF v_org IS NULL THEN
    RAISE EXCEPTION 'project_not_found';
  END IF;

  SELECT user_role INTO v_role FROM public.get_current_approved_user() LIMIT 1;
  IF NOT public.org_is_current_user_org(v_org_id, v_org) OR NOT (v_modeler = public.get_current_user_id() OR v_role IN ('admin', 'super_admin')) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  FOR r IN SELECT value FROM jsonb_array_elements(COALESCE(p_rows, '[]'::jsonb)) LOOP
    INSERT INTO public.bom_single_level (
      product_id,
      material_id,
      consumption_rate,
      plant_name,
      project_id
    ) VALUES (
      r->>'product_id',
      r->>'material_id',
      CASE WHEN r ? 'consumption_rate' AND NULLIF(r->>'consumption_rate','') IS NOT NULL THEN (r->>'consumption_rate')::numeric ELSE NULL END,
      r->>'plant_name',
      (r->>'project_id')::uuid
    );
    inserted_count := inserted_count + 1;
  END LOOP;

  RETURN inserted_count;
END;
$function$;

CREATE OR REPLACE FUNCTION public.bulk_insert_inbound_logistics(p_rows jsonb, p_user_id uuid, p_user_email text)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_org text;
  v_org_id uuid;
  v_modeler uuid;
  v_role text;
  v_project_id uuid;
  r jsonb;
  inserted_count integer := 0;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);

  PERFORM public.set_current_user_context(p_user_id, p_user_email);

  SELECT (value->>'project_id')::uuid INTO v_project_id
  FROM jsonb_array_elements(COALESCE(p_rows, '[]'::jsonb))
  LIMIT 1;

  IF v_project_id IS NULL THEN
    RAISE EXCEPTION 'project_id_required';
  END IF;

  SELECT organization, organization_id, modeler_id INTO v_org, v_org_id, v_modeler
  FROM public.projects
  WHERE id = v_project_id;

  IF v_org IS NULL THEN
    RAISE EXCEPTION 'project_not_found';
  END IF;

  SELECT user_role INTO v_role FROM public.get_current_approved_user() LIMIT 1;
  IF NOT public.org_is_current_user_org(v_org_id, v_org) OR NOT (v_modeler = public.get_current_user_id() OR v_role IN ('admin', 'super_admin')) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  FOR r IN SELECT value FROM jsonb_array_elements(COALESCE(p_rows, '[]'::jsonb)) LOOP
    INSERT INTO public.inbound_logistics (
      supplier_id,
      material_id,
      volume,
      time_unit,
      lead_time,
      unit_price,
      plant_name,
      project_id
    ) VALUES (
      r->>'supplier_id',
      r->>'material_id',
      CASE WHEN r ? 'volume' AND NULLIF(r->>'volume','') IS NOT NULL THEN (r->>'volume')::numeric ELSE NULL END,
      NULLIF(r->>'time_unit',''),
      CASE WHEN r ? 'lead_time' AND NULLIF(r->>'lead_time','') IS NOT NULL THEN (r->>'lead_time')::numeric ELSE NULL END,
      CASE WHEN r ? 'unit_price' AND NULLIF(r->>'unit_price','') IS NOT NULL THEN (r->>'unit_price')::numeric ELSE NULL END,
      r->>'plant_name',
      (r->>'project_id')::uuid
    );
    inserted_count := inserted_count + 1;
  END LOOP;

  RETURN inserted_count;
END;
$function$;

CREATE OR REPLACE FUNCTION public.bulk_insert_multi_tier_supply_chain(p_rows jsonb, p_user_id uuid, p_user_email text)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_org text;
  v_org_id uuid;
  v_modeler uuid;
  v_role text;
  v_project_id uuid;
  r jsonb;
  inserted_count integer := 0;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);

  PERFORM public.set_current_user_context(p_user_id, p_user_email);

  SELECT (value->>'project_id')::uuid INTO v_project_id
  FROM jsonb_array_elements(COALESCE(p_rows, '[]'::jsonb))
  LIMIT 1;

  IF v_project_id IS NULL THEN
    RAISE EXCEPTION 'project_id_required';
  END IF;

  SELECT organization, organization_id, modeler_id INTO v_org, v_org_id, v_modeler
  FROM public.projects
  WHERE id = v_project_id;

  IF v_org IS NULL THEN
    RAISE EXCEPTION 'project_not_found';
  END IF;

  SELECT user_role INTO v_role FROM public.get_current_approved_user() LIMIT 1;
  IF NOT public.org_is_current_user_org(v_org_id, v_org) OR NOT (v_modeler = public.get_current_user_id() OR v_role IN ('admin', 'super_admin')) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  FOR r IN SELECT value FROM jsonb_array_elements(COALESCE(p_rows, '[]'::jsonb)) LOOP
    INSERT INTO public.multi_tier_supply_chain (
      project_id,
      plant_name,
      from_firm_id,
      to_firm_id,
      to_firm_tier,
      to_firm_relationship
    ) VALUES (
      (r->>'project_id')::uuid,
      r->>'plant_name',
      r->>'from_firm_id',
      r->>'to_firm_id',
      CASE WHEN r ? 'to_firm_tier' AND NULLIF(r->>'to_firm_tier','') IS NOT NULL THEN (r->>'to_firm_tier')::int ELSE NULL END,
      NULLIF(r->>'to_firm_relationship','')
    );
    inserted_count := inserted_count + 1;
  END LOOP;

  RETURN inserted_count;
END;
$function$;

CREATE OR REPLACE FUNCTION public.bulk_insert_network_edges(
  p_project_id uuid,
  p_plant_name text,
  p_user_id uuid,
  p_user_email text,
  p_rows jsonb
) RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_org text;
  v_org_id uuid;
  v_modeler uuid;
  v_role text;
  r jsonb;
  inserted_count integer := 0;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_inputs');

  -- Caller context for RLS helpers
  PERFORM public.set_current_user_context(p_user_id, p_user_email);

  -- Authorization: same org AND (project owner or admin)
  SELECT organization, organization_id, modeler_id INTO v_org, v_org_id, v_modeler
  FROM public.projects
  WHERE id = p_project_id;

  IF v_org IS NULL THEN
    RAISE EXCEPTION 'project_not_found';
  END IF;

  SELECT user_role INTO v_role FROM public.get_current_approved_user() LIMIT 1;

  IF NOT public.org_is_current_user_org(v_org_id, v_org)
     OR NOT (v_modeler = public.get_current_user_id() OR v_role IN ('admin', 'super_admin')) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  -- Insert rows; treat uncritical fields as NULL if missing/empty
  FOR r IN SELECT value FROM jsonb_array_elements(COALESCE(p_rows, '[]'::jsonb)) LOOP
    INSERT INTO public.network_edges (
      project_id,
      plant_name,
      src_uid,
      dst_uid,
      relation_type,
      relative_revenue,
      relative_revenue_percentage,
      depth,
      direction
    ) VALUES (
      p_project_id,
      p_plant_name,
      r->>'src_uid',
      r->>'dst_uid',
      NULLIF(r->>'relation_type',''),
      CASE WHEN r ? 'relative_revenue' AND NULLIF(r->>'relative_revenue','') IS NOT NULL THEN (r->>'relative_revenue')::numeric ELSE NULL END,
      CASE WHEN r ? 'relative_revenue_percentage' AND NULLIF(r->>'relative_revenue_percentage','') IS NOT NULL THEN (r->>'relative_revenue_percentage')::numeric ELSE NULL END,
      CASE WHEN r ? 'depth' AND NULLIF(r->>'depth','') IS NOT NULL THEN (r->>'depth')::int ELSE NULL END,
      NULLIF(r->>'direction','')
    );
    inserted_count := inserted_count + 1;
  END LOOP;

  RETURN inserted_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.bulk_insert_network_nodes(
  p_project_id uuid,
  p_plant_name text,
  p_user_id uuid,
  p_user_email text,
  p_rows jsonb
) RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_org text;
  v_org_id uuid;
  v_modeler uuid;
  v_role text;
  r jsonb;
  inserted_count integer := 0;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_inputs');

  -- Caller context for RLS helpers
  PERFORM public.set_current_user_context(p_user_id, p_user_email);

  -- Authorization: same org AND (project owner or admin)
  SELECT organization, organization_id, modeler_id INTO v_org, v_org_id, v_modeler
  FROM public.projects
  WHERE id = p_project_id;

  IF v_org IS NULL THEN
    RAISE EXCEPTION 'project_not_found';
  END IF;

  SELECT user_role INTO v_role FROM public.get_current_approved_user() LIMIT 1;

  IF NOT public.org_is_current_user_org(v_org_id, v_org)
     OR NOT (v_modeler = public.get_current_user_id() OR v_role IN ('admin', 'super_admin')) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  -- Insert rows; treat uncritical fields as NULL if missing/empty
  FOR r IN SELECT value FROM jsonb_array_elements(COALESCE(p_rows, '[]'::jsonb)) LOOP
    INSERT INTO public.network_nodes (
      project_id,
      plant_name,
      uid,
      depth,
      name,
      country,
      industry,
      website,
      traded_as,
      number_of_employees,
      revenue,
      lat,
      long,
      is_seed
    ) VALUES (
      p_project_id,
      p_plant_name,
      r->>'uid',
      CASE WHEN r ? 'depth' AND NULLIF(r->>'depth','') IS NOT NULL THEN (r->>'depth')::int ELSE NULL END,
      NULLIF(r->>'name',''),
      NULLIF(r->>'country',''),
      NULLIF(r->>'industry',''),
      NULLIF(r->>'website',''),
      NULLIF(r->>'traded_as',''),
      CASE WHEN r ? 'number_of_employees' AND NULLIF(r->>'number_of_employees','') IS NOT NULL THEN (r->>'number_of_employees')::int ELSE NULL END,
      CASE WHEN r ? 'revenue' AND NULLIF(r->>'revenue','') IS NOT NULL THEN (r->>'revenue')::numeric ELSE NULL END,
      CASE WHEN r ? 'lat' AND NULLIF(r->>'lat','') IS NOT NULL THEN (r->>'lat')::numeric ELSE NULL END,
      CASE WHEN r ? 'long' AND NULLIF(r->>'long','') IS NOT NULL THEN (r->>'long')::numeric ELSE NULL END,
      CASE WHEN r ? 'is_seed' THEN COALESCE((r->>'is_seed')::boolean, false) ELSE false END
    );
    inserted_count := inserted_count + 1;
  END LOOP;

  RETURN inserted_count;
END;
$function$;

CREATE OR REPLACE FUNCTION public.bulk_insert_network_summary(
  p_project_id uuid,
  p_plant_name text,
  p_user_id uuid,
  p_user_email text,
  p_rows jsonb
) RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_org text;
  v_modeler uuid;
  v_role text;
  r jsonb;
  inserted_count integer := 0;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_inputs');

  -- Set caller context for RLS helpers
  PERFORM public.set_current_user_context(p_user_id, p_user_email);

  -- Validate project and authorization
  SELECT p.organization, p.modeler_id INTO v_org, v_modeler
  FROM public.projects p
  WHERE p.id = p_project_id;

  IF v_org IS NULL THEN
    RAISE EXCEPTION 'project_not_found';
  END IF;

  SELECT au.role::text INTO v_role 
  FROM public.approved_users au 
  WHERE au.id = p_user_id 
  LIMIT 1;

  IF v_org <> (SELECT au.organization FROM public.approved_users au WHERE au.id = p_user_id LIMIT 1)
     OR NOT (v_modeler = p_user_id OR v_role IN ('admin', 'super_admin')) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  -- Insert rows into network_summary table
  FOR r IN SELECT value FROM jsonb_array_elements(COALESCE(p_rows, '[]'::jsonb)) LOOP
    INSERT INTO public.network_summary (
      project_id,
      plant_name,
      nodes_count,
      edges_count,
      tiers_data,
      created_by,
      uploaded_by,
      organization
    ) VALUES (
      p_project_id,
      p_plant_name,
      CASE WHEN r ? 'nodes_count' AND NULLIF(r->>'nodes_count','') IS NOT NULL THEN (r->>'nodes_count')::int ELSE NULL END,
      CASE WHEN r ? 'edges_count' AND NULLIF(r->>'edges_count','') IS NOT NULL THEN (r->>'edges_count')::int ELSE NULL END,
      CASE WHEN r ? 'tiers_data' THEN r->'tiers_data' ELSE NULL END,
      p_user_id,
      p_user_id,
      v_org
    );
    inserted_count := inserted_count + 1;
  END LOOP;

  RETURN inserted_count;
END;
$function$;

CREATE OR REPLACE FUNCTION public.bulk_insert_outbound_logistics(p_rows jsonb, p_user_id uuid, p_user_email text)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_org text;
  v_org_id uuid;
  v_modeler uuid;
  v_role text;
  v_project_id uuid;
  r jsonb;
  inserted_count integer := 0;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);

  PERFORM public.set_current_user_context(p_user_id, p_user_email);

  SELECT (value->>'project_id')::uuid INTO v_project_id
  FROM jsonb_array_elements(COALESCE(p_rows, '[]'::jsonb))
  LIMIT 1;

  IF v_project_id IS NULL THEN
    RAISE EXCEPTION 'project_id_required';
  END IF;

  SELECT organization, organization_id, modeler_id INTO v_org, v_org_id, v_modeler
  FROM public.projects
  WHERE id = v_project_id;

  IF v_org IS NULL THEN
    RAISE EXCEPTION 'project_not_found';
  END IF;

  SELECT user_role INTO v_role FROM public.get_current_approved_user() LIMIT 1;
  IF NOT public.org_is_current_user_org(v_org_id, v_org) OR NOT (v_modeler = public.get_current_user_id() OR v_role IN ('admin', 'super_admin')) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  FOR r IN SELECT value FROM jsonb_array_elements(COALESCE(p_rows, '[]'::jsonb)) LOOP
    INSERT INTO public.outbound_logistics (
      customer_id,
      product_id,
      volume,
      time_unit,
      expected_lead_time,
      unit_price,
      plant_name,
      project_id
    ) VALUES (
      r->>'customer_id',
      r->>'product_id',
      CASE WHEN r ? 'volume' AND NULLIF(r->>'volume','') IS NOT NULL THEN (r->>'volume')::numeric ELSE NULL END,
      NULLIF(r->>'time_unit',''),
      CASE WHEN r ? 'expected_lead_time' AND NULLIF(r->>'expected_lead_time','') IS NOT NULL THEN (r->>'expected_lead_time')::numeric ELSE NULL END,
      CASE WHEN r ? 'unit_price' AND NULLIF(r->>'unit_price','') IS NOT NULL THEN (r->>'unit_price')::numeric ELSE NULL END,
      r->>'plant_name',
      (r->>'project_id')::uuid
    );
    inserted_count := inserted_count + 1;
  END LOOP;

  RETURN inserted_count;
END;
$function$;

CREATE OR REPLACE FUNCTION public.bulk_insert_tier2_suppliers(
  p_project_id uuid,
  p_data jsonb,
  p_user_id uuid,
  p_user_email text
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_org text;
  v_org_id uuid;
  v_modeler uuid;
  v_role text;
  v_plant text;
  inserted_count integer := 0;
  row_data jsonb;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_inputs');

  PERFORM public.set_current_user_context(p_user_id, p_user_email);

  SELECT organization, organization_id, modeler_id, plant_name INTO v_org, v_org_id, v_modeler, v_plant
  FROM public.projects WHERE id = p_project_id;

  IF v_org IS NULL THEN RAISE EXCEPTION 'project_not_found'; END IF;

  SELECT user_role INTO v_role FROM public.get_current_approved_user() LIMIT 1;
  IF NOT public.org_is_current_user_org(v_org_id, v_org) OR NOT (v_modeler = public.get_current_user_id() OR v_role IN ('admin', 'super_admin')) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  FOR row_data IN SELECT * FROM jsonb_array_elements(p_data) LOOP
    INSERT INTO public.tier2_suppliers (
      project_id, plant_name, supplier_id, upstream_supplier_id, 
      material_id, relationship_type, volume, unit_price, lead_time, time_unit
    ) VALUES (
      p_project_id,
      v_plant,
      row_data->>'supplier_id',
      row_data->>'upstream_supplier_id',
      row_data->>'material_id',
      row_data->>'relationship_type',
      CASE WHEN row_data->>'volume' ~ '^[0-9]+\.?[0-9]*$' THEN (row_data->>'volume')::numeric ELSE NULL END,
      CASE WHEN row_data->>'unit_price' ~ '^[0-9]+\.?[0-9]*$' THEN (row_data->>'unit_price')::numeric ELSE NULL END,
      CASE WHEN row_data->>'lead_time' ~ '^[0-9]+\.?[0-9]*$' THEN (row_data->>'lead_time')::numeric ELSE NULL END,
      row_data->>'time_unit'
    );
    inserted_count := inserted_count + 1;
  END LOOP;

  RETURN inserted_count;
END;
$function$;

CREATE OR REPLACE FUNCTION public.bulk_insert_tier3_suppliers(
  p_project_id uuid,
  p_data jsonb,
  p_user_id uuid,
  p_user_email text
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_org text;
  v_org_id uuid;
  v_modeler uuid;
  v_role text;
  v_plant text;
  inserted_count integer := 0;
  row_data jsonb;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_inputs');

  PERFORM public.set_current_user_context(p_user_id, p_user_email);

  SELECT organization, organization_id, modeler_id, plant_name INTO v_org, v_org_id, v_modeler, v_plant
  FROM public.projects WHERE id = p_project_id;

  IF v_org IS NULL THEN RAISE EXCEPTION 'project_not_found'; END IF;

  SELECT user_role INTO v_role FROM public.get_current_approved_user() LIMIT 1;
  IF NOT public.org_is_current_user_org(v_org_id, v_org) OR NOT (v_modeler = public.get_current_user_id() OR v_role IN ('admin', 'super_admin')) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  FOR row_data IN SELECT * FROM jsonb_array_elements(p_data) LOOP
    INSERT INTO public.tier3_suppliers (
      project_id, plant_name, supplier_id, upstream_supplier_id, 
      material_id, relationship_type, volume, unit_price, lead_time, time_unit
    ) VALUES (
      p_project_id,
      v_plant,
      row_data->>'supplier_id',
      row_data->>'upstream_supplier_id',
      row_data->>'material_id',
      row_data->>'relationship_type',
      CASE WHEN row_data->>'volume' ~ '^[0-9]+\.?[0-9]*$' THEN (row_data->>'volume')::numeric ELSE NULL END,
      CASE WHEN row_data->>'unit_price' ~ '^[0-9]+\.?[0-9]*$' THEN (row_data->>'unit_price')::numeric ELSE NULL END,
      CASE WHEN row_data->>'lead_time' ~ '^[0-9]+\.?[0-9]*$' THEN (row_data->>'lead_time')::numeric ELSE NULL END,
      row_data->>'time_unit'
    );
    inserted_count := inserted_count + 1;
  END LOOP;

  RETURN inserted_count;
END;
$function$;

CREATE OR REPLACE FUNCTION public.bulk_move_chat_threads(
  p_thread_ids uuid[], p_folder_id uuid, p_user_id uuid DEFAULT NULL
) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_count integer;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);

  IF p_user_id IS NULL THEN RAISE EXCEPTION 'forbidden'; END IF;
  IF p_folder_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.chat_folders f WHERE f.id = p_folder_id AND f.user_id = p_user_id
  ) THEN
    RAISE EXCEPTION 'folder % not found', p_folder_id;
  END IF;
  UPDATE public.chat_threads
     SET folder_id = p_folder_id
   WHERE id = ANY (COALESCE(p_thread_ids, '{}'::uuid[]))
     AND user_id = p_user_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END; $$;

CREATE OR REPLACE FUNCTION public.bulk_set_thread_flags(
  p_thread_ids uuid[], p_pinned boolean, p_archived boolean, p_user_id uuid DEFAULT NULL
) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_count integer;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);

  IF p_user_id IS NULL THEN RAISE EXCEPTION 'forbidden'; END IF;
  UPDATE public.chat_threads
     SET pinned   = COALESCE(p_pinned, pinned),
         archived = COALESCE(p_archived, archived)
   WHERE id = ANY (COALESCE(p_thread_ids, '{}'::uuid[]))
     AND user_id = p_user_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END; $$;

CREATE OR REPLACE FUNCTION public.bulk_upsert_materials(
  p_project_id uuid,
  p_rows       jsonb,
  _actor_user_id uuid DEFAULT NULL) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_bad   text;
  v_count integer;
BEGIN
  -- D309: bind caller assertions before the original operation.
  _actor_user_id := public.security_actor(_actor_user_id);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_inputs');


  -- D71, closed for this path (WP 6.2 slice 12). LOCAL to this transaction and
  -- set BEFORE any tier write, so `audit_tier_write`'s `get_current_user_id()`
  -- resolves and the audit rows below name the caller rather than recording
  -- `actor_known: false`. Guarded: `_actor_user_id` is DEFAULT NULL so every
  -- existing caller keeps working unchanged, and an unguarded set_config would
  -- BLANK an actor the caller's transaction had already established.
  IF _actor_user_id IS NOT NULL THEN
    PERFORM set_config('app.current_user_id', _actor_user_id::text, true);
  END IF;
  SELECT r->>'lead_time_dist' INTO v_bad
  FROM jsonb_array_elements(p_rows) AS r
  WHERE NULLIF(r->>'lead_time_dist', '') IS NOT NULL
    AND r->>'lead_time_dist' NOT IN ('deterministic', 'lognormal', 'gamma')
  LIMIT 1;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'invalid lead_time_dist "%" — engine accepts: deterministic, lognormal, gamma', v_bad;
  END IF;

  INSERT INTO public.materials
    (project_id, material_id, name, cost, holding_cost_pct, moq,
     initial_on_hand, lead_time_dist, lead_time_cv, updated_at)
  SELECT
    p_project_id,
    r->>'material_id',
    NULLIF(r->>'name', ''),
    NULLIF(r->>'cost', '')::numeric,
    NULLIF(r->>'holding_cost_pct', '')::numeric,
    NULLIF(r->>'moq', '')::numeric,
    NULLIF(r->>'initial_on_hand', '')::numeric,
    NULLIF(r->>'lead_time_dist', ''),
    NULLIF(r->>'lead_time_cv', '')::numeric,
    now()
  FROM jsonb_array_elements(p_rows) AS r
  WHERE NULLIF(r->>'material_id', '') IS NOT NULL
  ON CONFLICT (project_id, material_id) DO UPDATE SET
    name             = excluded.name,
    cost             = excluded.cost,
    holding_cost_pct = excluded.holding_cost_pct,
    moq              = excluded.moq,
    initial_on_hand  = excluded.initial_on_hand,
    lead_time_dist   = excluded.lead_time_dist,
    lead_time_cv     = excluded.lead_time_cv,
    updated_at       = now();

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.bulk_upsert_policy_overrides(
  p_project_id uuid,
  p_rows       jsonb,
  _actor_user_id uuid DEFAULT NULL) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE v_hash text;
BEGIN
  -- D309: bind caller assertions before the original operation.
  _actor_user_id := public.security_actor(_actor_user_id);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_policies');


  -- D71, closed for this path (WP 6.2 slice 12). LOCAL to this transaction and
  -- set BEFORE any tier write, so `audit_tier_write`'s `get_current_user_id()`
  -- resolves and the audit rows below name the caller rather than recording
  -- `actor_known: false`. Guarded: `_actor_user_id` is DEFAULT NULL so every
  -- existing caller keeps working unchanged, and an unguarded set_config would
  -- BLANK an actor the caller's transaction had already established.
  IF _actor_user_id IS NOT NULL THEN
    PERFORM set_config('app.current_user_id', _actor_user_id::text, true);
  END IF;
  -- D275 · a named actor must hold Edit Policies on the project.
  PERFORM public.assert_may_edit_policies(p_project_id, _actor_user_id);
  -- ONCE, outside the insert: a per-row call would rebuild the eleven-table
  -- snapshot for every override in a bulk seed, and two rows of one seed could
  -- land on different hashes if a write raced them.
  v_hash := public.current_graph_hash(p_project_id);

  INSERT INTO public.policy_overrides
    (project_id, scope, target_key, family, patch, seeded_from_hash, updated_at)
  SELECT
    p_project_id,
    r->>'scope',
    r->>'target_key',
    r->>'family',
    r->'patch',
    CASE WHEN COALESCE((r->>'seeded')::boolean, false) THEN v_hash ELSE NULL END,
    now()
  FROM jsonb_array_elements(p_rows) AS r
  ON CONFLICT (project_id, scope, target_key, family)
  DO UPDATE SET patch            = excluded.patch,
                seeded_from_hash = excluded.seeded_from_hash,
                updated_at       = now();
END;
$fn$;

CREATE OR REPLACE FUNCTION public.bulk_upsert_products(
  p_project_id uuid,
  p_rows       jsonb,
  _actor_user_id uuid DEFAULT NULL) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_bad   text;
  v_count integer;
BEGIN
  -- D309: bind caller assertions before the original operation.
  _actor_user_id := public.security_actor(_actor_user_id);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_inputs');


  -- D71, closed for this path (WP 6.2 slice 12). LOCAL to this transaction and
  -- set BEFORE any tier write, so `audit_tier_write`'s `get_current_user_id()`
  -- resolves and the audit rows below name the caller rather than recording
  -- `actor_known: false`. Guarded: `_actor_user_id` is DEFAULT NULL so every
  -- existing caller keeps working unchanged, and an unguarded set_config would
  -- BLANK an actor the caller's transaction had already established.
  IF _actor_user_id IS NOT NULL THEN
    PERFORM set_config('app.current_user_id', _actor_user_id::text, true);
  END IF;
  SELECT r->>'fulfillment_mode' INTO v_bad
  FROM jsonb_array_elements(p_rows) AS r
  WHERE NULLIF(r->>'fulfillment_mode', '') IS NOT NULL
    AND lower(r->>'fulfillment_mode') NOT IN ('mto', 'mts')
  LIMIT 1;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'invalid fulfillment_mode "%" — engine accepts: mto, mts (ato is not yet runnable)', v_bad;
  END IF;

  SELECT r->>'demand_distribution' INTO v_bad
  FROM jsonb_array_elements(p_rows) AS r
  WHERE NULLIF(r->>'demand_distribution', '') IS NOT NULL
    AND lower(r->>'demand_distribution') NOT IN ('triangular', 'deterministic', 'poisson', 'negbin')
  LIMIT 1;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'invalid demand_distribution "%" — engine accepts: triangular, deterministic, poisson, negbin', v_bad;
  END IF;

  INSERT INTO public.products
    (project_id, product_id, name, sell_price, production_capacity,
     fulfillment_mode, demand_distribution, demand_mean, demand_cv,
     demand_min, demand_max, updated_at)
  SELECT
    p_project_id,
    r->>'product_id',
    NULLIF(r->>'name', ''),
    NULLIF(r->>'sell_price', '')::numeric,
    NULLIF(r->>'production_capacity', '')::numeric,
    lower(NULLIF(r->>'fulfillment_mode', '')),
    lower(NULLIF(r->>'demand_distribution', '')),
    NULLIF(r->>'demand_mean', '')::numeric,
    NULLIF(r->>'demand_cv', '')::numeric,
    NULLIF(r->>'demand_min', '')::numeric,
    NULLIF(r->>'demand_max', '')::numeric,
    now()
  FROM jsonb_array_elements(p_rows) AS r
  WHERE NULLIF(r->>'product_id', '') IS NOT NULL
  ON CONFLICT (project_id, product_id) DO UPDATE SET
    name                = excluded.name,
    sell_price          = excluded.sell_price,
    production_capacity = excluded.production_capacity,
    fulfillment_mode    = excluded.fulfillment_mode,
    demand_distribution = excluded.demand_distribution,
    demand_mean         = excluded.demand_mean,
    demand_cv           = excluded.demand_cv,
    demand_min          = excluded.demand_min,
    demand_max          = excluded.demand_max,
    updated_at          = now();

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.bulk_upsert_suppliers(
  p_project_id uuid,
  p_rows       jsonb,
  _actor_user_id uuid DEFAULT NULL) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_count integer;
BEGIN
  -- D309: bind caller assertions before the original operation.
  _actor_user_id := public.security_actor(_actor_user_id);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_inputs');


  -- D71, closed for this path (WP 6.2 slice 12). LOCAL to this transaction and
  -- set BEFORE any tier write, so `audit_tier_write`'s `get_current_user_id()`
  -- resolves and the audit rows below name the caller rather than recording
  -- `actor_known: false`. Guarded: `_actor_user_id` is DEFAULT NULL so every
  -- existing caller keeps working unchanged, and an unguarded set_config would
  -- BLANK an actor the caller's transaction had already established.
  IF _actor_user_id IS NOT NULL THEN
    PERFORM set_config('app.current_user_id', _actor_user_id::text, true);
  END IF;
  INSERT INTO public.suppliers
    (project_id, supplier_id, name, capacity_per_week, reliability_score, updated_at)
  SELECT
    p_project_id,
    r->>'supplier_id',
    NULLIF(r->>'name', ''),
    NULLIF(r->>'capacity_per_week', '')::numeric,  -- NULL = unlimited
    COALESCE(NULLIF(r->>'reliability_score', '')::numeric, 1.0),
    now()
  FROM jsonb_array_elements(p_rows) AS r
  WHERE NULLIF(r->>'supplier_id', '') IS NOT NULL
  ON CONFLICT (project_id, supplier_id) DO UPDATE SET
    name              = excluded.name,
    capacity_per_week = excluded.capacity_per_week,
    reliability_score = excluded.reliability_score,
    updated_at        = now();

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.capture_graph_version(
  p_project_id    uuid,
  _actor_user_id  uuid,
  p_label         text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_before bigint;
  v_id     uuid;
  v_row    public.dataset_versions%ROWTYPE;
BEGIN
  -- D309: bind caller assertions before the original operation.
  _actor_user_id := public.security_actor(_actor_user_id);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_inputs');

  PERFORM public.assert_writer_may_act('capture_graph_version', p_project_id, _actor_user_id);
  SELECT count(*) INTO v_before FROM public.dataset_versions WHERE project_id = p_project_id;
  v_id := public.snapshot_dataset(p_project_id, p_label, _actor_user_id, NULL);
  SELECT * INTO v_row FROM public.dataset_versions WHERE id = v_id;
  RETURN jsonb_build_object(
    'dataset_version_id', v_row.id, 'version_no', v_row.version_no,
    'graph_hash', v_row.graph_hash,
    'created', (SELECT count(*) FROM public.dataset_versions WHERE project_id = p_project_id) > v_before);
END;
$$;

CREATE OR REPLACE FUNCTION public.change_own_password(
  p_old_password text,
  p_new_password text,
  p_user_id      uuid DEFAULT NULL
)
RETURNS timestamptz
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid     uuid := public.account_self_resolve(p_user_id);
  v_hash    text;
  v_active  boolean;
  v_expires timestamptz;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);

  SELECT au.password_hash, au.is_active INTO v_hash, v_active
    FROM public.approved_users au WHERE au.id = v_uid;

  IF NOT v_active THEN
    RAISE EXCEPTION 'account_inactive' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_new_password IS NULL OR length(p_new_password) < 8 THEN
    RAISE EXCEPTION 'password_too_short' USING ERRCODE = 'check_violation';
  END IF;
  IF v_hash IS NULL OR p_old_password IS NULL
     OR v_hash <> extensions.crypt(p_old_password, v_hash) THEN
    RAISE EXCEPTION 'invalid_current_password' USING ERRCODE = 'invalid_password';
  END IF;
  IF v_hash = extensions.crypt(p_new_password, v_hash) THEN
    RAISE EXCEPTION 'password_unchanged' USING ERRCODE = 'check_violation';
  END IF;

  v_expires := now() + public.password_max_age();
  UPDATE public.approved_users
     SET password_hash         = extensions.crypt(p_new_password, extensions.gen_salt('bf')),
         password_changed_at   = now(),
         password_expires_at   = v_expires,
         force_password_change = false,
         updated_at            = now()
   WHERE id = v_uid;

  BEGIN
    INSERT INTO public.audit_logs (plane, actor_user_id, action, target_type, target_id, after)
    VALUES ('access', v_uid, 'auth.password_changed', 'approved_users', v_uid::text,
            jsonb_build_object('password_expires_at', v_expires));
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'password-change audit skipped: %', SQLERRM;   -- never fail the change over it
  END;

  RETURN v_expires;
END;
$$;

CREATE OR REPLACE FUNCTION public.clear_policy_preset(
  p_project_id uuid,
  _actor_user_id uuid DEFAULT NULL) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  -- D309: bind caller assertions before the original operation.
  _actor_user_id := public.security_actor(_actor_user_id);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_policies');


  -- D71, closed for this path (WP 6.2 slice 12). LOCAL to this transaction and
  -- set BEFORE any tier write, so `audit_tier_write`'s `get_current_user_id()`
  -- resolves and the audit rows below name the caller rather than recording
  -- `actor_known: false`. Guarded: `_actor_user_id` is DEFAULT NULL so every
  -- existing caller keeps working unchanged, and an unguarded set_config would
  -- BLANK an actor the caller's transaction had already established.
  IF _actor_user_id IS NOT NULL THEN
    PERFORM set_config('app.current_user_id', _actor_user_id::text, true);
  END IF;
  -- D275 · a named actor must hold Edit Policies on the project.
  PERFORM public.assert_may_edit_policies(p_project_id, _actor_user_id);
  UPDATE public.policy_defaults
     SET active_preset     = NULL,
         preset_applied_at = NULL,
         updated_at        = now()
   WHERE project_id = p_project_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.combine_project_into_supply_chain(
  p_project_id uuid, p_user_id uuid, p_user_email text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_org     text;
  v_org_id  uuid;
  v_modeler uuid;
  v_role    text;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_inputs');

  PERFORM public.set_current_user_context(p_user_id, p_user_email);

  SELECT organization, organization_id, modeler_id INTO v_org, v_org_id, v_modeler
    FROM public.projects WHERE id = p_project_id;

  IF v_org IS NULL THEN
    RAISE EXCEPTION 'project_not_found';
  END IF;

  -- UNCHANGED (`20260920000003`): this path's authorization is D66's to move.
  SELECT user_role INTO v_role FROM public.get_current_approved_user() LIMIT 1;
  IF NOT public.org_is_current_user_org(v_org_id, v_org)
     OR NOT (v_modeler = public.get_current_user_id() OR v_role IN ('admin', 'super_admin')) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  PERFORM public.rebuild_supply_chain_lanes(p_project_id, p_user_id);
  -- WP 10.1 · §4 D234 — the world the combine ran over has a number.
  PERFORM public.snapshot_dataset(p_project_id,
    'After combine ' || to_char(now(), 'YYYY-MM-DD HH24:MI'), p_user_id, p_user_email);
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_agent_proposal(
  p_project_id      uuid,
  p_agent_id        text,
  p_artifact_type   text,
  p_title           text,
  p_payload         jsonb,
  p_citations       jsonb,
  p_provenance      text,
  p_grounding       jsonb,
  p_idempotency_key text,
  p_thread_id       text DEFAULT NULL,
  p_model_code      text DEFAULT NULL,
  p_provider_code   text DEFAULT NULL,
  p_user_id         uuid DEFAULT NULL,
  p_user_email      text DEFAULT NULL,
  p_status          text DEFAULT 'proposed'   -- 'draft' | 'proposed' only
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_id uuid;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_inputs');

  IF p_status NOT IN ('draft','proposed') THEN
    RAISE EXCEPTION 'create_agent_proposal: status must be draft or proposed';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.projects WHERE id = p_project_id) THEN
    RAISE EXCEPTION 'project % not found', p_project_id;
  END IF;
  SELECT id INTO v_id FROM public.proposals
   WHERE project_id = p_project_id AND idempotency_key = p_idempotency_key
     AND status IN ('draft','proposed','approved')
   LIMIT 1;
  IF v_id IS NOT NULL THEN RETURN v_id; END IF;

  -- §8 T10: per-user live-proposal cap (DEFAULT 20) — mass drafting cannot
  -- bloat the fabric or spam cards.
  IF (SELECT count(*) FROM public.proposals
       WHERE project_id = p_project_id
         AND created_by IS NOT DISTINCT FROM p_user_id
         AND status IN ('draft','proposed','approved')) >= 20 THEN
    RAISE EXCEPTION 'too_large: live-proposal cap (20) reached for this project';
  END IF;

  INSERT INTO public.proposals (
    project_id, agent_id, artifact_type, title, payload, citations,
    provenance, grounding, idempotency_key, thread_id,
    model_code, provider_code, created_by, created_by_email, status
  ) VALUES (
    p_project_id, p_agent_id, p_artifact_type, p_title, p_payload,
    COALESCE(p_citations,'[]'::jsonb), p_provenance,
    COALESCE(p_grounding,'{}'::jsonb), p_idempotency_key, p_thread_id,
    p_model_code, p_provider_code, p_user_id, p_user_email, p_status
  ) RETURNING id INTO v_id;
  RETURN v_id;
END; $$;

CREATE OR REPLACE FUNCTION public.create_api_key(
  p_user_id     uuid,
  p_user_email  text,
  p_name        text,
  p_scopes      text[],
  p_env         text DEFAULT 'live',
  p_project_ids uuid[] DEFAULT NULL,
  p_expires_at  timestamptz DEFAULT NULL,
  p_org_id      uuid DEFAULT NULL,
  p_principal   text DEFAULT 'org'
) RETURNS TABLE (id uuid, key_prefix text, plaintext_key text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_org     uuid;
  v_manage  boolean;
  v_prefix  text;
  v_secret  text;
  v_hash    text;
  v_id      uuid;
  v_scope   text;
  v_bad     uuid;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);

  PERFORM public.set_current_user_context(p_user_id, p_user_email);
  SELECT c.org_id, c.can_manage INTO v_org, v_manage FROM public._api_key_caller(p_user_id, p_org_id) c;

  IF p_env NOT IN ('live','test') THEN RAISE EXCEPTION 'env must be live or test'; END IF;
  IF COALESCE(p_principal, '') NOT IN ('org','personal') THEN
    RAISE EXCEPTION 'principal must be org or personal';
  END IF;
  IF NOT v_manage AND p_principal <> 'personal' THEN
    RAISE EXCEPTION 'forbidden: only an admin or modeler can create an organization key';
  END IF;
  -- A personal key acts as its creator, so its creator must be a member of the
  -- organization it is minted for — a super admin minting for another org gets
  -- an organization key or nothing.
  IF p_principal = 'personal' AND NOT EXISTS (
       SELECT 1 FROM public.approved_users u
        WHERE u.id = p_user_id AND u.organization_id = v_org AND COALESCE(u.is_active, false)) THEN
    RAISE EXCEPTION 'a personal key can only be created for your own organization';
  END IF;
  IF p_scopes IS NULL OR array_length(p_scopes, 1) IS NULL THEN
    RAISE EXCEPTION 'at least one scope is required';
  END IF;
  FOREACH v_scope IN ARRAY p_scopes LOOP
    IF v_scope NOT IN ('read:data','write:data','read:policies','write:policies',
                       'read:runs','write:runs','read:experiments','write:experiments',
                       'admin:keys') THEN
      RAISE EXCEPTION 'unknown scope: %', v_scope;
    END IF;
    IF NOT v_manage AND v_scope <> ALL (public.api_key_self_service_scopes()) THEN
      RAISE EXCEPTION 'forbidden: % needs an admin or modeler role — your keys are read-only', v_scope;
    END IF;
  END LOOP;

  IF p_project_ids IS NOT NULL THEN
    SELECT pid INTO v_bad FROM unnest(p_project_ids) AS pid
    WHERE NOT EXISTS (SELECT 1 FROM public.projects pr
                      WHERE pr.id = pid AND pr.organization_id = v_org)
    LIMIT 1;
    IF v_bad IS NOT NULL THEN
      RAISE EXCEPTION 'project % is not in your organization', v_bad;
    END IF;
  END IF;

  v_prefix := substr(encode(extensions.gen_random_bytes(6), 'hex'), 1, 8);
  v_secret := encode(extensions.gen_random_bytes(32), 'hex');
  v_hash   := encode(extensions.digest(v_secret, 'sha256'), 'hex');

  INSERT INTO public.api_keys
    (key_prefix, secret_hash, org_id, created_by, name, scopes, project_ids, env, expires_at, principal)
  VALUES
    (v_prefix, v_hash, v_org, p_user_id, COALESCE(NULLIF(trim(p_name), ''), 'API key'),
     p_scopes, p_project_ids, p_env, p_expires_at, p_principal)
  RETURNING api_keys.id INTO v_id;

  PERFORM public._api_key_audit(p_user_id, 'api_key.create', v_id, NULL,
    jsonb_build_object('name', p_name, 'env', p_env, 'scopes', p_scopes, 'principal', p_principal,
                       'project_ids', p_project_ids, 'expires_at', p_expires_at, 'org_id', v_org,
                       'self_service', NOT v_manage));

  RETURN QUERY SELECT v_id, v_prefix, 'sk_' || p_env || '_' || v_prefix || '_' || v_secret;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_chat_folder(
  p_user_id uuid, p_name text, p_position integer DEFAULT 0
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_id uuid;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);

  IF p_user_id IS NULL THEN RAISE EXCEPTION 'forbidden'; END IF;
  INSERT INTO public.chat_folders (user_id, name, position)
  VALUES (p_user_id, p_name, COALESCE(p_position, 0))
  ON CONFLICT (user_id, name) DO UPDATE SET position = EXCLUDED.position
  RETURNING id INTO v_id;
  RETURN v_id;
END; $$;

CREATE OR REPLACE FUNCTION public.create_disruption_scenario_v2(
  p_project_id uuid, 
  p_plant_name text, 
  p_scenario_name text, 
  p_user_id uuid, 
  p_user_email text, 
  p_status disruption_status DEFAULT 'draft'::disruption_status, 
  p_description text DEFAULT NULL::text, 
  p_tags text[] DEFAULT '{}'::text[], 
  p_targets jsonb DEFAULT NULL::jsonb, 
  p_effects jsonb DEFAULT NULL::jsonb, 
  p_settings jsonb DEFAULT NULL::jsonb,
  p_disruption_start date DEFAULT NULL::date,
  p_disruption_end date DEFAULT NULL::date
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_org text;
  v_modeler uuid;
  v_role text;
  new_profile_id uuid;
  t jsonb;
  e jsonb;
  k text;
  v jsonb;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, 'simulation_lab');

  -- Set user context
  PERFORM public.set_current_user_context(p_user_id, p_user_email);

  -- Validate project and authorization
  SELECT organization, modeler_id INTO v_org, v_modeler
  FROM public.projects
  WHERE id = p_project_id;

  IF v_org IS NULL THEN RAISE EXCEPTION 'project_not_found'; END IF;

  SELECT user_role INTO v_role FROM public.get_current_approved_user() LIMIT 1;
  IF v_org <> public.get_current_user_org() OR NOT (v_modeler = public.get_current_user_id() OR v_role IN ('admin', 'super_admin')) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  -- Insert profile with disruption dates
  INSERT INTO public.disruption_scenario_profiles (
    project_id, plant_name, scenario_name, status, description, tags, 
    created_by, organization, disruption_start, disruption_end
  ) VALUES (
    p_project_id, p_plant_name, p_scenario_name, COALESCE(p_status, 'draft'), 
    p_description, COALESCE(p_tags, '{}'), p_user_id, v_org, 
    p_disruption_start, p_disruption_end
  ) RETURNING id INTO new_profile_id;

  -- Insert targets
  IF p_targets IS NOT NULL AND jsonb_typeof(p_targets) = 'array' THEN
    FOR t IN SELECT * FROM jsonb_array_elements(p_targets) LOOP
      INSERT INTO public.disruption_scenario_targets (
        profile_id, target_type, node_ids, edge_list, selector
      ) VALUES (
        new_profile_id,
        COALESCE((t->>'target_type')::public.disruption_target_type, 'node'),
        CASE WHEN (t ? 'node_ids') THEN ARRAY(SELECT jsonb_array_elements_text(t->'node_ids')) ELSE NULL END,
        CASE WHEN (t ? 'edges') THEN t->'edges' ELSE NULL END,
        CASE WHEN (t ? 'selector') THEN t->'selector' ELSE NULL END
      );
    END LOOP;
  END IF;

  -- Insert effects
  IF p_effects IS NOT NULL AND jsonb_typeof(p_effects) = 'array' THEN
    FOR e IN SELECT * FROM jsonb_array_elements(p_effects) LOOP
      INSERT INTO public.disruption_scenario_effects (
        profile_id, effect_type, magnitude, unit
      ) VALUES (
        new_profile_id,
        (e->>'effect_type')::public.disruption_effect_type,
        COALESCE((e->>'magnitude')::numeric, 0),
        (e->>'unit')
      );
    END LOOP;
  END IF;

  -- Insert settings: accept object map or array of {key,value}
  IF p_settings IS NOT NULL THEN
    IF jsonb_typeof(p_settings) = 'object' THEN
      FOR k, v IN SELECT key, value FROM jsonb_each(p_settings) LOOP
        INSERT INTO public.disruption_scenario_settings (profile_id, key, value)
        VALUES (new_profile_id, k, v)
        ON CONFLICT (profile_id, key) DO UPDATE SET value = EXCLUDED.value, updated_at = now();
      END LOOP;
    ELSIF jsonb_typeof(p_settings) = 'array' THEN
      FOR e IN SELECT * FROM jsonb_array_elements(p_settings) LOOP
        INSERT INTO public.disruption_scenario_settings (profile_id, key, value)
        VALUES (new_profile_id, e->>'key', COALESCE(e->'value', 'null'::jsonb))
        ON CONFLICT (profile_id, key) DO UPDATE SET value = EXCLUDED.value, updated_at = now();
      END LOOP;
    END IF;
  END IF;

  RETURN new_profile_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_disruption_scenario_v2(
  p_project_id uuid,
  p_plant_name text,
  p_scenario_name text,
  p_user_id uuid,
  p_user_email text,
  p_status public.disruption_status DEFAULT 'draft',
  p_description text DEFAULT NULL,
  p_tags text[] DEFAULT '{}',
  p_targets jsonb DEFAULT NULL,
  p_effects jsonb DEFAULT NULL,
  p_settings jsonb DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_org text;
  v_modeler uuid;
  v_role text;
  new_profile_id uuid;
  t jsonb;
  e jsonb;
  k text;
  v jsonb;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, 'simulation_lab');

  -- Set user context
  PERFORM public.set_current_user_context(p_user_id, p_user_email);

  -- Validate project and authorization
  SELECT organization, modeler_id INTO v_org, v_modeler
  FROM public.projects
  WHERE id = p_project_id;

  IF v_org IS NULL THEN RAISE EXCEPTION 'project_not_found'; END IF;

  SELECT user_role INTO v_role FROM public.get_current_approved_user() LIMIT 1;
  IF v_org <> public.get_current_user_org() OR NOT (v_modeler = public.get_current_user_id() OR v_role = 'admin') THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  -- Insert profile
  INSERT INTO public.disruption_scenario_profiles (
    project_id, plant_name, scenario_name, status, description, tags, created_by, organization
  ) VALUES (
    p_project_id, p_plant_name, p_scenario_name, COALESCE(p_status, 'draft'), p_description, COALESCE(p_tags, '{}'), p_user_id, v_org
  ) RETURNING id INTO new_profile_id;

  -- Insert targets
  IF p_targets IS NOT NULL AND jsonb_typeof(p_targets) = 'array' THEN
    FOR t IN SELECT * FROM jsonb_array_elements(p_targets) LOOP
      INSERT INTO public.disruption_scenario_targets (
        profile_id, target_type, node_ids, edge_list, selector
      ) VALUES (
        new_profile_id,
        COALESCE((t->>'target_type')::public.disruption_target_type, 'node'),
        CASE WHEN (t ? 'node_ids') THEN ARRAY(SELECT jsonb_array_elements_text(t->'node_ids')) ELSE NULL END,
        CASE WHEN (t ? 'edges') THEN t->'edges' ELSE NULL END,
        CASE WHEN (t ? 'selector') THEN t->'selector' ELSE NULL END
      );
    END LOOP;
  END IF;

  -- Insert effects
  IF p_effects IS NOT NULL AND jsonb_typeof(p_effects) = 'array' THEN
    FOR e IN SELECT * FROM jsonb_array_elements(p_effects) LOOP
      INSERT INTO public.disruption_scenario_effects (
        profile_id, effect_type, magnitude, unit
      ) VALUES (
        new_profile_id,
        (e->>'effect_type')::public.disruption_effect_type,
        COALESCE((e->>'magnitude')::numeric, 0),
        (e->>'unit')
      );
    END LOOP;
  END IF;

  -- Insert settings: accept object map or array of {key,value}
  IF p_settings IS NOT NULL THEN
    IF jsonb_typeof(p_settings) = 'object' THEN
      FOR k, v IN SELECT key, value FROM jsonb_each(p_settings) LOOP
        INSERT INTO public.disruption_scenario_settings (profile_id, key, value)
        VALUES (new_profile_id, k, v)
        ON CONFLICT (profile_id, key) DO UPDATE SET value = EXCLUDED.value, updated_at = now();
      END LOOP;
    ELSIF jsonb_typeof(p_settings) = 'array' THEN
      FOR e IN SELECT * FROM jsonb_array_elements(p_settings) LOOP
        INSERT INTO public.disruption_scenario_settings (profile_id, key, value)
        VALUES (new_profile_id, e->>'key', COALESCE(e->'value', 'null'::jsonb))
        ON CONFLICT (profile_id, key) DO UPDATE SET value = EXCLUDED.value, updated_at = now();
      END LOOP;
    END IF;
  END IF;

  RETURN new_profile_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_disruption_scenario(
  p_project_id uuid,
  p_plant_name text,
  p_node_id text,
  p_scenario_name text,
  p_capacity_reduction_percent numeric,
  p_time_delay_days numeric,
  p_description text,
  p_user_id uuid,
  p_user_email text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_org text;
  v_org_id uuid;
  v_modeler uuid;
  v_role text;
  new_id uuid;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, 'simulation_lab');

  -- Set user context so helper funcs and RLS checks use caller identity
  PERFORM public.set_current_user_context(p_user_id, p_user_email);

  -- Validate project and authorization
  SELECT organization, organization_id, modeler_id INTO v_org, v_org_id, v_modeler
  FROM public.projects
  WHERE id = p_project_id;

  IF v_org IS NULL THEN
    RAISE EXCEPTION 'project_not_found';
  END IF;

  SELECT user_role INTO v_role
  FROM public.get_current_approved_user()
  LIMIT 1;

  IF NOT public.org_is_current_user_org(v_org_id, v_org) OR NOT (v_modeler = public.get_current_user_id() OR v_role IN ('admin', 'super_admin')) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  -- Insert scenario, ensuring org and creator are set
  INSERT INTO public.disruption_scenarios (
    project_id,
    plant_name,
    node_id,
    scenario_name,
    capacity_reduction_percent,
    time_delay_days,
    description,
    created_by,
    organization
  ) VALUES (
    p_project_id,
    p_plant_name,
    p_node_id,
    p_scenario_name,
    COALESCE(p_capacity_reduction_percent, 0),
    COALESCE(p_time_delay_days, 0),
    p_description,
    p_user_id,
    v_org
  ) RETURNING id INTO new_id;

  RETURN new_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_project(
  p_name text,
  p_plant text,
  p_model text,
  p_bom_level text,
  p_user_id uuid,
  p_user_email text,
  p_user_name text,
  p_simulation_start date DEFAULT NULL::date,
  p_simulation_end date DEFAULT NULL::date,
  p_data_type text DEFAULT 'curated'::text,
  p_deep_tier_enabled boolean DEFAULT false
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  new_id uuid;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);

  -- Set app context for this session so RLS helper functions work
  PERFORM public.set_current_user_context(p_user_id, p_user_email);

  INSERT INTO public.projects (
    name,
    plant_name,
    supply_chain_model,
    bom_level,
    modeler_id,
    modeler_name,
    simulation_start,
    simulation_end,
    data_type,
    deep_tier_enabled
  ) VALUES (
    p_name,
    p_plant,
    p_model,
    p_bom_level,
    p_user_id,
    p_user_name,
    p_simulation_start,
    p_simulation_end,
    COALESCE(p_data_type, 'curated'),
    COALESCE(p_deep_tier_enabled, false)
  ) RETURNING id INTO new_id;

  RETURN new_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_simulation_result(
  p_project_id uuid,
  p_user_id uuid,
  p_user_email text,
  p_plant_name text,
  p_scenario_ids uuid[],
  p_status text DEFAULT 'running',
  p_started_at timestamptz DEFAULT now(),
  p_metrics jsonb DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_org text;
  v_org_id uuid;
  v_modeler uuid;
  v_role text;
  new_id uuid;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, 'simulation_lab');

  -- Set caller context for RLS helpers
  PERFORM public.set_current_user_context(p_user_id, p_user_email);

  -- Validate project and authorization (owner or admin in same org)
  SELECT organization, organization_id, modeler_id INTO v_org, v_org_id, v_modeler
  FROM public.projects
  WHERE id = p_project_id;

  IF v_org IS NULL THEN RAISE EXCEPTION 'project_not_found'; END IF;

  SELECT user_role INTO v_role FROM public.get_current_approved_user() LIMIT 1;
  IF NOT public.org_is_current_user_org(v_org_id, v_org) OR NOT (v_modeler = public.get_current_user_id() OR v_role IN ('admin', 'super_admin')) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  -- Insert simulation result (triggers/policies will enforce org & created_by)
  INSERT INTO public.simulation_results (
    project_id, plant_name, status, scenario_ids, started_at, created_by, organization, metrics
  ) VALUES (
    p_project_id, p_plant_name, COALESCE(p_status, 'running'), p_scenario_ids, COALESCE(p_started_at, now()),
    p_user_id, v_org, p_metrics
  ) RETURNING id INTO new_id;

  RETURN new_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_simulation_run(
  p_run              jsonb,
  p_force_rerun      boolean DEFAULT false,
  p_attach_inflight  boolean DEFAULT true,
  _actor_user_id     uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  v_scenario  uuid := (p_run ->> 'scenario_id')::uuid;
  v_project   uuid := (p_run ->> 'project_id')::uuid;
  v_target    integer := GREATEST(1, COALESCE((p_run ->> 'rep_count_target')::int, 1));
  v_overrides jsonb := COALESCE(p_run -> 'protocol_overrides', '{}'::jsonb);
  v_engine    public.sim_engines%ROWTYPE;
  v_spec      jsonb;
  v_key       text;
  v_hit       record;
  v_model     uuid := NULLIF(p_run ->> 'model_validation_id', '')::uuid;
  v_id        uuid;
  v_rep_weeks bigint;
  v_actor     uuid;
  v_sim       text;
  v_simver    uuid;
  v_mpol      text;
  v_mds       uuid;
  v_msim      text;
  v_mgraph    text;
BEGIN
  -- D309: bind caller assertions before the original operation.
  _actor_user_id := public.security_actor(_actor_user_id);

  IF _actor_user_id IS NOT NULL THEN
    PERFORM set_config('app.current_user_id', _actor_user_id::text, true);
  END IF;
  IF v_scenario IS NULL OR v_project IS NULL THEN
    RAISE EXCEPTION 'a run names its project and scenario' USING ERRCODE = 'not_null_violation';
  END IF;
  IF jsonb_typeof(v_overrides) <> 'object' THEN
    RAISE EXCEPTION 'protocol_overrides is an object' USING ERRCODE = 'check_violation';
  END IF;

  v_engine := public.sim_engine_for_dispatch(NULLIF(p_run ->> 'engine_id', '')::uuid);
  -- WP 11.2 · §4 D260 — the key hashes what the engine READS: the simulation scope of
  -- the snapshot this run is bound to (read here, so a caller cannot hand the key a
  -- hash its snapshot does not carry), else the one the caller names.
  SELECT dv.hash_inputs, dv.simulation_version_id INTO v_sim, v_simver
    FROM public.dataset_versions dv
   WHERE dv.id = NULLIF(p_run ->> 'dataset_version_id', '')::uuid AND dv.project_id = v_project;
  v_sim := COALESCE(v_sim, NULLIF(p_run ->> 'hash_simulation', ''));
  IF v_simver IS NULL AND v_sim IS NOT NULL THEN
    SELECT id INTO v_simver FROM public.graph_level_versions
     WHERE project_id = v_project AND level = 'simulation' AND level_hash = v_sim;
  END IF;
  -- PLAN.md §23 WP 13.3 · §4 D280 — WHAT WAS VALIDATED IS WHAT RUNS. A run that
  -- follows a Validated Model (and is not exploratory) must read the model's own
  -- content: its policy hash, and — when the model names its dataset version — the
  -- simulation inputs of that version. A run naming the model while reading other
  -- data or other policies would carry a validation it does not have. Content, not
  -- ids: a run stamped by content after a deep-tier edit the engine does not read
  -- (WP 11.2) still reads the model's inputs and is accepted.
  IF v_model IS NOT NULL AND NOT COALESCE((p_run ->> 'exploratory')::boolean, false) THEN
    SELECT mv.policy_hash, mv.dataset_version_id,
           COALESCE(mv.hash_simulation, dvm.hash_inputs) AS sim, mv.graph_hash
      INTO v_mpol, v_mds, v_msim, v_mgraph
      FROM public.model_validations mv
      LEFT JOIN public.dataset_versions dvm ON dvm.id = mv.dataset_version_id
     WHERE mv.id = v_model AND mv.project_id = v_project;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'the Validated Model % is not this project''s', v_model USING ERRCODE = 'check_violation';
    END IF;
    IF v_mpol IS DISTINCT FROM (p_run ->> 'policy_hash') THEN
      RAISE EXCEPTION 'a run of a Validated Model reads the model''s policy version — this run names other policies (§23 WP 13.3)'
        USING ERRCODE = 'check_violation';
    END IF;
    IF v_mds IS NOT NULL AND (
         CASE WHEN v_msim IS NOT NULL THEN v_sim IS DISTINCT FROM v_msim
              ELSE (SELECT graph_hash FROM public.dataset_versions
                     WHERE id = NULLIF(p_run ->> 'dataset_version_id', '')::uuid) IS DISTINCT FROM v_mgraph
         END) THEN
      RAISE EXCEPTION 'a run of a Validated Model reads the model''s dataset version — this run names other data; run it as exploratory instead (§23 WP 13.3)'
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  v_spec := public.simulation_run_spec(v_scenario, p_run ->> 'policy_hash', v_sim,
                                       v_engine.id, v_overrides);
  v_key := public.simulation_run_key(v_spec);
  PERFORM pg_advisory_xact_lock(hashtextextended('simulation_run:' || v_project::text || ':' || v_key, 0));

  IF NOT COALESCE(p_force_rerun, false) THEN
    SELECT r.id, r.ended_at, r.created_at, r.code_version, r.rep_count_done INTO v_hit
      FROM public.simulation_runs r
     WHERE r.project_id = v_project AND r.scenario_id = v_scenario AND r.run_key = v_key
       AND r.status = 'done' AND COALESCE(r.rep_count_done, 0) >= v_target
     ORDER BY r.created_at DESC LIMIT 1;
    IF FOUND THEN
      RETURN jsonb_build_object('reuse', jsonb_build_object(
        'run_id', v_hit.id, 'ended_at', v_hit.ended_at, 'created_at', v_hit.created_at,
        'code_version', v_hit.code_version, 'rep_count_done', v_hit.rep_count_done), 'run_key', v_key);
    END IF;
  END IF;

  IF COALESCE(p_attach_inflight, true) THEN
    SELECT r.id INTO v_hit
      FROM public.simulation_runs r
     WHERE r.project_id = v_project AND r.scenario_id = v_scenario AND r.run_key = v_key
       AND COALESCE(r.rep_count_target, 0) >= v_target
       AND (r.status = 'running' OR (r.status = 'queued' AND r.created_at > now() - interval '15 minutes'))
     ORDER BY r.created_at DESC LIMIT 1;
    IF FOUND THEN
      RETURN jsonb_build_object('run_id', v_hit.id, 'attached', true, 'run_key', v_key);
    END IF;
  END IF;

  -- WP 10.7 · §4 D247 — capacity is checked HERE, for a run that will actually be
  -- computed: a reuse or an attach above consumes nothing. One enforcement point
  -- for every front door (the browser, /v1, agent-apply all reach this through
  -- the shared dispatcher). The actor is the app's asserted user (D28).
  v_rep_weeks := v_target::bigint * GREATEST(1, ceil(COALESCE((v_spec -> 'scenario' ->> 'horizon_days')::numeric, 364) / 7.0))::bigint;
  -- The member whose share this run draws on: the app's asserted user, which the
  -- dispatcher passes in the run (D28 — client-asserted); `_actor_user_id` when
  -- the caller has nothing else. A run with no actor is held to the pool only.
  v_actor := COALESCE(NULLIF(p_run ->> 'actor_user_id', '')::uuid, _actor_user_id);
  PERFORM public._capacity_admit(v_project, v_actor, v_target, v_rep_weeks,
                                 COALESCE((p_run ->> 'bytes_estimate')::bigint, 0),
                                 COALESCE(p_run -> 'limits', '{}'::jsonb));

  INSERT INTO public.simulation_runs (
    scenario_id, project_id, status, rep_count_target, rep_count_done, code_version,
    policy_version_id, policy_hash, dataset_version_id, graph_hash, created_by,
    scenario_hash, model_validation_id, gate_skipped, seed, disruption_schedule,
    engine_id, run_spec, run_key, protocol_overrides, exploratory,
    hash_simulation, simulation_version_id
  ) VALUES (
    v_scenario, v_project, 'queued', v_target, 0, '',
    NULLIF(p_run ->> 'policy_version_id', '')::uuid, p_run ->> 'policy_hash',
    NULLIF(p_run ->> 'dataset_version_id', '')::uuid, p_run ->> 'graph_hash',
    NULLIF(p_run ->> 'created_by', '')::uuid,
    p_run ->> 'scenario_hash', v_model,
    COALESCE((p_run ->> 'gate_skipped')::boolean, false),
    (p_run ->> 'seed')::bigint, p_run -> 'disruption_schedule',
    v_engine.id, v_spec, v_key, v_overrides,
    -- exploratory: said by the caller, and never false for a run with no model.
    COALESCE((p_run ->> 'exploratory')::boolean, false) OR v_model IS NULL,
    v_sim, v_simver
  )
  RETURNING id INTO v_id;
  -- The reservation: replication-weeks at dispatch, settled at completion.
  INSERT INTO public.run_usage (org_id, user_id, project_id, run_id, rep_weeks, bytes, kind)
  VALUES ((SELECT organization_id FROM public.projects WHERE id = v_project), v_actor, v_project, v_id,
          v_rep_weeks, 0, 'dispatch');
  -- The engine travels to the worker in the envelope, so a worker that runs a
  -- different one refuses the run instead of computing and relabelling it.
  RETURN jsonb_build_object('run_id', v_id, 'attached', false, 'run_key', v_key,
    'engine', jsonb_build_object('id', v_engine.id, 'slug', v_engine.slug,
                                 'code_version', v_engine.code_version));
END;
$fn$;

CREATE OR REPLACE FUNCTION public.create_user_file(
  p_user_id     uuid,
  p_kind        text,
  p_name        text,
  p_path        text,
  p_size_bytes  bigint,
  p_org_id      uuid DEFAULT NULL,
  p_project_id  uuid DEFAULT NULL,
  p_proposal_id uuid DEFAULT NULL,
  p_expires_at  timestamptz DEFAULT NULL,
  -- caller-supplied id so the row id equals the <file_id> embedded in the
  -- storage path (the §16.2 path law's audit story)
  p_id          uuid DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_org uuid := p_org_id;
  v_id  uuid;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_inputs');

  IF p_user_id IS NULL THEN RAISE EXCEPTION 'user id required'; END IF;
  IF v_org IS NULL THEN
    SELECT organization_id INTO v_org FROM public.approved_users WHERE id = p_user_id;
  END IF;
  INSERT INTO public.user_files (id, org_id, user_id, project_id, proposal_id, kind, name, path, size_bytes, expires_at)
  VALUES (COALESCE(p_id, gen_random_uuid()), v_org, p_user_id, p_project_id, p_proposal_id, p_kind,
          left(p_name, 200), p_path, p_size_bytes,
          COALESCE(p_expires_at, now() + interval '14 days'))
  RETURNING id INTO v_id;
  RETURN v_id;
END; $$;

CREATE OR REPLACE FUNCTION public.delete_all_disruption_scenarios(
  p_project_id uuid, 
  p_user_id uuid, 
  p_user_email text
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_org text;
  v_org_id uuid;
  v_modeler uuid;
  v_role text;
  deleted_count integer := 0;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, 'simulation_lab');

  -- Set user context for RLS policies
  PERFORM public.set_current_user_context(p_user_id, p_user_email);

  -- Validate project and authorization
  SELECT organization, organization_id, modeler_id INTO v_org, v_org_id, v_modeler
  FROM public.projects
  WHERE id = p_project_id;

  IF v_org IS NULL THEN 
    RAISE EXCEPTION 'project_not_found'; 
  END IF;

  -- Authorization: same org AND (project owner or admin)
  SELECT user_role INTO v_role FROM public.get_current_approved_user() LIMIT 1;
  IF NOT public.org_is_current_user_org(v_org_id, v_org) OR NOT (v_modeler = public.get_current_user_id() OR v_role IN ('admin', 'super_admin')) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  -- Delete all scenario profiles for this project (cascading deletes will handle related tables)
  DELETE FROM public.disruption_scenario_profiles 
  WHERE project_id = p_project_id;
  
  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  
  RETURN deleted_count;
END;
$function$;

CREATE OR REPLACE FUNCTION public.delete_chat_folder(
  p_folder_id uuid, p_user_id uuid
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);

  DELETE FROM public.chat_folders WHERE id = p_folder_id AND user_id = p_user_id;
END; $$;

CREATE OR REPLACE FUNCTION public.delete_chat_thread(
  p_thread_id uuid, p_user_id uuid
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);

  PERFORM public._chat_assert_thread_owner(p_thread_id, p_user_id);
  DELETE FROM public.chat_threads WHERE id = p_thread_id;
END; $$;

CREATE OR REPLACE FUNCTION public.delete_disruption_scenario(p_scenario_id uuid, p_user_id uuid, p_user_email text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $$
DECLARE
  v_org text;
  v_org_id uuid;
  v_modeler uuid;
  v_role text;
  v_project_id uuid;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);

  -- Set user context for RLS policies
  PERFORM public.set_current_user_context(p_user_id, p_user_email);

  -- Get project info from the scenario
  SELECT dsp.project_id, p.organization, p.organization_id, p.modeler_id 
  INTO v_project_id, v_org, v_org_id, v_modeler
  FROM public.disruption_scenario_profiles dsp
  JOIN public.projects p ON p.id = dsp.project_id
  WHERE dsp.id = p_scenario_id;

  IF v_org IS NULL THEN 
    RAISE EXCEPTION 'scenario_not_found'; 
  END IF;

  -- Authorization: same org AND (project owner or admin)
  SELECT user_role INTO v_role FROM public.get_current_approved_user() LIMIT 1;
  IF NOT public.org_is_current_user_org(v_org_id, v_org) OR NOT (v_modeler = public.get_current_user_id() OR v_role IN ('admin', 'super_admin')) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  -- Delete the scenario (cascading deletes will handle related tables)
  DELETE FROM public.disruption_scenario_profiles 
  WHERE id = p_scenario_id;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'scenario_not_found';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_policy_override(
  p_project_id uuid,
  p_scope      text,
  p_target_key text,
  p_family     text,
  _actor_user_id uuid DEFAULT NULL) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  -- D309: bind caller assertions before the original operation.
  _actor_user_id := public.security_actor(_actor_user_id);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_policies');


  -- D71, closed for this path (WP 6.2 slice 12). LOCAL to this transaction and
  -- set BEFORE any tier write, so `audit_tier_write`'s `get_current_user_id()`
  -- resolves and the audit rows below name the caller rather than recording
  -- `actor_known: false`. Guarded: `_actor_user_id` is DEFAULT NULL so every
  -- existing caller keeps working unchanged, and an unguarded set_config would
  -- BLANK an actor the caller's transaction had already established.
  IF _actor_user_id IS NOT NULL THEN
    PERFORM set_config('app.current_user_id', _actor_user_id::text, true);
  END IF;
  -- D275 · a named actor must hold Edit Policies on the project.
  PERFORM public.assert_may_edit_policies(p_project_id, _actor_user_id);
  DELETE FROM public.policy_overrides
   WHERE project_id = p_project_id
     AND scope       = p_scope
     AND target_key  = p_target_key
     AND family      = p_family;
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_policy_version(
  p_version_id   uuid,
  _actor_user_id uuid DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_runs  bigint;
  v_cards bigint;
BEGIN
  -- D309: bind caller assertions before the original operation.
  _actor_user_id := public.security_actor(_actor_user_id);

  IF _actor_user_id IS NOT NULL THEN
    PERFORM set_config('app.current_user_id', _actor_user_id::text, true);
  END IF;
  -- D275 · a named actor must hold Edit Policies on the project.
  PERFORM public.assert_may_edit_policies((SELECT project_id FROM public.policy_versions WHERE id = p_version_id), _actor_user_id);

  SELECT count(*) INTO v_runs  FROM public.simulation_runs  WHERE policy_version_id = p_version_id;
  SELECT count(*) INTO v_cards FROM public.model_validations WHERE policy_version_id = p_version_id;

  IF v_runs > 0 OR v_cards > 0 THEN
    RAISE EXCEPTION
      'Cannot delete: this version is bound to % simulation run(s) and % validated model card(s). Versions referenced by runs or model cards are kept for provenance.',
      v_runs, v_cards
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  DELETE FROM public.policy_versions WHERE id = p_version_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_project_dataset(
  p_project_id uuid,
  p_dataset text,
  p_user_id uuid,
  p_user_email text
) RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_org text;
  v_org_id uuid;
  v_bom_level text;
  v_modeler uuid;
  v_role text;
  deleted_count integer := 0;
  temp_count integer;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_inputs');

  -- Ensure this function has the correct caller context
  PERFORM public.set_current_user_context(p_user_id, p_user_email);

  SELECT organization, organization_id, bom_level, modeler_id
  INTO v_org, v_org_id, v_bom_level, v_modeler
  FROM public.projects
  WHERE id = p_project_id;

  IF v_org IS NULL THEN
    RAISE EXCEPTION 'project_not_found';
  END IF;

  -- Authorization: same org AND (project owner or admin, or an admin of the organization — D304)
  SELECT user_role INTO v_role FROM public.get_current_approved_user() LIMIT 1;
  IF NOT public.org_is_current_user_org(v_org_id, v_org)
     OR NOT (v_modeler = public.get_current_user_id() OR v_role IN ('admin', 'super_admin')
             OR public.project_org_admin(public.get_current_user_id(), p_project_id)) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  IF lower(p_dataset) = 'inbound' THEN
    DELETE FROM public.inbound_logistics WHERE project_id = p_project_id;
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
  ELSIF lower(p_dataset) = 'outbound' THEN
    DELETE FROM public.outbound_logistics WHERE project_id = p_project_id;
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
  ELSIF lower(p_dataset) = 'demand_forecasts' THEN
    -- PLAN.md §24 WP 14.2 — the per-row forecast buckets.
    DELETE FROM public.demand_forecasts WHERE project_id = p_project_id;
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
  ELSIF lower(p_dataset) IN ('multitier','multi_tier') THEN
    DELETE FROM public.multi_tier_supply_chain WHERE project_id = p_project_id;
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
  ELSIF lower(p_dataset) = 'bom' THEN
    IF v_bom_level = 'single' THEN
      DELETE FROM public.bom_single_level WHERE project_id = p_project_id;
      GET DIAGNOSTICS deleted_count = ROW_COUNT;
    ELSE
      DELETE FROM public.bom_multi_level WHERE project_id = p_project_id;
      GET DIAGNOSTICS deleted_count = ROW_COUNT;
    END IF;
  ELSIF lower(p_dataset) IN ('network_nodes','deep_nodes') THEN
    DELETE FROM public.network_nodes WHERE project_id = p_project_id;
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
  ELSIF lower(p_dataset) IN ('network_edges','deep_edges') THEN
    DELETE FROM public.network_edges WHERE project_id = p_project_id;
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
  ELSIF lower(p_dataset) IN ('network_summary','deep_summary') THEN
    DELETE FROM public.network_summary WHERE project_id = p_project_id;
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
  ELSIF lower(p_dataset) = 'deep_tier' THEN
    DELETE FROM public.network_edges WHERE project_id = p_project_id;
    GET DIAGNOSTICS temp_count = ROW_COUNT;
    deleted_count := temp_count;

    DELETE FROM public.network_nodes WHERE project_id = p_project_id;
    GET DIAGNOSTICS temp_count = ROW_COUNT;
    deleted_count := deleted_count + temp_count;

    DELETE FROM public.network_summary WHERE project_id = p_project_id;
    GET DIAGNOSTICS temp_count = ROW_COUNT;
    deleted_count := deleted_count + temp_count;
  ELSIF lower(p_dataset) = 'node_list_uploads' THEN
    UPDATE public.node_list
       SET description_text = NULL,
           location_text    = NULL,
           latitude         = NULL,
           longitude        = NULL,
           updated_at       = now()
     WHERE project_id = p_project_id
       AND (description_text IS NOT NULL OR location_text IS NOT NULL
            OR latitude IS NOT NULL OR longitude IS NOT NULL);
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
  ELSIF lower(p_dataset) = 'all' THEN
    DELETE FROM public.inbound_logistics WHERE project_id = p_project_id;
    GET DIAGNOSTICS temp_count = ROW_COUNT;
    deleted_count := temp_count;

    DELETE FROM public.outbound_logistics WHERE project_id = p_project_id;
    GET DIAGNOSTICS temp_count = ROW_COUNT;
    deleted_count := deleted_count + temp_count;

    DELETE FROM public.multi_tier_supply_chain WHERE project_id = p_project_id;
    GET DIAGNOSTICS temp_count = ROW_COUNT;
    deleted_count := deleted_count + temp_count;

    DELETE FROM public.demand_forecasts WHERE project_id = p_project_id;
    GET DIAGNOSTICS temp_count = ROW_COUNT;
    deleted_count := deleted_count + temp_count;

    IF v_bom_level = 'single' THEN
      DELETE FROM public.bom_single_level WHERE project_id = p_project_id;
      GET DIAGNOSTICS temp_count = ROW_COUNT;
      deleted_count := deleted_count + temp_count;
    ELSE
      DELETE FROM public.bom_multi_level WHERE project_id = p_project_id;
      GET DIAGNOSTICS temp_count = ROW_COUNT;
      deleted_count := deleted_count + temp_count;
    END IF;
  ELSE
    RAISE EXCEPTION 'invalid_dataset';
  END IF;

  RETURN deleted_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_project(
  p_project_id uuid,
  p_user_id    uuid,
  p_user_email text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_exists  boolean;
  v_org_id  uuid;
  v_modeler uuid;
  v_role    text;
  v_user_org uuid;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_inputs');

  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'delete_project: this delete must name its actor'
      USING ERRCODE = 'null_value_not_allowed';
  END IF;

  SELECT true, p.organization_id, p.modeler_id
    INTO v_exists, v_org_id, v_modeler
    FROM public.projects p
   WHERE p.id = p_project_id;
  IF NOT COALESCE(v_exists, false) THEN
    RAISE EXCEPTION 'delete_project: project % not found', p_project_id
      USING ERRCODE = 'no_data_found';
  END IF;

  SELECT au.role::text, au.organization_id INTO v_role, v_user_org
    FROM public.approved_users au WHERE au.id = p_user_id;
  IF v_role IS NULL THEN
    RAISE EXCEPTION 'delete_project: % is not an approved user', p_user_id
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF NOT (
       v_modeler = p_user_id
    OR (v_role IN ('admin', 'super_admin') AND v_org_id IS NOT DISTINCT FROM v_user_org AND v_org_id IS NOT NULL)
    OR public.project_org_admin(p_user_id, p_project_id)   -- D304
  ) THEN
    RAISE EXCEPTION 'delete_project: % may not delete project % (only its creator, an app admin or an admin of its organization, working in it, may)',
      p_user_id, p_project_id
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- The actor, LOCAL to this transaction, so every trigger below names them.
  PERFORM public.set_current_user_context(p_user_id, COALESCE(p_user_email, ''));

  PERFORM public._delete_project_rows(p_project_id, p_user_id, p_user_email);
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_simulation_result(
  p_simulation_id uuid,
  p_user_id uuid,
  p_user_email text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_org text;
  v_org_id uuid;
  v_modeler uuid;
  v_role text;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);

  -- Set user context for RLS policies
  PERFORM public.set_current_user_context(p_user_id, p_user_email);

  -- Validate simulation exists and get project info for authorization
  SELECT p.organization, p.organization_id, p.modeler_id INTO v_org, v_org_id, v_modeler
  FROM public.simulation_results sr
  JOIN public.projects p ON p.id = sr.project_id
  WHERE sr.id = p_simulation_id;

  IF v_org IS NULL THEN
    RAISE EXCEPTION 'simulation_not_found';
  END IF;

  -- Authorization: same org AND (project owner or admin)
  SELECT user_role INTO v_role FROM public.get_current_approved_user() LIMIT 1;
  IF NOT public.org_is_current_user_org(v_org_id, v_org) OR NOT (v_modeler = public.get_current_user_id() OR v_role IN ('admin', 'super_admin')) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  -- Delete the simulation result
  DELETE FROM public.simulation_results WHERE id = p_simulation_id;
  
  IF NOT FOUND THEN
    RAISE EXCEPTION 'simulation_not_found';
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.delete_simulation_results_batch(
  p_simulation_ids uuid[],
  p_user_id uuid,
  p_user_email text
) RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_org text;
  v_org_id uuid;
  v_modeler uuid;
  v_role text;
  deleted_count integer := 0;
  sim_id uuid;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);

  -- Set user context for RLS policies
  PERFORM public.set_current_user_context(p_user_id, p_user_email);

  -- Get user role once
  SELECT user_role INTO v_role FROM public.get_current_approved_user() LIMIT 1;
  
  -- Delete each simulation with proper authorization check
  FOREACH sim_id IN ARRAY p_simulation_ids LOOP
    -- Check authorization for this specific simulation
    SELECT p.organization, p.organization_id, p.modeler_id INTO v_org, v_org_id, v_modeler
    FROM public.simulation_results sr
    JOIN public.projects p ON p.id = sr.project_id
    WHERE sr.id = sim_id;

    -- Skip if simulation not found or not authorized
    IF v_org IS NULL OR 
       NOT public.org_is_current_user_org(v_org_id, v_org) OR 
       NOT (v_modeler = public.get_current_user_id() OR v_role IN ('admin', 'super_admin')) THEN
      CONTINUE;
    END IF;

    -- Delete the simulation result
    DELETE FROM public.simulation_results WHERE id = sim_id;
    IF FOUND THEN
      deleted_count := deleted_count + 1;
    END IF;
  END LOOP;

  RETURN deleted_count;
END;
$function$;

CREATE OR REPLACE FUNCTION public.delete_user_file(
  p_file_id uuid,
  p_user_id uuid
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_row public.user_files;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);

  SELECT * INTO v_row FROM public.user_files
   WHERE id = p_file_id AND user_id = p_user_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'file % not found', p_file_id; END IF;
  PERFORM public._delete_workspace_objects(ARRAY[v_row.path]);
  DELETE FROM public.user_files WHERE id = p_file_id;
END; $$;

CREATE OR REPLACE FUNCTION public.docs_list_faq(p_user_id uuid DEFAULT NULL)
RETURNS TABLE (
  id uuid, question text, answer text, section_key text,
  related_slugs text[], sort_order integer, updated_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rank integer := public.docs_audience_rank(public.docs_reader_level(p_user_id));
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);

  IF public.docs_audience_rank(public.docs_section_audience('questions')) > v_rank THEN
    RETURN;
  END IF;
  RETURN QUERY
    SELECT f.id, f.question, f.answer, f.section_key, f.related_slugs, f.sort_order, f.updated_at
      FROM public.docs_faq f
     WHERE f.is_published
       AND (f.section_key IS NULL
            OR public.docs_audience_rank(public.docs_section_audience(f.section_key)) <= v_rank)
     ORDER BY f.sort_order, f.question;
END; $$;

CREATE OR REPLACE FUNCTION public.docs_reader_level(p_user_id uuid)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_role text;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);

  IF p_user_id IS NULL THEN RETURN 'public'; END IF;
  SELECT role::text INTO v_role FROM public.approved_users
   WHERE id = p_user_id AND is_active;
  IF v_role IS NULL THEN RETURN 'public'; END IF;
  IF v_role = 'super_admin' THEN RETURN 'confidential'; END IF;
  IF COALESCE((public.capabilities_for_user(p_user_id) -> 'features' ->> 'docs_confidential')::boolean, false) THEN
    RETURN 'confidential';
  END IF;
  RETURN 'internal';
END; $$;

CREATE OR REPLACE FUNCTION public.ensure_item_masters(p_project_id uuid,
  _actor_user_id uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  -- D309: bind caller assertions before the original operation.
  _actor_user_id := public.security_actor(_actor_user_id);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_inputs');


  -- D71, closed for this path (WP 6.2 slice 12). LOCAL to this transaction and
  -- set BEFORE any tier write, so `audit_tier_write`'s `get_current_user_id()`
  -- resolves and the audit rows below name the caller rather than recording
  -- `actor_known: false`. Guarded: `_actor_user_id` is DEFAULT NULL so every
  -- existing caller keeps working unchanged, and an unguarded set_config would
  -- BLANK an actor the caller's transaction had already established.
  IF _actor_user_id IS NOT NULL THEN
    PERFORM set_config('app.current_user_id', _actor_user_id::text, true);
  END IF;
  INSERT INTO public.suppliers (project_id, supplier_id)
  SELECT DISTINCT p_project_id, il.supplier_id
  FROM public.inbound_logistics il
  WHERE il.project_id = p_project_id AND il.supplier_id IS NOT NULL
  ON CONFLICT (project_id, supplier_id) DO NOTHING;

  INSERT INTO public.materials (project_id, material_id)
  SELECT DISTINCT p_project_id, m FROM (
    SELECT material_id AS m FROM public.inbound_logistics WHERE project_id = p_project_id
    UNION
    SELECT material_id     FROM public.bom_single_level   WHERE project_id = p_project_id
  ) q WHERE m IS NOT NULL
  ON CONFLICT (project_id, material_id) DO NOTHING;

  INSERT INTO public.products (project_id, product_id)
  SELECT DISTINCT p_project_id, p FROM (
    SELECT product_id AS p FROM public.bom_single_level  WHERE project_id = p_project_id
    UNION
    SELECT product_id      FROM public.outbound_logistics WHERE project_id = p_project_id
  ) q WHERE p IS NOT NULL
  ON CONFLICT (project_id, product_id) DO NOTHING;
END;
$$;

CREATE OR REPLACE FUNCTION public.etl_replace_supply_chain(
  _project_id uuid,
  _actor_user_id uuid,
  _rows jsonb,
  _multi_tier_rows jsonb DEFAULT '[]'::jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE v_deleted int; v_ins int; v_mt_del int; v_mt_ins int;
BEGIN
  -- D309: bind caller assertions before the original operation.
  _actor_user_id := public.security_actor(_actor_user_id);
  PERFORM public.security_assert_project(_project_id, 'data_edit_inputs');

  PERFORM public.assert_writer_may_act('etl_replace_supply_chain', _project_id, _actor_user_id);

  IF jsonb_typeof(_rows) <> 'array' OR jsonb_typeof(_multi_tier_rows) <> 'array' THEN
    RAISE EXCEPTION 'etl_replace_supply_chain: both row payloads must be json arrays'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  DELETE FROM public.supply_chain_data WHERE project_id = _project_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  DELETE FROM public.supply_chain_data_multi_tier WHERE project_id = _project_id;
  GET DIAGNOSTICS v_mt_del = ROW_COUNT;

  INSERT INTO public.supply_chain_data (
    project_id, plant_name, data_source,
    from_location, to_location, weighted, material_consumption_rate, sourcing_ratio,
    uploaded_by, organization)
  SELECT _project_id, r.plant_name, r.data_source,
         r.from_location, r.to_location, r.weighted, r.material_consumption_rate,
         r.sourcing_ratio, r.uploaded_by, r.organization
    FROM jsonb_populate_recordset(null::public.supply_chain_data, _rows) AS r;
  GET DIAGNOSTICS v_ins = ROW_COUNT;

  INSERT INTO public.supply_chain_data_multi_tier (
    project_id, plant_name, data_source, from_location, to_location,
    material_consumption_rate, sourcing_ratio, weighted, level, bom_depth, path_root,
    uploaded_by, organization)
  SELECT _project_id, r.plant_name, r.data_source, r.from_location, r.to_location,
         r.material_consumption_rate, r.sourcing_ratio, r.weighted, r.level,
         r.bom_depth, r.path_root, r.uploaded_by, r.organization
    FROM jsonb_populate_recordset(null::public.supply_chain_data_multi_tier, _multi_tier_rows) AS r;
  GET DIAGNOSTICS v_mt_ins = ROW_COUNT;

  RETURN jsonb_build_object(
    'deleted', v_deleted, 'inserted', v_ins,
    'multi_tier_deleted', v_mt_del, 'multi_tier_inserted', v_mt_ins);
END; $fn$;

CREATE OR REPLACE FUNCTION public.get_baseline_simulation_results(p_project_id uuid, p_user_id uuid, p_user_email text)
 RETURNS TABLE(id uuid, project_id uuid, plant_name text, status text, scenario_ids uuid[], started_at timestamp with time zone, completed_at timestamp with time zone, metrics jsonb, result_data jsonb, created_at timestamp with time zone, updated_at timestamp with time zone, created_by uuid, organization text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, NULL);

  -- Return baseline simulation results (no scenarios) for the given project only
  RETURN QUERY
  SELECT
    sr.id,
    sr.project_id,
    sr.plant_name,
    sr.status,
    sr.scenario_ids,
    sr.started_at,
    sr.completed_at,
    sr.metrics,
    sr.result_data,
    sr.created_at,
    sr.updated_at,
    sr.created_by,
    sr.organization
  FROM public.simulation_results sr
  WHERE sr.project_id = p_project_id
    AND (sr.scenario_ids IS NULL OR array_length(sr.scenario_ids, 1) = 0)
  ORDER BY sr.created_at DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_critical_node_stats(
  p_project_id uuid,
  p_user_id    uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_run     public.analysis_runs;
  v_run_id  uuid;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, NULL);

  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'get_critical_node_stats: this read must name its reader'
      USING ERRCODE = 'null_value_not_allowed';
  END IF;
  -- LOCAL, so it cannot outlive this transaction on a pooled connection, and so
  -- `has_project_access` answers for the named reader (the D169 shape).
  PERFORM set_config('app.current_user_id', p_user_id::text, true);
  IF NOT public.has_project_access(p_project_id) THEN
    RAISE EXCEPTION 'get_critical_node_stats: % cannot read project %', p_user_id, p_project_id
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- A run on the CURRENT lane graph first; the newest run otherwise, and then it
  -- says it is stale (§4 D238's rule, the same one the network-metrics read uses).
  -- Only runs that scored NODES qualify: a run from before D307 scored lane rows,
  -- and during the deploy window the published function can still write one, which
  -- must not mask a node-level answer by being newer.
  SELECT r.id INTO v_run_id
    FROM public.analysis_runs r
   WHERE r.project_id = p_project_id AND r.analysis_kind = 'critical_nodes'
     AND r.status = 'succeeded'
     AND EXISTS (SELECT 1 FROM public.analysis_results ar
                  WHERE ar.run_id = r.id AND ar.entity_type = 'node')
   ORDER BY public.analysis_run_is_current(r.id) DESC NULLS LAST, r.started_at DESC, r.id
   LIMIT 1;
  IF v_run_id IS NULL THEN
    RETURN jsonb_build_object('run_id', NULL);
  END IF;
  SELECT * INTO v_run FROM public.analysis_runs WHERE id = v_run_id;

  RETURN jsonb_build_object(
    'run_id',       v_run.id,
    'finished_at',  v_run.finished_at,
    'is_current',   public.analysis_run_is_current(v_run.id),
    'method',       v_run.params ->> 'method',
    'threshold',    (v_run.params ->> 'threshold')::numeric,
    'demand_basis', v_run.row_counts ->> 'demand_basis',
    'warnings',     COALESCE(v_run.warnings, '[]'::jsonb),
    'total',        (SELECT COUNT(*) FROM public.analysis_results ar
                      WHERE ar.run_id = v_run.id AND ar.entity_type = 'node'),
    'nexus',        (SELECT COUNT(*) FROM public.analysis_results ar
                      WHERE ar.run_id = v_run.id AND ar.entity_type = 'node'
                        AND (ar.metrics ->> 'is_critical')::boolean),
    -- The ten highest, with what made them so — the role is READ from
    -- `node_list.echelon` (§4 D127), never inferred here.
    'top', COALESCE((
      SELECT jsonb_agg(t.j ORDER BY t.rank)
        FROM (
          SELECT (ar.metrics ->> 'rank')::int AS rank,
                 jsonb_build_object(
                   'node_id',           ar.entity_id,
                   'echelon',           nl.echelon,
                   'score',             (ar.metrics ->> 'score')::numeric,
                   'is_critical',       (ar.metrics ->> 'is_critical')::boolean,
                   'rank',              (ar.metrics ->> 'rank')::int,
                   'products_affected', (ar.metrics ->> 'products_affected')::int,
                   'sole_source_of',    COALESCE(ar.metrics -> 'sole_source_of', '[]'::jsonb)) AS j
            FROM public.analysis_results ar
            LEFT JOIN public.node_list nl
              ON nl.project_id = v_run.project_id AND nl.node_id = ar.entity_id
           WHERE ar.run_id = v_run.id AND ar.entity_type = 'node'
             AND ar.metrics ->> 'rank' IS NOT NULL
           ORDER BY (ar.metrics ->> 'rank')::int
           LIMIT 10) t), '[]'::jsonb)
  );
END; $fn$;

CREATE OR REPLACE FUNCTION public.get_deep_tier_datasets(p_project_id uuid, p_user_id uuid, p_user_email text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_org text;
  v_org_id uuid;
  v_deep boolean;
  nodes jsonb := '[]'::jsonb;
  edges jsonb := '[]'::jsonb;
  summary jsonb := '[]'::jsonb;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, NULL);

  -- Set user context for RLS policies
  PERFORM public.set_current_user_context(p_user_id, p_user_email);

  -- Validate project and org access
  SELECT organization, organization_id, deep_tier_enabled INTO v_org, v_org_id, v_deep
  FROM public.projects WHERE id = p_project_id;

  IF v_org IS NULL THEN RAISE EXCEPTION 'project_not_found'; END IF;
  IF NOT public.org_is_current_user_org(v_org_id, v_org) THEN RAISE EXCEPTION 'forbidden'; END IF;

  IF COALESCE(v_deep, false) = false THEN
    RETURN jsonb_build_object('nodes', nodes, 'edges', edges, 'summary', summary);
  END IF;

  -- Aggregate datasets
  SELECT COALESCE(jsonb_agg(to_jsonb(n.*)), '[]'::jsonb) INTO nodes
  FROM public.network_nodes n WHERE n.project_id = p_project_id;

  SELECT COALESCE(jsonb_agg(to_jsonb(e.*)), '[]'::jsonb) INTO edges
  FROM public.network_edges e WHERE e.project_id = p_project_id;

  SELECT COALESCE(jsonb_agg(to_jsonb(s.*)), '[]'::jsonb) INTO summary
  FROM public.network_summary s WHERE s.project_id = p_project_id;

  RETURN jsonb_build_object('nodes', nodes, 'edges', edges, 'summary', summary);
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_disruption_scenarios(p_project_id uuid, p_plant_name text, p_user_id uuid, p_user_email text)
 RETURNS TABLE(id uuid, scenario_name text, description text, status disruption_status, created_at timestamp with time zone, disruption_start date, disruption_end date, targets jsonb, effects jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, NULL);

  -- Set user context for RLS policies
  PERFORM public.set_current_user_context(p_user_id, p_user_email);
  
  -- Return scenario profiles with their targets, effects, and disruption dates
  RETURN QUERY
  SELECT 
    dsp.id,
    dsp.scenario_name,
    dsp.description,
    dsp.status,
    dsp.created_at,
    dsp.disruption_start,
    dsp.disruption_end,
    COALESCE(
      (SELECT jsonb_agg(
        jsonb_build_object(
          'target_type', dst.target_type,
          'node_ids', dst.node_ids,
          'edge_list', dst.edge_list
        )
      )
      FROM disruption_scenario_targets dst 
      WHERE dst.profile_id = dsp.id),
      '[]'::jsonb
    ) as targets,
    COALESCE(
      (SELECT jsonb_agg(
        jsonb_build_object(
          'effect_type', dse.effect_type,
          'magnitude', dse.magnitude,
          'unit', dse.unit
        )
      )
      FROM disruption_scenario_effects dse 
      WHERE dse.profile_id = dsp.id),
      '[]'::jsonb
    ) as effects
  FROM disruption_scenario_profiles dsp
  WHERE dsp.project_id = p_project_id
    AND (p_plant_name IS NULL OR dsp.plant_name = p_plant_name)
  ORDER BY dsp.created_at DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_graph_nodes(
  p_project_id uuid,
  p_user_id    uuid,
  p_user_email text
)
RETURNS TABLE(
  node_id     text,
  echelon     text,
  node_type   text,
  bom_depth   integer,
  supply_tier integer,
  plant_name  text,
  label       text,
  location_text text,
  longitude   numeric,
  latitude    numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, NULL);

  -- The same context call every reader in this schema makes, so RLS answers for the
  -- named user. This function READS and writes nothing, so there is no audit row to
  -- name an actor in — `audit-actor` (G4) is about writes.
  PERFORM public.set_current_user_context(p_user_id, p_user_email);

  RETURN QUERY
  SELECT
    nl.node_id,
    nl.echelon,
    nl.node_type,
    nl.bom_depth,
    nl.supply_tier,
    nl.plant_name,
    -- `label` is the id today, because `node_list` carries no display name. It is a
    -- SEPARATE column rather than the page falling back to the id, so the day a
    -- name lands there is one place to change and no page has to know.
    nl.node_id AS label,
    nl.location_text,
    nl.longitude,
    nl.latitude
  FROM public.node_list nl
  WHERE nl.project_id = p_project_id
  -- Ordered by the ECHELON as the chain runs, then by depth, then by id — so a page
  -- that renders in receive order renders the chain in order, and the ordering rule
  -- lives here rather than being re-derived in four components. `unknown` and NULL
  -- sort LAST and together: both mean the data does not place this node, and putting
  -- them anywhere else in the sequence would imply a position (T1).
  ORDER BY CASE COALESCE(nl.echelon, 'unknown')
             WHEN 'supplier'    THEN 0
             WHEN 'material'    THEN 1
             WHEN 'subassembly' THEN 2
             WHEN 'plant'       THEN 3
             WHEN 'product'     THEN 4
             WHEN 'customer'    THEN 5
             ELSE 6
           END,
           nl.bom_depth NULLS FIRST,
           nl.node_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_individual_scenario_results(p_project_id uuid, p_user_id uuid, p_user_email text)
RETURNS TABLE(
  simulation_id uuid,
  scenario_id uuid,
  scenario_name text,
  scenario_description text,
  scenario_effects jsonb,
  status text,
  started_at timestamp with time zone,
  completed_at timestamp with time zone,
  metrics jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, NULL);

  -- Return individual scenario results for the given project only
  RETURN QUERY
  SELECT 
    sr.id as simulation_id,
    sp.id as scenario_id,
    sp.scenario_name,
    sp.description as scenario_description,
    COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'effect_type', se.effect_type,
          'magnitude', se.magnitude,
          'unit', se.unit
        )
      ) FILTER (WHERE se.id IS NOT NULL),
      '[]'::jsonb
    ) as scenario_effects,
    sr.status,
    sr.started_at,
    sr.completed_at,
    sr.metrics
  FROM public.simulation_results sr
  CROSS JOIN LATERAL unnest(sr.scenario_ids) AS scenario_id_unnest(scenario_id)
  JOIN public.disruption_scenario_profiles sp ON sp.id = scenario_id_unnest.scenario_id
  LEFT JOIN public.disruption_scenario_effects se ON se.profile_id = sp.id
  WHERE sr.project_id = p_project_id
  GROUP BY sr.id, sp.id, sp.scenario_name, sp.description, sr.status, sr.started_at, sr.completed_at, sr.metrics
  ORDER BY sr.started_at DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_integrated_process_network_data(
  p_project_id uuid,
  p_user_id uuid,
  p_user_email text
)
RETURNS TABLE(
  project_id uuid,
  plant_name text,
  node_id text,
  node_name text,
  node_type text,
  level integer,
  from_location text,
  to_location text,
  material_consumption_rate numeric,
  weighted numeric,
  data_source text,
  connection_type text,
  is_connected boolean,
  mapping_confidence numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, NULL);

  -- Ensure RLS helper functions use caller context
  PERFORM public.set_current_user_context(p_user_id, p_user_email);

  -- Return node records (connection_type = 'node') followed by edge records
  RETURN QUERY
  WITH scd AS (
    SELECT *
    FROM public.supply_chain_data_multi_tier s
    WHERE s.project_id = p_project_id
  ),
  locs AS (
    SELECT s.from_location AS loc, MIN(s.plant_name) AS plant_name
    FROM scd s
    GROUP BY s.from_location
    UNION
    SELECT s.to_location AS loc, MIN(s.plant_name) AS plant_name
    FROM scd s
    GROUP BY s.to_location
  ),
  node_features AS (
    SELECT 
      l.loc,
      l.plant_name,
      BOOL_OR(s.level = -1 AND s.to_location = l.loc) AS is_customer,
      BOOL_OR(s.level = 0 AND (s.from_location = l.loc OR s.to_location = l.loc)) AS is_product,
      BOOL_OR(s.level = 5 AND s.from_location = l.loc) AS is_supplier_from,
      BOOL_OR(s.level BETWEEN 1 AND 4 AND (s.from_location = l.loc OR s.to_location = l.loc)) AS is_material,
      CASE 
        WHEN COUNT(*) FILTER (WHERE s.level BETWEEN 1 AND 4 AND (s.from_location = l.loc OR s.to_location = l.loc)) > 0
        THEN ROUND(AVG(s.level) FILTER (WHERE s.level BETWEEN 1 AND 4 AND (s.from_location = l.loc OR s.to_location = l.loc)))::int
        ELSE NULL
      END AS material_level
    FROM scd s
    JOIN locs l ON s.from_location = l.loc OR s.to_location = l.loc
    GROUP BY l.loc, l.plant_name
  ),
  nodes AS (
    SELECT 
      l.loc AS node_id,
      l.loc AS node_name,
      CASE 
        WHEN nf.is_customer THEN 'customer'
        WHEN nf.is_product THEN 'product'
        WHEN nf.is_supplier_from THEN 'supplier'
        WHEN nf.is_material THEN 'material'
        ELSE 'material'
      END AS node_type,
      CASE 
        WHEN nf.is_customer THEN -1
        WHEN nf.is_product THEN 0
        WHEN nf.is_supplier_from THEN 6
        WHEN nf.is_material AND nf.material_level IS NOT NULL THEN nf.material_level
        WHEN nf.is_material THEN 1
        ELSE 1
      END AS level,
      l.plant_name
    FROM locs l
    JOIN node_features nf ON nf.loc = l.loc
  )
  -- Node records
  SELECT 
    p_project_id,
    n.plant_name,
    n.node_id,
    n.node_name,
    n.node_type,
    n.level,
    NULL::text,
    NULL::text,
    NULL::numeric,
    NULL::numeric,
    'derived'::text,
    'node'::text,
    TRUE,
    1.0::numeric
  FROM nodes n

  UNION ALL

  -- Edge records  
  SELECT 
    s.project_id,
    s.plant_name,
    s.from_location,
    s.from_location,
    CASE 
      WHEN s.level = -1 THEN 'customer'
      WHEN s.level = 0 THEN 'product'
      WHEN s.level BETWEEN 1 AND 4 THEN 'material'
      WHEN s.level = 5 THEN 'supplier'
      ELSE 'unknown'
    END,
    s.level,
    s.from_location,
    s.to_location,
    s.material_consumption_rate,
    s.weighted,
    s.data_source,
    CASE 
      WHEN s.level = -1 THEN 'customer_connection'
      WHEN lower(s.data_source) = 'inbound' THEN 'inbound'
      WHEN lower(s.data_source) = 'bom' THEN 'bom'
      WHEN lower(s.data_source) = 'outbound' THEN 'outbound'
      ELSE 'edge'
    END,
    TRUE,
    1.0::numeric
  FROM scd s
  ORDER BY level, node_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_multi_tier_network_data(
  p_project_id uuid,
  p_user_id uuid,
  p_user_email text
)
RETURNS TABLE(
  id uuid,
  project_id uuid,
  plant_name text,
  from_location text,
  to_location text,
  level integer,
  bom_depth integer,
  material_consumption_rate numeric,
  sourcing_ratio numeric,
  weighted numeric,
  data_source text,
  path_root text,
  uploaded_by uuid,
  organization text,
  created_at timestamp with time zone,
  updated_at timestamp with time zone
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  v_org text;
  v_org_id uuid;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, NULL);

  PERFORM public.set_current_user_context(p_user_id, p_user_email);

  -- QUALIFIED, and this is D149's SECOND fatal error rather than a tidy-up. The
  -- `RETURNS TABLE` declares an OUT parameter named `organization`, so the
  -- unqualified `SELECT organization … FROM public.projects` that stood here
  -- raised `column reference "organization" is ambiguous` — BEFORE the missing
  -- column could even be reached. Two independent run-time failures in one
  -- fourteen-line body, which is what "this function has never executed once"
  -- looks like from the inside.
  SELECT p.organization, p.organization_id INTO v_org, v_org_id
  FROM public.projects p WHERE p.id = p_project_id;

  IF v_org IS NULL THEN
    RAISE EXCEPTION 'project_not_found';
  END IF;

  IF NOT public.org_is_current_user_org(v_org_id, v_org) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  RETURN QUERY
  SELECT
    smt.id, smt.project_id, smt.plant_name, smt.from_location, smt.to_location,
    -- D149 — `smt.data_source_group` stood here, and
    -- `supply_chain_data_multi_tier` has never had that column. This function
    -- raised `column smt.data_source_group does not exist` on EVERY call, and it
    -- is `InteractiveNetworkSpace`'s fallback: the path a user reaches only after
    -- the primary read has already failed. See the `SELECT … INTO` above for the
    -- second, independent raise in the same body.
    smt.level, smt.bom_depth,
    smt.material_consumption_rate, smt.sourcing_ratio, smt.weighted,
    smt.data_source, smt.path_root, smt.uploaded_by, smt.organization,
    smt.created_at, smt.updated_at
  FROM public.supply_chain_data_multi_tier smt
  WHERE smt.project_id = p_project_id
  ORDER BY smt.bom_depth ASC NULLS LAST, smt.from_location ASC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_my_organization_access(p_user_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid     uuid := public.account_self_resolve(p_user_id);
  v_me      public.approved_users%ROWTYPE;
  v_org     public.organizations%ROWTYPE;
  v_members jsonb;
  v_projects jsonb;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);

  SELECT * INTO v_me FROM public.approved_users WHERE id = v_uid;
  IF NOT COALESCE(v_me.is_active, true) THEN
    RAISE EXCEPTION 'account_inactive' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_org FROM public.organizations WHERE id = v_me.organization_id;
  IF v_org.id IS NULL THEN
    RETURN jsonb_build_object('organization', NULL, 'members', '[]'::jsonb, 'projects', '[]'::jsonb);
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'user_id',        u.id,
           'name',           u.name,
           'email',          u.email,
           'role',           u.role::text,
           'is_super_admin', u.role = 'super_admin'::public.app_role,
           'account_active', COALESCE(u.is_active, true),
           'org_role',       m.org_role,
           'joined_at',      m.joined_at,
           'is_you',         u.id = v_uid,
           -- Working in this organization now (D210's active organization).
           'working_here',   u.organization_id = v_org.id,
           'default_org_id',   dm.org_id,
           'default_org_name', dmo.name)
         ORDER BY CASE m.org_role WHEN 'owner' THEN 0 WHEN 'admin' THEN 1 ELSE 2 END,
                  lower(COALESCE(u.name, u.email, '')), u.id), '[]'::jsonb)
    INTO v_members
    FROM public.organization_members m
    JOIN public.approved_users u ON u.id = m.user_id
    LEFT JOIN public.organization_members dm ON dm.user_id = u.id AND dm.is_default
    LEFT JOIN public.organizations dmo ON dmo.id = dm.org_id
   WHERE m.org_id = v_org.id;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'project_id',  p.id,
           'name',        p.name,
           'owner_id',    p.modeler_id,
           'owner_name',  COALESCE(ow.name, ow.email),
           'my_role',     public.effective_project_role(v_uid, p.id),
           -- The owner, unexpired members and live delegates, each counted once.
           'role_holders', (SELECT count(*) FROM (
               SELECT p.modeler_id AS u WHERE p.modeler_id IS NOT NULL
               UNION
               SELECT pm.user_id FROM public.project_members pm
                WHERE pm.project_id = p.id AND (pm.expires_at IS NULL OR pm.expires_at > now())
               UNION
               SELECT dg.grantee_user_id FROM public.delegation_grants dg
                WHERE dg.project_id = p.id AND dg.revoked_at IS NULL AND dg.expires_at > now()) r))
         ORDER BY lower(COALESCE(p.name, '')), p.id), '[]'::jsonb)
    INTO v_projects
    FROM public.projects p
    LEFT JOIN public.approved_users ow ON ow.id = p.modeler_id
   WHERE p.organization_id = v_org.id;

  RETURN jsonb_build_object(
    'organization', jsonb_build_object(
      'id',         v_org.id,
      'name',       v_org.name,
      'my_org_role', (SELECT m.org_role FROM public.organization_members m
                       WHERE m.org_id = v_org.id AND m.user_id = v_uid),
      'is_my_default', EXISTS (SELECT 1 FROM public.organization_members m
                                WHERE m.org_id = v_org.id AND m.user_id = v_uid AND m.is_default)),
    'members',  v_members,
    'projects', v_projects);
END; $$;

CREATE OR REPLACE FUNCTION public.get_my_profile(p_user_id uuid DEFAULT NULL)
RETURNS TABLE(
  id uuid,
  email text,
  name text,
  first_name text,
  last_name text,
  display_name text,
  phone text,
  avatar_color text,
  role text,
  organization text,
  is_active boolean,
  force_password_change boolean,
  password_changed_at timestamptz,
  password_expires_at timestamptz,
  password_expired boolean,
  password_max_age_days integer,
  access_period text,
  access_valid_from timestamptz,
  access_valid_until timestamptz,
  access_expired boolean,
  access_exempt boolean,
  project_limit integer,
  projects_used bigint,
  user_limit integer,
  users_used bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := public.account_self_resolve(p_user_id);
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);

  RETURN QUERY
  SELECT au.id, au.email, au.name, au.first_name, au.last_name,
         au.display_name, au.phone, au.avatar_color,
         au.role::text, COALESCE(o.name, au.organization), au.is_active, au.force_password_change,
         au.password_changed_at, au.password_expires_at,
         (au.password_expires_at <= now()),
         extract(day FROM public.password_max_age())::integer,
         o.access_period, o.access_valid_from, o.access_valid_until,
         -- Expired FOR THIS ACCOUNT: the ACTIVE organization's period ended and the
         -- account is not a super admin (`20260929000004` header §3).
         COALESCE(o.access_valid_until <= now(), false) AND au.role <> 'super_admin'::public.app_role,
         au.role = 'super_admin'::public.app_role,
         o.project_limit,
         CASE WHEN o.id IS NULL THEN NULL
              ELSE (SELECT count(*) FROM public.projects p WHERE p.organization_id = o.id) END,
         o.user_limit,
         CASE WHEN o.id IS NULL THEN NULL
              ELSE (SELECT count(*) FROM public.organization_members m WHERE m.org_id = o.id) END
    FROM public.approved_users au
    LEFT JOIN public.organizations o ON o.id = au.organization_id
   WHERE au.id = v_uid;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_my_project_access(
  p_project_id uuid, p_user_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid     uuid := public.account_self_resolve(p_user_id);
  v_me      public.approved_users%ROWTYPE;
  v_org_id  uuid;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, NULL);

  SELECT * INTO v_me FROM public.approved_users WHERE id = v_uid;
  IF NOT COALESCE(v_me.is_active, true) THEN
    RAISE EXCEPTION 'account_inactive' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT p.organization_id INTO v_org_id FROM public.projects p WHERE p.id = p_project_id;
  -- An unknown project and one the reader may not see answer alike, so the read does not
  -- say which project ids exist in another tenant.
  IF NOT FOUND OR NOT (
       v_me.role = 'super_admin'::public.app_role
       OR (v_org_id IS NOT NULL AND v_org_id = v_me.organization_id)
       OR public.effective_project_role(v_uid, p_project_id) IS NOT NULL) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = 'insufficient_privilege';
  END IF;

  RETURN public.project_access_read(p_project_id);
END; $$;

CREATE OR REPLACE FUNCTION public.get_my_project_rights(
  p_project_id uuid, p_user_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid    uuid := public.account_self_resolve(p_user_id);
  v_me     public.approved_users%ROWTYPE;
  v_org_id uuid;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, NULL);

  SELECT * INTO v_me FROM public.approved_users WHERE id = v_uid;
  IF NOT COALESCE(v_me.is_active, true) THEN
    RAISE EXCEPTION 'account_inactive' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT p.organization_id INTO v_org_id FROM public.projects p WHERE p.id = p_project_id;
  -- `get_my_project_access`'s rule: an unknown project and one the reader may not see
  -- answer alike.
  IF NOT FOUND OR NOT (
       v_me.role = 'super_admin'::public.app_role
       OR (v_org_id IS NOT NULL AND v_org_id = v_me.organization_id)
       OR public.effective_project_role(v_uid, p_project_id) IS NOT NULL) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = 'insufficient_privilege';
  END IF;

  RETURN public.project_rights_for_user(v_uid, p_project_id)
      || jsonb_build_object(
           'project_id',     p_project_id,
           'effective_role', public.effective_project_role(v_uid, p_project_id),
           'is_modeler',     EXISTS (SELECT 1 FROM public.projects p
                                      WHERE p.id = p_project_id AND p.modeler_id = v_uid));
END; $$;

CREATE OR REPLACE FUNCTION public.get_network_metrics_for_materials(
  p_project_id uuid,
  p_user_id uuid,
  p_user_email text
) RETURNS TABLE(
  id                         uuid,
  uid                        text,
  name                       text,
  revenue                    numeric,
  degree_centrality          numeric,
  weighted_degree_centrality numeric,
  eigenvector_centrality     numeric,
  betweenness_centrality     numeric,
  closeness_centrality       numeric,
  prominence                 numeric,
  connection_count           bigint,
  metrics_source             text,
  run_id                     uuid,
  computed_from_hash         text,
  computed_at                timestamptz,
  hash_is_current            boolean
)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  v_run      uuid;
  v_hash     text;
  v_current  boolean;
  v_composite text;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, NULL);

  PERFORM public.set_current_user_context(p_user_id, p_user_email);

  -- §4 D238 — a run on the CURRENT level first; the newest run otherwise, said
  -- to be stale. It was "the newest", which let a newer run on an older graph win.
  v_run := COALESCE(public.analysis_current_run(p_project_id, 'network_metrics'),
                    public.analysis_latest_run(p_project_id, 'network_metrics'));
  SELECT r.input_hash INTO v_hash FROM public.analysis_runs r WHERE r.id = v_run;
  v_current := CASE WHEN v_run IS NULL THEN NULL ELSE public.analysis_run_is_current(v_run) END;
  v_composite := public.current_graph_hash(p_project_id);

  RETURN QUERY
  SELECT
    nn.id, nn.uid, nn.name, nn.revenue,
    COALESCE((ar.metrics ->> 'degree_centrality')::numeric,          nn.degree_centrality),
    COALESCE((ar.metrics ->> 'weighted_degree_centrality')::numeric, nn.weighted_degree_centrality),
    COALESCE((ar.metrics ->> 'eigenvector_centrality')::numeric,     nn.eigenvector_centrality),
    COALESCE((ar.metrics ->> 'betweenness_centrality')::numeric,     nn.betweenness_centrality),
    COALESCE((ar.metrics ->> 'closeness_centrality')::numeric,       nn.closeness_centrality),
    COALESCE((ar.metrics ->> 'prominence')::numeric,                 nn.prominence),
    (SELECT COUNT(*)::bigint FROM public.network_edges ne
      WHERE ne.project_id = p_project_id AND (ne.src_uid = nn.uid OR ne.dst_uid = nn.uid)),
    CASE
      WHEN ar.id IS NOT NULL THEN 'store'
      WHEN nn.degree_centrality IS NOT NULL OR nn.betweenness_centrality IS NOT NULL
        OR nn.eigenvector_centrality IS NOT NULL OR nn.closeness_centrality IS NOT NULL
        OR nn.weighted_degree_centrality IS NOT NULL OR nn.prominence IS NOT NULL THEN 'column'
      ELSE 'none'
    END,
    CASE WHEN ar.id IS NOT NULL THEN v_run ELSE NULL END,
    CASE WHEN ar.id IS NOT NULL THEN v_hash ELSE nn.computed_from_hash END,
    CASE WHEN ar.id IS NOT NULL THEN ar.created_at ELSE nn.computed_at END,
    CASE
      WHEN ar.id IS NOT NULL THEN v_current
      -- A legacy column carries the COMPOSITE it was computed against.
      WHEN nn.computed_from_hash IS NOT NULL AND v_composite IS NOT NULL
        THEN (nn.computed_from_hash = v_composite)
      ELSE NULL
    END
  FROM public.network_nodes nn
  LEFT JOIN public.analysis_results ar
         ON v_run IS NOT NULL AND ar.run_id = v_run
        AND ar.entity_type = 'node' AND ar.entity_id = nn.uid
  WHERE nn.project_id = p_project_id
    AND EXISTS (
      SELECT 1 FROM public.supply_chain_data scd
       WHERE scd.project_id = p_project_id
         AND scd.data_source = 'bom'
         AND (scd.from_location = nn.uid OR scd.to_location = nn.uid)
    )
  ORDER BY nn.prominence DESC NULLS LAST, nn.degree_centrality DESC NULLS LAST;
END; $fn$;

CREATE OR REPLACE FUNCTION public.get_network_nodes(
  p_project_id uuid,
  p_user_id uuid,
  p_user_email text,
  p_plant_name text DEFAULT NULL
)
RETURNS TABLE(
  id uuid, project_id uuid, plant_name text, uid text, name text, industry text,
  website text, traded_as text, number_of_employees integer, revenue numeric,
  depth integer, lat numeric, long numeric, is_seed boolean, uploaded_by uuid,
  created_by uuid, organization text, created_at timestamptz, updated_at timestamptz,
  country text,
  -- WP 10.1 · the stored prominence and its provenance (T1/T2).
  prominence numeric,
  metrics_source text,
  metrics_run_id uuid,
  metrics_computed_at timestamptz,
  hash_is_current boolean
)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE
  v_run     uuid;
  v_current boolean;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, NULL);

  PERFORM public.set_current_user_context(p_user_id, p_user_email);
  v_run := COALESCE(public.analysis_current_run(p_project_id, 'prominence'),
                    public.analysis_latest_run(p_project_id, 'prominence'));
  v_current := CASE WHEN v_run IS NULL THEN NULL ELSE public.analysis_run_is_current(v_run) END;

  RETURN QUERY
  SELECT
    nn.id, nn.project_id, nn.plant_name, nn.uid, nn.name, nn.industry, nn.website,
    nn.traded_as, nn.number_of_employees, nn.revenue, nn.depth, nn.lat, nn.long,
    nn.is_seed, nn.uploaded_by, nn.created_by, nn.organization, nn.created_at,
    nn.updated_at, nn.country,
    COALESCE((ar.metrics ->> 'prominence')::numeric, nn.prominence),
    CASE WHEN ar.id IS NOT NULL THEN 'store'
         WHEN nn.prominence IS NOT NULL THEN 'column'
         ELSE 'none' END,
    CASE WHEN ar.id IS NOT NULL THEN v_run ELSE NULL END,
    CASE WHEN ar.id IS NOT NULL THEN ar.created_at ELSE nn.prominence_updated_at END,
    CASE WHEN ar.id IS NOT NULL THEN v_current ELSE NULL END
  FROM public.network_nodes nn
  LEFT JOIN public.analysis_results ar
         ON v_run IS NOT NULL AND ar.run_id = v_run
        AND ar.entity_type = 'node' AND ar.entity_id = nn.uid
  WHERE nn.project_id = p_project_id
    AND (p_plant_name IS NULL OR nn.plant_name = p_plant_name)
  ORDER BY nn.created_at;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.get_node_list(
  p_project_id uuid,
  p_plant_name text,
  p_user_id uuid,
  p_user_email text
)
RETURNS TABLE(
  id uuid,
  project_id uuid,
  plant_name text,
  node_id text,
  node_type text,
  node_group text,
  description_text text,
  location_text text,
  longitude numeric,
  latitude numeric,
  is_critical_node boolean,
  critical_node_score numeric,
  prediction_timestamp timestamptz,
  created_by uuid,
  organization text,
  created_at timestamptz,
  updated_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, NULL);

  PERFORM public.set_current_user_context(p_user_id, p_user_email);

  RETURN QUERY
  SELECT
    nl.id,
    nl.project_id,
    nl.plant_name,
    nl.node_id,
    nl.node_type,
    nl.node_group,
    nl.description_text,
    nl.location_text,
    nl.longitude,
    nl.latitude,
    nl.is_critical_node,
    nl.critical_node_score,
    nl.prediction_timestamp,
    nl.created_by,
    nl.organization,
    nl.created_at,
    nl.updated_at
  FROM public.node_list nl
  WHERE nl.project_id = p_project_id
    AND (p_plant_name IS NULL OR nl.plant_name = p_plant_name)
  ORDER BY
    CASE lower(coalesce(nl.node_type, ''))
      WHEN 'customer' THEN 1
      WHEN 'product'  THEN 2
      WHEN 'material' THEN 3
      WHEN 'supplier' THEN 4
      ELSE 5
    END,
    nl.node_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_org_access(p_actor_id uuid, p_actor_email text, p_org_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);

  PERFORM public.set_current_user_context(p_actor_id, p_actor_email);
  IF NOT public.is_super_admin(p_actor_id) THEN RAISE EXCEPTION 'forbidden'; END IF;
  RETURN jsonb_build_object(
    'org_id', p_org_id,
    'org_name', (SELECT name FROM public.organizations WHERE id = p_org_id),
    'capabilities', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'key', c.key, 'kind', c.kind, 'label', c.label, 'description', c.description,
        'sort_order', c.sort_order, 'org_override', oc.allowed)
        ORDER BY c.kind, c.sort_order, c.key), '[]'::jsonb)
      FROM public.capabilities c
      LEFT JOIN public.org_capabilities oc ON oc.org_id = p_org_id AND oc.capability_key = c.key));
END; $$;

CREATE OR REPLACE FUNCTION public.get_prediction_stats(p_plant_name text, p_user_id uuid, p_user_email text)
RETURNS TABLE(
  total_count bigint,
  critical_count bigint,
  non_critical_count bigint,
  last_prediction_timestamp timestamp with time zone
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_total bigint := 0;
  v_critical bigint := 0;
  v_last_prediction timestamp with time zone := null;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);

  -- Set user context for RLS policies
  PERFORM public.set_current_user_context(p_user_id, p_user_email);
  
  -- Get total count
  SELECT COUNT(*)
  INTO v_total
  FROM public.supply_chain_data scd
  WHERE scd.plant_name = p_plant_name;
  
  -- Get critical count
  SELECT COUNT(*)
  INTO v_critical
  FROM public.supply_chain_data scd
  WHERE scd.plant_name = p_plant_name
    AND scd.is_critical_node = true;
  
  -- Get latest prediction timestamp
  SELECT MAX(scd.prediction_timestamp)
  INTO v_last_prediction
  FROM public.supply_chain_data scd
  WHERE scd.plant_name = p_plant_name
    AND scd.prediction_timestamp IS NOT NULL;
  
  -- Return the results
  RETURN QUERY
  SELECT 
    v_total as total_count,
    v_critical as critical_count,
    (v_total - v_critical) as non_critical_count,
    v_last_prediction as last_prediction_timestamp;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_process_level_integrated_network_data(
  p_project_id uuid, 
  p_user_id uuid, 
  p_user_email text
)
RETURNS TABLE(
  node_id text,
  node_type text, -- 'supplier', 'material', 'product', 'customer'
  node_level integer, -- BOM level (NULL for suppliers/customers)
  parent_id text,
  consumption_rate numeric,
  flow_volume numeric,
  is_final_product boolean,
  metadata jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, NULL);

  -- Set user context for RLS policies
  PERFORM public.set_current_user_context(p_user_id, p_user_email);
  
  -- Return integrated network data combining suppliers, BOM hierarchy, products, and customers
  RETURN QUERY
  WITH 
  -- Get customer demand for final products
  customer_demand AS (
    SELECT 
      o.product_id,
      o.customer_id,
      SUM(COALESCE(o.volume, 0)) as total_demand
    FROM public.outbound_logistics o
    WHERE o.project_id = p_project_id
    GROUP BY o.product_id, o.customer_id
  ),
  
  -- Get supplier supply for materials
  supplier_supply AS (
    SELECT 
      i.material_id,
      i.supplier_id,
      SUM(COALESCE(i.volume, 0)) as total_supply
    FROM public.inbound_logistics i
    WHERE i.project_id = p_project_id
    GROUP BY i.material_id, i.supplier_id
  ),
  
  -- Get BOM hierarchy with propagated demand
  bom_hierarchy AS (
    SELECT 
      bm.material_id,
      bm.higher_level_component_id,
      bm.level,
      bm.consumption_rate,
      -- Calculate demand propagation
      CASE 
        WHEN bm.higher_level_component_id IS NULL THEN -- Final products (Level 0)
          COALESCE(cd.total_demand, 0)
        ELSE 0 -- Will be calculated in recursive part
      END as propagated_demand
    FROM public.bom_multi_level bm
    LEFT JOIN customer_demand cd ON cd.product_id = bm.material_id AND bm.higher_level_component_id IS NULL
    WHERE bm.project_id = p_project_id
  )
  
  -- 1. Suppliers
  SELECT DISTINCT
    ss.supplier_id as node_id,
    'supplier'::text as node_type,
    NULL::integer as node_level,
    NULL::text as parent_id,
    NULL::numeric as consumption_rate,
    ss.total_supply as flow_volume,
    false as is_final_product,
    jsonb_build_object('supply_volume', ss.total_supply) as metadata
  FROM supplier_supply ss
  
  UNION ALL
  
  -- 2. Materials/Components from BOM
  SELECT 
    bh.material_id as node_id,
    'material'::text as node_type,
    bh.level as node_level,
    bh.higher_level_component_id as parent_id,
    bh.consumption_rate,
    bh.propagated_demand * COALESCE(bh.consumption_rate, 1) as flow_volume,
    (bh.higher_level_component_id IS NULL) as is_final_product,
    jsonb_build_object(
      'bom_level', bh.level,
      'consumption_rate', bh.consumption_rate,
      'is_root', (bh.higher_level_component_id IS NULL)
    ) as metadata
  FROM bom_hierarchy bh
  
  UNION ALL
  
  -- 3. Products (final products from BOM that have customer demand)
  SELECT DISTINCT
    cd.product_id as node_id,
    'product'::text as node_type,
    0 as node_level, -- Products are at level 0
    NULL::text as parent_id,
    NULL::numeric as consumption_rate,
    cd.total_demand as flow_volume,
    true as is_final_product,
    jsonb_build_object('customer_demand', cd.total_demand) as metadata
  FROM customer_demand cd
  
  UNION ALL
  
  -- 4. Customers
  SELECT DISTINCT
    cd.customer_id as node_id,
    'customer'::text as node_type,
    NULL::integer as node_level,
    cd.product_id as parent_id, -- Connected to products
    NULL::numeric as consumption_rate,
    cd.total_demand as flow_volume,
    false as is_final_product,
    jsonb_build_object('demand_volume', cd.total_demand) as metadata
  FROM customer_demand cd
  
  UNION ALL
  
  -- 5. Supplier → Material connections
  SELECT DISTINCT
    CONCAT('edge_', ss.supplier_id, '_', ss.material_id) as node_id,
    'edge'::text as node_type,
    NULL::integer as node_level,
    ss.supplier_id as parent_id,
    NULL::numeric as consumption_rate,
    ss.total_supply as flow_volume,
    false as is_final_product,
    jsonb_build_object(
      'edge_type', 'supply',
      'source', ss.supplier_id,
      'target', ss.material_id,
      'volume', ss.total_supply
    ) as metadata
  FROM supplier_supply ss
  
  ORDER BY node_type, node_level NULLS LAST, node_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_process_level_network_data(p_project_id uuid, p_user_id uuid, p_user_email text)
RETURNS TABLE(
  id uuid,
  project_id uuid,
  plant_name text,
  material_id text,
  higher_level_component_id text,
  level integer,
  consumption_rate numeric,
  created_at timestamp with time zone,
  updated_at timestamp with time zone
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, NULL);

  -- Set user context for RLS policies
  PERFORM public.set_current_user_context(p_user_id, p_user_email);
  
  -- Return multi-level BOM data for the specified project
  RETURN QUERY
  SELECT
    bml.id,
    bml.project_id,
    bml.plant_name,
    bml.material_id,
    bml.higher_level_component_id,
    bml.level,
    bml.consumption_rate,
    bml.created_at,
    bml.updated_at
  FROM public.bom_multi_level bml
  WHERE bml.project_id = p_project_id
  ORDER BY bml.level, bml.material_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_project_dataset_counts(
  p_project_id uuid, 
  p_user_id uuid, 
  p_user_email text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_org text;
  v_org_id uuid;
  v_bom_level text;
  v_deep_tier_enabled boolean;
  bom_count integer := 0;
  inbound_count integer := 0;
  outbound_count integer := 0;
  multi_tier_count integer := 0;
  result jsonb;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, NULL);

  -- Set user context for RLS policies
  PERFORM public.set_current_user_context(p_user_id, p_user_email);

  -- Get project info and validate access
  SELECT organization, organization_id, bom_level, deep_tier_enabled
  INTO v_org, v_org_id, v_bom_level, v_deep_tier_enabled
  FROM public.projects
  WHERE id = p_project_id;

  IF v_org IS NULL THEN
    RAISE EXCEPTION 'project_not_found';
  END IF;

  -- Authorization: same organization only
  IF NOT public.org_is_current_user_org(v_org_id, v_org) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  -- Get BOM count (either single or multi-level)
  IF v_bom_level = 'single' THEN
    SELECT COUNT(*) INTO bom_count FROM public.bom_single_level WHERE project_id = p_project_id;
  ELSE
    SELECT COUNT(*) INTO bom_count FROM public.bom_multi_level WHERE project_id = p_project_id;
  END IF;

  -- Get other dataset counts
  SELECT COUNT(*) INTO inbound_count FROM public.inbound_logistics WHERE project_id = p_project_id;
  SELECT COUNT(*) INTO outbound_count FROM public.outbound_logistics WHERE project_id = p_project_id;
  SELECT COUNT(*) INTO multi_tier_count FROM public.multi_tier_supply_chain WHERE project_id = p_project_id;

  result := jsonb_build_object(
    'bom_level', v_bom_level,
    'deep_tier_enabled', COALESCE(v_deep_tier_enabled, false),
    'bom_count', bom_count,
    'inbound_count', inbound_count,
    'outbound_count', outbound_count,
    'multi_tier_count', multi_tier_count,
    'total_records', bom_count + inbound_count + outbound_count + multi_tier_count
  );

  RETURN result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_project_dataset_status(p_project_id uuid, p_user_id uuid, p_user_email text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_org text;
  v_org_id uuid;
  v_bom_level text;
  v_deep_tier_enabled boolean;
  has_bom boolean := false;
  has_inbound boolean := false;
  has_outbound boolean := false;
  has_deep_tier_nodes boolean := false;
  has_deep_tier_edges boolean := false;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, NULL);

  -- Set user context for RLS policies
  PERFORM public.set_current_user_context(p_user_id, p_user_email);

  -- Get project info
  SELECT organization, organization_id, bom_level, deep_tier_enabled
  INTO v_org, v_org_id, v_bom_level, v_deep_tier_enabled
  FROM public.projects
  WHERE id = p_project_id;

  IF v_org IS NULL THEN
    RAISE EXCEPTION 'project_not_found';
  END IF;

  -- Authorization: same organization only
  IF NOT public.org_is_current_user_org(v_org_id, v_org) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  -- Check BOM data (either single or multi-level)
  SELECT (
    EXISTS(SELECT 1 FROM public.bom_single_level WHERE project_id = p_project_id)
    OR EXISTS(SELECT 1 FROM public.bom_multi_level WHERE project_id = p_project_id)
  ) INTO has_bom;

  -- Check other datasets
  SELECT EXISTS(SELECT 1 FROM public.inbound_logistics WHERE project_id = p_project_id) INTO has_inbound;
  SELECT EXISTS(SELECT 1 FROM public.outbound_logistics WHERE project_id = p_project_id) INTO has_outbound;

  -- Check deep tier datasets if enabled (nodes + edges only)
  IF v_deep_tier_enabled THEN
    SELECT EXISTS(SELECT 1 FROM public.network_nodes WHERE project_id = p_project_id) INTO has_deep_tier_nodes;
    SELECT EXISTS(SELECT 1 FROM public.network_edges WHERE project_id = p_project_id) INTO has_deep_tier_edges;
  END IF;

  RETURN jsonb_build_object(
    'bom_level', v_bom_level,
    'deep_tier_enabled', v_deep_tier_enabled,
    'has_bom', has_bom,
    'has_inbound', has_inbound,
    'has_outbound', has_outbound,
    'has_deep_tier_nodes', has_deep_tier_nodes,
    'has_deep_tier_edges', has_deep_tier_edges,
    'completed', CASE
      WHEN v_deep_tier_enabled THEN
        (has_bom AND has_inbound AND has_outbound AND has_deep_tier_nodes AND has_deep_tier_edges)
      ELSE
        (has_bom AND has_inbound AND has_outbound)
    END
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_project_datasets(
  p_project_id uuid,
  p_user_id uuid,
  p_user_email text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_org text;
  v_org_id uuid;
  v_bom_level text;
  result jsonb;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, NULL);

  -- Ensure this function has the correct caller context
  PERFORM public.set_current_user_context(p_user_id, p_user_email);

  SELECT organization, organization_id, bom_level
  INTO v_org, v_org_id, v_bom_level
  FROM public.projects
  WHERE id = p_project_id;

  IF v_org IS NULL THEN
    RAISE EXCEPTION 'project_not_found';
  END IF;

  -- Authorization: same organization only
  IF NOT public.org_is_current_user_org(v_org_id, v_org) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  result := jsonb_build_object(
    'bom_level', v_bom_level,
    'bom', CASE 
      WHEN v_bom_level = 'single' THEN COALESCE((
        SELECT jsonb_agg(to_jsonb(b.*)) FROM public.bom_single_level b WHERE b.project_id = p_project_id
      ), '[]'::jsonb)
      ELSE COALESCE((
        SELECT jsonb_agg(to_jsonb(bm.*)) FROM public.bom_multi_level bm WHERE bm.project_id = p_project_id
      ), '[]'::jsonb)
    END,
    'inbound', COALESCE((
      SELECT jsonb_agg(to_jsonb(i.*)) FROM public.inbound_logistics i WHERE i.project_id = p_project_id
    ), '[]'::jsonb),
    'outbound', COALESCE((
      SELECT jsonb_agg(to_jsonb(o.*)) FROM public.outbound_logistics o WHERE o.project_id = p_project_id
    ), '[]'::jsonb),
    'multiTier', COALESCE((
      SELECT jsonb_agg(to_jsonb(m.*)) FROM public.multi_tier_supply_chain m WHERE m.project_id = p_project_id
    ), '[]'::jsonb)
  );

  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_project_demand_forecasts(
  p_project_id uuid,
  p_user_id uuid,
  p_user_email text
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE
  v_org text;
  v_org_id uuid;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, NULL);

  PERFORM public.set_current_user_context(p_user_id, p_user_email);
  SELECT organization, organization_id INTO v_org, v_org_id
    FROM public.projects WHERE id = p_project_id;
  IF v_org IS NULL THEN
    RAISE EXCEPTION 'project_not_found';
  END IF;
  IF NOT public.org_is_current_user_org(v_org_id, v_org) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'customer_id', f.customer_id, 'product_id', f.product_id,
      'period_start', f.period_start, 'period_end', f.period_end,
      'time_unit', f.time_unit, 'quantity', f.quantity,
      'weekly_quantity', f.weekly_quantity
    ) ORDER BY f.customer_id, f.product_id, f.period_start)
    FROM public.demand_forecasts f WHERE f.project_id = p_project_id
  ), '[]'::jsonb);
END; $fn$;

CREATE OR REPLACE FUNCTION public.get_role_access(p_actor_id uuid, p_actor_email text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_scoped  jsonb;
  v_prm     jsonb;
  v_eff     jsonb;
  v_hold    jsonb;
  v_capped  jsonb;
  v_orgov   jsonb;
  v_userov  jsonb;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);

  PERFORM public.set_current_user_context(p_actor_id, p_actor_email);
  IF NOT public.is_super_admin(p_actor_id) THEN RAISE EXCEPTION 'forbidden'; END IF;

  SELECT COALESCE(jsonb_agg(DISTINCT capability_key ORDER BY capability_key), '[]'::jsonb)
    INTO v_scoped FROM public.project_role_capabilities;

  SELECT COALESCE(jsonb_object_agg(r.project_role, r.caps), '{}'::jsonb) INTO v_prm
    FROM (SELECT prc.project_role, jsonb_object_agg(prc.capability_key, prc.allowed) AS caps
            FROM public.project_role_capabilities prc GROUP BY prc.project_role) r;

  -- account role × project role ('none' = no project role) × key, by the rule itself, from
  -- the role defaults alone (organization and person overrides are listed separately).
  SELECT COALESCE(jsonb_object_agg(a.account_role, a.by_prole), '{}'::jsonb) INTO v_eff
    FROM (
      SELECT ar.account_role, jsonb_object_agg(pr.project_role, pr.by_key) AS by_prole
        FROM (VALUES ('user'), ('modeler'), ('admin'), ('super_admin')) ar(account_role)
        CROSS JOIN LATERAL (
          SELECT prl.project_role, jsonb_object_agg(k.key, public.project_right_decide(
                   ar.account_role = 'super_admin', NULL,
                   NULLIF(prl.project_role, 'none'),
                   (SELECT prc.allowed FROM public.project_role_capabilities prc
                     WHERE prc.project_role = prl.project_role AND prc.capability_key = k.key),
                   COALESCE((SELECT rc.allowed FROM public.role_capabilities rc
                              WHERE rc.role = ar.account_role AND rc.capability_key = k.key), false))) AS by_key
            FROM (VALUES ('none'), ('viewer'), ('analyst'), ('editor'), ('owner')) prl(project_role)
            CROSS JOIN (SELECT DISTINCT capability_key AS key FROM public.project_role_capabilities) k
           GROUP BY prl.project_role) pr
       GROUP BY ar.account_role) a;

  -- How many memberships sit in each (account role, project role) cell today.
  SELECT COALESCE(jsonb_object_agg(h.account_role, h.by_prole), '{}'::jsonb) INTO v_hold
    FROM (SELECT x.account_role, jsonb_object_agg(x.project_role, x.n) AS by_prole
            FROM (SELECT account_role, project_role, count(*) AS n
                    FROM public.project_role_holdings() GROUP BY 1, 2) x
           GROUP BY x.account_role) h;

  -- Every membership whose project role grants a right the account role caps.
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'user_id', h.user_id, 'name', COALESCE(u.name, u.email), 'account_role', h.account_role,
           'project_id', h.project_id, 'project_name', p.name, 'project_role', h.project_role,
           'capability_key', d.key, 'account_source', d.value ->> 'account_source')
           ORDER BY lower(COALESCE(u.name, u.email, '')), p.name, d.key), '[]'::jsonb)
    INTO v_capped
    FROM public.project_role_holdings() h
    JOIN public.approved_users u ON u.id = h.user_id
    JOIN public.projects p ON p.id = h.project_id
    CROSS JOIN LATERAL jsonb_each(public.project_right_decisions(h.user_id, h.project_id)) d
   WHERE d.value ->> 'decided_by' = 'account_ceiling';

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'org_id', oc.org_id, 'org_name', o.name, 'capability_key', oc.capability_key,
           'allowed', oc.allowed) ORDER BY o.name, oc.capability_key), '[]'::jsonb)
    INTO v_orgov
    FROM public.org_capabilities oc
    LEFT JOIN public.organizations o ON o.id = oc.org_id
   WHERE oc.capability_key IN (SELECT capability_key FROM public.project_role_capabilities);

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'user_id', uc.user_id, 'name', COALESCE(u.name, u.email), 'capability_key', uc.capability_key,
           'allowed', uc.allowed) ORDER BY lower(COALESCE(u.name, u.email, '')), uc.capability_key), '[]'::jsonb)
    INTO v_userov
    FROM public.user_capabilities uc
    LEFT JOIN public.approved_users u ON u.id = uc.user_id
   WHERE uc.capability_key IN (SELECT capability_key FROM public.project_role_capabilities);

  RETURN jsonb_build_object(
    'capabilities', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'key', c.key, 'kind', c.kind, 'label', c.label,
        'description', c.description, 'sort_order', c.sort_order)
        ORDER BY c.kind, c.sort_order, c.key), '[]'::jsonb) FROM public.capabilities c),
    'roles', (SELECT jsonb_object_agg(role, caps) FROM (
        SELECT rc.role, jsonb_object_agg(rc.capability_key, rc.allowed) AS caps
        FROM public.role_capabilities rc GROUP BY rc.role) r),
    -- D276
    'project_scoped',     v_scoped,
    'project_roles',      v_prm,
    'effective',          v_eff,
    'holdings',           v_hold,
    'capped',             v_capped,
    'org_overrides',      v_orgov,
    'person_overrides',   v_userov,
    'agent_rights',       public.agent_artifact_project_rights());
END; $$;

CREATE OR REPLACE FUNCTION public.get_scenario_simulation_results(p_project_id uuid, p_user_id uuid, p_user_email text)
RETURNS TABLE(
  simulation_id uuid,
  scenario_id uuid,
  scenario_name text,
  scenario_description text,
  scenario_effects jsonb,
  status text,
  started_at timestamp with time zone,
  completed_at timestamp with time zone,
  metrics jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, NULL);

  -- Set user context for RLS policies
  PERFORM public.set_current_user_context(p_user_id, p_user_email);
  
  -- Enforce organization access control
  IF NOT EXISTS (
    SELECT 1 FROM public.projects p 
    WHERE p.id = p_project_id 
    AND public.org_is_current_user_org(p.organization_id, p.organization)
  ) THEN
    RAISE EXCEPTION 'Access denied: project not found or not in your organization';
  END IF;
  
  -- Return scenario simulation results with organization access control
  RETURN QUERY
  SELECT 
    sr.id as simulation_id,
    sp.id as scenario_id,
    sp.scenario_name,
    sp.description as scenario_description,
    COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'effect_type', se.effect_type,
          'magnitude', se.magnitude,
          'unit', se.unit
        )
      ) FILTER (WHERE se.id IS NOT NULL),
      '[]'::jsonb
    ) as scenario_effects,
    sr.status,
    sr.started_at,
    sr.completed_at,
    sr.metrics
  FROM public.simulation_results sr
  JOIN public.projects proj ON proj.id = sr.project_id
  CROSS JOIN LATERAL unnest(sr.scenario_ids) AS scenario_id_unnest(scenario_id)
  JOIN public.disruption_scenario_profiles sp ON sp.id = scenario_id_unnest.scenario_id
  LEFT JOIN public.disruption_scenario_effects se ON se.profile_id = sp.id
  WHERE sr.project_id = p_project_id
    AND public.org_is_current_user_org(proj.organization_id, proj.organization)
    AND array_length(sr.scenario_ids, 1) > 0
  GROUP BY sr.id, sp.id, sp.scenario_name, sp.description, sr.status, sr.started_at, sr.completed_at, sr.metrics
  ORDER BY sr.started_at DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_simulation_results(
  p_project_id uuid,
  p_user_id uuid,
  p_user_email text
) RETURNS TABLE(
  id uuid,
  project_id uuid,
  plant_name text,
  status text,
  scenario_ids uuid[],
  started_at timestamptz,
  completed_at timestamptz,
  metrics jsonb,
  result_data jsonb,
  created_by uuid,
  organization text,
  created_at timestamptz,
  updated_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_org text;
  v_org_id uuid;
  v_modeler uuid;
  v_role text;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, NULL);

  -- Set caller context for RLS helpers
  PERFORM public.set_current_user_context(p_user_id, p_user_email);

  -- Validate project and authorization (owner or admin in same org)
  SELECT p.organization, p.organization_id, p.modeler_id INTO v_org, v_org_id, v_modeler
  FROM public.projects p
  WHERE p.id = p_project_id;

  IF v_org IS NULL THEN RAISE EXCEPTION 'project_not_found'; END IF;

  SELECT user_role INTO v_role FROM public.get_current_approved_user() LIMIT 1;
  IF NOT public.org_is_current_user_org(v_org_id, v_org) OR NOT (v_modeler = public.get_current_user_id() OR v_role IN ('admin', 'super_admin')) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  -- Return simulation results for the project with fully qualified column names
  RETURN QUERY
  SELECT sr.id, sr.project_id, sr.plant_name, sr.status, sr.scenario_ids, 
         sr.started_at, sr.completed_at, sr.metrics, sr.result_data, 
         sr.created_by, sr.organization, sr.created_at, sr.updated_at
  FROM public.simulation_results sr
  WHERE sr.project_id = p_project_id
  ORDER BY sr.created_at DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_supply_chain_data_multi_tier(
  p_project_id uuid,
  p_user_id uuid,
  p_user_email text,
  p_limit integer DEFAULT NULL,
  p_offset integer DEFAULT 0
)
RETURNS TABLE(
  id uuid,
  project_id uuid,
  plant_name text,
  data_source text,
  from_location text,
  to_location text,
  level integer,
  bom_depth integer,
  material_consumption_rate numeric,
  sourcing_ratio numeric,
  weighted numeric,
  path_root text,
  organization text,
  uploaded_by uuid,
  created_at timestamptz,
  updated_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, NULL);

  PERFORM public.set_current_user_context(p_user_id, p_user_email);

  RETURN QUERY
  SELECT
    scdmt.id, scdmt.project_id, scdmt.plant_name, scdmt.data_source,
    scdmt.from_location, scdmt.to_location,
    -- D134 — the `COALESCE(scdmt.level, 0)` is GONE, in both branches. A NULL
    -- depth is UNKNOWN, the page has an `unknown` case it could never reach
    -- because this function answered the question before the page was asked it,
    -- and `0` is the one value the ladder calls a PRODUCT.
    scdmt.level, scdmt.bom_depth,
    scdmt.material_consumption_rate, scdmt.sourcing_ratio, scdmt.weighted,
    scdmt.path_root, scdmt.organization, scdmt.uploaded_by,
    scdmt.created_at, scdmt.updated_at
  FROM public.supply_chain_data_multi_tier scdmt
  WHERE scdmt.project_id = p_project_id
  -- NULLS LAST so dropping the COALESCE does not also drop the total order the
  -- pagination below depends on.
  ORDER BY scdmt.bom_depth ASC NULLS LAST, scdmt.created_at, scdmt.id
  OFFSET COALESCE(p_offset, 0)
  LIMIT CASE WHEN COALESCE(p_limit, 0) > 0 THEN p_limit ELSE NULL END;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_supply_chain_data(
  p_project_id uuid,
  p_plant_name text,
  p_user_id uuid,
  p_user_email text
)
RETURNS TABLE(
  id uuid,
  project_id uuid,
  data_source text,
  plant_name text,
  from_location text,
  to_location text,
  material_consumption_rate numeric,
  sourcing_ratio numeric,
  weighted numeric,
  uploaded_by uuid,
  organization text,
  is_critical_node boolean,
  critical_node_score numeric,
  prediction_timestamp timestamp with time zone,
  created_at timestamp with time zone,
  updated_at timestamp with time zone
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, NULL);

  -- Set user context for RLS policies
  PERFORM public.set_current_user_context(p_user_id, p_user_email);

  -- Explicitly select columns in the same order as the RETURNS TABLE definition
  RETURN QUERY
  SELECT
    scd.id,
    scd.project_id,
    scd.data_source,
    scd.plant_name,
    scd.from_location,
    scd.to_location,
    scd.material_consumption_rate,
    scd.sourcing_ratio,
    scd.weighted,
    scd.uploaded_by,
    scd.organization,
    scd.is_critical_node,
    scd.critical_node_score,
    scd.prediction_timestamp,
    scd.created_at,
    scd.updated_at
  FROM public.supply_chain_data scd
  WHERE scd.project_id = p_project_id
    AND (p_plant_name IS NULL OR scd.plant_name = p_plant_name)
  ORDER BY scd.created_at;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_supply_chain_plants(p_project_id uuid, p_user_id uuid, p_user_email text)
RETURNS TABLE(plant_name text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, NULL);

  -- Set user context for RLS policies
  PERFORM public.set_current_user_context(p_user_id, p_user_email);
  
  -- Return unique plant names from supply_chain_data for the given project
  RETURN QUERY
  SELECT DISTINCT scd.plant_name
  FROM public.supply_chain_data scd
  WHERE scd.project_id = p_project_id
  ORDER BY scd.plant_name;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_user_access(
  p_actor_id uuid, p_actor_email text, p_target_user_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role       text;
  v_org_id     uuid;
  v_is_super   boolean;
  v_caps       jsonb;
  v_models     jsonb;
  v_uap        public.user_ai_permissions%ROWTYPE;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_id := public.security_actor(p_actor_id);

  PERFORM public.set_current_user_context(p_actor_id, p_actor_email);
  IF NOT public.is_super_admin(p_actor_id) THEN RAISE EXCEPTION 'forbidden'; END IF;

  SELECT au.role::text, au.organization_id INTO v_role, v_org_id
  FROM public.approved_users au WHERE au.id = p_target_user_id;
  IF v_role IS NULL THEN RAISE EXCEPTION 'user not found'; END IF;
  v_is_super := (v_role = 'super_admin');

  SELECT jsonb_agg(j ORDER BY j->>'kind', (j->>'sort_order')::int, j->>'key') INTO v_caps
  FROM (
    SELECT jsonb_build_object(
      'key', c.key, 'kind', c.kind, 'label', c.label, 'description', c.description,
      'sort_order', c.sort_order,
      'role_default', COALESCE(rc.allowed, false),
      'org_override', oc.allowed,
      'user_override', uc.allowed,
      'effective', CASE
        WHEN v_is_super THEN true
        WHEN c.kind = 'page' AND c.key = '/profile' THEN true
        ELSE COALESCE(uc.allowed, oc.allowed, rc.allowed, false) END
    ) AS j
    FROM public.capabilities c
    LEFT JOIN public.role_capabilities rc ON rc.role = v_role      AND rc.capability_key = c.key
    LEFT JOIN public.org_capabilities  oc ON oc.org_id = v_org_id  AND oc.capability_key = c.key
    LEFT JOIN public.user_capabilities uc ON uc.user_id = p_target_user_id AND uc.capability_key = c.key
  ) s;

  SELECT * INTO v_uap FROM public.user_ai_permissions WHERE user_id = p_target_user_id;

  SELECT jsonb_build_object(
    'catalog', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                  'id', m.id, 'code', m.code, 'display_name', m.display_name,
                  'provider_code', p.code, 'provider_name', p.display_name, 'enabled', m.enabled
                ) ORDER BY p.display_name, m.display_name), '[]'::jsonb)
                FROM public.ai_models m LEFT JOIN public.ai_providers p ON p.id = m.provider_id
                WHERE m.enabled),
    'allowed_ids', to_jsonb(COALESCE(v_uap.allowed_model_ids, '{}')),
    'default_id',  v_uap.default_model_id,
    'fallback_id', v_uap.fallback_model_id,
    'all_allowed', v_is_super OR v_uap.allowed_model_ids IS NULL
                   OR array_length(v_uap.allowed_model_ids, 1) IS NULL
  ) INTO v_models;

  RETURN jsonb_build_object(
    'user_id', p_target_user_id,
    'name',  (SELECT name  FROM public.approved_users WHERE id = p_target_user_id),
    'email', (SELECT email FROM public.approved_users WHERE id = p_target_user_id),
    'role', v_role, 'organization_id', v_org_id, 'is_super_admin', v_is_super,
    'capabilities', COALESCE(v_caps, '[]'::jsonb),
    'models', v_models,
    'budgets', (public.capabilities_for_user(p_target_user_id) -> 'budgets'));
END; $$;

CREATE OR REPLACE FUNCTION public.import_local_threads(
  p_user_id uuid, p_threads jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_thread    jsonb;
  v_msg       jsonb;
  v_local_id  text;
  v_id        uuid;
  v_project   uuid;
  v_seq       integer;
  v_imported  integer := 0;
  v_skipped   integer := 0;
  v_mappings  jsonb := '[]'::jsonb;
  v_was_new   boolean;
  v_updated_at timestamptz;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);

  IF p_user_id IS NULL THEN RAISE EXCEPTION 'forbidden'; END IF;
  IF p_threads IS NULL OR jsonb_typeof(p_threads) <> 'array' THEN
    RAISE EXCEPTION 'import_local_threads: p_threads must be a json array';
  END IF;

  FOR v_thread IN SELECT * FROM jsonb_array_elements(p_threads) LOOP
    v_local_id := v_thread->>'id';
    IF v_local_id IS NULL OR v_local_id = '' THEN CONTINUE; END IF;

    IF v_local_id = 'quick' THEN
      v_id := public.chat_quick_thread_id(p_user_id);
    ELSIF v_local_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
      v_id := v_local_id::uuid;
    ELSE
      v_id := md5(p_user_id::text || ':' || v_local_id)::uuid;
    END IF;

    v_was_new := NOT EXISTS (SELECT 1 FROM public.chat_threads WHERE id = v_id);
    IF NOT v_was_new THEN
      v_skipped := v_skipped + 1;
      v_mappings := v_mappings || jsonb_build_object(
        'local_id', v_local_id, 'server_id', v_id, 'imported', false);
      CONTINUE;
    END IF;

    v_project := NULL;
    IF (v_thread->>'projectId') IS NOT NULL
       AND (v_thread->>'projectId') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
      SELECT id INTO v_project FROM public.projects WHERE id = (v_thread->>'projectId')::uuid;
    END IF;

    v_updated_at := CASE
      WHEN (v_thread->>'updatedAt') ~ '^[0-9]+(\.[0-9]+)?$'
        THEN to_timestamp((v_thread->>'updatedAt')::numeric / 1000.0)
      ELSE NULL END;

    INSERT INTO public.chat_threads (id, user_id, title, project_id, persona_id, last_message_at)
    VALUES (
      v_id, p_user_id,
      COALESCE(NULLIF(left(v_thread->>'title', 120), ''),
               CASE WHEN v_local_id = 'quick' THEN 'Quick chat' ELSE 'New chat' END),
      v_project,
      NULLIF(v_thread->>'agentId', ''),
      v_updated_at
    );

    v_seq := 0;
    IF jsonb_typeof(v_thread->'messages') = 'array' THEN
      FOR v_msg IN SELECT * FROM jsonb_array_elements(v_thread->'messages') LOOP
        IF (v_msg->>'role') NOT IN ('user','assistant') THEN CONTINUE; END IF;
        v_seq := v_seq + 1;
        INSERT INTO public.chat_messages
          (thread_id, seq, role, content, parts, tool_calls, created_at)
        VALUES (
          v_id, v_seq, v_msg->>'role',
          left(COALESCE(v_msg->>'content', ''), 32000),
          CASE WHEN jsonb_typeof(v_msg->'parts') = 'array' THEN v_msg->'parts' ELSE '[]'::jsonb END,
          CASE WHEN jsonb_typeof(v_msg->'toolCalls') = 'array' THEN v_msg->'toolCalls' ELSE '[]'::jsonb END,
          CASE WHEN (v_msg->>'createdAt') ~ '^[0-9]+(\.[0-9]+)?$'
               THEN to_timestamp((v_msg->>'createdAt')::numeric / 1000.0)
               ELSE now() END
        );
      END LOOP;
    END IF;

    v_imported := v_imported + 1;
    v_mappings := v_mappings || jsonb_build_object(
      'local_id', v_local_id, 'server_id', v_id, 'imported', true);
  END LOOP;

  RETURN jsonb_build_object('imported', v_imported, 'skipped', v_skipped, 'mappings', v_mappings);
END; $$;

CREATE OR REPLACE FUNCTION public.ingest_apply_run(
  _run_id        uuid,
  _actor_user_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_run       public.ingest_runs%ROWTYPE;
  v_role      text;
  v_plant     text;
  v_target    text;
  v_plan      record;
  v_update    text;
  v_written   integer;
  v_upd       integer;
  v_diff      jsonb;
  v_expect    integer;
  v_total     integer := 0;
  v_updated   integer := 0;
BEGIN
  -- D309: bind caller assertions before the original operation.
  _actor_user_id := public.security_actor(_actor_user_id);

  IF _actor_user_id IS NULL THEN
    RAISE EXCEPTION 'ingest_apply_run: a promotion must name its actor (invariant audit-actor)'
      USING ERRCODE = 'null_value_not_allowed';
  END IF;

  -- FOR UPDATE, so two clicks on "apply" cannot both find the run `staged`.
  SELECT * INTO v_run FROM public.ingest_runs WHERE id = _run_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ingest_apply_run: no run %', _run_id USING ERRCODE = 'no_data_found';
  END IF;
  IF v_run.status <> 'staged' THEN
    RAISE EXCEPTION 'ingest_apply_run: run % is %, not staged — a run is promoted once',
      _run_id, v_run.status USING ERRCODE = 'invalid_parameter_value';
  END IF;

  PERFORM set_config('app.current_user_id', _actor_user_id::text, true);

  -- THE EXIT CHECK, AS A STATEMENT ABOUT WHAT THE DATABASE DOES. A disabled
  -- button is not a refusal: the button is in a bundle anyone can read and the
  -- RPC is reachable without it. `supabase/rehearsal/100` asserts this against a
  -- real database, with an analyst who has genuine project access.
  v_role := public.effective_project_role(_actor_user_id, v_run.project_id);
  IF public.project_role_rank(v_role) < public.project_role_rank('editor') THEN
    RAISE EXCEPTION
      'ingest_apply_run: promoting a run into project % needs project role editor or higher; % has %',
      v_run.project_id, _actor_user_id, COALESCE(v_role, 'no role on this project')
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Fresh, in this transaction, against tier 2 as it is NOW.
  v_diff := public.ingest_diff_run(_run_id, _actor_user_id);

  -- `project_id` and `plant_name` come from the PROJECT and never from the file
  -- — the contract says so for every lane column (`set from the selected project,
  -- never from the CSV`), and `ensure_dataset_plant_matches_project` refuses the
  -- row otherwise.
  SELECT plant_name INTO v_plant FROM public.projects WHERE id = v_run.project_id;

  FOR v_target IN
    SELECT DISTINCT target_table FROM public.ingest_staged_rows WHERE ingest_run_id = _run_id
  LOOP
    IF NOT public.ingest_target_is_promotable(v_target) THEN
      RAISE EXCEPTION 'ingest_apply_run: % is not a promotable target', v_target
        USING ERRCODE = 'invalid_parameter_value';
    END IF;

    SELECT * INTO v_plan FROM public.ingest_promotion_plan(_run_id, v_target);
    CONTINUE WHEN v_plan.write_names IS NULL;   -- every row for this target was rejected

    -- Everything that is not part of the arbiter is overwritten by the incoming
    -- row. A key column must NOT appear: `ON CONFLICT DO UPDATE` forbids
    -- assigning to the columns it matched on, and it would be meaningless anyway
    -- — they are equal by construction.
    -- Empty when every written column is part of the arbiter — a pure-key table,
    -- where the upsert has nothing to change but must still stamp the provenance.
    -- The trailing comma belongs to this fragment so the statement is valid
    -- either way; `DO UPDATE SET` always has the three provenance assignments.
    SELECT COALESCE(string_agg(format('%I = EXCLUDED.%I,', c, c), ' ' ORDER BY c), '')
      INTO v_update
      FROM unnest(v_plan.write_names) AS c
     WHERE c <> ALL (v_plan.natural_key);

    -- ONE STATEMENT per target, which is what makes the tier-2 audit trigger
    -- write ONE row saying "n rows" rather than n rows saying one (WP 2.3).
    --
    -- `DISTINCT ON` IS NOT DECORATION. `ON CONFLICT DO UPDATE` raises 21000 —
    -- "cannot affect row a second time" — when ONE statement carries two rows
    -- with the same arbiter key, which is exactly what a CSV containing the same
    -- arc twice produces. Without it the whole promotion aborts on a duplicate
    -- LINE, with an error naming nothing the uploader can act on. With it the
    -- last line for a key wins — the same rule `20260916000017` applies to rows
    -- already in the table — and the superseded lines carry the finding
    -- `ingest_diff_run` gave them, which the review screen showed BEFORE this
    -- ran (§5 T2).
    --
    -- `xmax = 0` DISTINGUISHES AN INSERT FROM AN UPDATE in the RETURNING clause,
    -- and it is cross-checked against the diff below.
    EXECUTE format(
      'WITH up AS (
         INSERT INTO public.%I (%s, %s, ingest_run_id, source_row_id)
           SELECT DISTINCT ON (%s) %s, %s, $3, s.id
             FROM public.ingest_staged_rows s
            WHERE s.ingest_run_id = $3
              AND s.target_table  = $4
              AND NOT (s.findings @> ''[{"level": "error"}]''::jsonb)
            ORDER BY %s, s.source_row_number DESC
         ON CONFLICT (%s) DO UPDATE SET %s
              ingest_run_id = EXCLUDED.ingest_run_id,
              source_row_id = EXCLUDED.source_row_id,
              updated_at    = now()
         RETURNING (xmax = 0) AS inserted
       )
       SELECT count(*)::int, count(*) FILTER (WHERE NOT inserted)::int FROM up',
      v_target, v_plan.server_cols, v_plan.write_cols,
      COALESCE(v_plan.file_key, '1'), v_plan.server_vals, v_plan.write_vals,
      COALESCE(v_plan.file_key, '1'),
      (SELECT string_agg(quote_ident(c), ', ') FROM unnest(v_plan.natural_key) AS c),
      v_update)
      INTO v_written, v_upd
      USING v_run.project_id, v_plant, _run_id, v_target;

    v_total   := v_total + v_written;
    v_updated := v_updated + v_upd;
  END LOOP;

  -- THE TWO INDEPENDENT ANSWERS TO "HOW MANY OF THESE ROWS ALREADY EXISTED".
  -- One came from a tuple header, one from a catalog-driven join against tier 2.
  -- They are allowed to be equal and nothing else.
  v_expect := (v_diff ->> 'rows_changed')::int + (v_diff ->> 'rows_unchanged')::int;
  IF v_updated <> v_expect THEN
    RAISE EXCEPTION
      'ingest_apply_run: the diff expected % existing row(s) and the upsert updated % — '
      'tier 2 changed between the diff and the upsert, or the diff''s key predicate is wrong. '
      'Nothing is promoted; re-open the review.',
      v_expect, v_updated USING ERRCODE = 'serialization_failure';
  END IF;

  -- The counts are `ingest_diff_run`'s; this statement records only the
  -- transition. `rows_new` is the DIFF's rows_new — rows with no counterpart in
  -- tier 2 — and no longer `v_total`, which was inserts and updates together
  -- under a column named for one of them (D63).
  UPDATE public.ingest_runs
     SET status = 'applied', applied_at = now(), applied_by_user_id = _actor_user_id
   WHERE id = _run_id;

  RETURN jsonb_build_object(
    'run_id',          _run_id,
    'rows_promoted',   v_total,
    -- of those, how many already existed under this natural key. A second upload
    -- of an unchanged file promotes the same count and updates ALL of it, which
    -- is "uploading the same file twice is a no-op" as a number.
    'rows_updated',    v_updated,
    -- AND THE SPLIT THE PREVIOUS LINE CANNOT MAKE. `rows_updated` counts rows
    -- the upsert touched; it cannot say whether touching them changed anything,
    -- because an UPDATE that writes identical values is still an UPDATE. §16 ·
    -- WP 3.3's handoff said "12 new, 340 unchanged needs no second pass" — it
    -- does, and this is it (D63).
    'rows_new',        (v_diff ->> 'rows_new')::int,
    'rows_changed',    (v_diff ->> 'rows_changed')::int,
    'rows_unchanged',  (v_diff ->> 'rows_unchanged')::int,
    -- lines the file repeated; each one carries a finding in tier 1 naming the
    -- line that superseded it.
    'rows_superseded', (v_diff ->> 'rows_superseded')::int,
    'rows_held',       (v_diff ->> 'rows_held')::int,
    'promoted_by_role', v_role);
END; $fn$;

CREATE OR REPLACE FUNCTION public.ingest_diff_run(
  _run_id        uuid,
  _actor_user_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_run       public.ingest_runs%ROWTYPE;
  v_role      text;
  v_plant     text;
  v_target    text;
  v_plan      record;
  v_pred      text;
  v_lhs       text;
  v_rhs       text;
  v_staged    integer;
  v_new       integer := 0;
  v_changed   integer := 0;
  v_unchanged integer := 0;
  v_supers    integer := 0;
  v_held      integer := 0;
BEGIN
  -- D309: bind caller assertions before the original operation.
  _actor_user_id := public.security_actor(_actor_user_id);

  IF _actor_user_id IS NULL THEN
    RAISE EXCEPTION 'ingest_diff_run: a diff must name the person asking for it'
      USING ERRCODE = 'null_value_not_allowed';
  END IF;

  SELECT * INTO v_run FROM public.ingest_runs WHERE id = _run_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ingest_diff_run: no run %', _run_id USING ERRCODE = 'no_data_found';
  END IF;

  PERFORM set_config('app.current_user_id', _actor_user_id::text, true);

  -- REVIEWING IS THE READ SIDE, so the gate is "may this person reach the
  -- project at all", not "may they promote". It takes TWO predicates and that is
  -- not belt and braces — it is the honest shape of a half-migrated governance
  -- plane, found by `supabase/rehearsal/100` rather than by reading:
  --
  --   · `has_project_access` is "the modeler, or a platform admin". Every RLS
  --     policy on `ingest_runs`, `ingest_files` and `ingest_staged_rows` uses it,
  --     so it is what actually decides who can SELECT a staged row today.
  --   · `effective_project_role` is WP 2.2's membership, and it is the only one
  --     of the two that HAS a role — which is why the promotion below uses it
  --     alone. An EDITOR who is not the project's modeler passes that gate and
  --     fails the first one, so a diff checking only `has_project_access` would
  --     refuse the very person §10 says may promote. The first run of
  --     `rehearsal/100` failed on exactly that, inside `ingest_apply_run`.
  --
  -- The union is the read gate until the ingest RLS moves onto
  -- `effective_project_role`, which is `min_project_role` finally being enforced
  -- rather than declared — 37 sidecars declare it and nothing reads it
  -- (PLAN.md §4 D66, WP 6.2).
  v_role := public.effective_project_role(_actor_user_id, v_run.project_id);
  IF public.project_role_rank(v_role) < public.project_role_rank('viewer')
     AND NOT public.has_project_access(v_run.project_id) THEN
    RAISE EXCEPTION 'ingest_diff_run: % has no access to project %', _actor_user_id, v_run.project_id
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- A CONNECTOR RUN STAGES NOTHING HERE, and leaving its counts alone is not a
  -- branch on `source_kind` — §10's gap check forbids that and this is not one.
  -- It is a branch on whether this run has row-shaped staging at all, which is a
  -- structural question with a structural answer. `erp-sync-orbit-mrp` computes
  -- its own diff over the three typed staging tables and writes its own counts;
  -- zeroing them from here would be this function claiming to have measured
  -- something it never looked at.
  SELECT count(*) INTO v_staged FROM public.ingest_staged_rows WHERE ingest_run_id = _run_id;
  IF v_staged = 0 THEN
    RETURN jsonb_build_object('run_id', _run_id, 'rows_compared', 0,
      'actor_role', v_role,
      'actor_may_promote',
        public.project_role_rank(v_role) >= public.project_role_rank('editor'),
      'note', 'this run stages no ingest_staged_rows; its counts were not touched');
  END IF;

  SELECT plant_name INTO v_plant FROM public.projects WHERE id = v_run.project_id;

  -- A row held back by an error finding has no diff. Its key may be one of the
  -- fields that failed, so there is nothing to compare it against, and NULL says
  -- exactly that (D62).
  UPDATE public.ingest_staged_rows
     SET diff_state = NULL
   WHERE ingest_run_id = _run_id
     AND findings @> '[{"level": "error"}]'::jsonb
     AND diff_state IS NOT NULL;

  -- Idempotence, first half: a previous pass's superseded findings go before a
  -- new pass adds them, so re-diffing a run never doubles them.
  UPDATE public.ingest_staged_rows
     SET findings = COALESCE(
           (SELECT jsonb_agg(f) FROM jsonb_array_elements(findings) f
             WHERE f ->> 'code' IS DISTINCT FROM 'superseded_by_later_line'),
           '[]'::jsonb)
   WHERE ingest_run_id = _run_id
     AND findings @> '[{"code": "superseded_by_later_line"}]'::jsonb;

  FOR v_target IN
    SELECT DISTINCT target_table FROM public.ingest_staged_rows WHERE ingest_run_id = _run_id
  LOOP
    IF NOT public.ingest_target_is_promotable(v_target) THEN
      RAISE EXCEPTION 'ingest_diff_run: % is not a promotable target', v_target
        USING ERRCODE = 'invalid_parameter_value';
    END IF;

    SELECT * INTO v_plan FROM public.ingest_promotion_plan(_run_id, v_target);
    CONTINUE WHEN v_plan.write_names IS NULL;   -- every row for this target was rejected

    -- THE KEY PREDICATE USES `IS NOT DISTINCT FROM`, NOT `=`, AND THE REASON IS
    -- D5. Three of the seven natural keys contain a nullable column whose NULL is
    -- meaningful, so every index is `NULLS NOT DISTINCT` and `ON CONFLICT` treats
    -- two NULLs as the SAME key. A diff joining with `=` would find no match for
    -- exactly those rows, call them `new`, and then watch the upsert UPDATE them
    -- — the review screen and the promotion disagreeing about the same row, in
    -- the one case no constraint had ever covered before WP 3.3.
    SELECT string_agg(
             CASE k.c
               WHEN 'project_id' THEN 'tgt.project_id IS NOT DISTINCT FROM $1'
               WHEN 'plant_name' THEN 'tgt.plant_name IS NOT DISTINCT FROM $2'
               ELSE format('tgt.%I IS NOT DISTINCT FROM %s', k.c, COALESCE(e.expr, 'NULL'))
             END, ' AND ' ORDER BY k.ord)
      INTO v_pred
      FROM unnest(v_plan.natural_key) WITH ORDINALITY AS k(c, ord)
      LEFT JOIN LATERAL (
        SELECT u.expr FROM unnest(v_plan.write_names, v_plan.write_exprs) AS u(nm, expr)
         WHERE u.nm = k.c LIMIT 1) e ON true;

    -- What "changed" means: any column the promotion WOULD write, other than the
    -- arbiter's own, differs from what is in the row today — compared AFTER
    -- normalization and cast to the column's own type, because that is the value
    -- that would land. Comparing the raw cell would report a change every time a
    -- file restated 7/week as 30.4375/month, which is the same fact twice.
    SELECT string_agg(format('tgt.%I', u.nm), ', ' ORDER BY u.nm),
           string_agg(u.expr, ', ' ORDER BY u.nm)
      INTO v_lhs, v_rhs
      FROM unnest(v_plan.write_names, v_plan.write_exprs) AS u(nm, expr)
     WHERE u.nm <> ALL (v_plan.natural_key);

    EXECUTE format(
      'UPDATE public.ingest_staged_rows t
          SET diff_state = d.state
         FROM (
           SELECT s.id,
                  CASE WHEN x.found IS NULL THEN ''new''
                       WHEN x.differs      THEN ''changed''
                       ELSE                     ''unchanged'' END AS state
             FROM public.ingest_staged_rows s
             LEFT JOIN LATERAL (
                  SELECT true AS found, (%s) AS differs
                    FROM public.%I tgt
                   WHERE %s
                   LIMIT 1) x ON true
            WHERE s.ingest_run_id = $3
              AND s.target_table  = $4
              AND NOT (s.findings @> ''[{"level": "error"}]''::jsonb)) d
        WHERE t.id = d.id',
      -- A PURE-KEY TARGET has no non-arbiter column to compare, so a row that
      -- matches is `unchanged` by construction rather than by measurement.
      CASE WHEN v_lhs IS NULL THEN 'false'
           ELSE format('ROW(%s) IS DISTINCT FROM ROW(%s)', v_lhs, v_rhs) END,
      v_target, v_pred)
      USING v_run.project_id, v_plant, _run_id, v_target;

    -- Idempotence, second half — and this MOVED here from `ingest_apply_run`
    -- (WP 3.3, `20260916000019`) rather than being added beside it. The finding
    -- is what the review screen shows for the third row state, so it has to
    -- exist BEFORE the promotion, not as a side effect of it. Its wording is
    -- present-tense for the same reason: the same sentence is true at review
    -- time and after the apply.
    IF v_plan.file_key IS NOT NULL THEN
      EXECUTE format(
        'WITH g AS (
           SELECT s.id, s.source_row_number,
                  max(s.source_row_number) OVER (PARTITION BY %s) AS kept
             FROM public.ingest_staged_rows s
            WHERE s.ingest_run_id = $1 AND s.target_table = $2
              AND NOT (s.findings @> ''[{"level": "error"}]''::jsonb)
         )
         UPDATE public.ingest_staged_rows t
            SET findings = t.findings || jsonb_build_array(jsonb_build_object(
                  ''level'',   ''warning'',
                  ''code'',    ''superseded_by_later_line'',
                  ''row'',     g.source_row_number,
                  ''message'', format(
                     ''Row %%s repeats a row already in this file; row %%s carries the '' ||
                     ''same %s and supersedes it. This row is not promoted.'',
                     g.source_row_number, g.kept)))
           FROM g
          WHERE t.id = g.id AND g.source_row_number < g.kept',
        v_plan.file_key, array_to_string(v_plan.natural_key, ' + '))
        USING _run_id, v_target;
    END IF;
  END LOOP;

  -- THE COUNTS THE REVIEW SCREEN READS, and they partition the run exactly:
  -- new + changed + unchanged + superseded + held = rows staged. A screen whose
  -- categories do not add up to the file is a screen that has lost rows, so the
  -- three diff states are counted over the rows that will ACTUALLY promote —
  -- a superseded row is reported as superseded and not also as `changed`.
  SELECT count(*) FILTER (WHERE r.state = 'new'),
         count(*) FILTER (WHERE r.state = 'changed'),
         count(*) FILTER (WHERE r.state = 'unchanged'),
         count(*) FILTER (WHERE r.superseded),
         count(*) FILTER (WHERE r.held)
    INTO v_new, v_changed, v_unchanged, v_supers, v_held
    FROM (
      SELECT CASE WHEN s.findings @> '[{"level": "error"}]'::jsonb THEN NULL
                  WHEN s.findings @> '[{"code": "superseded_by_later_line"}]'::jsonb THEN NULL
                  ELSE s.diff_state END AS state,
             s.findings @> '[{"code": "superseded_by_later_line"}]'::jsonb AS superseded,
             s.findings @> '[{"level": "error"}]'::jsonb                   AS held
        FROM public.ingest_staged_rows s
       WHERE s.ingest_run_id = _run_id) r;

  UPDATE public.ingest_runs
     SET rows_new        = v_new,
         rows_changed    = v_changed,
         rows_unchanged  = v_unchanged,
         -- Not a measurement that came back zero: a file run cannot express
         -- `removed_upstream` at all. See the header.
         rows_removed    = 0,
         rows_superseded = v_supers,
         rows_held       = v_held
   WHERE id = _run_id;

  RETURN jsonb_build_object(
    'run_id',          _run_id,
    'rows_staged',     v_staged,
    -- THE CALLER'S OWN ROLE, ANSWERED BY THE DATABASE THAT WILL ENFORCE IT.
    -- The review screen disables its Promote button from this, and the reason it
    -- comes back with the counts rather than from a separate lookup is that
    -- there must not be a SECOND opinion about who may promote: the button and
    -- the refusal read the same function, so a disabled button is a preview of
    -- what `ingest_apply_run` would do and never a substitute for it.
    'actor_role',      v_role,
    'actor_may_promote',
      public.project_role_rank(v_role) >= public.project_role_rank('editor'),
    'rows_new',        v_new,
    'rows_changed',    v_changed,
    'rows_unchanged',  v_unchanged,
    'rows_superseded', v_supers,
    'rows_held',       v_held);
END; $fn$;

CREATE OR REPLACE FUNCTION public.ingest_land_file(
  _project_id        uuid,
  _actor_user_id     uuid,
  _source_kind       text,
  _fact_class        text,
  _target_table      text,
  _original_filename text,
  _storage_bucket    text,
  _storage_path      text,
  _content_type      text,
  _byte_size         bigint,
  _content_sha256    text,
  _rows              jsonb,   -- [{source_row_number, raw, parsed, findings}]
  _file_findings     jsonb DEFAULT '[]'::jsonb,
  _counts            jsonb DEFAULT '{}'::jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_run      uuid;
  v_file     uuid;
  v_audit    uuid;
  v_staged   integer := 0;
  v_rejected integer := 0;
BEGIN
  -- D309: bind caller assertions before the original operation.
  _actor_user_id := public.security_actor(_actor_user_id);
  PERFORM public.security_assert_project(_project_id, 'data_edit_inputs');

  -- A CSV upload always has a person. `triggered_by_user_id` is nullable because
  -- a SCHEDULED connector run genuinely has no actor (G4 is honest about that),
  -- but an anonymous file landing is not that case — it is an unattributed tier
  -- transition, which is the thing the invariant exists to forbid.
  IF _actor_user_id IS NULL THEN
    RAISE EXCEPTION 'ingest_land_file: a file landing must name its uploader (invariant audit-actor)'
      USING ERRCODE = 'null_value_not_allowed';
  END IF;

  -- LOCAL to this transaction. Everything below that asks who is acting — the
  -- access check here, the tier-2 audit trigger in ingest_apply_run — reads this.
  PERFORM set_config('app.current_user_id', _actor_user_id::text, true);

  IF NOT public.has_project_access(_project_id) THEN
    RAISE EXCEPTION 'ingest_land_file: % has no access to project %', _actor_user_id, _project_id
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF NOT public.ingest_target_is_promotable(_target_table) THEN
    RAISE EXCEPTION 'ingest_land_file: % is not a target this contract promotes into', _target_table
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- The run first, and this order is not a preference: `ingest_files.ingest_run_id`
  -- is NOT NULL and the row is write-once, so a file cannot be bound to a run
  -- afterwards. `source_kind` is stated because the column has no DEFAULT and
  -- must not get one (WP 3.1, §5 T1).
  INSERT INTO public.ingest_runs (
    project_id, link_id, source_kind, triggered_by, triggered_by_user_id, status,
    rows_fetched, mapping_warnings, fields_mapped, fields_defaulted, fields_failed)
  VALUES (
    _project_id, NULL, _source_kind, 'manual', _actor_user_id, 'staged',
    COALESCE(_counts -> 'rows_fetched', '{}'::jsonb),
    COALESCE(_file_findings, '[]'::jsonb),
    COALESCE((_counts ->> 'fields_mapped')::int, 0),
    COALESCE((_counts ->> 'fields_defaulted')::int, 0),
    COALESCE((_counts ->> 'fields_failed')::int, 0))
  RETURNING id INTO v_run;

  INSERT INTO public.ingest_files (
    ingest_run_id, source_kind, original_filename, storage_bucket, storage_path,
    content_type, byte_size, content_sha256, uploaded_by)
  VALUES (
    v_run, _source_kind, _original_filename, _storage_bucket, _storage_path,
    _content_type, _byte_size, _content_sha256, _actor_user_id)
  RETURNING id INTO v_file;

  INSERT INTO public.ingest_staged_rows (
    ingest_run_id, source_kind, fact_class, target_table,
    source_row_number, raw, parsed, findings)
  SELECT v_run, _source_kind, _fact_class, _target_table,
         (r ->> 'source_row_number')::int,
         COALESCE(r -> 'raw',      '{}'::jsonb),
         COALESCE(r -> 'parsed',   '{}'::jsonb),
         COALESCE(r -> 'findings', '[]'::jsonb)
    FROM jsonb_array_elements(COALESCE(_rows, '[]'::jsonb)) AS r;
  GET DIAGNOSTICS v_staged = ROW_COUNT;

  SELECT count(*) INTO v_rejected
    FROM public.ingest_staged_rows
   WHERE ingest_run_id = v_run AND findings @> '[{"level": "error"}]'::jsonb;

  -- THE AUDIT ROW THIS PACKAGE OWES. `ingest_files`'s sidecar says it plainly:
  -- a landing IS a tier transition — external bytes entering the system — and
  -- G4 says a tier transition writes a row NAMING the actor. Tier 0 and tier 1
  -- carry no `audit_tier_write` trigger (those are tier 2/3/4), so the emit is
  -- explicit, and it is exact about the actor because the actor was a parameter.
  v_audit := public.log_data_action(
    _actor_user_id, 'data', 'ingest_file_landed', 'ingest_files', v_file::text, NULL,
    jsonb_build_object(
      'tier',            '0/1',
      'run_id',          v_run,
      'project_id',      _project_id,
      'source_kind',     _source_kind,
      'fact_class',      _fact_class,
      'target_table',    _target_table,
      'filename',        _original_filename,
      'byte_size',       _byte_size,
      'content_sha256',  _content_sha256,
      'rows_staged',     v_staged,
      'rows_rejected',   v_rejected,
      -- Said in the row rather than inferred from a non-NULL actor later, the
      -- same way `audit_tier_write` says it.
      'actor_known',     true));

  RETURN jsonb_build_object(
    'run_id', v_run, 'file_id', v_file, 'audit_id', v_audit,
    'rows_staged', v_staged, 'rows_rejected', v_rejected);
END; $fn$;

CREATE OR REPLACE FUNCTION public.ingest_legacy_upsert_lane(
  _project_id    uuid,
  _actor_user_id uuid,
  _target        text,
  _rows          jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_key      text[];
  v_names    text[];
  v_file_key text;
  v_cols     text;
  v_vals     text;
  v_update   text;
  v_plant    text;
  v_written  integer;
  v_updated  integer;
BEGIN
  -- D309: bind caller assertions before the original operation.
  _actor_user_id := public.security_actor(_actor_user_id);
  PERFORM public.security_assert_project(_project_id, 'data_edit_inputs');

  PERFORM public.assert_writer_may_act('ingest_legacy_upsert_lane', _project_id, _actor_user_id);

  IF NOT public.ingest_target_is_promotable(_target) THEN
    RAISE EXCEPTION 'ingest_legacy_upsert_lane: % is not a writable lane', _target
      USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF jsonb_typeof(_rows) <> 'array' THEN
    RAISE EXCEPTION 'ingest_legacy_upsert_lane: rows must be a json array, got %',
      COALESCE(jsonb_typeof(_rows), 'null') USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF jsonb_array_length(_rows) = 0 THEN
    RETURN jsonb_build_object('rows_written', 0, 'rows_updated', 0, 'target', _target);
  END IF;

  SELECT plant_name INTO v_plant FROM public.projects WHERE id = _project_id;

  v_key := public.ingest_target_natural_key(_target);

  -- The arbiter columns the PAYLOAD supplies — the server-set two are excluded
  -- because they are the same value for every row and cannot discriminate.
  SELECT string_agg(quote_ident(c), ', ' ORDER BY c) INTO v_file_key
    FROM unnest(v_key) AS c WHERE c NOT IN ('project_id','plant_name');

  -- Which columns to write: the union of the payload's keys, intersected with
  -- the target's real columns, minus everything the server owns. A key the
  -- table does not have is DROPPED rather than raising — these are legacy
  -- callers and a new field in a client payload must not take the grid down.
  --
  -- KEPT AS AN ARRAY, which is the whole of this migration. `20260917000003`
  -- built the quoted column list and then SPLIT IT BACK on ', ' to derive the
  -- value list and the `DO UPDATE SET` fragment — a second, weaker source for a
  -- fact that was already in hand, and one that would mis-parse any identifier
  -- needing a quoted spelling. `ingest_promotion_plan` carries both a string
  -- and a `write_names text[]` for the same reason.
  SELECT array_agg(a.attname ORDER BY a.attname) INTO v_names
    FROM (SELECT DISTINCT k FROM jsonb_array_elements(_rows) e, jsonb_object_keys(e) k) p
    JOIN pg_attribute a
      ON a.attrelid = format('public.%I', _target)::regclass
     AND a.attname  = p.k AND a.attnum > 0 AND NOT a.attisdropped
   WHERE a.attname NOT IN ('id','project_id','plant_name','created_at','updated_at',
                           'ingest_run_id','source_row_id');

  IF v_names IS NULL THEN
    RAISE EXCEPTION
      'ingest_legacy_upsert_lane: the payload carries no column of %. Writing nothing '
      'and reporting success is how a silent data loss looks.', _target
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  SELECT string_agg(quote_ident(c), ', ' ORDER BY c),
         string_agg('r.' || quote_ident(c), ', ' ORDER BY c)
    INTO v_cols, v_vals
    FROM unnest(v_names) AS c;

  -- A key column must NOT appear in DO UPDATE SET: `ON CONFLICT` forbids
  -- assigning to what it matched on, and it would be meaningless anyway.
  SELECT COALESCE(string_agg(format('%I = EXCLUDED.%I,', c, c), ' ' ORDER BY c), '')
    INTO v_update
    FROM unnest(v_names) AS c
   WHERE c <> ALL (v_key);

  -- ONE STATEMENT, which is what makes the tier-2 audit trigger write ONE row
  -- saying "n rows" rather than n rows saying one (WP 2.3). `DISTINCT ON` is
  -- not decoration: `ON CONFLICT DO UPDATE` raises 21000 when one statement
  -- carries two rows with the same arbiter key, which a grid that assigns the
  -- same supplier twice produces. Last one wins, the same rule
  -- `ingest_apply_run` applies.
  EXECUTE format(
    'WITH up AS (
       INSERT INTO public.%I (project_id, plant_name, %s)
         SELECT DISTINCT ON (%s) $1, $2, %s
           FROM jsonb_populate_recordset(null::public.%I, $3) AS r
          ORDER BY %s
       ON CONFLICT (%s) DO UPDATE SET %s updated_at = now()
       RETURNING (xmax = 0) AS inserted
     )
     SELECT count(*)::int, count(*) FILTER (WHERE NOT inserted)::int FROM up',
    _target, v_cols,
    COALESCE(v_file_key, '1'),
    v_vals,
    _target,
    COALESCE(v_file_key, '1'),
    (SELECT string_agg(quote_ident(c), ', ') FROM unnest(v_key) AS c),
    v_update)
    INTO v_written, v_updated
    USING _project_id, v_plant, _rows;

  RETURN jsonb_build_object(
    'target', _target, 'rows_written', v_written, 'rows_updated', v_updated);
END; $fn$;

CREATE OR REPLACE FUNCTION public.ingest_row_provenance(
  p_project_id   uuid,
  p_user_id      uuid,
  p_target_table text
) RETURNS TABLE (
  natural_key        jsonb,
  has_provenance     boolean,
  source_row_number  integer,
  original_filename  text,
  content_sha256     text,
  uploaded_by_email  text,
  received_at        timestamptz,
  promoted_by_email  text,
  promoted_at        timestamptz
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_key  text[];
  v_expr text;
  v_sql  text;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_inputs');

  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'ingest_row_provenance: this read must name its reader'
      USING ERRCODE = 'null_value_not_allowed';
  END IF;
  IF NOT public.ingest_target_is_promotable(p_target_table) THEN
    RAISE EXCEPTION 'ingest_row_provenance: % is not a landable tier-2 table', p_target_table
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- LOCAL, so it belongs to this transaction and cannot leak onto the next caller
  -- of a pooled connection; and it is what makes `has_project_access` answer for
  -- the named reader rather than for whoever the connection last belonged to.
  PERFORM set_config('app.current_user_id', p_user_id::text, true);
  IF NOT public.has_project_access(p_project_id) THEN
    RAISE EXCEPTION 'ingest_row_provenance: % cannot read project %', p_user_id, p_project_id
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  v_key := public.ingest_target_natural_key(p_target_table);

  -- `jsonb_build_object('col', t.col, …)` over the key columns, quoted with %I so
  -- a column needing a quoted spelling cannot break the statement (§4 D99's class).
  SELECT string_agg(format('%L, t.%I', c, c), ', ' ORDER BY ord)
    INTO v_expr
    FROM unnest(v_key) WITH ORDINALITY AS k(c, ord);

  v_sql := format($q$
    SELECT jsonb_build_object(%s),
           (t.source_row_id IS NOT NULL),
           s.source_row_number,
           f.original_filename,
           f.content_sha256,
           up.email,
           f.received_at,
           ap.email,
           r.applied_at
      FROM public.%I t
      -- LEFT JOINs throughout: a row with no provenance must appear with NULLs and
      -- `has_provenance = false`, because the export's job is to list every row and
      -- say which ones cannot be traced. An inner join would silently drop them and
      -- the sheet would read as complete.
      LEFT JOIN public.ingest_staged_rows s ON s.id = t.source_row_id
      LEFT JOIN public.ingest_runs r        ON r.id = s.ingest_run_id
      LEFT JOIN public.ingest_files f       ON f.ingest_run_id = r.id
      LEFT JOIN public.approved_users up    ON up.id = f.uploaded_by
      LEFT JOIN public.approved_users ap    ON ap.id = r.applied_by_user_id
     WHERE t.project_id = $1
     ORDER BY 1
  $q$, v_expr, p_target_table);

  RETURN QUERY EXECUTE v_sql USING p_project_id;
END; $fn$;

CREATE OR REPLACE FUNCTION public.ingest_run_review(
  p_user_id uuid,
  p_run_id  uuid
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_project uuid;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);

  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'ingest_run_review: this read must name its reader'
      USING ERRCODE = 'null_value_not_allowed';
  END IF;

  -- LOCAL, so it cannot outlive this transaction on a pooled connection, and so
  -- `has_project_access` answers for the named reader.
  PERFORM set_config('app.current_user_id', p_user_id::text, true);

  SELECT r.project_id INTO v_project FROM public.ingest_runs r WHERE r.id = p_run_id;
  IF v_project IS NULL THEN
    RAISE EXCEPTION 'ingest_run_review: no run %', p_run_id
      USING ERRCODE = 'no_data_found';
  END IF;

  IF NOT public.has_project_access(v_project) THEN
    RAISE EXCEPTION 'ingest_run_review: % cannot read project %', p_user_id, v_project
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  RETURN jsonb_build_object(
    'run',  (SELECT to_jsonb(r) FROM public.ingest_runs r WHERE r.id = p_run_id),
    -- A run lands at most one file; a connector run lands none, and `null` says so.
    'file', (SELECT to_jsonb(f) FROM public.ingest_files f WHERE f.ingest_run_id = p_run_id),
    'rows', COALESCE(
              (SELECT jsonb_agg(to_jsonb(s) ORDER BY s.source_row_number)
                 FROM public.ingest_staged_rows s WHERE s.ingest_run_id = p_run_id),
              '[]'::jsonb)
  );
END; $fn$;

CREATE OR REPLACE FUNCTION public.ingest_value_chain(
  p_user_id       uuid,
  p_source_row_id uuid DEFAULT NULL,
  p_project_id    uuid DEFAULT NULL,
  p_target_table  text DEFAULT NULL
) RETURNS TABLE (
  has_provenance      boolean,
  project_id          uuid,
  target_table        text,
  source_kind         text,
  original_filename   text,
  content_sha256      text,
  byte_size           bigint,
  source_row_number   integer,
  raw                 jsonb,
  parsed              jsonb,
  findings            jsonb,
  diff_state          text,
  uploaded_by_name    text,
  uploaded_by_email   text,
  received_at         timestamptz,
  promoted_by_name    text,
  promoted_by_email   text,
  promoted_at         timestamptz,
  run_status          text,
  later_uploads       integer,
  latest_upload_at    timestamptz
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_project uuid;
  v_target  text;
  v_applied timestamptz;
  v_run     uuid;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_inputs');

  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'ingest_value_chain: this read must name its reader'
      USING ERRCODE = 'null_value_not_allowed';
  END IF;

  -- LOCAL — `true` — so it belongs to THIS transaction and cannot leak onto the
  -- next caller of a pooled connection. It is also what makes
  -- `has_project_access` answer for the named reader.
  PERFORM set_config('app.current_user_id', p_user_id::text, true);

  IF p_source_row_id IS NOT NULL THEN
    SELECT r.project_id, s.target_table, r.applied_at, r.id
      INTO v_project, v_target, v_applied, v_run
      FROM public.ingest_staged_rows s
      JOIN public.ingest_runs r ON r.id = s.ingest_run_id
     WHERE s.id = p_source_row_id;
    IF v_project IS NULL THEN
      RAISE EXCEPTION 'ingest_value_chain: no staged row %', p_source_row_id
        USING ERRCODE = 'no_data_found';
    END IF;
  ELSE
    IF p_project_id IS NULL OR p_target_table IS NULL THEN
      RAISE EXCEPTION 'ingest_value_chain: with no staged row, name the project and the target table'
        USING ERRCODE = 'null_value_not_allowed';
    END IF;
    -- Only this mode takes a table NAME from the caller, and it is checked
    -- against the set the promotion knows, so the parameter cannot name anything
    -- outside the landing path.
    IF NOT public.ingest_target_is_promotable(p_target_table) THEN
      RAISE EXCEPTION 'ingest_value_chain: % is not a landable tier-2 table', p_target_table
        USING ERRCODE = 'invalid_parameter_value';
    END IF;
    v_project := p_project_id;
    v_target  := p_target_table;
  END IF;

  IF NOT public.has_project_access(v_project) THEN
    RAISE EXCEPTION 'ingest_value_chain: % cannot read project %', p_user_id, v_project
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  RETURN QUERY
  SELECT
    (p_source_row_id IS NOT NULL),
    v_project,
    v_target,
    f.source_kind,
    f.original_filename,
    f.content_sha256,
    f.byte_size,
    s.source_row_number,
    s.raw,
    s.parsed,
    s.findings,
    s.diff_state,
    up.display_name,
    up.email,
    f.received_at,
    ap.display_name,
    ap.email,
    r.applied_at,
    r.status,
    -- FRESHNESS AS A COUNT, NOT A BOOLEAN. "Two later uploads of this dataset
    -- exist" is actionable where "stale" is not, and D70's rule is that an
    -- unknown must not be rendered as a known: with no provenance there is no
    -- `applied_at` to compare against, so EVERY applied run counts as later and
    -- the caller is told the provenance is unknown in the same breath.
    --
    -- `>=` WITH THE ROW'S OWN RUN EXCLUDED, NOT `>`, AND A REHEARSAL IS WHY.
    -- `applied_at` defaults to `now()`, which is TRANSACTION start time, so two
    -- promotions in one transaction carry the SAME timestamp and `>` counted
    -- neither as later than the other — `rehearsal/260` §4 failed on exactly
    -- that. Timestamp ties are therefore counted as later, deliberately: the
    -- error it admits is over-reporting a stale cell by the number of runs
    -- sharing an instant, and under-reporting staleness is the direction that
    -- misleads a reader about their own data.
    (SELECT count(*)::integer FROM public.ingest_runs r2
      WHERE r2.project_id = v_project
        AND r2.applied_at IS NOT NULL
        AND (v_applied IS NULL OR (r2.applied_at >= v_applied AND r2.id IS DISTINCT FROM v_run))
        AND EXISTS (SELECT 1 FROM public.ingest_staged_rows s2
                     WHERE s2.ingest_run_id = r2.id AND s2.target_table = v_target)),
    (SELECT max(r2.applied_at) FROM public.ingest_runs r2
      WHERE r2.project_id = v_project
        AND r2.applied_at IS NOT NULL
        AND EXISTS (SELECT 1 FROM public.ingest_staged_rows s2
                     WHERE s2.ingest_run_id = r2.id AND s2.target_table = v_target))
  -- LEFT JOIN from a one-row anchor so the no-provenance mode still returns its
  -- single row: an inner join on `ingest_staged_rows` would return NOTHING there,
  -- which is the failure this function's contract exists to rule out.
  FROM (SELECT 1) anchor
  LEFT JOIN public.ingest_staged_rows s ON s.id = p_source_row_id
  LEFT JOIN public.ingest_runs r ON r.id = s.ingest_run_id
  -- The file is reached through the RUN, not through the staged row: a run lands
  -- one file and the rows belong to the run, so there is one join key and no
  -- second copy of it — the reason `ingest_files` carries no `project_id`.
  LEFT JOIN public.ingest_files f ON f.ingest_run_id = r.id
  LEFT JOIN public.approved_users up ON up.id = f.uploaded_by
  LEFT JOIN public.approved_users ap ON ap.id = r.applied_by_user_id;
END; $fn$;

CREATE OR REPLACE FUNCTION public.list_api_keys(p_user_id uuid, p_user_email text)
RETURNS TABLE (
  id uuid, key_prefix text, org_id uuid, org_name text, name text, note text,
  scopes text[], project_ids uuid[], env text, status text,
  expires_at timestamptz, last_used_at timestamptz, revoked_at timestamptz,
  rotated_from uuid, created_at timestamptz, created_by_email text, principal text
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_org    uuid;
  v_manage boolean;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);

  PERFORM public.set_current_user_context(p_user_id, p_user_email);
  IF public.is_super_admin(p_user_id) THEN
    RETURN QUERY
    SELECT k.id, k.key_prefix, k.org_id, o.name, k.name, k.note, k.scopes, k.project_ids,
           k.env, k.status, k.expires_at, k.last_used_at, k.revoked_at, k.rotated_from,
           k.created_at, u.email, k.principal
    FROM public.api_keys k
    JOIN public.organizations o ON o.id = k.org_id
    LEFT JOIN public.approved_users u ON u.id = k.created_by
    ORDER BY k.created_at DESC;
    RETURN;
  END IF;
  SELECT c.org_id, c.can_manage INTO v_org, v_manage FROM public._api_key_caller(p_user_id, NULL) c;
  RETURN QUERY
  SELECT k.id, k.key_prefix, k.org_id, o.name, k.name, k.note, k.scopes, k.project_ids,
         k.env, k.status, k.expires_at, k.last_used_at, k.revoked_at, k.rotated_from,
         k.created_at, u.email, k.principal
  FROM public.api_keys k
  JOIN public.organizations o ON o.id = k.org_id
  LEFT JOIN public.approved_users u ON u.id = k.created_by
  WHERE k.org_id = v_org
    AND (v_manage OR (k.principal = 'personal' AND k.created_by = p_user_id))
  ORDER BY k.created_at DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_chat_messages(p_thread_id uuid, p_user_id uuid)
RETURNS SETOF public.chat_messages
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);

  PERFORM public._chat_assert_thread_owner(p_thread_id, p_user_id);
  RETURN QUERY SELECT * FROM public.chat_messages
   WHERE thread_id = p_thread_id ORDER BY seq ASC;
END; $$;

CREATE OR REPLACE FUNCTION public.list_chat_plans(p_thread_id uuid, p_user_id uuid)
RETURNS SETOF public.chat_plans
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);

  PERFORM public.expire_chat_plans(p_thread_id);
  RETURN QUERY SELECT * FROM public.chat_plans
   WHERE thread_id = p_thread_id AND user_id = p_user_id
   ORDER BY created_at DESC;
END; $$;

CREATE OR REPLACE FUNCTION public.list_my_organizations(p_user_id uuid DEFAULT NULL)
RETURNS TABLE(
  org_id uuid,
  name text,
  slug text,
  status text,
  org_role text,
  is_current boolean,
  joined_at timestamptz,
  access_period text,
  access_valid_until timestamptz,
  access_expired boolean,
  is_default boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := public.account_self_resolve(p_user_id);
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);

  RETURN QUERY
  SELECT o.id, o.name, o.slug, o.status, m.org_role,
         (o.id = au.organization_id),
         m.joined_at,
         o.access_period, o.access_valid_until,
         COALESCE(o.access_valid_until <= now(), false) AND au.role <> 'super_admin'::public.app_role,
         m.is_default
    FROM public.organization_members m
    JOIN public.organizations o ON o.id = m.org_id
    JOIN public.approved_users au ON au.id = m.user_id
   WHERE m.user_id = v_uid
   ORDER BY lower(o.name), o.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_projects(
  p_user_id uuid,
  p_user_email text
) RETURNS SETOF public.projects
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);

  -- Ensure RLS helper functions have context inside this call
  PERFORM public.set_current_user_context(p_user_id, p_user_email);

  RETURN QUERY
  SELECT p.*
  FROM public.projects p
  WHERE public.org_is_current_user_org(p.organization_id, p.organization)
  ORDER BY p.created_at DESC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.list_user_files(
  p_user_id    uuid,
  p_project_id uuid DEFAULT NULL
) RETURNS SETOF public.user_files
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, NULL);

  IF p_user_id IS NULL THEN RAISE EXCEPTION 'forbidden'; END IF;
  PERFORM public.sweep_expired_files(p_user_id);
  RETURN QUERY SELECT * FROM public.user_files
   WHERE user_id = p_user_id
     AND (p_project_id IS NULL OR project_id = p_project_id)
   ORDER BY created_at DESC;
END; $$;

CREATE OR REPLACE FUNCTION public.log_data_action(
  _actor_user_id uuid,
  _plane         text,
  _action        text,
  _target_type   text,
  _target_id     text,
  _before        jsonb DEFAULT NULL,
  _after         jsonb DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE new_id uuid;
BEGIN
  -- D309: bind caller assertions before the original operation.
  _actor_user_id := public.security_actor(_actor_user_id);

  IF _plane NOT IN ('data','access') THEN
    RAISE EXCEPTION 'log_data_action handles the data and access planes; % goes through log_admin_action', _plane
      USING ERRCODE = '22023';
  END IF;
  INSERT INTO public.audit_logs (plane, actor_user_id, action, target_type, target_id, before, after)
  VALUES (_plane, _actor_user_id, _action, _target_type, _target_id, _before, _after)
  RETURNING id INTO new_id;
  RETURN new_id;
END; $$;

CREATE OR REPLACE FUNCTION public.move_chat_thread(
  p_thread_id uuid, p_folder_id uuid, p_user_id uuid DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);

  PERFORM public._chat_assert_thread_owner(p_thread_id, p_user_id);
  IF p_folder_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.chat_folders f WHERE f.id = p_folder_id AND f.user_id = p_user_id
  ) THEN
    RAISE EXCEPTION 'folder % not found', p_folder_id;
  END IF;
  UPDATE public.chat_threads SET folder_id = p_folder_id WHERE id = p_thread_id;
END; $$;

CREATE OR REPLACE FUNCTION public.mrp_apply_staged_products(
  _run_id        uuid,
  _actor_user_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_run     public.ingest_runs%ROWTYPE;
  v_written integer;
  v_updated integer;
BEGIN
  -- D309: bind caller assertions before the original operation.
  _actor_user_id := public.security_actor(_actor_user_id);

  SELECT * INTO v_run FROM public.ingest_runs WHERE id = _run_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'mrp_apply_staged_products: no run %', _run_id USING ERRCODE = 'no_data_found';
  END IF;

  PERFORM public.assert_writer_may_act('mrp_apply_staged_products', v_run.project_id, _actor_user_id);

  WITH up AS (
    INSERT INTO public.products (project_id, product_id, name,
                                 source_system, source_external_id, source_synced_at)
      SELECT DISTINCT ON (COALESCE(s.sku, s.external_id))
             v_run.project_id, COALESCE(s.sku, s.external_id), s.name,
             'orbit-mrp', s.external_id, s.staged_at
        FROM public.ingest_staged_products s
       WHERE s.ingest_run_id = _run_id
         AND s.diff_state IS DISTINCT FROM 'removed_upstream'
         AND COALESCE(s.sku, s.external_id) IS NOT NULL
       ORDER BY COALESCE(s.sku, s.external_id), s.staged_at DESC
    ON CONFLICT (project_id, product_id) DO UPDATE
       SET name               = EXCLUDED.name,
           source_system      = EXCLUDED.source_system,
           source_external_id = EXCLUDED.source_external_id,
           source_synced_at   = EXCLUDED.source_synced_at,
           updated_at         = now()
    RETURNING (xmax = 0) AS inserted
  )
  SELECT count(*)::int, count(*) FILTER (WHERE NOT inserted)::int
    INTO v_written, v_updated FROM up;

  UPDATE public.ingest_runs
     SET status = 'applied', applied_at = now(), applied_by_user_id = _actor_user_id
   WHERE id = _run_id;

  RETURN jsonb_build_object(
    'run_id', _run_id, 'rows_promoted', v_written, 'rows_updated', v_updated);
END; $fn$;

CREATE OR REPLACE FUNCTION public.node_list_discover(p_project_id uuid, p_org text, p_actor uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  inserted_count integer := 0;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor := public.security_actor(p_actor);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_inputs');

  -- ATTRIBUTION, NOT AUTHORIZATION — and `dataPlaneAudit.test.ts` is what put this
  -- line here. The first draft of this function wrote a tier-3 table with no
  -- `app.current_user_id`, and the ratchet failed with the new name in the list:
  -- its audit rows would have said `actor_known: false`. `assert_writer_may_act` is
  -- the shared preamble three other writers already use (`20260917000005`): it
  -- refuses a NULL actor and sets the GUC LOCAL to this transaction, and it
  -- deliberately does NOT authorize — a role gate was written into it, found to
  -- refuse an organization admin on a live path, and removed, because
  -- `min_project_role` is D66's to make live and not each writer's to answer ad hoc.
  --
  -- So: this function names WHO, and nothing here decides WHETHER. See section 5's
  -- header for why the second half belongs to the caller.
  PERFORM public.assert_writer_may_act('node_list_discover', p_project_id, p_actor);

  WITH nodes AS (
    SELECT scd.plant_name, scd.from_location AS node_id
    FROM public.supply_chain_data scd
    WHERE scd.project_id = p_project_id
    UNION
    SELECT scd.plant_name, scd.to_location AS node_id
    FROM public.supply_chain_data scd
    WHERE scd.project_id = p_project_id
    UNION
    SELECT t.plant_name, t.from_location AS node_id
    FROM public.supply_chain_data_multi_tier t
    WHERE t.project_id = p_project_id
    UNION
    SELECT t.plant_name, t.to_location AS node_id
    FROM public.supply_chain_data_multi_tier t
    WHERE t.project_id = p_project_id
  ), dedup AS (
    SELECT node_id, MIN(plant_name) AS plant_name
    FROM nodes
    WHERE node_id IS NOT NULL AND btrim(node_id) <> ''
    GROUP BY node_id
  )
  INSERT INTO public.node_list (project_id, plant_name, node_id, organization, created_by)
  SELECT p_project_id, d.plant_name, d.node_id, p_org, p_actor
  FROM dedup d
  ON CONFLICT (project_id, node_id) DO NOTHING;

  GET DIAGNOSTICS inserted_count = ROW_COUNT;
  RETURN inserted_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.process_structure(
  p_project_id   uuid,
  _actor_user_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  k_code  constant text := 'process_structure@wp101.1';
  v_claim jsonb;
  v_run   uuid;
  v_res   jsonb;
  v_n     integer;
BEGIN
  -- D309: bind caller assertions before the original operation.
  _actor_user_id := public.security_actor(_actor_user_id);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_inputs');

  v_claim := public.analysis_get_or_start(p_project_id, 'process_structure', '{}'::jsonb, k_code, _actor_user_id);
  v_run := (v_claim ->> 'run_id')::uuid;

  IF (v_claim ->> 'cache_hit')::boolean IS NOT TRUE THEN
    IF (v_claim ->> 'claimed_by_other')::boolean IS TRUE THEN
      RETURN v_claim || jsonb_build_object('in_progress', true, 'reachable', '{}'::jsonb);
    END IF;

    WITH RECURSIVE
    arcs AS (
      SELECT DISTINCT btrim(from_location) AS a, btrim(to_location) AS b
        FROM public.supply_chain_data_multi_tier
       WHERE project_id = p_project_id
         AND COALESCE(btrim(from_location), '') <> '' AND COALESCE(btrim(to_location), '') <> ''
    ),
    starts AS (
      SELECT DISTINCT btrim(from_location) AS s
        FROM public.supply_chain_data_multi_tier
       WHERE project_id = p_project_id AND level = 1 AND COALESCE(btrim(from_location), '') <> ''
      UNION
      SELECT DISTINCT btrim(to_location)
        FROM public.supply_chain_data_multi_tier
       WHERE project_id = p_project_id AND level = 1 AND data_source <> 'outbound'
         AND COALESCE(btrim(to_location), '') <> ''
    ),
    down(s, n, path) AS (
      SELECT s, s, ARRAY[s] FROM starts
      UNION ALL
      SELECT d.s, a.b, d.path || a.b FROM down d JOIN arcs a ON a.a = d.n
       WHERE a.b <> ALL (d.path) AND array_length(d.path, 1) < 64
    ),
    up(s, n, path) AS (
      SELECT s, s, ARRAY[s] FROM starts
      UNION ALL
      SELECT u.s, a.a, u.path || a.a FROM up u JOIN arcs a ON a.b = u.n
       WHERE a.a <> ALL (u.path) AND array_length(u.path, 1) < 64
    ),
    per AS (
      SELECT st.s,
             (SELECT COALESCE(jsonb_agg(DISTINCT d.n ORDER BY d.n), '[]'::jsonb) FROM down d WHERE d.s = st.s AND d.n <> st.s) AS downstream,
             (SELECT COALESCE(jsonb_agg(DISTINCT u.n ORDER BY u.n), '[]'::jsonb) FROM up u WHERE u.s = st.s AND u.n <> st.s) AS upstream
        FROM starts st
    )
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
             'entity_type', 'node', 'entity_id', per.s,
             'metrics', jsonb_build_object('downstream', per.downstream, 'upstream', per.upstream))), '[]'::jsonb),
           count(*)
      INTO v_res, v_n
      FROM per;

    PERFORM public.analysis_complete_run(v_run, v_res,
      jsonb_build_object('nodes', v_n), '[]'::jsonb, _actor_user_id);
  END IF;

  RETURN v_claim || jsonb_build_object(
    'reachable', COALESCE((
      SELECT jsonb_object_agg(ar.entity_id, ar.metrics)
        FROM public.analysis_results ar
       WHERE ar.run_id = v_run AND ar.entity_type = 'node'), '{}'::jsonb));
END;
$fn$;

CREATE OR REPLACE FUNCTION public.project_creation_right(_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role     text;
  v_org_id   uuid;
  v_org_name text;
  v_org_role text;
  v_allowed  boolean;
  v_by       text;
BEGIN
  -- D309: bind caller assertions before the original operation.
  _user_id := public.security_actor(_user_id);

  SELECT au.role::text, au.organization_id INTO v_role, v_org_id
    FROM public.approved_users au WHERE au.id = _user_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('allowed', false, 'decided_by', 'no_account', 'account_role', NULL,
      'organization_id', NULL, 'organization_name', NULL, 'org_role', NULL);
  END IF;

  SELECT o.name INTO v_org_name FROM public.organizations o WHERE o.id = v_org_id;
  SELECT m.org_role INTO v_org_role FROM public.organization_members m
   WHERE m.user_id = _user_id AND m.org_id = v_org_id;

  IF v_role = 'super_admin' THEN
    v_allowed := true;  v_by := 'super_admin';
  ELSIF v_role IN ('admin', 'modeler') THEN
    v_allowed := true;  v_by := 'account_role';
  ELSIF v_org_role IN ('owner', 'admin') THEN
    v_allowed := true;  v_by := 'organization_role';
  ELSE
    v_allowed := false; v_by := 'none';
  END IF;

  RETURN jsonb_build_object('allowed', v_allowed, 'decided_by', v_by, 'account_role', v_role,
    'organization_id', v_org_id, 'organization_name', v_org_name, 'org_role', v_org_role);
END; $$;

CREATE OR REPLACE FUNCTION public.project_freshness(p_project_id uuid, p_user_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_hash     text;
  v_tables   jsonb := '{}'::jsonb;
  v_dsv      jsonb;
  v_runs     jsonb;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, NULL);

  -- The reader is NAMED, because the browser calls as `anon` and no session says who it is
  -- (D155). The same asserted-user model every upload RPC uses (D28): the database refuses
  -- a project that user cannot reach, which is a constraint and not proof of identity.
  -- A NULL name changes nothing, so a caller whose transaction already set the actor
  -- (the rehearsals, a service-side caller) is not blanked by omitting it.
  IF p_user_id IS NOT NULL THEN
    PERFORM set_config('app.current_user_id', p_user_id::text, true);
  END IF;

  IF NOT public.has_project_access(p_project_id) THEN
    RAISE EXCEPTION 'project_freshness: no access to project %', p_project_id
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  v_hash := public.current_graph_hash(p_project_id);

  -- One statement per derived table, each classifying its own rows against the
  -- single hash read above. `filter` rather than three scans.
  SELECT jsonb_object_agg(t, counts) INTO v_tables FROM (
    SELECT 'network_nodes' AS t, jsonb_build_object(
             'rows',    count(*),
             'fresh',   count(*) FILTER (WHERE computed_from_hash = v_hash),
             'stale',   count(*) FILTER (WHERE computed_from_hash IS NOT NULL
                                           AND computed_from_hash <> v_hash),
             'unknown', count(*) FILTER (WHERE computed_from_hash IS NULL),
             'computed_at', max(computed_at)) AS counts
      FROM public.network_nodes WHERE project_id = p_project_id
    UNION ALL
    SELECT 'node_list', jsonb_build_object(
             'rows', count(*),
             'fresh',   count(*) FILTER (WHERE computed_from_hash = v_hash),
             'stale',   count(*) FILTER (WHERE computed_from_hash IS NOT NULL
                                           AND computed_from_hash <> v_hash),
             'unknown', count(*) FILTER (WHERE computed_from_hash IS NULL),
             'computed_at', max(computed_at))
      FROM public.node_list WHERE project_id = p_project_id
    UNION ALL
    SELECT 'supply_chain_data', jsonb_build_object(
             'rows', count(*),
             'fresh',   count(*) FILTER (WHERE computed_from_hash = v_hash),
             'stale',   count(*) FILTER (WHERE computed_from_hash IS NOT NULL
                                           AND computed_from_hash <> v_hash),
             'unknown', count(*) FILTER (WHERE computed_from_hash IS NULL),
             'computed_at', max(computed_at))
      FROM public.supply_chain_data WHERE project_id = p_project_id
    UNION ALL
    SELECT 'network_summary', jsonb_build_object(
             'rows', count(*),
             'fresh',   count(*) FILTER (WHERE computed_from_hash = v_hash),
             'stale',   count(*) FILTER (WHERE computed_from_hash IS NOT NULL
                                           AND computed_from_hash <> v_hash),
             'unknown', count(*) FILTER (WHERE computed_from_hash IS NULL),
             'computed_at', max(computed_at))
      FROM public.network_summary WHERE project_id = p_project_id
    UNION ALL
    -- The one that is NOT a display concern. §11: the engine reads overrides,
    -- not the grid, so a stale seeded override changes what a simulation
    -- computes. A TYPED override (`seeded_from_hash IS NULL`) is a decision and
    -- is reported as `typed` rather than folded into `unknown` — it is not
    -- missing provenance, it has none to miss.
    SELECT 'policy_overrides', jsonb_build_object(
             'rows', count(*),
             'fresh',   count(*) FILTER (WHERE seeded_from_hash = v_hash),
             'stale',   count(*) FILTER (WHERE seeded_from_hash IS NOT NULL
                                           AND seeded_from_hash <> v_hash),
             'unknown', 0,
             'typed',   count(*) FILTER (WHERE seeded_from_hash IS NULL),
             'computed_at', max(updated_at))
      FROM public.policy_overrides WHERE project_id = p_project_id
  ) q;

  SELECT to_jsonb(d) - 'snapshot' INTO v_dsv
    FROM public.dataset_versions d
   WHERE d.project_id = p_project_id
   ORDER BY d.created_at DESC LIMIT 1;

  SELECT jsonb_agg(jsonb_build_object(
           'analysis_kind', r.analysis_kind,
           'run_id', r.id,
           'status', r.status,
           'code_version', r.code_version,
           'finished_at', r.finished_at,
           'freshness', public.freshness_of(r.input_hash, p_project_id),
           'warnings', r.warnings)
         ORDER BY r.started_at DESC) INTO v_runs
    FROM (SELECT DISTINCT ON (analysis_kind) *
            FROM public.analysis_runs
           WHERE project_id = p_project_id AND status = 'succeeded'
           ORDER BY analysis_kind, started_at DESC) r;

  RETURN jsonb_build_object(
    'project_id',      p_project_id,
    'graph_hash',      v_hash,
    'graph_hash_short', left(COALESCE(v_hash, ''), 12),
    'dataset_version', v_dsv,
    'tables',          COALESCE(v_tables, '{}'::jsonb),
    'latest_runs',     COALESCE(v_runs, '[]'::jsonb),
    'measured_at',     now());
END; $fn$;

CREATE OR REPLACE FUNCTION public.rebuild_node_list(p_project_id uuid, p_user_id uuid, p_user_email text)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_org text;
  v_org_id uuid;
  v_modeler uuid;
  v_role text;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_inputs');

  PERFORM public.set_current_user_context(p_user_id, p_user_email);

  SELECT organization, organization_id, modeler_id INTO v_org, v_org_id, v_modeler
  FROM public.projects
  WHERE id = p_project_id;

  IF v_org IS NULL THEN RAISE EXCEPTION 'project_not_found'; END IF;

  SELECT user_role INTO v_role FROM public.get_current_approved_user() LIMIT 1;
  IF NOT public.org_is_current_user_org(v_org_id, v_org) OR NOT (v_modeler = public.get_current_user_id() OR v_role IN ('admin', 'super_admin')) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  RETURN public.node_list_discover(p_project_id, v_org, public.get_current_user_id());
END;
$$;

CREATE OR REPLACE FUNCTION public.rebuild_supply_chain_lanes(
  p_project_id    uuid,
  p_actor_user_id uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_org      text;
  v_modeler  uuid;
  v_actor    uuid;
  v_email    text;
  v_exists   boolean;
  v_scd      integer := 0;
  v_mt       integer := 0;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_user_id := public.security_actor(p_actor_user_id);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_inputs');

  SELECT true, p.organization, p.modeler_id
    INTO v_exists, v_org, v_modeler
    FROM public.projects p
   WHERE p.id = p_project_id;

  -- The project is gone, or was never there. This runs from a statement trigger
  -- on four tables that CASCADE from `projects`, so a project deletion fires it
  -- with the parent row already removed — and a rebuild there would re-insert
  -- rows into two tables that carry NO cascade of their own (`node_list` and
  -- `supply_chain_data_multi_tier`), which is orphan rows created by a repair.
  IF NOT COALESCE(v_exists, false) THEN
    RETURN jsonb_build_object('skipped', 'no_project');
  END IF;

  -- ATTRIBUTION, NOT AUTHORIZATION. The caller's actor, else whoever the
  -- enclosing statement already named, else the project owner — a tier-3 write
  -- must name somebody (`audit-actor`, G4), and a trigger has no caller to ask.
  v_actor := COALESCE(p_actor_user_id, public.get_current_user_id(), v_modeler);

  SELECT au.email INTO v_email
    FROM public.approved_users au WHERE au.id = v_actor LIMIT 1;

  IF v_actor IS NOT NULL THEN
    PERFORM public.set_current_user_context(v_actor, COALESCE(v_email, ''));
  END IF;
  PERFORM public.assert_writer_may_act('rebuild_supply_chain_lanes', p_project_id, v_actor);

  DELETE FROM public.supply_chain_data            WHERE project_id = p_project_id;
  DELETE FROM public.supply_chain_data_multi_tier WHERE project_id = p_project_id;

  -- ONE insert per table rather than four. Every lane statement fires
  -- `auto_refresh_node_list_on_lane_change`, so the old ten-statement build paid
  -- for ten full re-classifications of the graph per combine — and after this
  -- package a source edit triggers a combine, so that cost is now paid on
  -- uploads too. Four statements instead of ten is not a micro-optimisation
  -- here; it is what makes the trigger in section 5 affordable.
  WITH RECURSIVE
  -- D150 — `rate_to_weekly` at EVERY read, which the deployed writer never had.
  -- WP 0.2 closed D2 in the edge function and the RPC kept all eight raw reads.
  -- `normalize-at-promotion` (I3) makes this exactly identity (×7/7) for any row
  -- promoted since WP 3.3 and load-bearing for every row that predates it, which
  -- is the same reason `sc_nodes` still converts.
  outb AS (
    SELECT o.plant_name, o.product_id, o.customer_id,
           public.rate_to_weekly(COALESCE(o.volume, 0), o.time_unit) AS wk
      FROM public.outbound_logistics o
     WHERE o.project_id = p_project_id
       AND COALESCE(btrim(o.product_id), '') <> ''
  ),
  demand AS (
    SELECT plant_name, product_id, SUM(wk) AS wk
      FROM outb GROUP BY plant_name, product_id
  ),
  -- Both BOM tables, normalized to (parent ← child, rate, depth). Unconditional,
  -- exactly as the RPC has always read them: `projects.bom_level` gates which one
  -- a project UPLOADS, and branching on it is what left three projects with a
  -- permanently empty Process page (D130). A project holding rows in both holds
  -- two real uploads and both are built.
  bom_edges AS (
    -- D129 / D141 — A PARENTLESS BOM ROW'S PARENT IS THE FINISHED PRODUCT.
    --
    -- `bom_multi_level.higher_level_component_id` is "empty at the top of the
    -- tree, where the parent is the finished product itself" — its own sidecar
    -- says so — and the table names NO product, so the BOM is plant-scoped and
    -- "the finished product" means every product that plant ships. With one
    -- product it is unambiguous; with several the row genuinely feeds each of
    -- them, and each root carries its OWN demand, so nothing is double counted.
    -- A plant that ships no product yields NULL here and the edge is dropped by
    -- the walk — which is the same answer as "reaches no finished product".
    --
    -- The old writers: the edge function looked up `plant::<blank>`, found no
    -- parent demand and skipped the row in the EMIT loop, so a count of `''`
    -- could never see it (D129). The RPC wrote `COALESCE(…, 'ROOT')` into both
    -- `to_location` and `path_root` — a node no CSV contains, no user can
    -- explain, and every centrality on the page would be computed over (D141).
    SELECT b.plant_name,
           COALESCE(NULLIF(btrim(b.higher_level_component_id), ''), d.product_id) AS parent_id,
           btrim(b.material_id)                       AS child_id,
           COALESCE(b.consumption_rate, 0)            AS rate,
           b.level                                    AS depth
      FROM public.bom_multi_level b
      LEFT JOIN demand d
        ON d.plant_name = b.plant_name
       AND NULLIF(btrim(b.higher_level_component_id), '') IS NULL
     WHERE b.project_id = p_project_id
       AND COALESCE(btrim(b.material_id), '') <> ''
       -- §4 D171 — A PARENTLESS ROW WHOSE CHILD IS ITSELF A PRODUCT IS THE
       -- PRODUCT'S OWN ROOT ROW, NOT A COMPONENT EDGE. D129's rule ("the
       -- parent is every product the plant ships") is for components at the
       -- top of the tree; applied to a row that NAMES a product as the child
       -- it fabricates parent = every OTHER product (P1→P2) and parent =
       -- itself (P1→P1), which typed every finished product `subassembly`
       -- and duplicated every real lane once per fabricated path root. The
       -- engine's flatten has always dropped blank-parent rows outright
       -- (datamap._flatten_multi_level_bom, roots-never-children), so before
       -- this line the two halves disagreed about the same uploaded file.
       -- "Is a product" is asked of both places a product can be declared:
       -- the item master, and the outbound lanes (`demand` covers a shipped
       -- product with no master row).
       AND NOT (NULLIF(btrim(b.higher_level_component_id), '') IS NULL
                AND (EXISTS (SELECT 1 FROM public.products pr
                              WHERE pr.project_id = p_project_id
                                AND btrim(pr.product_id) = btrim(b.material_id))
                     OR EXISTS (SELECT 1 FROM demand dd
                                 WHERE dd.plant_name = b.plant_name
                                   AND dd.product_id = btrim(b.material_id))))
    UNION ALL
    SELECT s.plant_name, btrim(s.product_id), btrim(s.material_id),
           COALESCE(s.consumption_rate, 0), 1
      FROM public.bom_single_level s
     WHERE s.project_id = p_project_id
       AND COALESCE(btrim(s.material_id), '') <> ''
       AND COALESCE(btrim(s.product_id), '')  <> ''
  ),
  -- THE DEMAND WALK, ported from `combine-project/index.ts`. A finished product's
  -- weekly demand propagates down the tree, multiplied by each edge's consumption
  -- rate, and every (node, root) pair sums the contributions of every path.
  --
  -- RECURSIVE and not a loop over `level`: a level-ordered loop is only correct if
  -- `level` is a topological order of the tree, and D140 is the finding that
  -- nobody may assume anything about that column. `path` is the cycle guard — a
  -- BOM that contains a cycle is bad data, not a reason to hang a migration — and
  -- the 64-step cap bounds a tree whose depth is data.
  walk AS (
    SELECT d.plant_name, d.product_id AS node_id, d.product_id AS root_id,
           d.wk AS qty, ARRAY[d.product_id] AS path
      FROM demand d
     WHERE d.wk IS NOT NULL
    UNION ALL
    SELECT e.plant_name, e.child_id, w.root_id, w.qty * e.rate, w.path || e.child_id
      FROM walk w
      JOIN bom_edges e
        ON e.plant_name = w.plant_name
       AND e.parent_id  = w.node_id
     WHERE e.child_id <> ALL (w.path)
       AND array_length(w.path, 1) < 64
  ),
  node_demand AS (
    SELECT plant_name, node_id, root_id, SUM(qty) AS qty
      FROM walk GROUP BY plant_name, node_id, root_id
  ),
  material_demand AS (
    SELECT plant_name, node_id, SUM(qty) AS qty
      FROM node_demand GROUP BY plant_name, node_id
  ),
  inb AS (
    SELECT i.plant_name, i.supplier_id, i.material_id,
           public.rate_to_weekly(COALESCE(i.volume, 0), i.time_unit) AS wk
      FROM public.inbound_logistics i
     WHERE i.project_id = p_project_id
       AND COALESCE(btrim(i.supplier_id), '') <> ''
       AND COALESCE(btrim(i.material_id), '') <> ''
  ),
  inb_total AS (
    SELECT plant_name, material_id, SUM(wk) AS wk
      FROM inb GROUP BY plant_name, material_id
  ),
  -- A PURCHASED material — one the plant buys rather than builds. This is what
  -- makes the flat lane the product-level graph: its bom rows run from the things
  -- a supplier delivers to the things a customer buys.
  purchased AS (
    SELECT DISTINCT plant_name, material_id FROM inb
  ),
  flat AS (
    SELECT o.plant_name, 'outbound'::text AS data_source,
           o.product_id AS from_location, o.customer_id AS to_location,
           o.wk AS rate,
           -- `volumeShare`, which is what this column's sidecar has always said
           -- it is. The RPC wrote a literal 1.0 on this lane and the edge
           -- function wrote the share; D140's class, settled toward the contract.
           CASE WHEN dm.wk > 0 THEN o.wk / dm.wk ELSE 1.0 END AS sourcing_ratio,
           o.wk AS weighted
      FROM outb o
      JOIN demand dm ON dm.plant_name = o.plant_name AND dm.product_id = o.product_id
     WHERE COALESCE(btrim(o.customer_id), '') <> ''
    UNION ALL
    SELECT nd.plant_name, 'bom',
           nd.node_id, nd.root_id,
           -- D136 — the EFFECTIVE consumption rate, where the multi-level path
           -- wrote a literal 0 and the single-level path wrote the real number.
           CASE WHEN dm.wk > 0 THEN nd.qty / dm.wk ELSE 0 END,
           1.0,
           nd.qty
      FROM node_demand nd
      JOIN purchased p  ON p.plant_name  = nd.plant_name AND p.material_id = nd.node_id
      JOIN demand    dm ON dm.plant_name = nd.plant_name AND dm.product_id = nd.root_id
     WHERE nd.qty > 0
       AND nd.node_id <> nd.root_id
    UNION ALL
    SELECT i.plant_name, 'inbound',
           i.supplier_id, i.material_id,
           i.wk,
           CASE WHEN t.wk > 0 THEN i.wk / t.wk ELSE 1.0 END,
           -- The MATERIAL's demand times this supplier's share of it. The RPC
           -- multiplied the plant's total outbound volume by the share instead,
           -- which is a number about products standing in for one about a
           -- material.
           COALESCE(md.qty, 0) * CASE WHEN t.wk > 0 THEN i.wk / t.wk ELSE 1.0 END
      FROM inb i
      JOIN inb_total t ON t.plant_name = i.plant_name AND t.material_id = i.material_id
      LEFT JOIN material_demand md
             ON md.plant_name = i.plant_name AND md.node_id = i.material_id
  )
  INSERT INTO public.supply_chain_data (
    project_id, plant_name, data_source, from_location, to_location,
    material_consumption_rate, sourcing_ratio, weighted, uploaded_by, organization)
  SELECT p_project_id, f.plant_name, f.data_source, f.from_location, f.to_location,
         f.rate, f.sourcing_ratio, f.weighted, v_actor, v_org
    FROM flat f
   WHERE COALESCE(btrim(f.from_location), '') <> ''
     AND COALESCE(btrim(f.to_location), '')   <> '';

  GET DIAGNOSTICS v_scd = ROW_COUNT;

  -- ── the deep lane ───────────────────────────────────────────────────────
  WITH RECURSIVE
  outb AS (
    SELECT o.plant_name, o.product_id, o.customer_id,
           public.rate_to_weekly(COALESCE(o.volume, 0), o.time_unit) AS wk
      FROM public.outbound_logistics o
     WHERE o.project_id = p_project_id
       AND COALESCE(btrim(o.product_id), '') <> ''
  ),
  demand AS (
    SELECT plant_name, product_id, SUM(wk) AS wk
      FROM outb GROUP BY plant_name, product_id
  ),
  bom_edges AS (
    SELECT b.plant_name,
           COALESCE(NULLIF(btrim(b.higher_level_component_id), ''), d.product_id) AS parent_id,
           btrim(b.material_id)            AS child_id,
           COALESCE(b.consumption_rate, 0) AS rate,
           -- D140 IN ONE LINE. The RPC wrote a literal 2 here and never read
           -- `b.level`, so `Project AA - ver3`'s four-level 396-row BOM landed
           -- entirely at level 2 and the page rendered 260 materials and 66
           -- products as one flat column labelled `material level 2`.
           b.level AS depth
      FROM public.bom_multi_level b
      LEFT JOIN demand d
        ON d.plant_name = b.plant_name
       AND NULLIF(btrim(b.higher_level_component_id), '') IS NULL
     WHERE b.project_id = p_project_id
       AND COALESCE(btrim(b.material_id), '') <> ''
       -- §4 D171 — A PARENTLESS ROW WHOSE CHILD IS ITSELF A PRODUCT IS THE
       -- PRODUCT'S OWN ROOT ROW, NOT A COMPONENT EDGE. D129's rule ("the
       -- parent is every product the plant ships") is for components at the
       -- top of the tree; applied to a row that NAMES a product as the child
       -- it fabricates parent = every OTHER product (P1→P2) and parent =
       -- itself (P1→P1), which typed every finished product `subassembly`
       -- and duplicated every real lane once per fabricated path root. The
       -- engine's flatten has always dropped blank-parent rows outright
       -- (datamap._flatten_multi_level_bom, roots-never-children), so before
       -- this line the two halves disagreed about the same uploaded file.
       -- "Is a product" is asked of both places a product can be declared:
       -- the item master, and the outbound lanes (`demand` covers a shipped
       -- product with no master row).
       AND NOT (NULLIF(btrim(b.higher_level_component_id), '') IS NULL
                AND (EXISTS (SELECT 1 FROM public.products pr
                              WHERE pr.project_id = p_project_id
                                AND btrim(pr.product_id) = btrim(b.material_id))
                     OR EXISTS (SELECT 1 FROM demand dd
                                 WHERE dd.plant_name = b.plant_name
                                   AND dd.product_id = btrim(b.material_id))))
    UNION ALL
    -- D130 — the single-level half of the deep lane, which never existed. A
    -- single-level BOM is a real two-level tree and the Process page can draw it.
    SELECT s.plant_name, btrim(s.product_id), btrim(s.material_id),
           COALESCE(s.consumption_rate, 0), 1
      FROM public.bom_single_level s
     WHERE s.project_id = p_project_id
       AND COALESCE(btrim(s.material_id), '') <> ''
       AND COALESCE(btrim(s.product_id), '')  <> ''
  ),
  walk AS (
    SELECT d.plant_name, d.product_id AS node_id, d.product_id AS root_id,
           d.wk AS qty, ARRAY[d.product_id] AS path
      FROM demand d
     WHERE d.wk IS NOT NULL
    UNION ALL
    SELECT e.plant_name, e.child_id, w.root_id, w.qty * e.rate, w.path || e.child_id
      FROM walk w
      JOIN bom_edges e
        ON e.plant_name = w.plant_name AND e.parent_id = w.node_id
     WHERE e.child_id <> ALL (w.path)
       AND array_length(w.path, 1) < 64
  ),
  node_demand AS (
    SELECT plant_name, node_id, root_id, SUM(qty) AS qty
      FROM walk GROUP BY plant_name, node_id, root_id
  ),
  material_demand AS (
    SELECT plant_name, node_id, SUM(qty) AS qty
      FROM node_demand GROUP BY plant_name, node_id
  ),
  inb AS (
    SELECT i.plant_name, i.supplier_id, i.material_id,
           public.rate_to_weekly(COALESCE(i.volume, 0), i.time_unit) AS wk
      FROM public.inbound_logistics i
     WHERE i.project_id = p_project_id
       AND COALESCE(btrim(i.supplier_id), '') <> ''
       AND COALESCE(btrim(i.material_id), '') <> ''
  ),
  inb_total AS (
    SELECT plant_name, material_id, SUM(wk) AS wk
      FROM inb GROUP BY plant_name, material_id
  ),
  deep AS (
    -- Outbound: the edge's upstream end is the finished product, and a finished
    -- product sits at BOM depth 0. That is a fact the tree states, not D134's
    -- substitution: NULL below means "this node is in no BOM", and a product is
    -- the root of one by definition.
    SELECT o.plant_name, 'outbound'::text AS data_source,
           o.product_id AS from_location, o.customer_id AS to_location,
           0::integer AS bom_depth, o.product_id AS path_root,
           o.wk AS rate,
           CASE WHEN dm.wk > 0 THEN o.wk / dm.wk ELSE 1.0 END AS sourcing_ratio,
           o.wk AS weighted
      FROM outb o
      JOIN demand dm ON dm.plant_name = o.plant_name AND dm.product_id = o.product_id
     WHERE COALESCE(btrim(o.customer_id), '') <> ''
    UNION ALL
    -- One row per BOM EDGE per ROOT PRODUCT, at the BOM's own depth.
    --
    -- `weighted` is THIS EDGE's contribution — the parent's demand for that root
    -- times this edge's rate — and not the child's total demand. The edge
    -- function wrote the child's total on every one of its parent edges, so a
    -- material used by two assemblies had its whole requirement counted twice.
    --
    -- LEFT JOIN, deliberately: a BOM subtree that reaches no finished product is
    -- still part of the tree this lane exists to draw. It arrives with a NULL
    -- `path_root` and a zero flow, which is what "we hold this structure and no
    -- demand reaches it" looks like — where an inner join would delete it and
    -- leave the Process page shorter than the CSV, with nothing to say why. It is
    -- also the only reading that does not regress a project holding a BOM and no
    -- outbound rows, which the RPC used to draw (flat, at level 2) and this would
    -- otherwise blank.
    SELECT e.plant_name, 'bom',
           e.child_id, e.parent_id,
           e.depth, nd.root_id,
           e.rate,
           1.0,
           COALESCE(nd.qty, 0) * e.rate
      FROM bom_edges e
      LEFT JOIN node_demand nd
        ON nd.plant_name = e.plant_name AND nd.node_id = e.parent_id
     WHERE e.parent_id IS NOT NULL
    UNION ALL
    -- Inbound: a supplier sits one step upstream of the material it feeds, so its
    -- depth is that material's depth PLUS ONE — from `node_bom_depth`, the one
    -- rule, and NULL when the material is in no BOM.
    --
    -- The RPC wrote `GREATEST(1, COALESCE(max_level, 0) + 1)`, whose two
    -- substitutions are the whole of the "two suppliers from one upload, four
    -- levels apart" §15 measured: a material absent from the BOM landed at 1,
    -- which the ladder calls a material, and one at depth 4 landed at 5.
    SELECT i.plant_name, 'inbound',
           i.supplier_id, i.material_id,
           public.node_bom_depth(p_project_id, i.material_id) + 1,
           i.material_id,
           i.wk,
           CASE WHEN t.wk > 0 THEN i.wk / t.wk ELSE 1.0 END,
           COALESCE(md.qty, 0) * CASE WHEN t.wk > 0 THEN i.wk / t.wk ELSE 1.0 END
      FROM inb i
      JOIN inb_total t ON t.plant_name = i.plant_name AND t.material_id = i.material_id
      LEFT JOIN material_demand md
             ON md.plant_name = i.plant_name AND md.node_id = i.material_id
  )
  INSERT INTO public.supply_chain_data_multi_tier (
    project_id, plant_name, data_source, from_location, to_location,
    level, bom_depth, path_root, material_consumption_rate, sourcing_ratio, weighted,
    uploaded_by, organization)
  SELECT p_project_id, d.plant_name, d.data_source, d.from_location, d.to_location,
         -- `level` is the deprecated ALIAS: the same value, NULLs included.
         d.bom_depth, d.bom_depth, d.path_root, d.rate, d.sourcing_ratio, d.weighted,
         v_actor, v_org
    FROM deep d
   WHERE COALESCE(btrim(d.from_location), '') <> ''
     AND COALESCE(btrim(d.to_location), '')   <> '';

  GET DIAGNOSTICS v_mt = ROW_COUNT;

  RETURN jsonb_build_object(
    'project_id',        p_project_id,
    'actor',             v_actor,
    'supply_chain_data', v_scd,
    'multi_tier',        v_mt);
END; $fn$;

CREATE OR REPLACE FUNCTION public.record_chat_ui_event(
  p_kind       text,
  p_user_id    uuid DEFAULT NULL,
  p_project_id uuid DEFAULT NULL,
  p_thread_id  text DEFAULT NULL,
  p_payload    jsonb DEFAULT '{}'::jsonb
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_payload jsonb := COALESCE(p_payload, '{}'::jsonb);
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_inputs');

  IF p_kind NOT IN ('mode.changed','suggestion.clicked') THEN
    RAISE EXCEPTION 'unsupported client event kind %', p_kind;
  END IF;
  IF length(v_payload::text) > 2000 THEN v_payload := '{}'::jsonb; END IF;
  INSERT INTO public.ai_chat_events (event_kind, user_id, project_id, thread_id, payload)
  VALUES (p_kind, p_user_id, p_project_id, left(p_thread_id, 120), v_payload);
END; $$;

CREATE OR REPLACE FUNCTION public.record_export(
  _actor_user_id uuid,
  _project_id    uuid,
  _export_kind   text,
  _row_count     integer DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caps    jsonb;
  v_allowed boolean;
  v_id      uuid;
BEGIN
  -- D309: bind caller assertions before the original operation.
  _actor_user_id := public.security_actor(_actor_user_id);
  PERFORM public.security_assert_project(_project_id, 'export');

  -- A missing actor is a CALLER BUG, not a refusal, so this one does raise: there
  -- is nobody to attribute the row to and recording it would be a lie.
  IF _actor_user_id IS NULL THEN
    RAISE EXCEPTION 'an export must name its actor' USING ERRCODE = '22023';
  END IF;

  v_caps := CASE
    WHEN _project_id IS NULL THEN public.capabilities_for_user(_actor_user_id)
    ELSE public.capabilities_for_user(_actor_user_id, _project_id)
  END;
  v_allowed := COALESCE((v_caps -> 'features' ->> 'export')::boolean, false);

  v_id := public.log_data_action(
    _actor_user_id, 'access',
    CASE WHEN v_allowed THEN 'export.allowed' ELSE 'export.refused' END,
    'project', _project_id::text, NULL,
    jsonb_build_object('kind', _export_kind, 'row_count', _row_count,
                       'allowed', v_allowed));

  RETURN jsonb_build_object(
    'allowed',  v_allowed,
    'audit_id', v_id,
    'reason',   CASE WHEN v_allowed THEN NULL
                     ELSE 'the "export" capability is not granted for this user on this project' END);
END; $$;

CREATE OR REPLACE FUNCTION public.record_external_evidence(
  p_project_id   uuid,
  p_source_id    text,
  p_url_or_ref   text,
  p_content_hash text,
  p_confidence   numeric,
  p_triple       jsonb,
  p_lei          text DEFAULT NULL,
  _actor_user_id uuid DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_id uuid;
BEGIN
  -- D309: bind caller assertions before the original operation.
  _actor_user_id := public.security_actor(_actor_user_id);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_inputs');

  IF _actor_user_id IS NOT NULL THEN
    PERFORM set_config('app.current_user_id', _actor_user_id::text, true);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.projects WHERE id = p_project_id) THEN
    RAISE EXCEPTION 'project % not found', p_project_id;
  END IF;
  IF p_triple IS NULL OR jsonb_typeof(p_triple) <> 'object' THEN
    RAISE EXCEPTION 'triple must be a JSON object';
  END IF;

  SELECT id INTO v_id FROM public.external_evidence
   WHERE project_id = p_project_id
     AND source_id = p_source_id
     AND content_hash = p_content_hash
     AND md5(triple::text) = md5(p_triple::text)
   LIMIT 1;
  IF v_id IS NOT NULL THEN RETURN v_id; END IF;

  IF (SELECT count(*) FROM public.external_evidence
       WHERE project_id = p_project_id) >= 5000 THEN
    RAISE EXCEPTION 'too_large: external-evidence cap (5000) reached for this project';
  END IF;

  INSERT INTO public.external_evidence
    (project_id, source_id, url_or_ref, content_hash, confidence, triple, lei)
  VALUES
    (p_project_id, p_source_id, NULLIF(p_url_or_ref, ''), p_content_hash,
     p_confidence, p_triple, NULLIF(upper(COALESCE(p_lei, '')), ''))
  RETURNING id INTO v_id;
  RETURN v_id;
END; $$;

CREATE OR REPLACE FUNCTION public.record_model_validation(
  p_project_id               uuid,
  p_policy_version_id        uuid,
  p_dataset_version_id       uuid,
  p_scenario_id              uuid,
  p_adopted_warmup_days      integer,
  p_warmup_method            text,
  p_recommended_replications integer,
  p_replication_basis        jsonb DEFAULT '{}'::jsonb,
  p_validation_tests         jsonb DEFAULT '[]'::jsonb,
  p_findings                 jsonb DEFAULT '[]'::jsonb,
  p_verdict                  text DEFAULT 'validated',
  p_basis                    text DEFAULT 'statistical',
  p_evidence_run_id          uuid DEFAULT NULL,
  p_user_id                  uuid DEFAULT NULL,
  p_user_email               text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  s         public.scenarios%ROWTYPE;
  v_horizon int;
  v_warm    int := ceil(GREATEST(0, p_adopted_warmup_days) / 7.0)::int;
  v_rule    text;
  v_target  numeric := NULLIF(p_replication_basis ->> 'target_precision', '')::numeric;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, 'simulation_lab');

  SELECT * INTO s FROM public.scenarios WHERE id = p_scenario_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'scenario % not found', p_scenario_id; END IF;
  v_horizon := GREATEST(1, ceil(COALESCE(s.horizon_days, 364) / 7.0)::int);
  v_rule := COALESCE(s.stopping_rule ->> 'kind', 'fixed_horizon');
  IF v_rule = 'ci_halfwidth' AND v_target IS NULL THEN v_rule := 'fixed_horizon'; END IF;
  RETURN public._insert_validated_model(
    p_project_id, p_policy_version_id, p_dataset_version_id, p_scenario_id, NULL,
    jsonb_build_object(
      'replications', GREATEST(1, LEAST(200, p_recommended_replications)),
      'root_seed', GREATEST(0, COALESCE(s.seed, 0)),
      'crn', COALESCE(s.crn, true),
      'warmup_week', LEAST(v_warm, v_horizon - 1),
      'horizon_weeks', v_horizon,
      'analysis_window_weeks', GREATEST(1, v_horizon - LEAST(v_warm, v_horizon - 1)),
      'ci_level', COALESCE(NULLIF(p_replication_basis ->> 'confidence', '')::numeric, 0.95),
      'ci_halfwidth_target', v_target,
      'stopping_rule', v_rule),
    p_warmup_method, p_replication_basis, p_validation_tests, p_findings,
    p_verdict, p_basis, NULL, p_evidence_run_id, '{}'::jsonb,
    p_user_id, p_user_email);
END;
$fn$;

CREATE OR REPLACE FUNCTION public.record_proposal_viewed(
  p_proposal_id uuid,
  p_user_id     uuid DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_row public.proposals%ROWTYPE;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);

  SELECT * INTO v_row FROM public.proposals WHERE id = p_proposal_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'proposal % not found', p_proposal_id; END IF;
  INSERT INTO public.ai_chat_events (
    user_id, project_id, thread_id, agent_id, model_code, provider_code,
    event_kind, proposal_id, payload
  ) VALUES (
    COALESCE(p_user_id, public.get_current_user_id()),
    v_row.project_id, v_row.thread_id, v_row.agent_id,
    v_row.model_code, v_row.provider_code,
    'proposal.viewed', v_row.id,
    jsonb_build_object('artifact_type', v_row.artifact_type,
                       'provenance', v_row.provenance)
  );
END; $$;

CREATE OR REPLACE FUNCTION public.record_validated_model(
  p_project_id         uuid,
  p_policy_version_id  uuid,
  p_dataset_version_id uuid,
  p_scenario_id        uuid,
  p_name               text,
  p_protocol           jsonb,
  p_warmup_method      text,
  p_replication_basis  jsonb,
  p_validation_tests   jsonb,
  p_findings           jsonb,
  p_basis              text,
  p_face_validation    text,
  p_evidence_run_id    uuid,
  p_evidence           jsonb,
  _actor_user_id       uuid,
  p_user_email         text DEFAULT NULL,
  p_planning_period    text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  v_tests  int;
  v_fail   int;
  v_id     uuid;
  v_period text := NULLIF(btrim(COALESCE(p_planning_period, '')), '');
BEGIN
  -- D309: bind caller assertions before the original operation.
  _actor_user_id := public.security_actor(_actor_user_id);
  PERFORM public.security_assert_project(p_project_id, 'simulation_lab');

  PERFORM public.assert_writer_may_act('record_validated_model', p_project_id, _actor_user_id);

  SELECT count(*), count(*) FILTER (WHERE COALESCE((t ->> 'pass')::boolean, false) IS NOT TRUE)
    INTO v_tests, v_fail
    FROM jsonb_array_elements(COALESCE(p_validation_tests, '[]'::jsonb)) t;

  IF p_basis = 'statistical' THEN
    IF v_tests = 0 THEN
      RAISE EXCEPTION 'a statistically validated model needs the KPI tests it rests on'
        USING ERRCODE = 'check_violation';
    END IF;
    IF v_fail > 0 THEN
      RAISE EXCEPTION 'every selected KPI must pass its test: % of % did not', v_fail, v_tests
        USING ERRCODE = 'check_violation';
    END IF;
  ELSIF p_basis = 'face' THEN
    IF NULLIF(btrim(COALESCE(p_face_validation, '')), '') IS NULL THEN
      RAISE EXCEPTION 'a face-validated model needs the recorded statement it rests on'
        USING ERRCODE = 'check_violation';
    END IF;
  ELSE
    RAISE EXCEPTION 'basis must be statistical or face' USING ERRCODE = 'check_violation';
  END IF;

  v_id := public._insert_validated_model(
    p_project_id, p_policy_version_id, p_dataset_version_id, p_scenario_id, p_name,
    p_protocol, p_warmup_method, p_replication_basis, p_validation_tests, p_findings,
    'validated', p_basis, p_face_validation, p_evidence_run_id, p_evidence,
    _actor_user_id, p_user_email);

  IF v_period IS NOT NULL THEN
    UPDATE public.model_validations SET planning_period = v_period WHERE id = v_id;
  END IF;

  RETURN v_id;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.refresh_node_list_for_project(p_project_id uuid, p_actor_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_modeler uuid;
  v_email   text;
  v_actor   uuid;
  v_org     text;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_actor_user_id := public.security_actor(p_actor_user_id);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_inputs');

  SELECT p.modeler_id INTO v_modeler
  FROM public.projects p
  WHERE p.id = p_project_id;

  IF v_modeler IS NULL THEN
    RETURN;
  END IF;

  -- The caller's actor when it has one, the project owner otherwise. A tier-3
  -- write must name somebody (`audit-actor`, G4).
  v_actor := COALESCE(p_actor_user_id, v_modeler);

  SELECT au.email INTO v_email
  FROM public.approved_users au
  WHERE au.id = v_actor
  LIMIT 1;

  SELECT p.organization INTO v_org
  FROM public.projects p
  WHERE p.id = p_project_id;

  PERFORM public.set_current_user_context(v_actor, COALESCE(v_email, ''));

  -- `node_list_discover`, NOT `rebuild_node_list`: the refresh runs from a trigger
  -- inside somebody else's statement, and that statement was already authorized.
  -- See section 5's header and §4 D66 — `rehearsal/090` and `/110` are what
  -- calling the checked wrapper here looks like.
  PERFORM public.node_list_discover(p_project_id, v_org, v_actor);

  UPDATE public.node_list nl
  SET echelon     = e.echelon,
      node_type   = CASE e.echelon WHEN 'subassembly' THEN 'material' ELSE e.echelon END,
      node_group  = initcap(CASE e.echelon WHEN 'subassembly' THEN 'material' ELSE e.echelon END),
      bom_depth   = public.node_bom_depth(nl.project_id, nl.node_id),
      supply_tier = public.node_supply_tier(nl.project_id, nl.node_id)
  FROM (
    SELECT id, public.classify_node_echelon(project_id, node_id) AS echelon
      FROM public.node_list
     WHERE project_id = p_project_id
  ) e
  WHERE nl.id = e.id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.restore_policy_version(p_version_id uuid,
  _actor_user_id uuid DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_row      public.policy_versions%ROWTYPE;
  v_defaults jsonb;
  v_is_v2    boolean;
BEGIN
  -- D309: bind caller assertions before the original operation.
  _actor_user_id := public.security_actor(_actor_user_id);


  -- D71, closed for this path (WP 6.2 slice 12). LOCAL to this transaction and
  -- set BEFORE any tier write, so `audit_tier_write`'s `get_current_user_id()`
  -- resolves and the audit rows below name the caller rather than recording
  -- `actor_known: false`. Guarded: `_actor_user_id` is DEFAULT NULL so every
  -- existing caller keeps working unchanged, and an unguarded set_config would
  -- BLANK an actor the caller's transaction had already established.
  IF _actor_user_id IS NOT NULL THEN
    PERFORM set_config('app.current_user_id', _actor_user_id::text, true);
  END IF;
  -- D275 · a named actor must hold Edit Policies on the project.
  PERFORM public.assert_may_edit_policies((SELECT project_id FROM public.policy_versions WHERE id = p_version_id), _actor_user_id);
  SELECT * INTO v_row FROM public.policy_versions WHERE id = p_version_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Version % not found', p_version_id; END IF;

  v_is_v2    := v_row.snapshot ? 'defaults';
  v_defaults := CASE WHEN v_is_v2 THEN v_row.snapshot -> 'defaults' ELSE v_row.snapshot END;

  UPDATE public.policy_defaults SET
    sourcing    = COALESCE(v_defaults -> 'sourcing',    sourcing),
    inventory   = COALESCE(v_defaults -> 'inventory',   inventory),
    transport   = COALESCE(v_defaults -> 'transport',   transport),
    fulfillment = COALESCE(v_defaults -> 'fulfillment', fulfillment),
    production  = COALESCE(v_defaults -> 'production',  production),
    recovery    = COALESCE(v_defaults -> 'recovery',    recovery),
    demand      = COALESCE(v_defaults -> 'demand',      demand),
    fulfillment_strategy = CASE
      WHEN v_is_v2 THEN COALESCE(v_row.snapshot ->> 'fulfillment_strategy', fulfillment_strategy)
      ELSE fulfillment_strategy
    END,
    updated_at  = now()
  WHERE project_id = v_row.project_id;

  -- v1 snapshots predate override capture: leave live overrides untouched.
  IF v_is_v2 THEN
    DELETE FROM public.policy_overrides WHERE project_id = v_row.project_id;

    INSERT INTO public.policy_overrides (project_id, scope, target_key, family, patch)
    SELECT
      v_row.project_id,
      o ->> 'scope',
      o ->> 'target_key',
      o ->> 'family',
      COALESCE(o -> 'patch', '{}'::jsonb)
    FROM jsonb_array_elements(COALESCE(v_row.snapshot -> 'overrides', '[]'::jsonb)) AS o;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.review_agent_proposal(
  p_proposal_id uuid,
  p_action      text,            -- 'approve' | 'reject' | 'propose'
  p_user_id     uuid DEFAULT NULL,
  p_user_email  text DEFAULT NULL,
  p_note        text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_row     public.proposals%ROWTYPE;
  v_caps    jsonb;
  v_ok      boolean;
  v_refusal text;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);

  SELECT * INTO v_row FROM public.proposals WHERE id = p_proposal_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'proposal % not found', p_proposal_id; END IF;

  -- §13.2 checkpoint 4 (fail closed): resolve grants for the asserted user.
  -- 'propose' is the agent completing its own draft (service context) and
  -- carries no user grant.
  IF p_action IN ('approve', 'reject') THEN
    v_caps := public.get_my_capabilities(p_user_id);
    IF COALESCE((v_caps->>'is_super_admin')::boolean, false) THEN
      v_ok := true;
    ELSIF p_action = 'reject' THEN
      v_ok := COALESCE((v_caps->'features'->>'agent_proposals')::boolean, false);
      IF NOT v_ok THEN
        RAISE EXCEPTION 'forbidden: reject requires the agent_proposals capability';
      END IF;
    ELSIF v_row.artifact_type = 'decision_report' THEN
      -- §13.3: decision_report apply = agent_proposals + reports; rendering
      -- mutates no project state, so agent_apply is deliberately NOT demanded.
      v_ok := COALESCE((v_caps->'features'->>'agent_proposals')::boolean, false)
          AND COALESCE((v_caps->'features'->>'reports')::boolean, false);
      IF NOT v_ok THEN
        RAISE EXCEPTION 'forbidden: approve requires the agent_proposals and reports capabilities';
      END IF;
    ELSE
      v_ok := COALESCE((v_caps->'features'->>'agent_apply')::boolean, false);
      IF NOT v_ok THEN
        RAISE EXCEPTION 'forbidden: approve requires the agent_apply capability';
      END IF;
    END IF;

    -- D276 — approving is never more than the approver could do by hand on this project.
    IF p_action = 'approve' AND NOT COALESCE((v_caps->>'is_super_admin')::boolean, false) THEN
      v_refusal := public.agent_project_right_refusal(p_user_id, v_row.project_id, v_row.artifact_type);
      IF v_refusal IS NOT NULL THEN RAISE EXCEPTION '%', v_refusal; END IF;
    END IF;
  END IF;

  IF p_action = 'approve' THEN
    IF v_row.status <> 'proposed' THEN RAISE EXCEPTION 'approve requires status=proposed (is %)', v_row.status; END IF;
    UPDATE public.proposals SET status='approved', reviewed_by=p_user_id,
      reviewed_at=now(), status_reason=p_note WHERE id=p_proposal_id;
  ELSIF p_action = 'reject' THEN
    IF v_row.status NOT IN ('proposed','approved') THEN RAISE EXCEPTION 'reject requires proposed|approved (is %)', v_row.status; END IF;
    UPDATE public.proposals SET status='rejected', reviewed_by=p_user_id,
      reviewed_at=now(), status_reason=p_note WHERE id=p_proposal_id;
  ELSIF p_action = 'propose' THEN
    IF v_row.status <> 'draft' THEN RAISE EXCEPTION 'propose requires status=draft (is %)', v_row.status; END IF;
    UPDATE public.proposals SET status='proposed' WHERE id=p_proposal_id;
  ELSE
    RAISE EXCEPTION 'unknown action %', p_action;
  END IF;

  -- §4.2 side effects: the review events, id-attributed only (§7.5).
  IF p_action IN ('approve', 'reject') THEN
    INSERT INTO public.ai_chat_events (
      user_id, project_id, thread_id, agent_id, model_code, provider_code,
      event_kind, proposal_id, payload
    ) VALUES (
      p_user_id, v_row.project_id, v_row.thread_id, v_row.agent_id,
      v_row.model_code, v_row.provider_code,
      CASE WHEN p_action = 'approve' THEN 'proposal.approved' ELSE 'proposal.rejected' END,
      v_row.id,
      jsonb_build_object('artifact_type', v_row.artifact_type,
                         'provenance', v_row.provenance,
                         'status_reason', p_note)
    );
  END IF;
END; $$;

CREATE OR REPLACE FUNCTION public.revoke_api_key(p_user_id uuid, p_user_email text, p_key_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_key    public.api_keys%ROWTYPE;
  v_manage boolean;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);

  PERFORM public.set_current_user_context(p_user_id, p_user_email);
  SELECT * INTO v_key FROM public.api_keys WHERE id = p_key_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'key not found'; END IF;
  SELECT c.can_manage INTO v_manage FROM public._api_key_caller(p_user_id, v_key.org_id) c;
  IF NOT v_manage AND (v_key.principal <> 'personal' OR v_key.created_by IS DISTINCT FROM p_user_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  UPDATE public.api_keys
     SET status = 'revoked', revoked_at = now(), revoked_by = p_user_id
   WHERE id = p_key_id AND status = 'active';

  PERFORM public._api_key_audit(p_user_id, 'api_key.revoke', p_key_id,
    jsonb_build_object('status', v_key.status), jsonb_build_object('status', 'revoked'));
END;
$$;

CREATE OR REPLACE FUNCTION public.revoke_model_validation(
  p_validation_id uuid,
  _actor_user_id  uuid DEFAULT NULL,
  p_reason        text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
BEGIN
  -- D309: bind caller assertions before the original operation.
  _actor_user_id := public.security_actor(_actor_user_id);

  IF _actor_user_id IS NOT NULL THEN
    PERFORM set_config('app.current_user_id', _actor_user_id::text, true);
  END IF;
  UPDATE public.model_validations
     SET status = 'revoked', revoked_at = now(), revoked_by = _actor_user_id,
         revoke_reason = NULLIF(btrim(COALESCE(p_reason, '')), '')
   WHERE id = p_validation_id AND status <> 'revoked';
END;
$fn$;

CREATE OR REPLACE FUNCTION public.revoke_project_delegation(_actor_user_id uuid, _grant_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_grant public.delegation_grants;
BEGIN
  -- D309: bind caller assertions before the original operation.
  _actor_user_id := public.security_actor(_actor_user_id);

  SELECT * INTO v_grant FROM public.delegation_grants WHERE id = _grant_id;
  IF v_grant.id IS NULL THEN
    RAISE EXCEPTION 'grant not found' USING ERRCODE = '42704';
  END IF;
  -- the grantor, anyone who outranks them on the project, or a super admin
  IF NOT (v_grant.grantor_user_id = _actor_user_id
          OR public.is_super_admin(_actor_user_id)
          OR public.project_role_rank(public.effective_project_role(_actor_user_id, v_grant.project_id))
             >= public.project_role_rank(v_grant.project_role)) THEN
    RAISE EXCEPTION 'not entitled to revoke this grant' USING ERRCODE = '42501';
  END IF;
  UPDATE public.delegation_grants SET revoked_at = now()
   WHERE id = _grant_id AND revoked_at IS NULL;
END; $$;

CREATE OR REPLACE FUNCTION public.rotate_api_key(
  p_user_id uuid, p_user_email text, p_key_id uuid, p_overlap_hours integer DEFAULT 72
) RETURNS TABLE (id uuid, key_prefix text, plaintext_key text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_key     public.api_keys%ROWTYPE;
  v_manage  boolean;
  v_prefix  text;
  v_secret  text;
  v_id      uuid;
  v_cutoff  timestamptz;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);

  PERFORM public.set_current_user_context(p_user_id, p_user_email);
  SELECT k.* INTO v_key FROM public.api_keys k WHERE k.id = p_key_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'key not found'; END IF;
  IF v_key.status <> 'active' THEN RAISE EXCEPTION 'cannot rotate a revoked key'; END IF;
  SELECT c.can_manage INTO v_manage FROM public._api_key_caller(p_user_id, v_key.org_id) c;
  IF v_key.principal = 'personal' AND v_key.created_by IS DISTINCT FROM p_user_id THEN
    RAISE EXCEPTION 'only its owner can rotate a personal key (an administrator can revoke it)';
  END IF;
  IF NOT v_manage AND v_key.principal <> 'personal' THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  -- A replacement is a NEW key: a non-manager cannot mint write scopes this way either.
  IF NOT v_manage AND NOT (v_key.scopes <@ public.api_key_self_service_scopes()) THEN
    RAISE EXCEPTION 'forbidden: this key carries scopes that need an admin or modeler role — revoke it and create a read-only key';
  END IF;

  v_prefix := substr(encode(extensions.gen_random_bytes(6), 'hex'), 1, 8);
  v_secret := encode(extensions.gen_random_bytes(32), 'hex');

  INSERT INTO public.api_keys
    (key_prefix, secret_hash, org_id, created_by, name, note, scopes, project_ids, env,
     expires_at, rotated_from, principal)
  VALUES
    (v_prefix, encode(extensions.digest(v_secret, 'sha256'), 'hex'), v_key.org_id, p_user_id,
     v_key.name, v_key.note, v_key.scopes, v_key.project_ids, v_key.env,
     v_key.expires_at, v_key.id, v_key.principal)
  RETURNING api_keys.id INTO v_id;

  v_cutoff := now() + make_interval(hours => GREATEST(0, COALESCE(p_overlap_hours, 0)));
  UPDATE public.api_keys k
     SET expires_at = LEAST(COALESCE(k.expires_at, v_cutoff), v_cutoff)
   WHERE k.id = p_key_id;

  PERFORM public._api_key_audit(p_user_id, 'api_key.rotate', p_key_id,
    jsonb_build_object('key_prefix', v_key.key_prefix),
    jsonb_build_object('replacement_id', v_id, 'old_key_expires_at', v_cutoff, 'principal', v_key.principal));

  RETURN QUERY SELECT v_id, v_prefix, 'sk_' || v_key.env || '_' || v_prefix || '_' || v_secret;
END;
$$;

CREATE OR REPLACE FUNCTION public.save_policy_defaults(
  p_project_id        uuid,
  p_family            text,
  p_value             jsonb,
  p_strategy          text        DEFAULT NULL,
  p_active_preset     text        DEFAULT NULL,
  p_preset_applied_at timestamptz DEFAULT NULL,
  _actor_user_id uuid DEFAULT NULL) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  -- D309: bind caller assertions before the original operation.
  _actor_user_id := public.security_actor(_actor_user_id);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_policies');


  -- D71, closed for this path (WP 6.2 slice 12). LOCAL to this transaction and
  -- set BEFORE any tier write, so `audit_tier_write`'s `get_current_user_id()`
  -- resolves and the audit rows below name the caller rather than recording
  -- `actor_known: false`. Guarded: `_actor_user_id` is DEFAULT NULL so every
  -- existing caller keeps working unchanged, and an unguarded set_config would
  -- BLANK an actor the caller's transaction had already established.
  IF _actor_user_id IS NOT NULL THEN
    PERFORM set_config('app.current_user_id', _actor_user_id::text, true);
  END IF;
  -- D275 · a named actor must hold Edit Policies on the project.
  PERFORM public.assert_may_edit_policies(p_project_id, _actor_user_id);
  INSERT INTO public.policy_defaults (project_id, updated_at)
  VALUES (p_project_id, now())
  ON CONFLICT (project_id) DO NOTHING;

  EXECUTE format(
    'UPDATE public.policy_defaults SET %I = $1, updated_at = now() WHERE project_id = $2',
    p_family
  ) USING p_value, p_project_id;

  IF p_strategy IS NOT NULL THEN
    UPDATE public.policy_defaults
       SET fulfillment_strategy = p_strategy, updated_at = now()
     WHERE project_id = p_project_id;
  END IF;

  IF p_active_preset IS NOT NULL THEN
    UPDATE public.policy_defaults
       SET active_preset     = p_active_preset,
           preset_applied_at = p_preset_applied_at,
           updated_at        = now()
     WHERE project_id = p_project_id;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.save_project_memory(
  p_project_id       uuid,
  p_kind             text,
  p_content          text,
  p_citations        jsonb DEFAULT '[]'::jsonb,
  p_source_thread_id uuid  DEFAULT NULL,
  p_user_id          uuid  DEFAULT NULL,
  p_grounding        jsonb DEFAULT '{}'::jsonb
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_id uuid;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_inputs');

  IF NOT EXISTS (SELECT 1 FROM public.projects WHERE id = p_project_id) THEN
    RAISE EXCEPTION 'project % not found', p_project_id;
  END IF;
  IF p_kind NOT IN ('fact','preference','decision') THEN
    RAISE EXCEPTION 'kind must be fact, preference or decision';
  END IF;
  IF p_content IS NULL OR btrim(p_content) = '' THEN
    RAISE EXCEPTION 'memory content must not be empty';
  END IF;
  IF char_length(p_content) > 500 THEN
    RAISE EXCEPTION 'too_large: memory content exceeds 500 characters';
  END IF;
  IF (SELECT count(*) FROM public.project_memory
       WHERE project_id = p_project_id AND status = 'active') >= 200 THEN
    RAISE EXCEPTION 'too_large: active-memory cap (200) reached for this project — archive older entries first';
  END IF;

  INSERT INTO public.project_memory
    (project_id, kind, content, citations, grounding, created_by, source_thread_id)
  VALUES
    (p_project_id, p_kind, btrim(p_content),
     COALESCE(p_citations, '[]'::jsonb), COALESCE(p_grounding, '{}'::jsonb),
     p_user_id, p_source_thread_id)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.seed_synthetic_simulation_data(
  p_project_id uuid,
  p_user_id uuid,
  p_user_email text,
  p_num_profiles integer DEFAULT 3,
  p_num_simulations integer DEFAULT 3
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_org text;
  v_org_id uuid;
  v_modeler uuid;
  v_role text;
  v_plant text;
  i integer;
  new_profile_id uuid;
  profile_ids uuid[] := ARRAY[]::uuid[];
  sim_id uuid;
  profile_name text;
  result_summary jsonb := '[]'::jsonb;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, 'simulation_lab');

  -- Establish caller context for RLS helper functions
  PERFORM public.set_current_user_context(p_user_id, p_user_email);

  -- Validate project and authorization (same org AND project owner or admin)
  SELECT organization, organization_id, modeler_id, plant_name
    INTO v_org, v_org_id, v_modeler, v_plant
  FROM public.projects
  WHERE id = p_project_id;

  IF v_org IS NULL THEN
    RAISE EXCEPTION 'project_not_found';
  END IF;

  SELECT user_role INTO v_role FROM public.get_current_approved_user() LIMIT 1;
  IF NOT public.org_is_current_user_org(v_org_id, v_org) OR NOT (v_modeler = public.get_current_user_id() OR v_role IN ('admin', 'super_admin')) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  -- Create synthetic disruption scenario profiles using the v2 helper (with explicit casts and dates)
  FOR i IN 1..GREATEST(1, COALESCE(p_num_profiles, 3)) LOOP
    profile_name := 'Scenario ' || i;
    new_profile_id := public.create_disruption_scenario_v2(
      p_project_id       => p_project_id,
      p_plant_name       => v_plant,
      p_scenario_name    => profile_name,
      p_user_id          => p_user_id,
      p_user_email       => p_user_email,
      p_status           => 'draft'::public.disruption_status,
      p_description      => 'Synthetic scenario ' || i,
      p_tags             => ARRAY['seed'],
      p_targets          => jsonb_build_array(
                              jsonb_build_object(
                                'target_type','node',
                                'node_ids', jsonb_build_array('N' || i)
                              )
                            ),
      p_effects          => jsonb_build_array(
                              jsonb_build_object(
                                'effect_type','capacity_reduction',
                                'magnitude', (10 + i)::numeric,
                                'unit','percent'
                              )
                            ),
      p_settings         => jsonb_build_object('simulation_horizon_days', 7),
      p_disruption_start => NULL::date,
      p_disruption_end   => NULL::date
    );
    profile_ids := array_append(profile_ids, new_profile_id);
  END LOOP;

  -- Create synthetic simulation results referencing the seeded profiles
  FOR i IN 1..GREATEST(1, COALESCE(p_num_simulations, 3)) LOOP
    INSERT INTO public.simulation_results (
      project_id,
      plant_name,
      status,
      scenario_ids,
      started_at,
      completed_at,
      metrics,
      result_data
    ) VALUES (
      p_project_id,
      v_plant,
      'completed',
      ARRAY[ profile_ids[((i - 1) % GREATEST(1, COALESCE(array_length(profile_ids,1),1))) + 1] ],
      now() - interval '2 days',
      now() - interval '1 days',
      jsonb_build_object(
        'available_kpis', jsonb_build_array('fill_rate','revenue'),
        'baseline', jsonb_build_object(
          'fill_rate', jsonb_build_array(
            jsonb_build_object('day',0,'value',0.96),
            jsonb_build_object('day',7,'value',0.97)
          ),
          'revenue', jsonb_build_array(
            jsonb_build_object('day',0,'value',120000),
            jsonb_build_object('day',7,'value',125000)
          )
        ),
        'scenario', jsonb_build_object(
          'fill_rate', jsonb_build_array(
            jsonb_build_object('day',0,'value',0.90),
            jsonb_build_object('day',7,'value',0.95)
          ),
          'revenue', jsonb_build_array(
            jsonb_build_object('day',0,'value',110000),
            jsonb_build_object('day',7,'value',120000)
          )
        )
      ),
      jsonb_build_object(
        'seed_tag','demo_seed',
        'simulation_period', jsonb_build_object('start_day',0,'end_day',7)
      )
    ) RETURNING id INTO sim_id;

    result_summary := result_summary || jsonb_build_array(jsonb_build_object('simulation_id', sim_id));
  END LOOP;

  RETURN jsonb_build_object('profile_ids', profile_ids, 'simulations', result_summary);
END;
$function$;

CREATE OR REPLACE FUNCTION public.set_file_retained(
  p_file_id  uuid,
  p_user_id  uuid,
  p_retained boolean
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_row      public.user_files;
  v_retained bigint;
  v_cap      bigint := public.workspace_retained_cap_bytes();
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);

  SELECT * INTO v_row FROM public.user_files
   WHERE id = p_file_id AND user_id = p_user_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'file % not found', p_file_id; END IF;

  IF p_retained THEN
    SELECT COALESCE(sum(size_bytes), 0) INTO v_retained
      FROM public.user_files
     WHERE user_id = p_user_id AND retained AND id <> p_file_id;
    IF v_retained + v_row.size_bytes > v_cap THEN
      RAISE EXCEPTION 'retention_cap: keeping this file (% bytes) would exceed the % MB per-user retained cap (% bytes already kept)',
        v_row.size_bytes, v_cap / 1048576, v_retained;
    END IF;
  END IF;

  UPDATE public.user_files SET retained = p_retained WHERE id = p_file_id;

  IF p_retained THEN
    BEGIN
      INSERT INTO public.ai_chat_events (event_kind, user_id, project_id, payload)
      VALUES ('file.kept', p_user_id, v_row.project_id,
              jsonb_build_object('file_id', v_row.id, 'kind', v_row.kind, 'size_bytes', v_row.size_bytes));
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END IF;
END; $$;

CREATE OR REPLACE FUNCTION public.set_model_planning_period(
  p_validation_id   uuid,
  p_planning_period text,
  _actor_user_id    uuid DEFAULT NULL
) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  v_project uuid;
  v_period  text;
  v_code    text;
BEGIN
  -- D309: bind caller assertions before the original operation.
  _actor_user_id := public.security_actor(_actor_user_id);

  SELECT project_id, planning_period INTO v_project, v_period
    FROM public.model_validations WHERE id = p_validation_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'validation % not found', p_validation_id; END IF;
  PERFORM public.assert_writer_may_act('set_model_planning_period', v_project, _actor_user_id);
  IF v_period IS NOT NULL THEN
    RAISE EXCEPTION 'this model''s planning period is already %; a period is set once', v_period
      USING ERRCODE = 'check_violation';
  END IF;
  UPDATE public.model_validations
     SET planning_period = NULLIF(btrim(COALESCE(p_planning_period, '')), '')
   WHERE id = p_validation_id
  RETURNING model_code INTO v_code;
  RETURN v_code;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.set_run_retention(
  p_run_id        uuid,
  p_retention     text,
  _actor_user_id  uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  r      public.simulation_runs%ROWTYPE;
  v_role text;
BEGIN
  -- D309: bind caller assertions before the original operation.
  _actor_user_id := public.security_actor(_actor_user_id);

  SELECT * INTO r FROM public.simulation_runs WHERE id = p_run_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'run % not found', p_run_id USING ERRCODE = 'no_data_found';
  END IF;
  PERFORM public.assert_writer_may_act('set_run_retention', r.project_id, _actor_user_id);
  v_role := public.effective_project_role(_actor_user_id, r.project_id);
  IF v_role IS NULL OR v_role NOT IN ('editor', 'owner') THEN
    RAISE EXCEPTION 'pinning a run needs the editor or owner role on its project (you hold %)',
      COALESCE(v_role, 'none') USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_retention NOT IN ('standard', 'pinned') THEN
    RAISE EXCEPTION 'retention must be standard or pinned' USING ERRCODE = 'check_violation';
  END IF;
  IF r.retention = 'evidence' THEN
    RAISE EXCEPTION 'this run is a Validated Model''s evidence and is kept with the model'
      USING ERRCODE = 'check_violation';
  END IF;
  IF r.series_expired_at IS NOT NULL THEN
    RAISE EXCEPTION 'this run''s series have already expired — re-run it (RunKey %) to reproduce them',
      COALESCE(left(r.run_key, 12), 'not recorded') USING ERRCODE = 'check_violation';
  END IF;
  UPDATE public.simulation_runs
     SET retention = p_retention,
         series_expires_at = CASE WHEN p_retention = 'pinned' THEN NULL
                                  WHEN status = 'done' THEN now() + public.run_series_retention(project_id)
                                  ELSE NULL END
   WHERE id = p_run_id
  RETURNING * INTO r;
  RETURN jsonb_build_object('run_id', r.id, 'retention', r.retention, 'series_expires_at', r.series_expires_at);
END;
$fn$;

CREATE OR REPLACE FUNCTION public.set_thread_flags(
  p_thread_id uuid, p_pinned boolean, p_archived boolean, p_user_id uuid DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);

  PERFORM public._chat_assert_thread_owner(p_thread_id, p_user_id);
  UPDATE public.chat_threads
     SET pinned   = COALESCE(p_pinned, pinned),
         archived = COALESCE(p_archived, archived)
   WHERE id = p_thread_id;
END; $$;

CREATE OR REPLACE FUNCTION public.set_thread_summary(
  p_thread_id uuid,
  p_user_id   uuid,
  p_summary   text,
  p_upto_seq  integer DEFAULT 0
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);

  PERFORM public._chat_assert_thread_owner(p_thread_id, p_user_id);
  IF p_summary IS NULL OR btrim(p_summary) = '' THEN
    UPDATE public.chat_threads SET summary = NULL, summary_upto_seq = 0
     WHERE id = p_thread_id;
  ELSE
    UPDATE public.chat_threads
       SET summary = left(p_summary, 4000),
           summary_upto_seq = GREATEST(COALESCE(p_upto_seq, 0), 0)
     WHERE id = p_thread_id;
  END IF;
END; $$;

CREATE OR REPLACE FUNCTION public.sim_engine_build_withdraw(
  p_build_id     uuid,
  p_reason       text,
  _actor_user_id uuid DEFAULT NULL
) RETURNS public.sim_engine_builds
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  v public.sim_engine_builds%ROWTYPE;
BEGIN
  -- D309: bind caller assertions before the original operation.
  _actor_user_id := public.security_actor(_actor_user_id);

  IF _actor_user_id IS NULL OR NOT public.is_super_admin(_actor_user_id) THEN
    RAISE EXCEPTION 'only a super admin may withdraw an engine build' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF NULLIF(btrim(p_reason), '') IS NULL THEN
    RAISE EXCEPTION 'a withdrawal states its reason' USING ERRCODE = 'check_violation';
  END IF;
  SELECT * INTO v FROM public.sim_engine_builds WHERE id = p_build_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'engine build % is not in the ledger', p_build_id USING ERRCODE = 'no_data_found';
  END IF;
  IF v.withdrawn_at IS NOT NULL THEN
    RETURN v;  -- already withdrawn: the first reason stands
  END IF;
  PERFORM set_config('app.current_user_id', _actor_user_id::text, true);
  UPDATE public.sim_engine_builds
     SET withdrawn_at = now(), withdrawn_reason = btrim(p_reason), withdrawn_by = _actor_user_id
   WHERE id = p_build_id
  RETURNING * INTO v;
  RETURN v;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.snapshot_dataset(
  p_project_id uuid,
  p_label      text DEFAULT NULL,
  p_user_id    uuid DEFAULT NULL,
  p_user_email text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  st      public.project_graph_state%ROWTYPE;
  v_gen   bigint := 0;
  v_snap  jsonb;
  v_h     jsonb;
  v_id    uuid;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_inputs');

  IF COALESCE(p_user_id, auth.uid()) IS NOT NULL THEN
    PERFORM set_config('app.current_user_id', COALESCE(p_user_id, auth.uid())::text, true);
  END IF;

  -- One version per content, so two concurrent saves of one world cannot both
  -- miss the lookup and insert twice. The numbering trigger takes the same key.
  PERFORM pg_advisory_xact_lock(hashtextextended('dataset_versions:' || p_project_id::text, 0));

  -- FAST PATH: the stored hash is clean and a version of it exists — that version
  -- IS this snapshot, and no snapshot needs building to say so.
  SELECT * INTO st FROM public.project_graph_state WHERE project_id = p_project_id;
  IF FOUND THEN
    v_gen := st.generation;
    IF NOT st.dirty AND st.graph_hash IS NOT NULL AND st.level_spec = 1 THEN
      SELECT id INTO v_id FROM public.dataset_versions
       WHERE project_id = p_project_id AND graph_hash = st.graph_hash
       ORDER BY created_at, id LIMIT 1;
      IF FOUND THEN RETURN v_id; END IF;
    END IF;
  END IF;

  v_snap := public._build_dataset_snapshot(p_project_id);
  v_h    := public._dataset_all_hashes(v_snap);
  PERFORM public._graph_state_store(p_project_id, v_h, v_gen);

  -- §4 D234: ANY version of this content, not the latest one — the OLDEST, so the
  -- answer is the same on every call.
  SELECT id INTO v_id FROM public.dataset_versions
   WHERE project_id = p_project_id AND graph_hash = v_h ->> 'graph_hash'
   ORDER BY created_at, id LIMIT 1;
  IF FOUND THEN
    -- A row frozen before the level hashes existed learns them from the same
    -- world it already describes (its graph_hash equals this one's).
    UPDATE public.dataset_versions
       SET hash_product = v_h ->> 'hash_product',
           hash_process = v_h ->> 'hash_process',
           hash_firm    = v_h ->> 'hash_firm'
     WHERE id = v_id AND hash_product IS NULL;
    RETURN v_id;
  END IF;

  INSERT INTO public.dataset_versions (
    project_id, label, snapshot, graph_hash, hash_inputs, hash_network,
    hash_product, hash_process, hash_firm, author_user_id, author_email
  ) VALUES (
    p_project_id,
    COALESCE(p_label, 'Dataset ' || to_char(now(), 'YYYY-MM-DD HH24:MI')),
    v_snap,
    v_h ->> 'graph_hash', v_h ->> 'hash_inputs', v_h ->> 'hash_network',
    v_h ->> 'hash_product', v_h ->> 'hash_process', v_h ->> 'hash_firm',
    COALESCE(p_user_id, auth.uid()), p_user_email
  )
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.snapshot_policy(
  p_project_id        uuid,
  p_label             text DEFAULT NULL,
  p_user_id           uuid DEFAULT NULL,
  p_user_email        text DEFAULT NULL,
  p_user_name         text DEFAULT NULL,
  p_parent_version_id uuid DEFAULT NULL,
  p_notes             text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_id       uuid;
  v_snapshot jsonb;
  v_hash     text;
  v_prev     jsonb;
  v_note     text := NULLIF(btrim(COALESCE(p_notes, '')), '');
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_policies');

  -- WP 6.4 · the actor, LOCAL to this transaction; a NULL never blanks one an
  -- enclosing statement already set.
  IF p_user_id IS NOT NULL THEN
    PERFORM set_config('app.current_user_id', p_user_id::text, true);
  END IF;

  v_snapshot := public._build_policy_snapshot(p_project_id);
  v_hash     := encode(extensions.digest(v_snapshot::text, 'sha256'), 'hex');

  -- One save at a time per project, so two identical saves racing each other
  -- cannot both miss the lookup below and insert two rows for one content. The
  -- numbering trigger takes the same key; a re-entrant advisory lock is free.
  PERFORM pg_advisory_xact_lock(hashtextextended('policy_versions:' || p_project_id::text, 0));

  -- D241: the content already has a version → that version IS this save. The
  -- OLDEST row, so the answer is the same on every call.
  SELECT id INTO v_id
    FROM public.policy_versions
   WHERE project_id = p_project_id
     AND policy_hash = v_hash
   ORDER BY created_at, id
   LIMIT 1;

  IF FOUND THEN
    -- A note is the one thing a repeat save may add. Appended, never replaced,
    -- and not twice: a client retrying the same save must not double it.
    IF v_note IS NOT NULL THEN
      UPDATE public.policy_versions
         SET notes = CASE
                       WHEN notes IS NULL THEN v_note
                       WHEN position(v_note IN notes) > 0 THEN notes
                       ELSE notes || E'\n\n' || v_note
                     END
       WHERE id = v_id
         AND (notes IS NULL OR position(v_note IN notes) = 0);
    END IF;
    RETURN v_id;
  END IF;

  IF p_parent_version_id IS NOT NULL THEN
    SELECT snapshot INTO v_prev FROM public.policy_versions WHERE id = p_parent_version_id;
  ELSE
    SELECT snapshot INTO v_prev
    FROM public.policy_versions
    WHERE project_id = p_project_id
    ORDER BY created_at DESC
    LIMIT 1;
  END IF;

  INSERT INTO public.policy_versions (
    project_id, label, notes, snapshot, created_by,
    author_user_id, author_email, author_name,
    parent_version_id, previous_snapshot, policy_hash
  ) VALUES (
    p_project_id,
    COALESCE(p_label, 'Snapshot ' || to_char(now(), 'YYYY-MM-DD HH24:MI')),
    v_note,
    v_snapshot,
    COALESCE(p_user_id, auth.uid()),
    COALESCE(p_user_id, auth.uid()),
    p_user_email,
    p_user_name,
    p_parent_version_id,
    v_prev,
    v_hash
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.surrogate_feature_spec(p_project_id uuid, _actor_user_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  v_start   jsonb;
  v_run     uuid;
  v_results jsonb;
  v_summary jsonb;
BEGIN
  -- D309: bind caller assertions before the original operation.
  _actor_user_id := public.security_actor(_actor_user_id);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_inputs');

  v_start := public.analysis_get_or_start(p_project_id, 'feature_spec',
               '{"feature_spec_version": 1}'::jsonb, 'feature_spec-1', _actor_user_id);
  v_run := (v_start ->> 'run_id')::uuid;
  IF NOT COALESCE((v_start ->> 'cache_hit')::boolean, false) THEN
    IF COALESCE((v_start ->> 'claimed_by_other')::boolean, false) THEN
      RETURN v_start || jsonb_build_object('features', NULL);
    END IF;
    v_results := public._feature_spec_compute(p_project_id);
    PERFORM public.analysis_complete_run(v_run, v_results,
      jsonb_build_object('results', jsonb_array_length(v_results)), '[]'::jsonb, _actor_user_id);
  END IF;
  SELECT metrics INTO v_summary FROM public.analysis_results
   WHERE run_id = v_run AND entity_type = 'graph' AND entity_id = 'summary';
  RETURN v_start || jsonb_build_object(
    -- WP 11.4 · §4 D261 — the PRODUCT level's version, which the features are keyed
    -- on; the composite snapshot's number under its own name.
    'level_version_id', (SELECT ar.level_version_id FROM public.analysis_runs ar WHERE ar.id = v_run),
    'product_version_no', (SELECT g.version_no FROM public.analysis_runs ar
                             JOIN public.graph_level_versions g ON g.id = ar.level_version_id
                            WHERE ar.id = v_run),
    'snapshot_version_no', (SELECT dv.version_no FROM public.analysis_runs ar
                              JOIN public.dataset_versions dv ON dv.id = ar.dataset_version_id
                             WHERE ar.id = v_run),
    'features', v_summary);
END;
$fn$;

CREATE OR REPLACE FUNCTION public.switch_my_organization(p_org_id uuid, p_user_id uuid DEFAULT NULL)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid    uuid := public.account_self_resolve(p_user_id);
  v_role   text;
  v_active boolean;
  v_before uuid;
  v_org    public.organizations%ROWTYPE;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);

  SELECT au.role::text, au.is_active, au.organization_id INTO v_role, v_active, v_before
    FROM public.approved_users au WHERE au.id = v_uid;
  IF NOT v_active THEN
    RAISE EXCEPTION 'account_inactive' USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT o.* INTO v_org
    FROM public.organization_members m
    JOIN public.organizations o ON o.id = m.org_id
   WHERE m.user_id = v_uid AND m.org_id = p_org_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_a_member: this account does not belong to that organization'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_org.access_valid_until IS NOT NULL AND v_org.access_valid_until <= now()
     AND v_role <> 'super_admin' THEN
    RAISE EXCEPTION 'org_access_ended: the access period for % ended on % — an administrator must renew it before it can be used',
      v_org.name, to_char(v_org.access_valid_until AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI "UTC"')
      USING ERRCODE = 'check_violation';
  END IF;

  IF v_before IS DISTINCT FROM p_org_id THEN
    UPDATE public.approved_users SET organization_id = p_org_id, updated_at = now() WHERE id = v_uid;

    BEGIN
      INSERT INTO public.audit_logs (plane, actor_user_id, action, target_type, target_id, before, after)
      VALUES ('access', v_uid, 'org.switch', 'approved_users', v_uid::text,
              jsonb_build_object('organization_id', v_before),
              jsonb_build_object('organization_id', p_org_id));
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'organization-switch audit skipped: %', SQLERRM;   -- never fail the switch over it
    END;
  END IF;

  RETURN v_org.name;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_own_profile(
  p_display_name text DEFAULT NULL,
  p_phone        text DEFAULT NULL,
  p_avatar_color text DEFAULT NULL,
  p_user_id      uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := public.account_self_resolve(p_user_id);
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);

  IF NOT (SELECT au.is_active FROM public.approved_users au WHERE au.id = v_uid) THEN
    RAISE EXCEPTION 'account_inactive' USING ERRCODE = 'insufficient_privilege';
  END IF;

  UPDATE public.approved_users
     SET display_name = CASE WHEN p_display_name IS NULL THEN display_name
                             ELSE NULLIF(btrim(p_display_name), '') END,
         phone        = CASE WHEN p_phone IS NULL THEN phone
                             ELSE NULLIF(btrim(p_phone), '') END,
         avatar_color = CASE WHEN p_avatar_color IS NULL THEN avatar_color
                             ELSE NULLIF(btrim(p_avatar_color), '') END,
         updated_at   = now()
   WHERE id = v_uid;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_policy_version_notes(
  p_version_id    uuid,
  p_notes         text,
  _actor_user_id  uuid DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  -- D309: bind caller assertions before the original operation.
  _actor_user_id := public.security_actor(_actor_user_id);

  IF _actor_user_id IS NOT NULL THEN
    PERFORM set_config('app.current_user_id', _actor_user_id::text, true);
  END IF;
  -- D275 · a named actor must hold Edit Policies on the project.
  PERFORM public.assert_may_edit_policies((SELECT project_id FROM public.policy_versions WHERE id = p_version_id), _actor_user_id);
  UPDATE public.policy_versions
     SET notes = NULLIF(btrim(COALESCE(p_notes, '')), '')
   WHERE id = p_version_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_project_completion_status(
  p_project_id uuid,
  p_user_id uuid,
  p_user_email text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_org text;
  v_org_id uuid;
  v_bom_level text;
  v_deep_tier_enabled boolean;
  has_bom boolean := false;
  has_inbound boolean := false;
  has_outbound boolean := false;
  has_deep_tier_nodes boolean := false;
  has_deep_tier_edges boolean := false;
  is_complete boolean := false;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_inputs');

  -- Set user context for RLS policies
  PERFORM public.set_current_user_context(p_user_id, p_user_email);

  -- Get project info and validate access
  SELECT organization, organization_id, bom_level, deep_tier_enabled
  INTO v_org, v_org_id, v_bom_level, v_deep_tier_enabled
  FROM public.projects
  WHERE id = p_project_id;

  IF v_org IS NULL THEN
    RAISE EXCEPTION 'project_not_found';
  END IF;

  -- Authorization: same organization only
  IF NOT public.org_is_current_user_org(v_org_id, v_org) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  -- Check BOM data (either single or multi-level)
  SELECT (
    EXISTS(SELECT 1 FROM public.bom_single_level WHERE project_id = p_project_id)
    OR EXISTS(SELECT 1 FROM public.bom_multi_level WHERE project_id = p_project_id)
  ) INTO has_bom;

  -- Check other datasets
  SELECT EXISTS(SELECT 1 FROM public.inbound_logistics WHERE project_id = p_project_id) INTO has_inbound;
  SELECT EXISTS(SELECT 1 FROM public.outbound_logistics WHERE project_id = p_project_id) INTO has_outbound;

  -- Check deep tier datasets if enabled
  IF v_deep_tier_enabled THEN
    SELECT EXISTS(SELECT 1 FROM public.network_nodes WHERE project_id = p_project_id) INTO has_deep_tier_nodes;
    SELECT EXISTS(SELECT 1 FROM public.network_edges WHERE project_id = p_project_id) INTO has_deep_tier_edges;
    is_complete := has_bom AND has_inbound AND has_outbound AND has_deep_tier_nodes AND has_deep_tier_edges;
  ELSE
    is_complete := has_bom AND has_inbound AND has_outbound;
  END IF;

  -- Update project completion status
  UPDATE public.projects 
  SET completed = is_complete, updated_at = now()
  WHERE id = p_project_id;

  -- Return status
  RETURN jsonb_build_object(
    'project_id', p_project_id,
    'completed', is_complete,
    'bom_level', v_bom_level,
    'deep_tier_enabled', v_deep_tier_enabled,
    'datasets', jsonb_build_object(
      'has_bom', has_bom,
      'has_inbound', has_inbound,
      'has_outbound', has_outbound,
      'has_deep_tier_nodes', has_deep_tier_nodes,
      'has_deep_tier_edges', has_deep_tier_edges
    )
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_project(
  p_project_id uuid,
  p_name text,
  p_plant text,
  p_model text,
  p_bom_level text,
  p_user_id uuid,
  p_user_email text,
  p_simulation_start date DEFAULT NULL::date,
  p_simulation_end date DEFAULT NULL::date,
  p_data_type text DEFAULT NULL::text,
  p_deep_tier_enabled boolean DEFAULT NULL::boolean
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_inputs');

  -- Set app context for this session so RLS helper functions work
  PERFORM public.set_current_user_context(p_user_id, p_user_email);

  UPDATE public.projects
  SET
    name = p_name,
    plant_name = p_plant,
    supply_chain_model = p_model,
    bom_level = p_bom_level,
    simulation_start = p_simulation_start,
    simulation_end = p_simulation_end,
    data_type = COALESCE(p_data_type, data_type),
    deep_tier_enabled = COALESCE(p_deep_tier_enabled, deep_tier_enabled),
    updated_at = now()
  WHERE id = p_project_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Project not found or access denied';
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_scenario_effect_magnitude_by_profile(
  p_profile_id uuid,
  p_user_id uuid,
  p_user_email text,
  p_magnitude numeric
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_count integer := 0;
  v_role text;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);

  -- Establish caller context for RLS helper functions
  PERFORM public.set_current_user_context(p_user_id, p_user_email);

  -- Authorization: same org AND (project owner or admin)
  IF NOT EXISTS (
    SELECT 1
    FROM public.disruption_scenario_profiles sp
    JOIN public.projects p ON p.id = sp.project_id
    WHERE sp.id = p_profile_id
      AND public.org_is_current_user_org(p.organization_id, p.organization)
      AND (
        p.modeler_id = public.get_current_user_id()
        OR (SELECT user_role FROM public.get_current_approved_user() LIMIT 1) = 'admin'
      )
  ) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  -- Update magnitude for all effects belonging to the profile_id
  UPDATE public.disruption_scenario_effects dse
  SET magnitude = p_magnitude,
      updated_at = now()
  WHERE dse.profile_id = p_profile_id;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$function$;

CREATE OR REPLACE FUNCTION public.upload_node_list_data(
  p_project_id uuid,
  p_user_id uuid,
  p_user_email text,
  p_rows jsonb
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_org text;
  v_org_id uuid;
  v_modeler uuid;
  v_role text;
  v_plant text;
  inserted_count integer := 0;
  row_item jsonb;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_inputs');

  -- Set user context
  PERFORM public.set_current_user_context(p_user_id, p_user_email);

  -- Validate project and authorization
  SELECT organization, organization_id, modeler_id, plant_name INTO v_org, v_org_id, v_modeler, v_plant
  FROM public.projects
  WHERE id = p_project_id;

  IF v_org IS NULL THEN
    RAISE EXCEPTION 'project_not_found';
  END IF;

  -- Authorization: same org AND (project owner or admin)
  SELECT user_role INTO v_role FROM public.get_current_approved_user() LIMIT 1;
  IF NOT public.org_is_current_user_org(v_org_id, v_org) OR NOT (v_modeler = public.get_current_user_id() OR v_role IN ('admin', 'super_admin')) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  -- Process each row
  FOR row_item IN SELECT * FROM jsonb_array_elements(p_rows)
  LOOP
    -- Upsert node list data
    INSERT INTO public.node_list (
      project_id,
      plant_name,
      node_id,
      description_text,
      location_text,
      longitude,
      latitude,
      created_by,
      organization
    ) VALUES (
      p_project_id,
      COALESCE((row_item->>'plant_name')::text, v_plant),
      (row_item->>'node_id')::text,
      NULLIF(trim(row_item->>'description_text'), ''),
      NULLIF(trim(row_item->>'location_text'), ''),
      CASE 
        WHEN trim(row_item->>'longitude') = '' OR trim(row_item->>'longitude') IS NULL 
        THEN NULL 
        ELSE (row_item->>'longitude')::numeric 
      END,
      CASE 
        WHEN trim(row_item->>'latitude') = '' OR trim(row_item->>'latitude') IS NULL 
        THEN NULL 
        ELSE (row_item->>'latitude')::numeric 
      END,
      p_user_id,
      v_org
    )
    ON CONFLICT (project_id, node_id) 
    DO UPDATE SET
      description_text = EXCLUDED.description_text,
      location_text = EXCLUDED.location_text,
      longitude = EXCLUDED.longitude,
      latitude = EXCLUDED.latitude,
      updated_at = now();

    inserted_count := inserted_count + 1;
  END LOOP;

  RETURN inserted_count;
END;
$function$;

CREATE OR REPLACE FUNCTION public.upsert_chat_plan(
  p_plan    jsonb,
  p_user_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_id      uuid;
  v_row     public.chat_plans;
  v_project uuid;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);

  IF p_user_id IS NULL THEN RAISE EXCEPTION 'forbidden'; END IF;
  IF p_plan IS NULL OR (p_plan->>'thread_id') IS NULL THEN
    RAISE EXCEPTION 'upsert_chat_plan: p_plan.thread_id is required';
  END IF;
  IF jsonb_typeof(COALESCE(p_plan->'steps', '[]'::jsonb)) <> 'array' THEN
    RAISE EXCEPTION 'upsert_chat_plan: steps must be a json array';
  END IF;
  IF jsonb_array_length(COALESCE(p_plan->'steps', '[]'::jsonb)) > 12 THEN
    RAISE EXCEPTION 'invalid_params: a plan allows at most 12 steps';
  END IF;
  v_project := NULLIF(p_plan->>'project_id', '')::uuid;
  IF v_project IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.projects WHERE id = v_project) THEN
    v_project := NULL;
  END IF;

  IF (p_plan->>'id') IS NULL THEN
    -- create; supersede any other live plan in the thread first.
    UPDATE public.chat_plans
       SET status = 'abandoned'
     WHERE thread_id = (p_plan->>'thread_id')::uuid
       AND user_id = p_user_id
       AND status = 'active';
    INSERT INTO public.chat_plans (thread_id, project_id, user_id, agent_id, title, status, steps, model_code)
    VALUES (
      (p_plan->>'thread_id')::uuid,
      v_project,
      p_user_id,
      p_plan->>'agent_id',
      COALESCE(left(p_plan->>'title', 140), 'Task plan'),
      COALESCE(p_plan->>'status', 'active'),
      COALESCE(p_plan->'steps', '[]'::jsonb),
      p_plan->>'model_code'
    ) RETURNING id INTO v_id;
  ELSE
    v_id := (p_plan->>'id')::uuid;
    SELECT * INTO v_row FROM public.chat_plans WHERE id = v_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'plan % not found', v_id; END IF;
    IF v_row.user_id IS DISTINCT FROM p_user_id THEN RAISE EXCEPTION 'forbidden'; END IF;
    IF v_row.thread_id::text IS DISTINCT FROM (p_plan->>'thread_id') THEN
      RAISE EXCEPTION 'plan % is not in this thread', v_id;
    END IF;
    UPDATE public.chat_plans SET
      title        = COALESCE(left(p_plan->>'title', 140), title),
      status       = COALESCE(p_plan->>'status', status),
      steps        = COALESCE(p_plan->'steps', steps),
      model_code   = COALESCE(p_plan->>'model_code', model_code),
      resume_count = resume_count + CASE WHEN COALESCE((p_plan->>'increment_resume')::boolean, false) THEN 1 ELSE 0 END
    WHERE id = v_id;
  END IF;

  SELECT * INTO v_row FROM public.chat_plans WHERE id = v_id;
  RETURN to_jsonb(v_row);
END; $$;

CREATE OR REPLACE FUNCTION public.upsert_chat_thread(
  p_user_id     uuid,
  p_id          uuid DEFAULT NULL,
  p_title       text DEFAULT NULL,
  p_project_id  uuid DEFAULT NULL,
  p_set_project boolean DEFAULT false,
  p_persona_id  text DEFAULT NULL,
  p_folder_id   uuid DEFAULT NULL,
  p_set_folder  boolean DEFAULT false,
  p_mode        text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_id uuid := COALESCE(p_id, gen_random_uuid());
  v_owner uuid;
  v_project uuid := p_project_id;
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, 'data_edit_inputs');

  IF p_user_id IS NULL THEN RAISE EXCEPTION 'forbidden'; END IF;
  IF p_mode IS NOT NULL AND p_mode NOT IN ('ask','review') THEN
    RAISE EXCEPTION 'invalid mode % (ask|review)', p_mode;
  END IF;
  -- a project reference must resolve (FK is SET NULL on delete, not validating)
  IF v_project IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.projects WHERE id = v_project) THEN
    v_project := NULL;
  END IF;

  SELECT user_id INTO v_owner FROM public.chat_threads WHERE id = v_id;
  IF FOUND THEN
    IF v_owner <> p_user_id THEN RAISE EXCEPTION 'forbidden'; END IF;
    UPDATE public.chat_threads SET
      title      = COALESCE(left(p_title, 120), title),
      project_id = CASE WHEN p_set_project THEN v_project ELSE project_id END,
      persona_id = COALESCE(p_persona_id, persona_id),
      folder_id  = CASE WHEN p_set_folder THEN p_folder_id ELSE folder_id END,
      mode       = COALESCE(p_mode, mode)
    WHERE id = v_id;
  ELSE
    INSERT INTO public.chat_threads (id, user_id, title, project_id, persona_id, folder_id, mode)
    VALUES (v_id, p_user_id, COALESCE(left(p_title, 120), 'New chat'),
            CASE WHEN p_set_project THEN v_project ELSE NULL END,
            p_persona_id,
            CASE WHEN p_set_folder THEN p_folder_id ELSE NULL END,
            COALESCE(p_mode, 'review'));
  END IF;
  RETURN v_id;
END; $$;

CREATE OR REPLACE FUNCTION public.verify_user_exists(p_user_id uuid, p_user_email text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- D309: bind caller assertions before the original operation.
  p_user_id := public.security_actor(p_user_id);

  RETURN EXISTS (
    SELECT 1 FROM public.approved_users
    WHERE id = p_user_id AND email = p_user_email
  );
END;
$$;

SELECT pg_notify('pgrst', 'reload schema');

-- SQL-language entry points do not pass through a PL/pgSQL preamble.
CREATE OR REPLACE FUNCTION public.get_my_capabilities(_user_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.capabilities_for_user(public.security_actor(_user_id));
$$;
REVOKE ALL ON FUNCTION public.get_my_capabilities(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_capabilities(uuid) TO authenticated, service_role;

-- An admin account in tenant A is never an admin of tenant B by account role alone.
CREATE OR REPLACE FUNCTION public.has_project_access(p_project_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.security_project_allowed(p_project_id, 'data_edit_inputs');
$$;
