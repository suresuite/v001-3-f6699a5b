-- D309/D310: SQL readers and remaining project entry points use the same verified boundary.

CREATE OR REPLACE FUNCTION public.active_model_validation_by_content(
  p_project_id    uuid,
  p_policy_hash   text,
  p_graph_hash    text,
  p_scenario_hash text
) RETURNS SETOF public.model_validations
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
#variable_conflict use_column
BEGIN

  PERFORM public.security_assert_project(p_project_id, NULL);

  RETURN QUERY WITH sim AS (
    SELECT dv.hash_inputs AS h
      FROM public.dataset_versions dv
     WHERE dv.project_id = p_project_id AND dv.graph_hash = p_graph_hash AND dv.hash_inputs IS NOT NULL
     ORDER BY dv.created_at, dv.id
     LIMIT 1
  )
  SELECT m.*
    FROM public.model_validations m
   WHERE m.project_id    = p_project_id
     AND m.policy_hash   = p_policy_hash
     AND m.scenario_hash = p_scenario_hash
     AND m.status        = 'active'
     AND m.verdict       = 'validated'
     AND ((m.hash_simulation IS NOT NULL AND m.hash_simulation = (SELECT h FROM sim))
       OR (m.hash_simulation IS NULL AND m.graph_hash = p_graph_hash))
   ORDER BY m.validated_at DESC, m.id
   LIMIT 1;
END;
$$;

CREATE OR REPLACE FUNCTION public.analysis_current_run(_project_id uuid, _analysis_kind text)
RETURNS uuid
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_scope text := COALESCE(public.analysis_scope_now(_project_id, _analysis_kind), 'all');
  v_hash  text;
  v_id    uuid;
BEGIN

  PERFORM public.security_assert_project(_project_id, NULL);

  v_hash := public.current_level_hash(_project_id, v_scope);
  SELECT r.id INTO v_id
    FROM public.analysis_runs r
   WHERE r.project_id = _project_id AND r.analysis_kind = _analysis_kind
     AND r.status = 'succeeded' AND r.input_scope = v_scope AND r.input_hash = v_hash
   ORDER BY r.started_at DESC, r.id
   LIMIT 1;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.analysis_latest_run(
  _project_id uuid,
  _analysis_kind text
) RETURNS uuid
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
#variable_conflict use_column
BEGIN

  PERFORM public.security_assert_project(_project_id, NULL);

  RETURN (SELECT r.id
    FROM public.analysis_runs r
   WHERE r.project_id = _project_id
     AND r.analysis_kind = _analysis_kind
     AND r.status = 'succeeded'
   ORDER BY r.started_at DESC, r.id
   LIMIT 1);
END;
$$;

CREATE OR REPLACE FUNCTION public.analysis_scope_now(p_project_id uuid, p_kind text)
RETURNS text
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
#variable_conflict use_column
BEGIN

  PERFORM public.security_assert_project(p_project_id, NULL);

  RETURN (SELECT CASE
           WHEN k.fallback_rule = 'deep_tier_incomplete'
            AND (NOT EXISTS (SELECT 1 FROM public.network_nodes n WHERE n.project_id = p_project_id)
                 OR NOT EXISTS (SELECT 1 FROM public.network_edges e WHERE e.project_id = p_project_id))
           THEN k.fallback_scope
           ELSE k.input_scope
         END
    FROM public.analysis_kinds k
   WHERE k.kind = p_kind);
END;
$$;

CREATE OR REPLACE FUNCTION public.api_can_access_project(p_org_id uuid, p_project_id uuid)
RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
#variable_conflict use_column
BEGIN

  PERFORM public.security_assert_project(p_project_id, NULL);

  RETURN (SELECT EXISTS (
    SELECT 1 FROM public.projects p
    WHERE p.id = p_project_id AND p.organization_id = p_org_id
  ));
END;
$$;

CREATE OR REPLACE FUNCTION public.classify_node_echelon(p_project_id uuid, p_node_id text)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  is_outbound_target boolean := false;   -- a customer
  is_outbound_source boolean := false;   -- a product
  is_inbound_source  boolean := false;   -- a supplier
  is_inbound_target  boolean := false;   -- a purchased material
  is_bom_source      boolean := false;   -- consumed by something
  is_bom_target      boolean := false;   -- built from something
  is_plant           boolean := false;
BEGIN

  PERFORM public.security_assert_project(p_project_id, NULL);

  IF p_node_id IS NULL OR btrim(p_node_id) = '' THEN
    RETURN 'unknown';
  END IF;

  -- One pass over each table rather than six EXISTS queries per node: the old
  -- classifier ran four correlated subqueries and `refresh_node_list_for_project`
  -- calls it twice per row, which is 8 scans per node on a 638-node project.
  SELECT
    bool_or(data_source = 'outbound' AND to_location   = p_node_id),
    bool_or(data_source = 'outbound' AND from_location = p_node_id),
    bool_or(data_source = 'inbound'  AND from_location = p_node_id),
    bool_or(data_source = 'inbound'  AND to_location   = p_node_id),
    bool_or(data_source = 'bom'      AND from_location = p_node_id),
    bool_or(data_source = 'bom'      AND to_location   = p_node_id)
  INTO is_outbound_target, is_outbound_source, is_inbound_source,
       is_inbound_target, is_bom_source, is_bom_target
  FROM (
    SELECT data_source, from_location, to_location
      FROM public.supply_chain_data
     WHERE project_id = p_project_id
       AND (from_location = p_node_id OR to_location = p_node_id)
    UNION ALL
    SELECT data_source, from_location, to_location
      FROM public.supply_chain_data_multi_tier
     WHERE project_id = p_project_id
       AND (from_location = p_node_id OR to_location = p_node_id)
  ) both_lanes;

  SELECT EXISTS (
    SELECT 1 FROM public.projects p
     WHERE p.id = p_project_id AND p.plant_name = p_node_id
  ) INTO is_plant;

  is_outbound_target := COALESCE(is_outbound_target, false);
  is_outbound_source := COALESCE(is_outbound_source, false);
  is_inbound_source  := COALESCE(is_inbound_source,  false);
  is_inbound_target  := COALESCE(is_inbound_target,  false);
  is_bom_source      := COALESCE(is_bom_source,      false);
  is_bom_target      := COALESCE(is_bom_target,      false);

  IF is_outbound_target AND NOT (is_outbound_source OR is_bom_source OR is_bom_target
                                 OR is_inbound_source OR is_inbound_target) THEN
    RETURN 'customer';
  ELSIF is_inbound_source AND NOT (is_outbound_target OR is_outbound_source
                                   OR is_bom_source OR is_bom_target OR is_inbound_target) THEN
    RETURN 'supplier';
  ELSIF is_bom_source AND is_bom_target THEN
    RETURN 'subassembly';
  ELSIF is_outbound_source OR is_bom_target THEN
    RETURN 'product';
  ELSIF is_inbound_target OR is_bom_source THEN
    RETURN 'material';
  ELSIF is_outbound_target THEN
    -- A customer that also holds another role: the outbound target is the claim a
    -- lane states directly, so it wins over nothing else matching.
    RETURN 'customer';
  ELSIF is_inbound_source THEN
    RETURN 'supplier';
  ELSIF is_plant THEN
    RETURN 'plant';
  ELSE
    RETURN 'unknown';
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.classify_node_type(p_project_id uuid, p_node_id text)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
#variable_conflict use_column
BEGIN

  PERFORM public.security_assert_project(p_project_id, NULL);

  RETURN (SELECT CASE public.classify_node_echelon(p_project_id, p_node_id)
           WHEN 'subassembly' THEN 'material'
           WHEN 'plant'       THEN 'plant'
           ELSE public.classify_node_echelon(p_project_id, p_node_id)
         END);
END;
$function$;

CREATE OR REPLACE FUNCTION public.current_graph_hash(p_project_id uuid)
RETURNS text
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'public'
AS $$
#variable_conflict use_column
BEGIN

  PERFORM public.security_assert_project(p_project_id, NULL);

  RETURN (SELECT public.project_graph_hashes(p_project_id) ->> 'graph_hash');
END;
$$;

CREATE OR REPLACE FUNCTION public.current_hash_inputs(p_project_id uuid)
RETURNS text
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'public'
AS $$
#variable_conflict use_column
BEGIN

  PERFORM public.security_assert_project(p_project_id, NULL);

  RETURN (SELECT public.project_graph_hashes(p_project_id) ->> 'hash_inputs');
END;
$$;

CREATE OR REPLACE FUNCTION public.current_hash_network(p_project_id uuid)
RETURNS text
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'public'
AS $$
#variable_conflict use_column
BEGIN

  PERFORM public.security_assert_project(p_project_id, NULL);

  RETURN (SELECT public.project_graph_hashes(p_project_id) ->> 'hash_network');
END;
$$;

CREATE OR REPLACE FUNCTION public.current_level_hash(p_project_id uuid, p_scope text)
RETURNS text
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'public'
AS $$
#variable_conflict use_column
BEGIN

  PERFORM public.security_assert_project(p_project_id, NULL);

  RETURN (SELECT public.project_graph_hashes(p_project_id) ->> public._scope_hash_key(p_scope));
END;
$$;

CREATE OR REPLACE FUNCTION public.current_policy_hash(p_project_id uuid)
RETURNS text
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
#variable_conflict use_column
BEGIN

  PERFORM public.security_assert_project(p_project_id, NULL);

  RETURN (SELECT encode(extensions.digest(public._build_policy_snapshot(p_project_id)::text, 'sha256'), 'hex'));
END;
$$;

CREATE OR REPLACE FUNCTION public.expire_agent_proposals(p_project_id uuid)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE v_n integer;
BEGIN

  PERFORM public.security_assert_project(p_project_id, NULL);

  -- TTL ONLY. Drift is answered by `proposal_grounding_state` below, computed
  -- at read time, so a proposal whose project drifts and drifts back is live
  -- again with nothing rewritten (WP 4.4, §4 D70).
  UPDATE public.proposals p
     SET status = 'expired',
         status_reason = 'ttl'
   WHERE p.project_id = p_project_id
     AND p.status IN ('draft','proposed','approved')
     AND p.expires_at < now();
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END; $fn$;

CREATE OR REPLACE FUNCTION public.freshness_of(
  _recorded_hash text,
  _project_id    uuid
) RETURNS text
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $fn$
#variable_conflict use_column
BEGIN

  PERFORM public.security_assert_project(_project_id, NULL);

  RETURN (SELECT CASE
    
    
    
    WHEN _recorded_hash IS NULL THEN 'unknown'
    WHEN _recorded_hash = public.current_graph_hash(_project_id) THEN 'fresh'
    ELSE 'stale'
  END);
END;
$fn$;

CREATE OR REPLACE FUNCTION public.get_chat_plan(p_plan_id uuid, p_user_id uuid)
RETURNS SETOF public.chat_plans
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
#variable_conflict use_column
BEGIN
  p_user_id := public.security_actor(p_user_id);

  RETURN QUERY SELECT * FROM public.chat_plans WHERE id = p_plan_id AND user_id = p_user_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_graph_version_state(p_project_id uuid)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_h   jsonb := public.project_graph_hashes(p_project_id);
  v_cur public.dataset_versions%ROWTYPE;
  v_lat public.dataset_versions%ROWTYPE;
  v_n   bigint;
BEGIN

  PERFORM public.security_assert_project(p_project_id, NULL);

  SELECT * INTO v_cur FROM public.dataset_versions
   WHERE project_id = p_project_id AND graph_hash = v_h ->> 'graph_hash'
   ORDER BY created_at, id LIMIT 1;
  SELECT * INTO v_lat FROM public.dataset_versions
   WHERE project_id = p_project_id ORDER BY created_at DESC, id DESC LIMIT 1;
  SELECT count(*) INTO v_n FROM public.dataset_versions WHERE project_id = p_project_id;
  RETURN jsonb_build_object(
    'current', v_h,
    'current_version', CASE WHEN v_cur.id IS NULL THEN NULL ELSE jsonb_build_object(
        'id', v_cur.id, 'version_no', v_cur.version_no, 'label', v_cur.label,
        'graph_hash', v_cur.graph_hash, 'created_at', v_cur.created_at) END,
    'latest', CASE WHEN v_lat.id IS NULL THEN NULL ELSE jsonb_build_object(
        'id', v_lat.id, 'version_no', v_lat.version_no, 'label', v_lat.label,
        'graph_hash', v_lat.graph_hash, 'hash_inputs', v_lat.hash_inputs,
        'hash_network', v_lat.hash_network, 'hash_product', v_lat.hash_product,
        'hash_process', v_lat.hash_process, 'hash_firm', v_lat.hash_firm,
        'product_version_id', v_lat.product_version_id,
        'process_version_id', v_lat.process_version_id,
        'firm_version_id', v_lat.firm_version_id,
        'simulation_version_id', v_lat.simulation_version_id,
        'author_email', v_lat.author_email, 'created_at', v_lat.created_at) END,
    'version_count', v_n,
    -- WP 11.1 · §4 D258 — each level's own version, from the same stored hashes.
    'levels', jsonb_build_object(
      'product', public._graph_level_state(p_project_id, 'product', v_h ->> 'hash_product'),
      'process', public._graph_level_state(p_project_id, 'process', v_h ->> 'hash_process'),
      'firm',    public._graph_level_state(p_project_id, 'firm',    v_h ->> 'hash_firm'),
      -- WP 11.2 · the scope the engine reads, by the ONE scope → hash mapping.
      'simulation', public._graph_level_state(p_project_id, 'simulation',
                                              v_h ->> public._scope_hash_key('simulation'))));
END;
$$;

CREATE OR REPLACE FUNCTION public.get_my_capacity(p_project_id uuid, _actor_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
#variable_conflict use_column
BEGIN
  _actor_user_id := public.security_actor(_actor_user_id);
  PERFORM public.security_assert_project(p_project_id, NULL);

  RETURN (SELECT public._capacity_state(p_project_id, _actor_user_id));
END;
$$;

CREATE OR REPLACE FUNCTION public.get_network_edges_for_prominence(p_project_id uuid)
RETURNS TABLE(
  src_uid text,
  dst_uid text,
  relative_revenue numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN

  PERFORM public.security_assert_project(p_project_id, NULL);

  RETURN QUERY
  SELECT 
    ne.src_uid,
    ne.dst_uid,
    ne.relative_revenue
  FROM public.network_edges ne
  WHERE ne.project_id = p_project_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_network_edges(
  p_project_id uuid,
  p_user_id uuid,
  p_user_email text,
  p_plant_name text DEFAULT NULL
)
RETURNS TABLE(
  id uuid,
  project_id uuid,
  plant_name text,
  src_uid text,
  dst_uid text,
  relation_type text,
  relative_revenue numeric,
  relative_revenue_percentage numeric,
  depth integer,
  direction text,
  uploaded_by uuid,
  created_by uuid,
  organization text,
  created_at timestamp with time zone,
  updated_at timestamp with time zone
) AS $$
BEGIN
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, NULL);

  -- Set caller context for RLS helpers
  PERFORM public.set_current_user_context(p_user_id, p_user_email);

  RETURN QUERY
  SELECT
    ne.id,
    ne.project_id,
    ne.plant_name,
    ne.src_uid,
    ne.dst_uid,
    ne.relation_type,
    ne.relative_revenue,
    ne.relative_revenue_percentage,
    ne.depth,
    ne.direction,
    ne.uploaded_by,
    ne.created_by,
    ne.organization,
    ne.created_at,
    ne.updated_at
  FROM public.network_edges ne
  WHERE ne.project_id = p_project_id
    AND (p_plant_name IS NULL OR ne.plant_name = p_plant_name)
  ORDER BY ne.created_at;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.get_network_nodes_for_prominence(p_project_id uuid)
RETURNS TABLE(
  id uuid,
  uid text,
  revenue numeric,
  name text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN

  PERFORM public.security_assert_project(p_project_id, NULL);

  RETURN QUERY
  SELECT 
    nn.id,
    nn.uid,
    nn.revenue,
    nn.name
  FROM public.network_nodes nn
  WHERE nn.project_id = p_project_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_network_summary(
  p_project_id uuid,
  p_user_id uuid,
  p_user_email text,
  p_plant_name text DEFAULT NULL
)
RETURNS TABLE(
  id uuid,
  project_id uuid,
  plant_name text,
  nodes_count integer,
  edges_count integer,
  tiers_data jsonb,
  uploaded_by uuid,
  created_by uuid,
  organization text,
  created_at timestamp with time zone,
  updated_at timestamp with time zone
) AS $$
BEGIN
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, NULL);

  -- Set caller context for RLS helpers
  PERFORM public.set_current_user_context(p_user_id, p_user_email);

  RETURN QUERY
  SELECT
    ns.id,
    ns.project_id,
    ns.plant_name,
    ns.nodes_count,
    ns.edges_count,
    ns.tiers_data,
    ns.uploaded_by,
    ns.created_by,
    ns.organization,
    ns.created_at,
    ns.updated_at
  FROM public.network_summary ns
  WHERE ns.project_id = p_project_id
    AND (p_plant_name IS NULL OR ns.plant_name = p_plant_name)
  ORDER BY ns.created_at;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE OR REPLACE FUNCTION public.get_policy_version_snapshot(p_version_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
#variable_conflict use_column
BEGIN

  PERFORM public.security_assert_project((SELECT p.project_id FROM public.policy_versions p WHERE p.id = p_version_id), NULL);

  RETURN (SELECT snapshot FROM public.policy_versions WHERE id = p_version_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_project_dataset_status(p_project_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_bom_level text;
  has_bom boolean := false;
  has_inbound boolean := false;
  has_outbound boolean := false;
BEGIN

  PERFORM public.security_assert_project(p_project_id, NULL);

  SELECT bom_level INTO v_bom_level
  FROM public.projects
  WHERE id = p_project_id;

  IF v_bom_level = 'single' THEN
    SELECT EXISTS(SELECT 1 FROM public.bom_single_level WHERE project_id = p_project_id)
    INTO has_bom;
  ELSE
    SELECT EXISTS(SELECT 1 FROM public.bom_multi_level WHERE project_id = p_project_id)
    INTO has_bom;
  END IF;

  SELECT EXISTS(SELECT 1 FROM public.inbound_logistics WHERE project_id = p_project_id)
  INTO has_inbound;

  SELECT EXISTS(SELECT 1 FROM public.outbound_logistics WHERE project_id = p_project_id)
  INTO has_outbound;

  RETURN jsonb_build_object(
    'bom', has_bom,
    'inbound', has_inbound,
    'outbound', has_outbound
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_validated_model_evidence(p_validation_id uuid)
RETURNS SETOF public.model_validation_evidence
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
#variable_conflict use_column
BEGIN

  PERFORM public.security_assert_project((SELECT p.project_id FROM public.model_validations p WHERE p.id = p_validation_id), NULL);

  RETURN QUERY SELECT * FROM public.model_validation_evidence WHERE validation_id = p_validation_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.grant_project_delegation(
  _grantor_user_id uuid,
  _project_id      uuid,
  _grantee_user_id uuid,
  _project_role    text,
  _expires_at      timestamptz,
  _rationale       text
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_grantor_role text;
  v_id           uuid;
BEGIN
  _grantor_user_id := public.security_actor(_grantor_user_id);
  PERFORM public.security_assert_project(_project_id, NULL);

  IF _project_role IS NULL OR public.project_role_rank(_project_role) = 0 THEN
    RAISE EXCEPTION 'unknown project_role %', _project_role USING ERRCODE = '22023';
  END IF;
  IF _rationale IS NULL OR btrim(_rationale) = '' THEN
    RAISE EXCEPTION 'a delegation must say why it exists' USING ERRCODE = '22023';
  END IF;

  -- EXPIRING: no end date, no grant.
  IF _expires_at IS NULL THEN
    RAISE EXCEPTION 'a delegation must expire — expires_at is required'
      USING ERRCODE = '22023';
  END IF;
  IF _expires_at <= now() THEN
    RAISE EXCEPTION 'expires_at % is already in the past', _expires_at
      USING ERRCODE = '22023';
  END IF;

  v_grantor_role := public.effective_project_role(_grantor_user_id, _project_id);
  IF v_grantor_role IS NULL THEN
    RAISE EXCEPTION 'grantor holds nothing on this project and cannot delegate'
      USING ERRCODE = '42501';
  END IF;

  -- SUBTRACTIVE: never more than the grantor's own level.
  IF public.project_role_rank(_project_role) > public.project_role_rank(v_grantor_role) THEN
    RAISE EXCEPTION 'a grant may not exceed the grantor''s own level (% > %)',
      _project_role, v_grantor_role USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.delegation_grants
    (project_id, grantor_user_id, grantee_user_id, project_role, expires_at, rationale)
  VALUES (_project_id, _grantor_user_id, _grantee_user_id, _project_role, _expires_at, _rationale)
  RETURNING id INTO v_id;
  RETURN v_id;
END; $$;

CREATE OR REPLACE FUNCTION public.is_stale(
  _recorded_hash text,
  _project_id    uuid
) RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $fn$
#variable_conflict use_column
BEGIN

  PERFORM public.security_assert_project(_project_id, NULL);

  RETURN (SELECT public.freshness_of(_recorded_hash, _project_id) <> 'fresh');
END;
$fn$;

CREATE OR REPLACE FUNCTION public.list_agent_proposals(
  p_project_id uuid, p_status text DEFAULT NULL
) RETURNS SETOF public.proposals
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN

  PERFORM public.security_assert_project(p_project_id, NULL);

  PERFORM public.expire_agent_proposals(p_project_id);
  RETURN QUERY SELECT * FROM public.proposals
   WHERE project_id = p_project_id
     AND (p_status IS NULL OR status = p_status)
   ORDER BY created_at DESC;
END; $$;

CREATE OR REPLACE FUNCTION public.list_chat_folders(p_user_id uuid)
RETURNS SETOF public.chat_folders
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
#variable_conflict use_column
BEGIN
  p_user_id := public.security_actor(p_user_id);

  RETURN QUERY SELECT * FROM public.chat_folders WHERE user_id = p_user_id
   ORDER BY position ASC, name ASC;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_chat_threads(p_user_id uuid)
RETURNS SETOF public.chat_threads
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
#variable_conflict use_column
BEGIN
  p_user_id := public.security_actor(p_user_id);

  RETURN QUERY SELECT * FROM public.chat_threads WHERE user_id = p_user_id
   ORDER BY pinned DESC, last_message_at DESC NULLS LAST, created_at DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_dataset_versions(p_project_id uuid)
RETURNS TABLE (
  id           uuid,
  label        text,
  graph_hash   text,
  author_email text,
  created_at   timestamptz,
  version_no   integer,
  tuple        jsonb
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
#variable_conflict use_column
BEGIN

  PERFORM public.security_assert_project(p_project_id, NULL);

  RETURN QUERY SELECT dv.id, dv.label, dv.graph_hash, dv.author_email, dv.created_at, dv.version_no,
         public.dataset_version_tuple(dv.id)
  FROM public.dataset_versions dv
  WHERE dv.project_id = p_project_id
  ORDER BY dv.created_at DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_model_validations(p_project_id uuid)
RETURNS TABLE (
  id                       uuid,
  policy_version_id        uuid,
  policy_hash              text,
  dataset_version_id       uuid,
  graph_hash               text,
  scenario_hash            text,
  engine_fingerprint       text,
  adopted_warmup_days      integer,
  warmup_method            text,
  recommended_replications integer,
  verdict                  text,
  basis                    text,
  status                   text,
  evidence_run_id          uuid,
  author_email             text,
  validated_at             timestamptz,
  hash_simulation          text,
  simulation_version_id    uuid
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
#variable_conflict use_column
BEGIN

  PERFORM public.security_assert_project(p_project_id, NULL);

  RETURN QUERY SELECT id, policy_version_id, policy_hash, dataset_version_id, graph_hash,
         scenario_hash, engine_fingerprint, adopted_warmup_days, warmup_method,
         recommended_replications, verdict, basis, status, evidence_run_id,
         author_email, validated_at, hash_simulation, simulation_version_id
  FROM public.model_validations
  WHERE project_id = p_project_id
  ORDER BY validated_at DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.list_policy_versions(p_project_id uuid)
RETURNS TABLE (
  id                uuid,
  label             text,
  notes             text,
  author_email      text,
  author_name       text,
  parent_version_id uuid,
  policy_hash       text,
  created_at        timestamptz,
  run_count         bigint,
  card_count        bigint,
  version_no        integer,
  version_code      text
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
#variable_conflict use_column
BEGIN

  PERFORM public.security_assert_project(p_project_id, NULL);

  RETURN QUERY SELECT
    v.id, v.label, v.notes, v.author_email, v.author_name,
    v.parent_version_id, v.policy_hash, v.created_at,
    (SELECT count(*) FROM public.simulation_runs  r WHERE r.policy_version_id = v.id),
    (SELECT count(*) FROM public.model_validations m WHERE m.policy_version_id = v.id),
    v.version_no,
    v.version_code
  FROM public.policy_versions v
  WHERE v.project_id = p_project_id
  ORDER BY v.created_at DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.node_bom_depth(p_project_id uuid, p_node_id text)
RETURNS integer
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
#variable_conflict use_column
BEGIN

  PERFORM public.security_assert_project(p_project_id, NULL);

  RETURN (SELECT MIN(d)::integer FROM (
    SELECT b.level AS d FROM public.bom_multi_level b
      WHERE b.project_id = p_project_id AND b.material_id = p_node_id
    UNION ALL
    SELECT GREATEST(b.level - 1, 0) FROM public.bom_multi_level b
      WHERE b.project_id = p_project_id AND b.higher_level_component_id = p_node_id
    UNION ALL
    
    
    
    SELECT 1 FROM public.bom_single_level s
      WHERE s.project_id = p_project_id AND s.material_id = p_node_id
    UNION ALL
    SELECT 0 FROM public.bom_single_level s
      WHERE s.project_id = p_project_id AND s.product_id = p_node_id
  ) depths);
END;
$function$;

CREATE OR REPLACE FUNCTION public.node_supply_tier(p_project_id uuid, p_node_id text)
RETURNS integer
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
#variable_conflict use_column
BEGIN

  PERFORM public.security_assert_project(p_project_id, NULL);

  RETURN (SELECT MIN(tier) FROM (
    SELECT 0 AS tier FROM public.projects p
      WHERE p.id = p_project_id AND p.plant_name = p_node_id
    UNION ALL
    SELECT 1 FROM public.inbound_logistics i
      WHERE i.project_id = p_project_id AND i.supplier_id = p_node_id
    UNION ALL
    SELECT 1 FROM public.tier2_suppliers t
      WHERE t.project_id = p_project_id AND t.supplier_id = p_node_id
    UNION ALL
    SELECT 2 FROM public.tier2_suppliers t
      WHERE t.project_id = p_project_id AND t.upstream_supplier_id = p_node_id
    UNION ALL
    SELECT 2 FROM public.tier3_suppliers t
      WHERE t.project_id = p_project_id AND t.supplier_id = p_node_id
    UNION ALL
    SELECT 3 FROM public.tier3_suppliers t
      WHERE t.project_id = p_project_id AND t.upstream_supplier_id = p_node_id
  ) tiers);
END;
$function$;

CREATE OR REPLACE FUNCTION public.project_access_read(p_project_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_project public.projects%ROWTYPE;
  v_people  jsonb;
  v_keys    jsonb;
  v_matrix  jsonb;
BEGIN

  PERFORM public.security_assert_project(p_project_id, NULL);

  SELECT * INTO v_project FROM public.projects WHERE id = p_project_id;
  IF v_project.id IS NULL THEN RAISE EXCEPTION 'project not found'; END IF;

  -- The same two reads as `admin_get_user_memberships`, so the legend is one legend.
  SELECT COALESCE(jsonb_agg(jsonb_build_object('key', c.key, 'label', c.label)
                            ORDER BY c.sort_order, c.key), '[]'::jsonb)
    INTO v_keys
    FROM public.capabilities c
   WHERE c.key IN (SELECT DISTINCT capability_key FROM public.project_role_capabilities);

  SELECT COALESCE(jsonb_object_agg(r.project_role, r.caps), '{}'::jsonb) INTO v_matrix
    FROM (SELECT prc.project_role, jsonb_object_agg(prc.capability_key, prc.allowed) AS caps
            FROM public.project_role_capabilities prc
           GROUP BY prc.project_role) r;

  -- Every account recorded on the project or able to see it through its organization.
  WITH reach AS (
    SELECT v_project.modeler_id AS user_id WHERE v_project.modeler_id IS NOT NULL
    UNION
    SELECT pm.user_id FROM public.project_members pm WHERE pm.project_id = v_project.id
    UNION
    SELECT dg.grantee_user_id FROM public.delegation_grants dg
     WHERE dg.project_id = v_project.id AND dg.revoked_at IS NULL AND dg.expires_at > now()
    UNION
    SELECT om.user_id FROM public.organization_members om
     WHERE v_project.organization_id IS NOT NULL AND om.org_id = v_project.organization_id
  ), people AS (
    SELECT u.*,
           (u.role = 'super_admin'::public.app_role)                        AS is_super,
           public.effective_project_role(u.id, v_project.id)                AS eff,
           public.project_rights_for_user(u.id, v_project.id)               AS rights,
           (v_project.organization_id IS NOT NULL
            AND u.organization_id = v_project.organization_id)              AS active_here
      FROM reach
      JOIN public.approved_users u ON u.id = reach.user_id
  )
  SELECT COALESCE(jsonb_agg(x.j ORDER BY x.is_modeler DESC, x.rank DESC, x.sort_key, x.user_id), '[]'::jsonb)
    INTO v_people
  FROM (
    SELECT u.id AS user_id,
           (u.id = v_project.modeler_id) AS is_modeler,
           COALESCE(public.project_role_rank(u.eff), 0) AS rank,
           lower(COALESCE(u.name, u.email, '')) AS sort_key,
           jsonb_build_object(
      'user_id',             u.id,
      'name',                u.name,
      'email',               u.email,
      'account_active',      COALESCE(u.is_active, true),
      'role',                u.role::text,
      'is_super_admin',      u.is_super,
      'is_modeler',          u.id = v_project.modeler_id,
      -- The account's role in THIS project's organization, NULL when it is not a member.
      'org_role',            om.org_role,
      'in_project_org',      om.user_id IS NOT NULL,
      -- "Projects: org-wide view" reads the ACTIVE organization and nothing else (D210).
      'active_in_project_org', u.active_here,
      -- D217 — the account's DEFAULT organization (D216), wherever it is; NULL when none.
      'default_org_id',      dm.org_id,
      'default_org_name',    dmo.name,
      -- D230 — the rights are `project_rights_for_user`'s, the answer the app's gates read.
      'visible',             (u.rights ->> 'visible')::boolean,
      'can_edit_project',    (u.rights ->> 'can_edit_project')::boolean,
      'may_land_uploads',    (u.rights ->> 'may_land_uploads')::boolean,
      'member', CASE WHEN pm.project_id IS NULL THEN NULL ELSE jsonb_build_object(
                  'project_role', pm.project_role,
                  'expires_at',   pm.expires_at,
                  'expired',      pm.expires_at IS NOT NULL AND pm.expires_at <= now(),
                  'rationale',    pm.rationale,
                  'granted_by',   COALESCE(gb.name, gb.email),
                  'updated_at',   pm.updated_at) END,
      'delegations', COALESCE((
          SELECT jsonb_agg(jsonb_build_object(
                   'id', dg.id, 'project_role', dg.project_role, 'expires_at', dg.expires_at,
                   'rationale', dg.rationale, 'grantor', COALESCE(g.name, g.email))
                   ORDER BY dg.expires_at)
            FROM public.delegation_grants dg
            LEFT JOIN public.approved_users g ON g.id = dg.grantor_user_id
           WHERE dg.grantee_user_id = u.id AND dg.project_id = v_project.id
             AND dg.revoked_at IS NULL AND dg.expires_at > now()), '[]'::jsonb),
      'effective_role',      u.eff,
      -- What the person may do (D230), and what the resolver's four layers alone would say.
      'capabilities',          u.rights -> 'capabilities',
      'resolved_capabilities', u.rights -> 'resolved_capabilities'
    ) AS j
      FROM people u
      LEFT JOIN public.organization_members om
             ON om.user_id = u.id AND om.org_id = v_project.organization_id
      LEFT JOIN public.organization_members dm ON dm.user_id = u.id AND dm.is_default
      LEFT JOIN public.organizations dmo ON dmo.id = dm.org_id
      LEFT JOIN public.project_members pm ON pm.project_id = v_project.id AND pm.user_id = u.id
      LEFT JOIN public.approved_users gb ON gb.id = pm.granted_by
  ) x;

  RETURN jsonb_build_object(
    'project_id',          v_project.id,
    'name',                v_project.name,
    'organization_id',     v_project.organization_id,
    'organization_name',   (SELECT o.name FROM public.organizations o WHERE o.id = v_project.organization_id),
    'modeler_id',          v_project.modeler_id,
    'people',              v_people,
    'project_capabilities', v_keys,
    'role_matrix',         v_matrix);
END; $$;

CREATE OR REPLACE FUNCTION public.project_graph_hashes(p_project_id uuid)
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  st     public.project_graph_state%ROWTYPE;
  v_gen  bigint := 0;
  v_snap jsonb;
  v_h    jsonb;
BEGIN

  PERFORM public.security_assert_project(p_project_id, NULL);

  SELECT * INTO st FROM public.project_graph_state WHERE project_id = p_project_id;
  IF FOUND THEN
    v_gen := st.generation;
    IF NOT st.dirty AND st.graph_hash IS NOT NULL AND st.level_spec = 1 THEN
      RETURN jsonb_build_object(
        'schema_version', st.schema_version, 'level_spec', st.level_spec,
        'graph_hash', st.graph_hash, 'hash_inputs', st.hash_inputs,
        'hash_network', st.hash_network, 'hash_product', st.hash_product,
        'hash_process', st.hash_process, 'hash_firm', st.hash_firm,
        'computed_at', st.computed_at, 'stored', true);
    END IF;
  END IF;
  v_snap := public._build_dataset_snapshot(p_project_id);
  v_h    := public._dataset_all_hashes(v_snap);
  PERFORM public._graph_state_store(p_project_id, v_h, v_gen);
  RETURN v_h || jsonb_build_object('computed_at', now(), 'stored', false);
END;
$$;

CREATE OR REPLACE FUNCTION public.run_series_retention(p_project_id uuid)
RETURNS interval
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
#variable_conflict use_column
BEGIN

  PERFORM public.security_assert_project(p_project_id, NULL);

  RETURN (SELECT CASE WHEN o.id IS NULL THEN interval '90 days'
              WHEN o.series_retention_days IS NULL THEN NULL
              ELSE make_interval(days => o.series_retention_days) END
    FROM public.projects p LEFT JOIN public.organizations o ON o.id = p.organization_id
   WHERE p.id = p_project_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.search_chat_messages(
  p_user_id uuid, p_query text, p_project_id uuid DEFAULT NULL
) RETURNS TABLE (
  thread_id uuid, thread_title text, project_id uuid,
  message_id uuid, seq integer, role text, snippet text, created_at timestamptz
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
#variable_conflict use_column
BEGIN
  p_user_id := public.security_actor(p_user_id);
  PERFORM public.security_assert_project(p_project_id, NULL);

  RETURN QUERY SELECT t.id, t.title, t.project_id,
         m.id, m.seq, m.role,
         ts_headline('english', m.content, plainto_tsquery('english', p_query),
                     'MaxWords=24, MinWords=8, ShortWord=2'),
         m.created_at
    FROM public.chat_messages m
    JOIN public.chat_threads t ON t.id = m.thread_id
   WHERE t.user_id = p_user_id
     AND (p_project_id IS NULL OR t.project_id = p_project_id)
     AND m.fts @@ plainto_tsquery('english', p_query)
   ORDER BY ts_rank(m.fts, plainto_tsquery('english', p_query)) DESC, m.created_at DESC
   LIMIT 50;
END;
$$;

CREATE OR REPLACE FUNCTION public.sweep_expired_files(p_user_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_rows  public.user_files[];
  v_paths text[];
  r       public.user_files;
BEGIN
  p_user_id := public.security_actor(p_user_id);

  SELECT array_agg(f.*) INTO v_rows
    FROM public.user_files f
   WHERE NOT f.retained
     AND f.expires_at < now()
     AND (p_user_id IS NULL OR f.user_id = p_user_id);
  IF v_rows IS NULL THEN
    RETURN jsonb_build_object('deleted', 0, 'paths', '[]'::jsonb);
  END IF;

  v_paths := ARRAY(SELECT (u).path FROM unnest(v_rows) AS u);
  PERFORM public._delete_workspace_objects(v_paths);
  DELETE FROM public.user_files WHERE path = ANY(v_paths);

  -- §16.3 file.expired — best-effort telemetry, never blocks the sweep.
  BEGIN
    FOREACH r IN ARRAY v_rows LOOP
      INSERT INTO public.ai_chat_events (event_kind, user_id, project_id, payload)
      VALUES ('file.expired', r.user_id, r.project_id,
              jsonb_build_object('file_id', r.id, 'kind', r.kind, 'size_bytes', r.size_bytes));
    END LOOP;
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  RETURN jsonb_build_object('deleted', coalesce(array_length(v_paths, 1), 0), 'paths', to_jsonb(v_paths));
END; $$;
REVOKE ALL ON FUNCTION public.get_erp_oauth_token(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_erp_oauth_token(text) TO service_role;
REVOKE ALL ON FUNCTION public.due_erp_sync_links() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.due_erp_sync_links() TO service_role;
REVOKE ALL ON FUNCTION public.prune_ai_chat_events(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.prune_ai_chat_events(integer) TO service_role;
REVOKE ALL ON FUNCTION public.cleanup_simulation_cache() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cleanup_simulation_cache() TO service_role;
REVOKE ALL ON FUNCTION public.sweep_expired_run_series(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.sweep_expired_run_series(integer) TO service_role;
REVOKE ALL ON FUNCTION public.audit_log_seal(boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.audit_log_seal(boolean) TO service_role;
REVOKE ALL ON FUNCTION public.sim_engine_report(text, text, text, jsonb, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.sim_engine_report(text, text, text, jsonb, jsonb) TO service_role;
REVOKE ALL ON FUNCTION public.mark_agent_proposal_applied(uuid, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mark_agent_proposal_applied(uuid, jsonb) TO service_role;
REVOKE ALL ON FUNCTION public.mark_agent_proposal_apply_failed(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mark_agent_proposal_apply_failed(uuid, text) TO service_role;
REVOKE ALL ON FUNCTION public.archive_project_memory(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.archive_project_memory(uuid) TO service_role;
REVOKE ALL ON FUNCTION public.update_risk_alert_impact(uuid, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_risk_alert_impact(uuid, jsonb) TO service_role;
REVOKE ALL ON FUNCTION public.supersede_agent_proposal(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.supersede_agent_proposal(uuid, uuid) TO service_role;
SELECT pg_notify('pgrst', 'reload schema');
