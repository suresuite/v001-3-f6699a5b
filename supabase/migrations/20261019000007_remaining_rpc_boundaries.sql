-- D309/D310: complete the effective-grant inventory, including legacy entry points.

CREATE OR REPLACE FUNCTION public.dataset_version_tuple(p_dataset_version_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
#variable_conflict use_column
BEGIN
  PERFORM public.security_assert_project((SELECT project_id FROM public.dataset_versions WHERE id = p_dataset_version_id), NULL);
  RETURN (SELECT jsonb_build_object(
    'dataset_version_id', dv.id,
    'version_no', dv.version_no,
    'graph_hash', dv.graph_hash,
    'created_at', dv.created_at,
    'product',    (SELECT jsonb_build_object('id', g.id, 'version_no', g.version_no, 'hash', g.level_hash,
                                             'version_code', g.version_code)
                     FROM public.graph_level_versions g WHERE g.id = dv.product_version_id),
    'process',    (SELECT jsonb_build_object('id', g.id, 'version_no', g.version_no, 'hash', g.level_hash,
                                             'version_code', g.version_code)
                     FROM public.graph_level_versions g WHERE g.id = dv.process_version_id),
    'firm',       (SELECT jsonb_build_object('id', g.id, 'version_no', g.version_no, 'hash', g.level_hash,
                                             'version_code', g.version_code)
                     FROM public.graph_level_versions g WHERE g.id = dv.firm_version_id),
    'simulation', (SELECT jsonb_build_object('id', g.id, 'version_no', g.version_no, 'hash', g.level_hash,
                                             'version_code', g.version_code)
                     FROM public.graph_level_versions g WHERE g.id = dv.simulation_version_id))
  FROM public.dataset_versions dv
  WHERE dv.id = p_dataset_version_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.graph_level_version_no(p_level_version_id uuid)
RETURNS integer
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
#variable_conflict use_column
BEGIN
  PERFORM public.security_assert_project((SELECT project_id FROM public.graph_level_versions WHERE id = p_level_version_id), NULL);
  RETURN (SELECT version_no FROM public.graph_level_versions WHERE id = p_level_version_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.scenario_fingerprint_hash(p_scenario_id uuid)
RETURNS text
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
#variable_conflict use_column
BEGIN
  PERFORM public.security_assert_project((SELECT project_id FROM public.scenarios WHERE id = p_scenario_id), NULL);
  RETURN (SELECT encode(
    extensions.digest(public._build_scenario_fingerprint(p_scenario_id)::text, 'sha256'),
    'hex'
  ));
END;
$$;

CREATE OR REPLACE FUNCTION public.active_model_validation(
  p_policy_version_id uuid,
  p_graph_hash        text,
  p_scenario_hash     text
) RETURNS SETOF public.model_validations
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
#variable_conflict use_column
BEGIN
  PERFORM public.security_assert_project((SELECT project_id FROM public.policy_versions WHERE id = p_policy_version_id), NULL);
  RETURN QUERY SELECT mv.*
    FROM public.policy_versions pv
    CROSS JOIN LATERAL public.active_model_validation_by_content(
      pv.project_id, public._policy_version_hash(pv.id), p_graph_hash, p_scenario_hash
    ) mv
   WHERE pv.id = p_policy_version_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.analysis_run_is_current(p_run_id uuid)
RETURNS boolean
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'public'
AS $$
#variable_conflict use_column
BEGIN
  PERFORM public.security_assert_project((SELECT project_id FROM public.analysis_runs WHERE id = p_run_id), NULL);
  RETURN (SELECT r.input_scope = COALESCE(public.analysis_scope_now(r.project_id, r.analysis_kind), 'all')
     AND r.input_hash = public.current_level_hash(r.project_id, r.input_scope)
    FROM public.analysis_runs r
   WHERE r.id = p_run_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.expire_chat_plans(p_thread_id uuid)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_n integer;
BEGIN
  IF NOT public.security_is_service() AND NOT EXISTS (SELECT 1 FROM public.ai_chat_threads WHERE id = p_thread_id AND user_id = public.security_actor(NULL)) THEN RAISE EXCEPTION 'forbidden: thread owner required' USING ERRCODE = '42501'; END IF;

  UPDATE public.chat_plans
     SET status = 'expired'
   WHERE thread_id = p_thread_id
     AND status = 'active'
     AND expires_at < now();
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END; $$;

CREATE OR REPLACE FUNCTION public.get_self_profile()
RETURNS TABLE(id uuid, email text, name text, role text, organization text, created_at timestamptz, updated_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT u.id, u.email, u.name, u.role::text, u.organization, u.created_at, u.updated_at
  FROM public.approved_users u WHERE u.id = public.security_actor(NULL);
$$;

CREATE OR REPLACE FUNCTION public.list_approved_users_safe()
RETURNS TABLE(id uuid, email text, name text, role text, organization text, created_at timestamptz, updated_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := public.security_actor(NULL); v_role text; v_org uuid;
BEGIN
  SELECT u.role::text, u.organization_id INTO v_role, v_org FROM public.approved_users u WHERE u.id = v_uid;
  IF v_role IS NULL OR v_role NOT IN ('admin', 'super_admin') THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY SELECT u.id, u.email, u.name, u.role::text, u.organization, u.created_at, u.updated_at
  FROM public.approved_users u WHERE v_role = 'super_admin' OR u.organization_id = v_org ORDER BY u.created_at DESC;
END;
$$;

-- Raw resolvers are internal. Browser front doors (get_my_capabilities/profile/
-- project access) bind the subject; SECURITY DEFINER callers retain these helpers.
REVOKE ALL ON FUNCTION public.capabilities_for_user(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.capabilities_for_user(uuid,uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_effective_capabilities(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.effective_project_role(uuid,uuid) FROM PUBLIC, anon, authenticated;
-- This resolver is also called by invoker views/policies. Bind its argument
-- rather than revoking the executable policy dependency.
CREATE OR REPLACE FUNCTION public.get_current_user_org_id(_user_id uuid)
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
 SELECT u.organization_id FROM public.approved_users u WHERE u.id = _user_id
   AND (public.security_is_service() OR _user_id = public.get_current_user_id());
$$;
GRANT EXECUTE ON FUNCTION public.get_current_user_org_id(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.capabilities_for_user(uuid), public.capabilities_for_user(uuid,uuid),
  public.get_effective_capabilities(uuid), public.effective_project_role(uuid,uuid), public.get_current_user_org_id(uuid) TO service_role;

-- These signatures exist in effective production metadata but have no tracked
-- definition/consumer in this repository. Preserve service access, close browser
-- EXECUTE, and tolerate their absence in clean contract-built databases.
DO $legacy$
DECLARE signature text; target regprocedure;
BEGIN
  FOREACH signature IN ARRAY ARRAY[
    'public.bulk_upsert_customers(uuid,jsonb)',
    'public.generate_multi_tier_supply_chain_data(uuid,uuid,text)',
    'public.get_multi_tier_supply_chain_data(uuid,uuid,text)',
    'public.get_unlinked_products(uuid,uuid,text)',
    'public.ingest_inbound_logistics_rpc(jsonb,uuid,text)',
    'public.ingest_outbound_logistics_rpc(jsonb,uuid,text)',
    'public.ingest_dedup_natural_key(text,text[],text[])',
    'public.recompute_project_completion(uuid)'
  ] LOOP
    target := to_regprocedure(signature);
    IF target IS NOT NULL THEN
      EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', target);
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', target);
    END IF;
  END LOOP;
END;
$legacy$;
SELECT pg_notify('pgrst', 'reload schema');

-- Explicit project membership/delegation and the creator remain legitimate
-- scope on legacy rows without organization UUIDs. Stamped projects retain
-- the existing organization membership requirement. Account admin alone
-- never makes a caller a member of another tenant. Capability resolution stays
-- the existing single source.
CREATE OR REPLACE FUNCTION public.project_rights_for_user(p_user_id uuid, p_project_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user      public.approved_users%ROWTYPE;
  v_project   public.projects%ROWTYPE;
  v_active    boolean;
  v_super     boolean;
  v_member    boolean;
  v_here      boolean;
  v_land      boolean;
  v_resolved  jsonb;
  v_caps      jsonb;
  v_decisions jsonb;
BEGIN
  SELECT * INTO v_user FROM public.approved_users WHERE id = p_user_id;
  SELECT * INTO v_project FROM public.projects WHERE id = p_project_id;
  IF v_user.id IS NULL OR v_project.id IS NULL THEN RETURN NULL; END IF;

  -- A suspended account cannot sign in (D205), so it holds nothing, whatever its role says.
  v_active := COALESCE(v_user.is_active, false) AND (v_user.role = 'super_admin'::public.app_role OR NOT EXISTS (SELECT 1 FROM public.organizations o WHERE o.id=v_project.organization_id AND o.access_valid_until <= now()));
  v_super  := (v_user.role = 'super_admin'::public.app_role);
  -- D231 — rights are stated as the account has them WHILE WORKING IN THE PROJECT'S
  -- ORGANIZATION.
  v_member := v_project.organization_id IS NOT NULL AND EXISTS (
                SELECT 1 FROM public.organization_members om
                 WHERE om.org_id = v_project.organization_id AND om.user_id = v_user.id);
  v_here   := v_project.organization_id IS NOT NULL AND v_user.organization_id = v_project.organization_id;
  -- `has_project_access` — the gate `ingest_land_file` applies to every upload (D279: the
  -- modeler, an app admin, or Editor/Owner on the project).
  v_land   := v_project.modeler_id = v_user.id
              OR v_user.role IN ('admin'::public.app_role, 'super_admin'::public.app_role)
              OR public.project_role_rank(public.effective_project_role(v_user.id, v_project.id))
                 >= public.project_role_rank('editor');

  -- The resolver's project answer, for the keys its project layer has an opinion on.
  SELECT COALESCE(jsonb_object_agg(f.key, f.value), '{}'::jsonb) INTO v_resolved
    FROM jsonb_each(public.capabilities_for_user(v_user.id, v_project.id) -> 'features') f
   WHERE f.key IN (SELECT DISTINCT capability_key FROM public.project_role_capabilities);

  SELECT COALESCE(jsonb_object_agg(r.key,
           to_jsonb(v_active AND COALESCE((r.value #>> '{}')::boolean, false)
                    AND (r.key <> 'data_edit_inputs' OR v_land))), '{}'::jsonb)
    INTO v_caps
    FROM jsonb_each(v_resolved) r;

  -- D276 — why each right holds or not. The rule's own decider, then the two gates applied
  -- after it: suspension and, for Edit Input Data, the upload gate.
  SELECT COALESCE(jsonb_object_agg(d.key,
           d.value || jsonb_build_object(
             'allowed', COALESCE((v_caps ->> d.key)::boolean, false),
             'decided_by', CASE
               WHEN NOT v_active THEN 'suspended'
               WHEN d.key = 'data_edit_inputs' AND (d.value ->> 'allowed')::boolean AND NOT v_land
                 THEN 'upload_gate'
               ELSE d.value ->> 'decided_by' END)), '{}'::jsonb)
    INTO v_decisions
    FROM jsonb_each(public.project_right_decisions(v_user.id, v_project.id)) d;

  RETURN jsonb_build_object(
    'account_active',        v_active,
    'visible',               v_active AND (v_super OR v_member OR (v_project.organization_id IS NULL AND (v_project.modeler_id = v_user.id OR public.effective_project_role(v_user.id, v_project.id) IS NOT NULL))),
    'can_edit_project',      v_active AND (v_super OR (v_member AND (v_project.modeler_id = v_user.id
                                                                     OR v_user.role IN ('admin'::public.app_role, 'super_admin'::public.app_role)))),
    'working_in_project_org', v_here,
    'may_land_uploads',      v_active AND v_land,
    'capabilities',          v_caps,
    'resolved_capabilities', v_resolved,
    'decisions',             v_decisions);
END; $$;
