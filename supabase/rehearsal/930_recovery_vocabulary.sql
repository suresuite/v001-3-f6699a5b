-- §4 D114 · D315 · A STORED PLAYBOOK SPEAKS THE ENGINE'S VOCABULARY.
--
-- `20261027000003` rewrites every mutable playbook through
-- `recovery_config_canonical()`. What only a running database can settle:
--
--   §1 THE RULE, case by case: the system playbooks' `responses` becomes `response`
--      (the key the engine reads); `reroute` and `expedite_freight` become `mode_shift`;
--      `demand_shaping` becomes `allocate_materials`, or is dropped for a preset;
--      duplicates collapse in first-seen order; the other keys survive.
--   §2 NOTHING ELSE MOVES: a config with no response list, a NULL, a non-object, and
--      an already-canonical config come back identical — so the migration's
--      `IS DISTINCT FROM` guard updates only rows that change.
--   §3 IDEMPOTENT: applying it twice is applying it once.
--   §4 THE UPDATE: a scenario holding a copied system playbook (`responses`) is
--      rewritten by the migration's own statement, and a canonical one is not touched.
--   §5 GRANTS: not callable by PUBLIC, `anon` or `authenticated` — nor are §4 D314's
--      `node_list_attributes` (SECURITY DEFINER, any project's nodes) and
--      `node_echelon_from_flags`, whose grants `20261027000002` left open.

DO $d315$
DECLARE
  f   jsonb;
  v_n integer;
BEGIN
  -- ── §1 the rule ──────────────────────────────────────────────────────────
  f := public.recovery_config_canonical(
         '{"responses":["dual_source_activate","mode_shift","safety_stock_drawdown"],"cost_cap":100000}');
  IF f IS DISTINCT FROM '{"response":["dual_source_activate","mode_shift","safety_stock_drawdown"],"cost_cap":100000}'::jsonb THEN
    RAISE EXCEPTION 'D315/930 §1: a system playbook''s `responses` did not become `response`: %', f;
  END IF;
  f := public.recovery_config_canonical('{"response":["mode_shift","reroute","capacity_flex","expedite_freight"]}');
  IF f -> 'response' IS DISTINCT FROM '["mode_shift","capacity_flex"]'::jsonb THEN
    RAISE EXCEPTION 'D315/930 §1: reroute/expedite_freight were not folded into mode_shift: %', f;
  END IF;
  f := public.recovery_config_canonical('{"response":["demand_shaping","safety_stock_drawdown"]}');
  IF f -> 'response' IS DISTINCT FROM '["allocate_materials","safety_stock_drawdown"]'::jsonb THEN
    RAISE EXCEPTION 'D315/930 §1: demand_shaping did not become allocate_materials: %', f;
  END IF;
  f := public.recovery_config_canonical('{"enabled":true,"response":["safety_stock_drawdown","demand_shaping"]}', true);
  IF f IS DISTINCT FROM '{"enabled":true,"response":["safety_stock_drawdown"]}'::jsonb THEN
    RAISE EXCEPTION 'D315/930 §1: a preset''s demand_shaping was not dropped: %', f;
  END IF;
  -- The card's singular key wins over a copied plural one.
  f := public.recovery_config_canonical('{"response":["capacity_flex"],"responses":["reroute"]}');
  IF f IS DISTINCT FROM '{"response":["capacity_flex"]}'::jsonb THEN
    RAISE EXCEPTION 'D315/930 §1: `response` did not win over `responses`: %', f;
  END IF;

  -- ── §2 nothing else moves ────────────────────────────────────────────────
  IF public.recovery_config_canonical(NULL) IS NOT NULL
     OR public.recovery_config_canonical('[1,2]') IS DISTINCT FROM '[1,2]'::jsonb
     OR public.recovery_config_canonical('{"enabled":false}') IS DISTINCT FROM '{"enabled":false}'::jsonb
     OR public.recovery_config_canonical('{"response":["dual_source_activate"],"backup_lanes":[{"material_id":"m"}]}')
          IS DISTINCT FROM '{"response":["dual_source_activate"],"backup_lanes":[{"material_id":"m"}]}'::jsonb THEN
    RAISE EXCEPTION 'D315/930 §2: a config with nothing to rewrite came back changed';
  END IF;

  -- ── §3 idempotent ────────────────────────────────────────────────────────
  f := '{"responses":["reroute","demand_shaping","reroute"],"detection_lag_days":1}';
  IF public.recovery_config_canonical(public.recovery_config_canonical(f))
       IS DISTINCT FROM public.recovery_config_canonical(f) THEN
    RAISE EXCEPTION 'D315/930 §3: applying the rule twice differs from applying it once';
  END IF;

  RAISE NOTICE 'D315/930 §1–§3: the playbook vocabulary rule holds';
END;
$d315$;

-- ── §4 the migration's own UPDATE, on rows planted before it ─────────────────
DO $d315u$
DECLARE
  v_org  uuid := gen_random_uuid();
  v_user uuid := gen_random_uuid();
  v_p    uuid := gen_random_uuid();
  v_old  uuid := gen_random_uuid();
  v_new  uuid := gen_random_uuid();
  v_ts   timestamptz;
  v_n    integer;
BEGIN
  INSERT INTO public.organizations (id, name, slug) VALUES (v_org, 'D315 Org', 'd315-' || substr(v_org::text, 1, 8));
  INSERT INTO public.approved_users (id, email, name, password_hash, role, organization, organization_id, is_active)
  VALUES (v_user, 'd315@example.invalid', 'D315', 'x', 'admin', 'D315 Org', v_org, true);
  INSERT INTO public.projects (id, name, modeler_id, plant_name, organization, organization_id, bom_level)
  VALUES (v_p, 'D315 p', v_user, 'D315P', 'D315 Org', v_org, 'single');
  INSERT INTO public.scenarios (id, project_id, name, recovery_overrides) VALUES
    (v_old, v_p, 'copied system playbook', '{"responses":["mode_shift","reroute"],"cost_cap":50000}'),
    (v_new, v_p, 'canonical', '{"response":["capacity_flex"]}');
  SELECT updated_at INTO v_ts FROM public.scenarios WHERE id = v_new;

  UPDATE public.scenarios
     SET recovery_overrides = public.recovery_config_canonical(recovery_overrides)
   WHERE public.recovery_config_canonical(recovery_overrides) IS DISTINCT FROM recovery_overrides
     AND project_id = v_p;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'D315/930 §4: the guarded UPDATE touched % row(s), expected only the legacy one', v_n;
  END IF;
  IF (SELECT recovery_overrides FROM public.scenarios WHERE id = v_old)
       IS DISTINCT FROM '{"response":["mode_shift"],"cost_cap":50000}'::jsonb THEN
    RAISE EXCEPTION 'D315/930 §4: the copied playbook reads %',
      (SELECT recovery_overrides FROM public.scenarios WHERE id = v_old);
  END IF;
  RAISE NOTICE 'D315/930 §4: only the legacy scenario was rewritten';
END;
$d315u$;

-- ── §5 grants ─────────────────────────────────────────────────────────────────
DO $d315g$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc p, aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
              WHERE p.oid IN ('public.recovery_config_canonical(jsonb, boolean)'::regprocedure,
                              -- §4 D314's two, whose grants this migration closes
                              'public.node_list_attributes(uuid)'::regprocedure,
                              'public.node_echelon_from_flags(boolean, boolean, boolean, boolean, boolean, boolean, boolean)'::regprocedure)
                AND a.privilege_type = 'EXECUTE'
                AND (a.grantee = 0
                     OR a.grantee IN (SELECT oid FROM pg_roles WHERE rolname IN ('anon', 'authenticated')))) THEN
    RAISE EXCEPTION 'D315/930 §5: recovery_config_canonical, node_list_attributes or node_echelon_from_flags is executable by PUBLIC, anon or authenticated';
  END IF;
END;
$d315g$;
