-- PLAN.md §27 WP 17.3 · §4 D310 — THE NEXUS BATTERY, STORED WITH ITS BASELINE.
--
-- The battery (`scsim.stress.nexus`, WP 17.2) disrupts every supplier and every
-- supplied material alone under one shared scenario and records the € of sales
-- each outage costs, per duration 2…9 weeks. It runs off the request path (WP
-- 17.4); this migration is where it lands and how the Nexus card reads it.
--
-- One battery is ONE `analysis_runs` row of the new kind `nexus_stress` and one
-- `analysis_results` row per target. Nothing new is a table: the store already
-- keys a run on its inputs, params and engine build and is append-only.
--
--   1. `analysis_start_nexus_stress` opens the run. It does NOT use
--      `analysis_get_or_start`, because that freezes the project's CURRENT data:
--      a battery is bound to a VALIDATED MODEL (its policy version) and a chosen
--      data version (the model's, by default), which is what "only runnable on a
--      validated baseline" means in the database (§27 WP 17.7). The binding is
--      written by the server into `params`, so a caller cannot misstate it, and
--      `input_hash` is the data version's `hash_inputs` — the simulation scope,
--      the same hash a simulation's RunKey binds (WP 11.2), so an upload the
--      engine never reads does not make a battery stale.
--   2. `analysis_publish_nexus_stress` validates every row against the run's own
--      declared scenario — the target kinds, one column per declared duration,
--      ranks 1…n — and completes the run through `analysis_complete_run`. A
--      battery is published whole or not at all.
--   3. `get_nexus_stress_results` is the card's read: the baseline (model, policy
--      version, data version, engine build, scenario), the summary, and the
--      materials and suppliers in rank order, with whether the data it was run on
--      is still the project's and whether its model is still active. Refuses a
--      reader without access to the project.
-- ============================================================================

-- ── 1 · the kind, and the level it reads ────────────────────────────────────

INSERT INTO public.analysis_kinds (kind, input_scope, fallback_scope, fallback_rule, description) VALUES
  ('nexus_stress', 'simulation', NULL, NULL,
   'The nexus battery (PLAN.md §27): every supplier and supplied material disrupted alone under one '
   'shared scenario, lost sales in € per duration, bound to a Validated Model and a data version.')
ON CONFLICT (kind) DO UPDATE
  SET input_scope = EXCLUDED.input_scope, fallback_scope = EXCLUDED.fallback_scope,
      fallback_rule = EXCLUDED.fallback_rule, description = EXCLUDED.description;

-- ── 2 · opening a battery ───────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.analysis_start_nexus_stress(
  _project_id          uuid,
  _model_validation_id uuid,
  _dataset_version_id  uuid,
  _code_version        text,
  _params              jsonb,
  _actor_user_id       uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_model       public.model_validations;
  v_ds          public.dataset_versions;
  v_params      jsonb;
  v_params_hash text;
  v_run         public.analysis_runs;
BEGIN
  PERFORM public.assert_writer_may_act('analysis_start_nexus_stress', _project_id, _actor_user_id);

  IF _code_version IS NULL OR _code_version = '' THEN
    RAISE EXCEPTION 'analysis_start_nexus_stress: the engine build is part of the key and may not be empty'
      USING ERRCODE = 'null_value_not_allowed';
  END IF;
  IF jsonb_typeof(_params -> 'scenario') IS DISTINCT FROM 'object'
     OR COALESCE(_params ->> 'scenario_hash', '') = '' THEN
    RAISE EXCEPTION 'analysis_start_nexus_stress: params must carry the battery''s scenario and its hash'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  -- Only on a validated baseline (§27 WP 17.7).
  SELECT * INTO v_model FROM public.model_validations WHERE id = _model_validation_id;
  IF NOT FOUND OR v_model.project_id IS DISTINCT FROM _project_id THEN
    RAISE EXCEPTION 'analysis_start_nexus_stress: no Validated Model % on project %', _model_validation_id, _project_id
      USING ERRCODE = 'no_data_found';
  END IF;
  IF v_model.status <> 'active' OR v_model.revoked_at IS NOT NULL THEN
    RAISE EXCEPTION 'analysis_start_nexus_stress: Validated Model % is %, and a battery runs only on an active one',
      _model_validation_id, v_model.status USING ERRCODE = 'P0A01';
  END IF;

  SELECT * INTO v_ds FROM public.dataset_versions
   WHERE id = COALESCE(_dataset_version_id, v_model.dataset_version_id);
  IF NOT FOUND OR v_ds.project_id IS DISTINCT FROM _project_id THEN
    RAISE EXCEPTION 'analysis_start_nexus_stress: data version % is not one of project %''s',
      COALESCE(_dataset_version_id, v_model.dataset_version_id), _project_id USING ERRCODE = 'no_data_found';
  END IF;
  IF v_ds.hash_inputs IS NULL THEN
    RAISE EXCEPTION 'analysis_start_nexus_stress: data version % has no simulation hash, so the battery could not name its inputs (I5)', v_ds.id
      USING ERRCODE = 'null_value_not_allowed';
  END IF;

  -- The binding, written HERE — the caller's own keys cannot override it.
  v_params := COALESCE(_params, '{}'::jsonb) || jsonb_build_object(
    'model_validation_id', v_model.id,
    'model_hash',          v_model.model_hash,
    'policy_version_id',   v_model.policy_version_id,
    'policy_hash',         v_model.policy_hash,
    'dataset_version_id',  v_ds.id,
    'graph_hash',          v_ds.graph_hash,
    'hash_inputs',         v_ds.hash_inputs);
  v_params_hash := encode(extensions.digest(v_params::text, 'sha256'), 'hex');

  SELECT * INTO v_run FROM public.analysis_runs
   WHERE project_id = _project_id AND analysis_kind = 'nexus_stress'
     AND input_hash = v_ds.hash_inputs AND params_hash = v_params_hash
     AND code_version = _code_version AND status = 'succeeded'
   LIMIT 1;
  IF FOUND THEN
    RETURN jsonb_build_object('run_id', v_run.id, 'cache_hit', true, 'status', v_run.status,
                              'params', v_run.params);
  END IF;

  INSERT INTO public.analysis_runs
    (project_id, analysis_kind, input_hash, input_scope, dataset_version_id, level_version_id,
     params_hash, params, code_version, actor_user_id)
  VALUES
    (_project_id, 'nexus_stress', v_ds.hash_inputs, 'simulation', v_ds.id, v_ds.simulation_version_id,
     v_params_hash, v_params, _code_version, _actor_user_id)
  ON CONFLICT DO NOTHING
  RETURNING * INTO v_run;
  IF FOUND THEN
    RETURN jsonb_build_object('run_id', v_run.id, 'cache_hit', false, 'status', v_run.status,
                              'params', v_run.params);
  END IF;

  -- Another job holds the same key and is still running.
  SELECT * INTO v_run FROM public.analysis_runs
   WHERE project_id = _project_id AND analysis_kind = 'nexus_stress'
     AND input_hash = v_ds.hash_inputs AND params_hash = v_params_hash
     AND code_version = _code_version AND status <> 'failed'
   LIMIT 1;
  RETURN jsonb_build_object('run_id', v_run.id, 'cache_hit', v_run.status = 'succeeded',
                            'status', v_run.status, 'params', v_run.params, 'claimed_by_other', true);
END; $fn$;

COMMENT ON FUNCTION public.analysis_start_nexus_stress(uuid, uuid, uuid, text, jsonb, uuid) IS
  'PLAN.md §27 WP 17.3 — opens a nexus battery bound to an ACTIVE Validated Model (its policy version) and '
  'a data version (the model''s by default). The binding is written into params by the server; the key is '
  'the data version''s simulation hash, the params and the engine build. Service role only.';

REVOKE ALL ON FUNCTION public.analysis_start_nexus_stress(uuid, uuid, uuid, text, jsonb, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.analysis_start_nexus_stress(uuid, uuid, uuid, text, jsonb, uuid) TO service_role;

-- ── 3 · publishing a battery, whole ─────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.analysis_publish_nexus_stress(
  _run_id        uuid,
  _results       jsonb,
  _summary       jsonb,
  _actor_user_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_run       public.analysis_runs;
  v_durations jsonb;
  v_n         integer;
  v_bad       text;
BEGIN
  SELECT * INTO v_run FROM public.analysis_runs WHERE id = _run_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'analysis_publish_nexus_stress: no run %', _run_id USING ERRCODE = 'no_data_found';
  END IF;
  PERFORM public.assert_writer_may_act('analysis_publish_nexus_stress', v_run.project_id, _actor_user_id);
  IF v_run.analysis_kind <> 'nexus_stress' THEN
    RAISE EXCEPTION 'analysis_publish_nexus_stress: run % is a % run', _run_id, v_run.analysis_kind
      USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF v_run.status <> 'running' THEN
    RAISE EXCEPTION 'analysis_publish_nexus_stress: run % is %, and a published battery is never rewritten',
      _run_id, v_run.status USING ERRCODE = 'P0A01';
  END IF;
  IF jsonb_typeof(_results) IS DISTINCT FROM 'array' OR jsonb_array_length(_results) = 0 THEN
    RAISE EXCEPTION 'analysis_publish_nexus_stress: a battery has at least one target row'
      USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF (_summary ->> 'scenario_hash') IS DISTINCT FROM (v_run.params ->> 'scenario_hash') THEN
    RAISE EXCEPTION 'analysis_publish_nexus_stress: the rows were computed under scenario %, the run was opened for %',
      _summary ->> 'scenario_hash', v_run.params ->> 'scenario_hash' USING ERRCODE = 'invalid_parameter_value';
  END IF;

  v_durations := v_run.params -> 'scenario' -> 'durations_weeks';
  v_n := jsonb_array_length(_results);

  -- Every row: a supplier or material, an id, a rank, an Average, and one cell per
  -- declared duration with a numeric mean — the table the card draws, nothing less.
  SELECT format('%s:%s', r ->> 'entity_type', r ->> 'entity_id') INTO v_bad
    FROM jsonb_array_elements(_results) r
   WHERE (r ->> 'entity_type') IS DISTINCT FROM 'material' AND (r ->> 'entity_type') IS DISTINCT FROM 'supplier'
      OR COALESCE(r ->> 'entity_id', '') = ''
      OR jsonb_typeof(r -> 'metrics' -> 'rank') IS DISTINCT FROM 'number'
      OR jsonb_typeof(r -> 'metrics' -> 'average_eur') IS DISTINCT FROM 'number'
      OR EXISTS (SELECT 1 FROM jsonb_array_elements_text(v_durations) d
                  WHERE jsonb_typeof(r -> 'metrics' -> 'by_duration' -> d -> 'mean') IS DISTINCT FROM 'number')
   LIMIT 1;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'analysis_publish_nexus_stress: row % is not a battery row (kind, id, rank, average_eur, and a mean for every declared duration)', v_bad
      USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF (SELECT array_agg((r -> 'metrics' ->> 'rank')::int ORDER BY (r -> 'metrics' ->> 'rank')::int)
        FROM jsonb_array_elements(_results) r)
     IS DISTINCT FROM (SELECT array_agg(g ORDER BY g) FROM generate_series(1, v_n) g) THEN
    RAISE EXCEPTION 'analysis_publish_nexus_stress: ranks must be 1…% with none repeated', v_n
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  RETURN public.analysis_complete_run(_run_id, _results, _summary, '[]'::jsonb, _actor_user_id);
END; $fn$;

COMMENT ON FUNCTION public.analysis_publish_nexus_stress(uuid, jsonb, jsonb, uuid) IS
  'PLAN.md §27 WP 17.3 — publishes a RUNNING nexus battery whole: every row a supplier or material with a '
  'rank, an Average and a mean for each declared duration; ranks 1…n; the summary''s scenario the run''s. '
  'Completes the run through analysis_complete_run. Service role only.';

REVOKE ALL ON FUNCTION public.analysis_publish_nexus_stress(uuid, jsonb, jsonb, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.analysis_publish_nexus_stress(uuid, jsonb, jsonb, uuid) TO service_role;

-- ── 4 · the card's read ─────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_nexus_stress_results(
  p_project_id uuid,
  p_user_id    uuid
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_run   public.analysis_runs;
  v_model public.model_validations;
  v_pv    public.policy_versions;
  v_ds    public.dataset_versions;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'get_nexus_stress_results: this read must name its reader'
      USING ERRCODE = 'null_value_not_allowed';
  END IF;
  -- LOCAL, and `has_project_access` answers for the named reader (the D169 shape).
  PERFORM set_config('app.current_user_id', p_user_id::text, true);
  IF NOT public.has_project_access(p_project_id) THEN
    RAISE EXCEPTION 'get_nexus_stress_results: % cannot read project %', p_user_id, p_project_id
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- The newest published battery. It is shown even when the data has moved on —
  -- the card says so (rule 6); it never recomputes on view (rule 7).
  SELECT * INTO v_run FROM public.analysis_runs
   WHERE project_id = p_project_id AND analysis_kind = 'nexus_stress' AND status = 'succeeded'
   ORDER BY finished_at DESC NULLS LAST, id
   LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('run_id', NULL);
  END IF;
  SELECT * INTO v_model FROM public.model_validations WHERE id = (v_run.params ->> 'model_validation_id')::uuid;
  SELECT * INTO v_pv    FROM public.policy_versions   WHERE id = (v_run.params ->> 'policy_version_id')::uuid;
  SELECT * INTO v_ds    FROM public.dataset_versions  WHERE id = v_run.dataset_version_id;

  RETURN jsonb_build_object(
    'run_id',        v_run.id,
    'finished_at',   v_run.finished_at,
    'code_version',  v_run.code_version,
    'scenario',      v_run.params -> 'scenario',
    'scenario_hash', v_run.params ->> 'scenario_hash',
    'summary',       v_run.row_counts,
    'baseline', jsonb_build_object(
      'model_validation_id', v_model.id,
      'model_name',          v_model.name,
      'model_code',          v_model.model_code,
      'model_status',        v_model.status,
      'policy_version_id',   v_pv.id,
      'policy_version_no',   v_pv.version_no,
      'policy_version_code', v_pv.version_code,
      'policy_label',        v_pv.label,
      'dataset_version_id',  v_ds.id,
      'dataset_version_no',  v_ds.version_no,
      'dataset_label',       v_ds.label),
    -- The data the battery ran on is still the project's: the run's own hash
    -- against the project's current hash for the run's OWN scope. Not
    -- `analysis_run_is_current`, which re-derives the scope from the kinds catalog
    -- and reads a simulation-scoped run as stale wherever that row is absent.
    'data_is_current',  COALESCE(v_run.input_hash = public.current_level_hash(v_run.project_id, v_run.input_scope), false),
    'model_is_active',  COALESCE(v_model.status = 'active' AND v_model.revoked_at IS NULL, false),
    'materials', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('id', ar.entity_id) || ar.metrics
                       ORDER BY (ar.metrics ->> 'rank')::int)
        FROM public.analysis_results ar
       WHERE ar.run_id = v_run.id AND ar.entity_type = 'material'), '[]'::jsonb),
    'suppliers', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('id', ar.entity_id) || ar.metrics
                       ORDER BY (ar.metrics ->> 'rank')::int)
        FROM public.analysis_results ar
       WHERE ar.run_id = v_run.id AND ar.entity_type = 'supplier'), '[]'::jsonb)
  );
END; $fn$;

COMMENT ON FUNCTION public.get_nexus_stress_results(uuid, uuid) IS
  'PLAN.md §27 WP 17.3 — the Nexus card''s read: the project''s newest published nexus battery with its '
  'baseline (Validated Model, policy version, data version, engine build, scenario), whether its data is '
  'still the project''s and its model still active, and the materials and suppliers in rank order. '
  'Refuses a reader without access to the project.';

REVOKE ALL ON FUNCTION public.get_nexus_stress_results(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_nexus_stress_results(uuid, uuid) TO anon, authenticated, service_role;

SELECT pg_notify('pgrst', 'reload schema');
