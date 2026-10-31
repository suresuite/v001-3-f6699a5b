-- PLAN.md §28 · WP 18.1 · §4 D318 — every run says which calendar it was read against.
--
-- A disruption's start can now be entered as an ISO week or a date, converted
-- through `projects.simulation_start` (run week 0). A run's dates must not move
-- when somebody later edits that start, so the run row carries the calendar it
-- was dispatched against, stamped at INSERT and never re-read from the project.
--
--   calendar_start         the project's simulation_start the run was read against
--   calendar_start_source  'dispatch' — stamped when the row was inserted
--                          'backfill' — filled by this migration for a run that
--                                       predates the column, from the project's
--                                       start AS IT WAS ON THE DAY THIS RAN; the
--                                       run itself never recorded one, and every
--                                       screen that shows it says so (§5 T1)
--
-- Not in `simulation_run_spec`: the engine never reads a calendar date, so the
-- RunKey of an identical simulation does not move. Nothing else on a run row is
-- written: `sim_runs_updated_at` is held off for the backfill, so `updated_at`
-- stays the run's own (`rehearsal/940` proves no other column moves).

ALTER TABLE public.simulation_runs
  ADD COLUMN IF NOT EXISTS calendar_start        date,
  ADD COLUMN IF NOT EXISTS calendar_start_source text;

ALTER TABLE public.simulation_runs DROP CONSTRAINT IF EXISTS simulation_runs_calendar_start_source_check;
ALTER TABLE public.simulation_runs
  ADD CONSTRAINT simulation_runs_calendar_start_source_check
  CHECK ((calendar_start IS NULL) = (calendar_start_source IS NULL)
         AND (calendar_start_source IS NULL OR calendar_start_source IN ('dispatch', 'backfill')));

COMMENT ON COLUMN public.simulation_runs.calendar_start IS
  'projects.simulation_start this run was read against — run week 0 (PLAN.md §4 D318). Never re-read from the project.';
COMMENT ON COLUMN public.simulation_runs.calendar_start_source IS
  '''dispatch'' (stamped at insert) or ''backfill'' (filled by 20261101000001 for an earlier run, from the project start as of that day).';

-- ── the stamp, on the one table rather than in each writer ─────────────────
-- A derivation inside somebody else's INSERT names WHAT and decides nothing
-- (20261001000009's rule). SECURITY DEFINER so a caller whose RLS cannot see the
-- project row still gets the stamp; it reads one column of the run's own project.
CREATE OR REPLACE FUNCTION public._simulation_run_calendar()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.calendar_start IS NULL THEN
      SELECT p.simulation_start INTO NEW.calendar_start
        FROM public.projects p WHERE p.id = NEW.project_id;
      NEW.calendar_start_source := CASE WHEN NEW.calendar_start IS NULL THEN NULL ELSE 'dispatch' END;
    END IF;
    RETURN NEW;
  END IF;
  -- UPDATE: a calendar once recorded is the run's, like its seed and schedule.
  IF OLD.calendar_start IS NOT NULL
     AND (NEW.calendar_start IS DISTINCT FROM OLD.calendar_start
          OR NEW.calendar_start_source IS DISTINCT FROM OLD.calendar_start_source) THEN
    RAISE EXCEPTION 'simulation_runs: a run''s calendar_start is recorded once and never changed (§4 D318)'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public._simulation_run_calendar() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS simulation_runs_calendar_ins ON public.simulation_runs;
CREATE TRIGGER simulation_runs_calendar_ins
  BEFORE INSERT ON public.simulation_runs
  FOR EACH ROW EXECUTE FUNCTION public._simulation_run_calendar();
DROP TRIGGER IF EXISTS simulation_runs_calendar_upd ON public.simulation_runs;
CREATE TRIGGER simulation_runs_calendar_upd
  BEFORE UPDATE OF calendar_start, calendar_start_source ON public.simulation_runs
  FOR EACH ROW EXECUTE FUNCTION public._simulation_run_calendar();

-- ── history: the owner's decision (2026-10-31) — fill past runs, and say so ─
ALTER TABLE public.simulation_runs DISABLE TRIGGER sim_runs_updated_at;
UPDATE public.simulation_runs r
   SET calendar_start = p.simulation_start,
       calendar_start_source = 'backfill'
  FROM public.projects p
 WHERE p.id = r.project_id
   AND r.calendar_start IS NULL
   AND p.simulation_start IS NOT NULL;
ALTER TABLE public.simulation_runs ENABLE TRIGGER sim_runs_updated_at;

SELECT pg_notify('pgrst', 'reload schema');
