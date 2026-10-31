-- §4 D318 · A RUN SAYS WHICH CALENDAR IT WAS READ AGAINST.
--
-- `20261101000001` adds `simulation_runs.calendar_start` + `calendar_start_source`.
-- What only a running database can settle:
--
--   §1 THE STAMP: a run inserted for a project with a simulation start records it,
--      source 'dispatch'; a project with none leaves both NULL.
--   §2 FIXED: once recorded, the calendar cannot be changed — editing the project
--      start afterwards does not move it, and neither does a direct UPDATE.
--   §3 THE BACKFILL: the migration's statement fills a run that predates the
--      column with source 'backfill', and moves NO other column — `updated_at`
--      included, because `sim_runs_updated_at` is held off while it runs.
--   §4 THE CHECK: a calendar with no source, or a source outside the two, is refused.
--   §5 GRANTS: the trigger function is not callable by PUBLIC, `anon` or `authenticated`.

DO $r940$
DECLARE
  v_org   uuid := gen_random_uuid();
  v_user  uuid := gen_random_uuid();
  v_proj  uuid := gen_random_uuid();
  v_bare  uuid := gen_random_uuid();
  v_scen  uuid := gen_random_uuid();
  v_scen2 uuid := gen_random_uuid();
  v_run   uuid;
  v_none  uuid;
  v_old   uuid;
  v_row   public.simulation_runs%ROWTYPE;
  v_after public.simulation_runs%ROWTYPE;
  v_state text;
BEGIN
  INSERT INTO public.organizations (id, name, slug) VALUES (v_org, 'R940 Org', 'r940-' || substr(v_org::text, 1, 8));
  INSERT INTO public.approved_users (id, email, name, password_hash, role, organization, organization_id, is_active)
    VALUES (v_user, 'r940u@example.invalid', 'R940 User', 'x', 'modeler', 'R940 Org', v_org, true);
  INSERT INTO public.projects (id, name, modeler_id, plant_name, simulation_start, simulation_end)
    VALUES (v_proj, 'R940', v_user, 'P', DATE '2027-01-04', DATE '2029-12-31');
  INSERT INTO public.projects (id, name, modeler_id, plant_name) VALUES (v_bare, 'R940 bare', v_user, 'P');
  UPDATE public.projects SET simulation_start = NULL WHERE id = v_bare;
  INSERT INTO public.scenarios (id, project_id, name, horizon_days, seed, replications)
    VALUES (v_scen, v_proj, 'R940 baseline', 364, 42, 1), (v_scen2, v_bare, 'R940 bare', 364, 42, 1);

  -- ══ §1 the stamp ══
  INSERT INTO public.simulation_runs (scenario_id, project_id, status, rep_count_target, rep_count_done, code_version)
    VALUES (v_scen, v_proj, 'queued', 1, 0, '') RETURNING id INTO v_run;
  SELECT * INTO v_row FROM public.simulation_runs WHERE id = v_run;
  IF v_row.calendar_start IS DISTINCT FROM DATE '2027-01-04' OR v_row.calendar_start_source IS DISTINCT FROM 'dispatch' THEN
    RAISE EXCEPTION 'R940 §1: a dispatched run did not record its project start: % / %',
      v_row.calendar_start, v_row.calendar_start_source;
  END IF;
  INSERT INTO public.simulation_runs (scenario_id, project_id, status, rep_count_target, rep_count_done, code_version)
    VALUES (v_scen2, v_bare, 'queued', 1, 0, '') RETURNING id INTO v_none;
  SELECT * INTO v_row FROM public.simulation_runs WHERE id = v_none;
  IF v_row.calendar_start IS NOT NULL OR v_row.calendar_start_source IS NOT NULL THEN
    RAISE EXCEPTION 'R940 §1: a project with no start gave its run a calendar';
  END IF;

  -- ══ §2 fixed ══
  UPDATE public.projects SET simulation_start = DATE '2027-02-01' WHERE id = v_proj;
  IF (SELECT calendar_start FROM public.simulation_runs WHERE id = v_run) IS DISTINCT FROM DATE '2027-01-04' THEN
    RAISE EXCEPTION 'R940 §2: editing the project start moved a recorded run''s calendar';
  END IF;
  v_state := NULL;
  BEGIN
    UPDATE public.simulation_runs SET calendar_start = DATE '2027-02-01' WHERE id = v_run;
  EXCEPTION WHEN check_violation THEN v_state := 'refused';
  END;
  IF v_state IS NULL THEN RAISE EXCEPTION 'R940 §2: a recorded calendar was changed'; END IF;
  -- Other columns of the run still update.
  UPDATE public.simulation_runs SET status = 'running' WHERE id = v_run;

  -- ══ §3 the backfill ══
  -- A run as it was before the column: inserted with the stamp held off.
  ALTER TABLE public.simulation_runs DISABLE TRIGGER simulation_runs_calendar_ins;
  INSERT INTO public.simulation_runs (scenario_id, project_id, status, rep_count_target, rep_count_done, code_version,
                                      created_at, updated_at)
    VALUES (v_scen, v_proj, 'completed', 1, 1, '', now() - interval '30 days', now() - interval '29 days')
    RETURNING id INTO v_old;
  ALTER TABLE public.simulation_runs ENABLE TRIGGER simulation_runs_calendar_ins;
  SELECT * INTO v_row FROM public.simulation_runs WHERE id = v_old;
  IF v_row.calendar_start IS NOT NULL THEN RAISE EXCEPTION 'R940 §3: setup — the old run already has a calendar'; END IF;

  -- The migration's statement, verbatim (20261101000001 · history).
  ALTER TABLE public.simulation_runs DISABLE TRIGGER sim_runs_updated_at;
  UPDATE public.simulation_runs r
     SET calendar_start = p.simulation_start,
         calendar_start_source = 'backfill'
    FROM public.projects p
   WHERE p.id = r.project_id
     AND r.calendar_start IS NULL
     AND p.simulation_start IS NOT NULL;
  ALTER TABLE public.simulation_runs ENABLE TRIGGER sim_runs_updated_at;

  SELECT * INTO v_after FROM public.simulation_runs WHERE id = v_old;
  IF v_after.calendar_start IS DISTINCT FROM DATE '2027-02-01' OR v_after.calendar_start_source IS DISTINCT FROM 'backfill' THEN
    RAISE EXCEPTION 'R940 §3: the backfill did not fill an earlier run: % / %', v_after.calendar_start, v_after.calendar_start_source;
  END IF;
  IF (to_jsonb(v_after) - ARRAY['calendar_start','calendar_start_source'])
       IS DISTINCT FROM (to_jsonb(v_row) - ARRAY['calendar_start','calendar_start_source']) THEN
    RAISE EXCEPTION 'R940 §3: the backfill moved another column of the run: before % after %', to_jsonb(v_row), to_jsonb(v_after);
  END IF;
  IF (SELECT calendar_start_source FROM public.simulation_runs WHERE id = v_run) IS DISTINCT FROM 'dispatch'
     OR (SELECT calendar_start FROM public.simulation_runs WHERE id = v_none) IS NOT NULL THEN
    RAISE EXCEPTION 'R940 §3: the backfill touched a run that already had a calendar, or one with no project start';
  END IF;

  -- ══ §4 the check ══
  v_state := NULL;
  BEGIN
    INSERT INTO public.simulation_runs (scenario_id, project_id, status, rep_count_target, rep_count_done, code_version,
                                        calendar_start, calendar_start_source)
      VALUES (v_scen, v_proj, 'queued', 1, 0, '', DATE '2027-01-04', 'guess');
  EXCEPTION WHEN check_violation THEN v_state := 'refused';
  END;
  IF v_state IS NULL THEN RAISE EXCEPTION 'R940 §4: a calendar source outside dispatch/backfill was accepted'; END IF;
  v_state := NULL;
  BEGIN
    UPDATE public.simulation_runs SET calendar_start_source = 'dispatch' WHERE id = v_none;
  EXCEPTION WHEN check_violation THEN v_state := 'refused';
  END;
  IF v_state IS NULL THEN RAISE EXCEPTION 'R940 §4: a source with no calendar was accepted'; END IF;

  -- ══ §5 grants ══
  IF has_function_privilege('anon', 'public._simulation_run_calendar()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public._simulation_run_calendar()', 'EXECUTE') THEN
    RAISE EXCEPTION 'R940 §5: the calendar trigger function is callable by a client role';
  END IF;

  RAISE NOTICE 'R940 run calendar: stamp, fixed once recorded, backfill moves nothing else, check, grants — all hold';
END
$r940$;
