-- PLAN.md §4 D313 (closes D137) — THE PRODUCT-LEVEL VIEW'S METRICS, STORED ON ITS LEVEL.
--
-- What only a database can say about `20261027000001`:
--
--   §1 `product_metrics` is declared once, over the PROCESS level (the level
--      `supply_chain_data` is rebuilt from), and a run opened on it is keyed on that
--      level's hash;
--   §2 the read returns NOTHING before a run exists — no fallback to any column;
--   §3 after a run, the read returns every stored node with its echelon, the master's
--      name (the id when the master has none), and says the run is current;
--   §4 a price edit — which no graph level reads — leaves it current; a quantity edit
--      to the BOM makes it stale, and the stale rows are STILL shown;
--   §5 the read refuses a stranger and a reader who names nobody;
--   §6 the grants are explicit.

DO $d313$
DECLARE
  v_user     uuid := gen_random_uuid();
  v_stranger uuid := gen_random_uuid();
  v_proj     uuid := gen_random_uuid();
  v_res      jsonb;
  v_run      uuid;
  v_state    text;
  v_n        integer;
  v_row      record;
  r          text;
BEGIN
  -- The catalog's rows are data: a base built from the artifact this branch writes
  -- (`--since HEAD`) has the table without them (as 570, 620, 670). DO NOTHING, so on
  -- a database the migration ran on, §1 still reads the migration's own row.
  INSERT INTO public.analysis_kinds (kind, input_scope, fallback_scope, fallback_rule, description) VALUES
    ('product_metrics', 'process', NULL, NULL, 'rehearsal seed')
  ON CONFLICT (kind) DO NOTHING;

  INSERT INTO public.approved_users (id, email, name, password_hash) VALUES
    (v_user, 'r910@example.invalid', 'R910', 'x'),
    (v_stranger, 'r910s@example.invalid', 'R910 stranger', 'x');
  INSERT INTO public.projects (id, name, modeler_id, plant_name) VALUES (v_proj, 'R910', v_user, 'P');
  PERFORM set_config('app.current_user_id', v_user::text, true);
  INSERT INTO public.suppliers (project_id, supplier_id) VALUES (v_proj, 'S1');
  INSERT INTO public.materials (project_id, material_id, name, cost) VALUES (v_proj, 'M1', 'Steel coil', 10);
  INSERT INTO public.products (project_id, product_id) VALUES (v_proj, 'P1');
  INSERT INTO public.inbound_logistics (project_id, plant_name, supplier_id, material_id, unit_price, volume, time_unit)
    VALUES (v_proj, 'P', 'S1', 'M1', 4, 100, 'week');
  INSERT INTO public.bom_single_level (project_id, plant_name, product_id, material_id, consumption_rate)
    VALUES (v_proj, 'P', 'P1', 'M1', 2);

  -- ══ §1 · declared once, over the process level ══
  IF (SELECT input_scope FROM public.analysis_kinds WHERE kind = 'product_metrics') IS DISTINCT FROM 'process' THEN
    RAISE EXCEPTION 'R910 §1: product_metrics is not declared over the process level';
  END IF;

  -- ══ §2 · no run, no rows ══
  SELECT count(*) INTO v_n FROM public.get_product_level_metrics(v_proj, v_user);
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'R910 §2: the read returned % rows before any run existed', v_n;
  END IF;

  v_res := public.analysis_get_or_start(v_proj, 'product_metrics', '{"graph":"product_level"}'::jsonb,
                                        'product_metrics@test', v_user);
  v_run := (v_res ->> 'run_id')::uuid;
  IF v_res ->> 'input_scope' <> 'process'
     OR v_res ->> 'input_hash' IS DISTINCT FROM public.current_level_hash(v_proj, 'process') THEN
    RAISE EXCEPTION 'R910 §1: the run is not keyed on the process level: %', v_res;
  END IF;

  -- A run still running is not an answer.
  SELECT count(*) INTO v_n FROM public.get_product_level_metrics(v_proj, v_user);
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'R910 §2: the read served % rows of a run that has not finished', v_n;
  END IF;

  PERFORM public.analysis_complete_run(v_run, jsonb_build_array(
    jsonb_build_object('entity_type', 'material', 'entity_id', 'M1', 'metrics', jsonb_build_object(
      'connections', 2, 'flow', 40, 'degree_centrality', 0.67, 'weighted_degree_centrality', 1,
      'eigenvector_centrality', 0.6, 'betweenness_centrality', 0.5, 'closeness_centrality', 0.75,
      'prominence', 0.7)),
    jsonb_build_object('entity_type', 'supplier', 'entity_id', 'S1', 'metrics', jsonb_build_object(
      'connections', 1, 'flow', 40, 'degree_centrality', 0.33, 'weighted_degree_centrality', 0.5,
      'eigenvector_centrality', 0.3, 'betweenness_centrality', 0, 'closeness_centrality', 0.5,
      'prominence', 0.3))),
    '{"nodes":2}'::jsonb, '[]'::jsonb, v_user);

  -- ══ §3 · every stored node, named, current ══
  SELECT count(*) INTO v_n FROM public.get_product_level_metrics(v_proj, v_user);
  IF v_n <> 2 THEN RAISE EXCEPTION 'R910 §3: expected 2 rows, got %', v_n; END IF;
  SELECT * INTO v_row FROM public.get_product_level_metrics(v_proj, v_user) WHERE uid = 'M1';
  IF v_row.echelon <> 'material' OR v_row.name <> 'Steel coil' OR v_row.flow <> 40
     OR v_row.connection_count <> 2 OR v_row.prominence <> 0.7 OR v_row.metrics_source <> 'store'
     OR v_row.run_id IS DISTINCT FROM v_run OR v_row.hash_is_current IS NOT TRUE THEN
    RAISE EXCEPTION 'R910 §3: the material row is wrong: %', to_jsonb(v_row);
  END IF;
  SELECT * INTO v_row FROM public.get_product_level_metrics(v_proj, v_user) WHERE uid = 'S1';
  IF v_row.name <> 'S1' OR v_row.echelon <> 'supplier' THEN
    RAISE EXCEPTION 'R910 §3: a node whose master has no name must show its id: %', to_jsonb(v_row);
  END IF;

  -- ══ §4 · a price edit is not a graph edit; a BOM quantity is ══
  UPDATE public.inbound_logistics SET unit_price = 9 WHERE project_id = v_proj;
  SELECT * INTO v_row FROM public.get_product_level_metrics(v_proj, v_user) WHERE uid = 'M1';
  IF v_row.hash_is_current IS NOT TRUE THEN
    RAISE EXCEPTION 'R910 §4: a price edit made the product-level metrics stale';
  END IF;
  UPDATE public.bom_single_level SET consumption_rate = 3 WHERE project_id = v_proj;
  SELECT * INTO v_row FROM public.get_product_level_metrics(v_proj, v_user) WHERE uid = 'M1';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'R910 §4: a stale run''s rows were hidden rather than said to be stale';
  END IF;
  IF v_row.hash_is_current IS NOT FALSE THEN
    RAISE EXCEPTION 'R910 §4: a BOM quantity edit left the metrics current: %', to_jsonb(v_row);
  END IF;

  -- ══ §5 · a stranger, and a reader who names nobody ══
  v_state := NULL;
  BEGIN
    PERFORM * FROM public.get_product_level_metrics(v_proj, v_stranger);
  EXCEPTION WHEN insufficient_privilege THEN v_state := 'refused';
  END;
  IF v_state IS NULL THEN RAISE EXCEPTION 'R910 §5: a stranger read the metrics'; END IF;
  v_state := NULL;
  BEGIN
    PERFORM * FROM public.get_product_level_metrics(v_proj, NULL);
  EXCEPTION WHEN null_value_not_allowed THEN v_state := 'refused';
  END;
  IF v_state IS NULL THEN RAISE EXCEPTION 'R910 §5: a read that names nobody was served'; END IF;

  -- ══ §6 · explicit grants ══
  FOREACH r IN ARRAY ARRAY['anon', 'authenticated', 'service_role'] LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_proc p, aclexplode(p.proacl) a
       WHERE p.oid = 'public.get_product_level_metrics(uuid,uuid)'::regprocedure
         AND a.grantee = (SELECT oid FROM pg_roles WHERE rolname = r)
         AND a.privilege_type = 'EXECUTE') THEN
      RAISE EXCEPTION 'R910 §6: % is not an EXPLICIT grantee of get_product_level_metrics', r;
    END IF;
  END LOOP;

  RAISE NOTICE 'R910 · product-level metrics: declared on the process level, store-only, current/stale, access-checked';
END
$d313$;
