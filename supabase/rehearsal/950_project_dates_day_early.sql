-- §4 D318 · THE PROJECT DATES SAVED A DAY EARLY, CORRECTED — and nothing else.
--
-- `20261101000002` moves `YYYY-12-31 → (YYYY+1)-12-30` windows one day later. What
-- only a running database can settle (the statement is run verbatim, as 940 does):
--
--   §1 THE SIGNATURE PAIR moves, in an ordinary year and across a leap year.
--   §2 NOTHING ELSE MOVES: a 31 December start with another end, a 1 January
--      project, a 30 December end with another start, and a project with no dates.
--   §3 IDEMPOTENT: applying it twice is applying it once.
--   §4 RUNS KEEP THEIR CALENDAR: a run recorded against the old start keeps it.

DO $r950$
DECLARE
  v_org  uuid := gen_random_uuid();
  v_user uuid := gen_random_uuid();
  p1 uuid := gen_random_uuid();  -- 2025-12-31 → 2026-12-30  (signature)
  p2 uuid := gen_random_uuid();  -- 2023-12-31 → 2024-12-30  (signature, leap year)
  p3 uuid := gen_random_uuid();  -- 2025-12-31 → 2026-06-30  (31 Dec start, other end)
  p4 uuid := gen_random_uuid();  -- 2026-01-01 → 2026-12-31  (already right)
  p5 uuid := gen_random_uuid();  -- 2026-03-02 → 2026-12-30  (30 Dec end, other start)
  p6 uuid := gen_random_uuid();  -- no dates
  v_scen uuid := gen_random_uuid();
  v_run  uuid;
  v_n    integer;
BEGIN
  INSERT INTO public.organizations (id, name, slug) VALUES (v_org, 'R950 Org', 'r950-' || substr(v_org::text, 1, 8));
  INSERT INTO public.approved_users (id, email, name, password_hash, role, organization, organization_id, is_active)
    VALUES (v_user, 'r950u@example.invalid', 'R950 User', 'x', 'modeler', 'R950 Org', v_org, true);
  INSERT INTO public.projects (id, name, modeler_id, plant_name, simulation_start, simulation_end) VALUES
    (p1, 'R950 a', v_user, 'P', DATE '2025-12-31', DATE '2026-12-30'),
    (p2, 'R950 b', v_user, 'P', DATE '2023-12-31', DATE '2024-12-30'),
    (p3, 'R950 c', v_user, 'P', DATE '2025-12-31', DATE '2026-06-30'),
    (p4, 'R950 d', v_user, 'P', DATE '2026-01-01', DATE '2026-12-31'),
    (p5, 'R950 e', v_user, 'P', DATE '2026-03-02', DATE '2026-12-30');
  INSERT INTO public.projects (id, name, modeler_id, plant_name) VALUES (p6, 'R950 f', v_user, 'P');
  UPDATE public.projects SET simulation_start = NULL, simulation_end = NULL WHERE id = p6;

  INSERT INTO public.scenarios (id, project_id, name, horizon_days, seed, replications)
    VALUES (v_scen, p1, 'R950 baseline', 364, 42, 1);
  INSERT INTO public.simulation_runs (scenario_id, project_id, status, rep_count_target, rep_count_done, code_version)
    VALUES (v_scen, p1, 'completed', 1, 1, '') RETURNING id INTO v_run;

  -- The migration's statement, verbatim (20261101000002).
  FOR v_n IN 1..2 LOOP  -- §3: twice
    UPDATE public.projects
       SET simulation_start = simulation_start + 1,
           simulation_end   = simulation_end + 1
     WHERE extract(month FROM simulation_start) = 12
       AND extract(day FROM simulation_start) = 31
       AND simulation_end = (simulation_start + 1) + interval '1 year' - interval '2 days';
  END LOOP;

  -- ══ §1 the signature pair, and §3 once only ══
  IF (SELECT (simulation_start, simulation_end) FROM public.projects WHERE id = p1)
       IS DISTINCT FROM (DATE '2026-01-01', DATE '2026-12-31') THEN
    RAISE EXCEPTION 'R950 §1/§3: 2025-12-31 → 2026-12-30 did not become 2026-01-01 → 2026-12-31 exactly once';
  END IF;
  IF (SELECT (simulation_start, simulation_end) FROM public.projects WHERE id = p2)
       IS DISTINCT FROM (DATE '2024-01-01', DATE '2024-12-31') THEN
    RAISE EXCEPTION 'R950 §1: the leap-year pair 2023-12-31 → 2024-12-30 was not corrected';
  END IF;

  -- ══ §2 nothing else ══
  IF (SELECT (simulation_start, simulation_end) FROM public.projects WHERE id = p3)
       IS DISTINCT FROM (DATE '2025-12-31', DATE '2026-06-30')
     OR (SELECT (simulation_start, simulation_end) FROM public.projects WHERE id = p4)
       IS DISTINCT FROM (DATE '2026-01-01', DATE '2026-12-31')
     OR (SELECT (simulation_start, simulation_end) FROM public.projects WHERE id = p5)
       IS DISTINCT FROM (DATE '2026-03-02', DATE '2026-12-30')
     OR (SELECT simulation_start FROM public.projects WHERE id = p6) IS NOT NULL THEN
    RAISE EXCEPTION 'R950 §2: a date outside the signature pair was moved';
  END IF;

  -- ══ §4 runs keep their calendar ══
  IF (SELECT calendar_start FROM public.simulation_runs WHERE id = v_run) IS DISTINCT FROM DATE '2025-12-31' THEN
    RAISE EXCEPTION 'R950 §4: a run''s recorded calendar moved with its project';
  END IF;

  RAISE NOTICE 'R950 project dates: the signature pair moves once, nothing else moves, runs keep their calendar — all hold';
END
$r950$;
