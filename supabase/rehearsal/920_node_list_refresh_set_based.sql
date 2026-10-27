-- §4 D314 · PROMOTING A TRON-SIZED UPLOAD FITS IN THE 8 s AN EDGE-FUNCTION RPC GETS.
--
-- `20261027000002` makes the node-list refresh one pass. What only a running database
-- can settle:
--
--   §1 SAME ANSWER: on a graph with a sub-assembly, a node that is both a supplier and a
--      BOM input, a supplier whose material is in no BOM, the plant and a listed node no
--      lane names, `node_list_attributes` gives every node the echelon, BOM depth and
--      supply tier the per-node functions give it — and after a refresh `node_list`
--      holds exactly those values. One rule, two collectors (§4 D127).
--   §2 A REFRESH THAT CHANGES NOTHING WRITES NOTHING: a second refresh leaves every
--      row's `ctid` where it was. Not `xmin` — this file is one transaction, so a row
--      rewritten here keeps its `xmin` and that check could not fail (it did not,
--      against the old refresh, which rewrites every row).
--   §3 THE TIMING: a project shaped like the TRON upload that timed out in production
--      (17 products, 560 materials, 61 suppliers; 599 BOM rows, 635 inbound lanes, 17
--      outbound lanes) is promoted through `ingest_land_file` + `ingest_apply_run`, the
--      edge function's own path, one dataset at a time. Each promotion must finish in
--      under 6 s, below the 8 s production gives it with room for a slower CI runner.
--      Measured on an idle local database: this shape promotes in 0.5 / 1.9 / 2.4 s;
--      with the pre-D314 refresh restored it took 3.0 s and then 10.4 s for inbound
--      (the real TRON files: 1.1 / 4.4 / 12.2 s before, 0.4 / 1.4 / 1.7 s after).
--      Elapsed time is read with `clock_timestamp()`: a `statement_timeout` set inside
--      a running statement is never armed (880's note).

DO $d314$
DECLARE
  v_org   uuid := gen_random_uuid();
  v_user  uuid := gen_random_uuid();
  v_small uuid := gen_random_uuid();
  v_big   uuid := gen_random_uuid();
  v_run   uuid;
  v_n     integer;
  v_bad   text;
  v_ds    text;
  v_rows  jsonb;
  v_t0    timestamptz;
  v_took  interval;
BEGIN
  INSERT INTO public.organizations (id, name, slug) VALUES
    (v_org, 'D314 Org', 'd314-' || substr(v_org::text, 1, 8));
  INSERT INTO public.approved_users (id, email, name, password_hash, role, organization, organization_id, is_active) VALUES
    (v_user, 'd314@example.invalid', 'D314 Admin', 'x', 'admin', 'D314 Org', v_org, true);
  INSERT INTO public.projects (id, name, modeler_id, plant_name, organization, organization_id, bom_level) VALUES
    (v_small, 'D314 small', v_user, 'D314P', 'D314 Org', v_org, 'single'),
    (v_big,   'D314 TRON',  v_user, 'D314T', 'D314 Org', v_org, 'single');

  -- ── §1 same answer ─────────────────────────────────────────────────────────
  INSERT INTO public.bom_single_level (project_id, plant_name, product_id, material_id, consumption_rate) VALUES
    (v_small, 'D314P', 'PROD',   'SUBASM', 1),
    (v_small, 'D314P', 'SUBASM', 'RAW',    2),
    (v_small, 'D314P', 'PROD',   'DUAL',   1);
  INSERT INTO public.inbound_logistics (project_id, plant_name, supplier_id, material_id, volume, time_unit, lead_time, unit_price) VALUES
    (v_small, 'D314P', 'SUP1', 'RAW',   10, 'week', 2, 1),
    (v_small, 'D314P', 'SUP2', 'LOOSE', 10, 'week', 2, 1),
    (v_small, 'D314P', 'DUAL', 'RAW',   10, 'week', 2, 1);
  INSERT INTO public.outbound_logistics (project_id, plant_name, customer_id, product_id, volume, time_unit, expected_lead_time, unit_price) VALUES
    (v_small, 'D314P', 'CUST', 'PROD', 5, 'week', 1, 9);
  INSERT INTO public.node_list (project_id, plant_name, node_id, organization, created_by) VALUES
    (v_small, 'D314P', 'D314P',  'D314 Org', v_user),
    (v_small, 'D314P', 'ORPHAN', 'D314 Org', v_user)
  ON CONFLICT (project_id, node_id) DO NOTHING;
  PERFORM public.refresh_node_list_for_project(v_small, v_user);

  SELECT string_agg(format('%s: set %s/%s/%s, per-node %s/%s/%s', a.node_id,
                           a.echelon, a.bom_depth, a.supply_tier,
                           public.classify_node_echelon(v_small, a.node_id),
                           public.node_bom_depth(v_small, a.node_id),
                           public.node_supply_tier(v_small, a.node_id)), '; ')
    INTO v_bad
    FROM public.node_list_attributes(v_small) a
   WHERE (a.echelon, a.bom_depth, a.supply_tier) IS DISTINCT FROM
         (public.classify_node_echelon(v_small, a.node_id),
          public.node_bom_depth(v_small, a.node_id),
          public.node_supply_tier(v_small, a.node_id));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'D314/920 §1: the set-based collector and the per-node functions disagree — %', v_bad;
  END IF;

  SELECT string_agg(format('%s=%s', n.node_id, n.echelon), ', ' ORDER BY n.node_id) INTO v_bad
    FROM public.node_list n WHERE n.project_id = v_small;
  IF v_bad IS DISTINCT FROM
     'CUST=customer, D314P=plant, DUAL=material, LOOSE=material, ORPHAN=unknown, PROD=product, RAW=material, SUBASM=subassembly, SUP1=supplier, SUP2=supplier' THEN
    RAISE EXCEPTION 'D314/920 §1: node_list after the refresh reads %', v_bad;
  END IF;

  SELECT string_agg(n.node_id, ', ') INTO v_bad
    FROM public.node_list n
    JOIN public.node_list_attributes(v_small) a ON a.node_id = n.node_id
   WHERE n.project_id = v_small
     AND (n.echelon, n.node_type, n.node_group, n.bom_depth, n.supply_tier) IS DISTINCT FROM
         (a.echelon, CASE a.echelon WHEN 'subassembly' THEN 'material' ELSE a.echelon END,
          initcap(CASE a.echelon WHEN 'subassembly' THEN 'material' ELSE a.echelon END),
          a.bom_depth, a.supply_tier);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'D314/920 §1: node_list does not hold the computed attributes for %', v_bad;
  END IF;

  -- ── §2 a refresh that changes nothing writes nothing ───────────────────────
  CREATE TEMP TABLE d314_before ON COMMIT DROP AS
    SELECT id, ctid::text AS x FROM public.node_list WHERE project_id = v_small;
  PERFORM public.refresh_node_list_for_project(v_small, v_user);
  SELECT count(*) INTO v_n
    FROM public.node_list n JOIN d314_before b ON b.id = n.id
   WHERE n.ctid::text <> b.x;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'D314/920 §2: a refresh that changed nothing rewrote % node_list row(s)', v_n;
  END IF;

  -- ── §3 the timing, through the edge function's own path ────────────────────
  FOREACH v_ds IN ARRAY ARRAY['bom_single_level', 'inbound_logistics', 'outbound_logistics'] LOOP
    IF v_ds = 'bom_single_level' THEN
      SELECT jsonb_agg(jsonb_build_object('source_row_number', g + 2, 'raw', '{}'::jsonb, 'findings', '[]'::jsonb,
               'parsed', jsonb_build_object(
                 'product_id',  'PRD-' || lpad((g % 17 + 1)::text, 3, '0'),
                 'material_id', 'MAT-' || lpad((g % 560 + 1)::text, 4, '0'),
                 'consumption_rate', 1)))
        INTO v_rows FROM generate_series(0, 598) g;
    ELSIF v_ds = 'inbound_logistics' THEN
      SELECT jsonb_agg(jsonb_build_object('source_row_number', g + 2, 'raw', '{}'::jsonb, 'findings', '[]'::jsonb,
               'parsed', jsonb_build_object(
                 'supplier_id', 'SUP-' || lpad((g % 61 + 1)::text, 3, '0'),
                 'material_id', 'MAT-' || lpad((g % 560 + 1)::text, 4, '0'),
                 'volume', 10, 'time_unit', 'week', 'lead_time', 4, 'unit_price', 1,
                 'lead_time_unit', 'weeks')))
        INTO v_rows FROM generate_series(0, 634) g;
    ELSE
      SELECT jsonb_agg(jsonb_build_object('source_row_number', g + 2, 'raw', '{}'::jsonb, 'findings', '[]'::jsonb,
               'parsed', jsonb_build_object(
                 'customer_id', 'CUST-001',
                 'product_id',  'PRD-' || lpad((g + 1)::text, 3, '0'),
                 'volume', 50, 'time_unit', 'week', 'expected_lead_time', 1, 'unit_price', 40)))
        INTO v_rows FROM generate_series(0, 16) g;
    END IF;

    v_run := (public.ingest_land_file(
      v_big, v_user, 'csv',
      CASE v_ds WHEN 'bom_single_level' THEN 'master' ELSE 'transactional' END,
      v_ds, v_ds || '.csv', 'ingest', 'p/d314/' || v_ds || '.csv', 'text/csv', 1,
      repeat('d', 64), v_rows) ->> 'run_id')::uuid;

    v_t0 := clock_timestamp();
    PERFORM public.ingest_apply_run(v_run, v_user);
    v_took := clock_timestamp() - v_t0;
    RAISE NOTICE 'D314/920 §3: promoting % took %', v_ds, v_took;
    IF v_took > interval '6 seconds' THEN
      RAISE EXCEPTION 'D314/920 §3: promoting the TRON-sized % took % — production cancels an edge-function RPC at 8 s',
        v_ds, v_took;
    END IF;
  END LOOP;

  SELECT count(*) INTO v_n FROM public.node_list WHERE project_id = v_big;
  IF v_n <> 17 + 560 + 61 + 1 THEN
    RAISE EXCEPTION 'D314/920 §3: the TRON-sized project lists % node(s), expected % (products, materials, suppliers, one customer)',
      v_n, 17 + 560 + 61 + 1;
  END IF;
  SELECT string_agg(n.node_id, ', ') INTO v_bad
    FROM public.node_list n
   WHERE n.project_id = v_big
     AND n.echelon IS DISTINCT FROM public.classify_node_echelon(v_big, n.node_id);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'D314/920 §3: after the promotions these nodes are typed differently from classify_node_echelon: %', v_bad;
  END IF;

  RAISE NOTICE 'D314/920: the TRON-sized promotions fit in the edge function''s statement timeout';
END;
$d314$;
