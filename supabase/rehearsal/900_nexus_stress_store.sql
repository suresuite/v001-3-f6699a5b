-- PLAN.md §27 WP 17.3 · §4 D310 — THE NEXUS BATTERY, STORED WITH ITS BASELINE.
--
-- What only a database can say about `20261021000001`:
--
--   §1 a battery opens only on an ACTIVE Validated Model of the project, and on a
--      data version of the project;
--   §2 the binding is the SERVER's: params carry the model's policy version and
--      hash and the data version's hashes whatever the caller wrote, the run is
--      keyed on the data version's simulation hash, and re-opening the same key
--      returns the same run;
--   §3 a publish is refused unless every row is a supplier or material with a
--      rank, an Average and a mean for each declared duration, ranks are 1…n, and
--      the scenario is the run's — and a refused publish leaves the run running;
--   §4 a good publish completes the run, a second publish is refused, and opening
--      the key again is a cache hit;
--   §5 the read gives the baseline and the two tables in rank order, says the data
--      is current, and says it is NOT after a live edit — still showing the result;
--   §6 the read refuses a stranger and a reader who names nobody; the writers
--      refuse a NULL actor;
--   §7 the grants are explicit, and the writers are not open to the browser.

DO $wp173$
DECLARE
  v_user     uuid := gen_random_uuid();
  v_stranger uuid := gen_random_uuid();
  v_proj     uuid := gen_random_uuid();
  v_other    uuid := gen_random_uuid();
  v_scen     uuid := gen_random_uuid();
  v_pv       uuid;
  v_ds       uuid;
  v_ds_other uuid;
  v_m        uuid;
  v_res      jsonb;
  v_res2     jsonb;
  v_run      uuid;
  v_read     jsonb;
  v_state    text;
  v_n        integer;
  v_row      record;
  k_scen     jsonb := '{"version":1,"start_week":26,"durations_weeks":[2,3,4,5,6,7,8,9]}'::jsonb;
  k_params   jsonb;
  k_summary  jsonb;
  k_good     jsonb;
  k_proto    jsonb := '{"replications":10,"root_seed":42,"crn":true,"warmup_week":4,"horizon_weeks":52,
                        "analysis_window_weeks":48,"ci_level":0.95,"ci_halfwidth_target":0.05,
                        "stopping_rule":"fixed_horizon"}'::jsonb;
  k_pass     jsonb := '[{"kpi":"fill_rate","ks":0.1,"ks_p":0.6,"t":0.2,"t_p":0.7,"n":40,"source":"weekly series","pass":true}]'::jsonb;

BEGIN
  INSERT INTO public.sim_engines (slug, name, status) VALUES ('scsim', 'scsim', 'active')
    ON CONFLICT (slug) DO NOTHING;
  INSERT INTO public.approved_users (id, email, name, password_hash) VALUES
    (v_user, 'r900@example.invalid', 'R900', 'x'),
    (v_stranger, 'r900s@example.invalid', 'R900 stranger', 'x');
  INSERT INTO public.projects (id, name, modeler_id, plant_name) VALUES
    (v_proj, 'R900', v_user, 'P'), (v_other, 'R900 other', v_user, 'P');
  PERFORM set_config('app.current_user_id', v_user::text, true);
  IF NOT EXISTS (SELECT 1 FROM public.policy_defaults WHERE project_id = v_proj) THEN
    INSERT INTO public.policy_defaults (project_id) VALUES (v_proj);
  END IF;
  INSERT INTO public.scenarios (id, project_id, name, horizon_days, seed, replications) VALUES
    (v_scen, v_proj, 'R900 baseline', 364, 42, 10);
  INSERT INTO public.suppliers (project_id, supplier_id) VALUES (v_proj, 'S1'), (v_proj, 'S2');
  INSERT INTO public.materials (project_id, material_id, cost) VALUES (v_proj, 'M1', 10);
  INSERT INTO public.products (project_id, product_id) VALUES (v_proj, 'P1');
  INSERT INTO public.inbound_logistics (project_id, plant_name, supplier_id, material_id, unit_price, volume, time_unit)
    VALUES (v_proj, 'P', 'S1', 'M1', 4, 100, 'week'), (v_proj, 'P', 'S2', 'M1', 5, 50, 'week');
  INSERT INTO public.bom_single_level (project_id, plant_name, product_id, material_id, consumption_rate)
    VALUES (v_proj, 'P', 'P1', 'M1', 2);
  INSERT INTO public.suppliers (project_id, supplier_id) VALUES (v_other, 'X1');
  v_ds_other := public.snapshot_dataset(v_other, NULL, v_user);

  v_pv := public.snapshot_policy(v_proj, 'R900', v_user);
  v_ds := public.snapshot_dataset(v_proj, NULL, v_user);
  v_m  := public.record_validated_model(v_proj, v_pv, v_ds, v_scen, 'R900 model', k_proto, 'mser5',
            '{"confidence":0.95}'::jsonb, k_pass, '[]'::jsonb, 'statistical', NULL, NULL, '{}'::jsonb, v_user);

  -- The caller tries to name other policies; §2 proves the server's binding wins.
  k_params := jsonb_build_object('scenario', k_scen, 'scenario_hash', 'h-scen-1',
                                 'policy_version_id', gen_random_uuid(), 'policy_hash', 'not-the-model');
  k_summary := jsonb_build_object('scenario_hash', 'h-scen-1', 'warmup_week', 14, 'start_week', 26,
                                  'replications', 10, 'clean_lost_sales_eur', jsonb_build_object('mean', 0));
  k_good := jsonb_build_array(
    jsonb_build_object('entity_type', 'material', 'entity_id', 'M1', 'metrics', jsonb_build_object(
      'rank', 1, 'average_eur', 5400, 'zero_reason', NULL, 'by_duration', jsonb_build_object(
        '2', '{"mean":1000}'::jsonb, '3', '{"mean":2000}'::jsonb, '4', '{"mean":3000}'::jsonb,
        '5', '{"mean":4000}'::jsonb, '6', '{"mean":5000}'::jsonb, '7', '{"mean":6000}'::jsonb,
        '8', '{"mean":8000}'::jsonb, '9', '{"mean":14200}'::jsonb))),
    jsonb_build_object('entity_type', 'supplier', 'entity_id', 'S1', 'metrics', jsonb_build_object(
      'rank', 2, 'average_eur', 1200, 'zero_reason', NULL, 'by_duration', jsonb_build_object(
        '2', '{"mean":0}'::jsonb, '3', '{"mean":0}'::jsonb, '4', '{"mean":0}'::jsonb,
        '5', '{"mean":600}'::jsonb, '6', '{"mean":1200}'::jsonb, '7', '{"mean":1800}'::jsonb,
        '8', '{"mean":2400}'::jsonb, '9', '{"mean":3600}'::jsonb))),
    jsonb_build_object('entity_type', 'supplier', 'entity_id', 'S2', 'metrics', jsonb_build_object(
      'rank', 3, 'average_eur', 0, 'zero_reason', 'absorbed', 'by_duration', jsonb_build_object(
        '2', '{"mean":0}'::jsonb, '3', '{"mean":0}'::jsonb, '4', '{"mean":0}'::jsonb,
        '5', '{"mean":0}'::jsonb, '6', '{"mean":0}'::jsonb, '7', '{"mean":0}'::jsonb,
        '8', '{"mean":0}'::jsonb, '9', '{"mean":0}'::jsonb))));

  -- ══ §1 · only on an active Validated Model, only on the project's data ══
  v_state := NULL;
  BEGIN
    PERFORM public.analysis_start_nexus_stress(v_proj, gen_random_uuid(), NULL, 'scsim-test+1', k_params, v_user);
  EXCEPTION WHEN no_data_found THEN v_state := 'refused';
  END;
  IF v_state IS NULL THEN RAISE EXCEPTION 'R900 §1: a battery opened with no Validated Model'; END IF;
  v_state := NULL;
  BEGIN
    PERFORM public.analysis_start_nexus_stress(v_proj, v_m, v_ds_other, 'scsim-test+1', k_params, v_user);
  EXCEPTION WHEN no_data_found THEN v_state := 'refused';
  END;
  IF v_state IS NULL THEN RAISE EXCEPTION 'R900 §1: a battery opened on another project''s data version'; END IF;
  v_state := NULL;
  BEGIN
    PERFORM public.analysis_start_nexus_stress(v_proj, v_m, NULL, 'scsim-test+1', '{}'::jsonb, v_user);
  EXCEPTION WHEN invalid_parameter_value THEN v_state := 'refused';
  END;
  IF v_state IS NULL THEN RAISE EXCEPTION 'R900 §1: a battery opened without its scenario'; END IF;

  -- ══ §2 · the server's binding; the simulation key; one run per key ══
  v_res := public.analysis_start_nexus_stress(v_proj, v_m, NULL, 'scsim-test+1', k_params, v_user);
  v_run := (v_res ->> 'run_id')::uuid;
  SELECT * INTO v_row FROM public.analysis_runs WHERE id = v_run;
  IF v_row.params ->> 'policy_version_id' IS DISTINCT FROM v_pv::text
     OR v_row.params ->> 'policy_hash' IS DISTINCT FROM (SELECT policy_hash FROM public.model_validations WHERE id = v_m)
     OR v_row.params ->> 'model_validation_id' IS DISTINCT FROM v_m::text
     OR v_row.dataset_version_id IS DISTINCT FROM v_ds
     OR v_row.input_scope <> 'simulation'
     OR v_row.input_hash IS DISTINCT FROM (SELECT hash_inputs FROM public.dataset_versions WHERE id = v_ds)
     OR v_row.status <> 'running' THEN
    RAISE EXCEPTION 'R900 §2: the battery is not bound to the model and its data version: %', to_jsonb(v_row);
  END IF;
  v_res2 := public.analysis_start_nexus_stress(v_proj, v_m, NULL, 'scsim-test+1', k_params, v_user);
  IF (v_res2 ->> 'run_id')::uuid IS DISTINCT FROM v_run THEN
    RAISE EXCEPTION 'R900 §2: re-opening the same key made a second run: %', v_res2;
  END IF;

  -- ══ §3 · a publish that is not the table is refused, and the run stays open ══
  FOR v_row IN
    SELECT * FROM (VALUES
      ('a missing duration', jsonb_set(k_good, '{0,metrics,by_duration}', (k_good #> '{0,metrics,by_duration}') - '9'), k_summary),
      ('a product row',      jsonb_set(k_good, '{0,entity_type}', '"product"'), k_summary),
      ('a repeated rank',    jsonb_set(k_good, '{1,metrics,rank}', '1'), k_summary),
      ('no Average',         jsonb_set(k_good, '{2,metrics}', (k_good #> '{2,metrics}') - 'average_eur'), k_summary),
      ('another scenario',   k_good, jsonb_set(k_summary, '{scenario_hash}', '"h-other"')),
      ('no rows',            '[]'::jsonb, k_summary)) c(what, results, summary)
  LOOP
    v_state := NULL;
    BEGIN
      PERFORM public.analysis_publish_nexus_stress(v_run, v_row.results, v_row.summary, v_user);
    EXCEPTION WHEN invalid_parameter_value THEN v_state := 'refused';
    END;
    IF v_state IS NULL THEN RAISE EXCEPTION 'R900 §3: a publish with % was accepted', v_row.what; END IF;
  END LOOP;
  IF (SELECT status FROM public.analysis_runs WHERE id = v_run) <> 'running'
     OR EXISTS (SELECT 1 FROM public.analysis_results WHERE run_id = v_run) THEN
    RAISE EXCEPTION 'R900 §3: a refused publish changed the run';
  END IF;

  -- ══ §4 · a good publish completes it; never twice; then a cache hit ══
  v_res := public.analysis_publish_nexus_stress(v_run, k_good, k_summary, v_user);
  IF (v_res ->> 'results_written')::int <> 3
     OR (SELECT status FROM public.analysis_runs WHERE id = v_run) <> 'succeeded' THEN
    RAISE EXCEPTION 'R900 §4: the publish did not complete the battery: %', v_res;
  END IF;
  v_state := NULL;
  BEGIN
    PERFORM public.analysis_publish_nexus_stress(v_run, k_good, k_summary, v_user);
  EXCEPTION WHEN SQLSTATE 'P0A01' THEN v_state := 'refused';
  END;
  IF v_state IS NULL THEN RAISE EXCEPTION 'R900 §4: a published battery was published again'; END IF;
  v_res := public.analysis_start_nexus_stress(v_proj, v_m, NULL, 'scsim-test+1', k_params, v_user);
  IF NOT (v_res ->> 'cache_hit')::boolean OR (v_res ->> 'run_id')::uuid IS DISTINCT FROM v_run THEN
    RAISE EXCEPTION 'R900 §4: the published key was not a cache hit: %', v_res;
  END IF;

  -- ══ §5 · the read: baseline, two tables in rank order, current — then not ══
  v_read := public.get_nexus_stress_results(v_proj, v_user);
  IF (v_read ->> 'run_id')::uuid IS DISTINCT FROM v_run
     OR v_read #>> '{baseline,model_validation_id}' IS DISTINCT FROM v_m::text
     OR v_read #>> '{baseline,policy_version_id}'   IS DISTINCT FROM v_pv::text
     OR v_read #>> '{baseline,dataset_version_id}'  IS DISTINCT FROM v_ds::text
     OR v_read ->> 'code_version' <> 'scsim-test+1'
     OR (v_read #>> '{summary,start_week}')::int <> 26
     OR NOT (v_read ->> 'data_is_current')::boolean
     OR NOT (v_read ->> 'model_is_active')::boolean
     OR jsonb_array_length(v_read -> 'materials') <> 1
     OR v_read #>> '{suppliers,0,id}' <> 'S1' OR v_read #>> '{suppliers,1,id}' <> 'S2'
     OR (v_read #>> '{suppliers,1,average_eur}')::numeric <> 0
     OR v_read #>> '{suppliers,1,zero_reason}' <> 'absorbed'
     OR (v_read #>> '{materials,0,by_duration,9,mean}')::numeric <> 14200 THEN
    RAISE EXCEPTION 'R900 §5: the read is not the battery: %', v_read;
  END IF;
  UPDATE public.materials SET cost = 25 WHERE project_id = v_proj AND material_id = 'M1';  -- a live edit
  v_read := public.get_nexus_stress_results(v_proj, v_user);
  IF (v_read ->> 'data_is_current')::boolean OR (v_read ->> 'run_id')::uuid IS DISTINCT FROM v_run THEN
    RAISE EXCEPTION 'R900 §5: after a live edit the read did not say the data moved, or stopped showing the battery: %',
      v_read ->> 'data_is_current';
  END IF;
  IF (public.get_nexus_stress_results(v_other, v_user) ->> 'run_id') IS NOT NULL THEN
    RAISE EXCEPTION 'R900 §5: a project with no battery read one';
  END IF;

  -- ══ §6 · refusals: a stranger, nobody, a NULL actor ══
  v_state := NULL;
  BEGIN
    PERFORM public.get_nexus_stress_results(v_proj, v_stranger);
  EXCEPTION WHEN insufficient_privilege THEN v_state := 'refused';
  END;
  IF v_state IS NULL THEN RAISE EXCEPTION 'R900 §6: a stranger read the battery'; END IF;
  v_state := NULL;
  BEGIN
    PERFORM public.get_nexus_stress_results(v_proj, NULL);
  EXCEPTION WHEN null_value_not_allowed THEN v_state := 'refused';
  END;
  IF v_state IS NULL THEN RAISE EXCEPTION 'R900 §6: the read answered a reader who named nobody'; END IF;
  v_state := NULL;
  BEGIN
    PERFORM public.analysis_start_nexus_stress(v_proj, v_m, NULL, 'scsim-test+2', k_params, NULL);
  EXCEPTION WHEN null_value_not_allowed THEN v_state := 'refused';
  END;
  IF v_state IS NULL THEN RAISE EXCEPTION 'R900 §6: a battery opened with no actor'; END IF;

  -- ══ §7 · the grants are explicit; the writers are not the browser's ══
  FOR v_row IN
    SELECT * FROM (VALUES
      ('public.get_nexus_stress_results(uuid,uuid)', 'anon'),
      ('public.get_nexus_stress_results(uuid,uuid)', 'authenticated'),
      ('public.get_nexus_stress_results(uuid,uuid)', 'service_role'),
      ('public.analysis_start_nexus_stress(uuid,uuid,uuid,text,jsonb,uuid)', 'service_role'),
      ('public.analysis_publish_nexus_stress(uuid,jsonb,jsonb,uuid)', 'service_role')) g(fn, role)
  LOOP
    SELECT count(*) INTO v_n
      FROM pg_proc p
      CROSS JOIN LATERAL aclexplode(p.proacl) a
      JOIN pg_roles r ON r.oid = a.grantee
     WHERE p.oid = v_row.fn::regprocedure AND r.rolname = v_row.role
       AND a.privilege_type = 'EXECUTE';
    IF v_n < 1 THEN
      RAISE EXCEPTION 'R900 §7: % is not an explicit EXECUTE grantee of %', v_row.role, v_row.fn;
    END IF;
  END LOOP;
  SELECT count(*) INTO v_n
    FROM pg_proc p
    CROSS JOIN LATERAL aclexplode(p.proacl) a
    LEFT JOIN pg_roles r ON r.oid = a.grantee
   WHERE p.oid IN ('public.analysis_start_nexus_stress(uuid,uuid,uuid,text,jsonb,uuid)'::regprocedure,
                   'public.analysis_publish_nexus_stress(uuid,jsonb,jsonb,uuid)'::regprocedure)
     AND (a.grantee = 0 OR r.rolname IN ('anon', 'authenticated'))
     AND a.privilege_type = 'EXECUTE';
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'R900 §7: a nexus battery writer is executable by PUBLIC, anon or authenticated (% grant(s))', v_n;
  END IF;

  RAISE NOTICE 'WP 17.3 · 900: the nexus battery is stored with its baseline and read by project — 7 section(s)';
END $wp173$;
