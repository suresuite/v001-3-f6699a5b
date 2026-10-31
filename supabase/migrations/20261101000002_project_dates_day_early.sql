-- PLAN.md §28 · WP 18.3 · §4 D318 — the project dates saved a day early, corrected.
--
-- Until #420 the project form stored a picked date through `toISOString()`, which
-- converts the picker's LOCAL midnight to UTC first. East of Greenwich that is the
-- previous day, so the default window "1 Jan – 31 Dec" was stored as
-- `YYYY-12-31 → (YYYY+1)-12-30`. The WP 18.2 reading (§15 run 41220357251) found that
-- pair on every project that has dates — five at 2025-12-31 → 2026-12-30 and
-- `Project AA - ver3` at 2023-12-31 → 2024-12-30. Since WP 18.1 `simulation_start` is
-- run week 0, so the error dated every calendar label a day early.
--
-- Owner decision (2026-10-31): move them to the days that were picked.
--
-- ONLY THE SIGNATURE PAIR moves: a start on 31 December AND an end one year less a
-- day after the corrected start (30 December of the next year). Any other date might
-- have been typed on purpose, and nothing records the zone that wrote it, so it is left
-- alone. The window's length does not change (52 weeks, or 53 across a leap year).
--
-- NOT TOUCHED: `simulation_runs.calendar_start`. A run's calendar is fixed once
-- recorded (`20261101000001`); the 164 runs backfilled from these starts keep the
-- 31 December they recorded, and every surface already labels them "filled later".
-- No hash, RunKey, fingerprint, engine or worker reads these two columns.
--
-- Idempotent: a corrected start is 1 January, which the signature no longer matches.

UPDATE public.projects
   SET simulation_start = simulation_start + 1,
       simulation_end   = simulation_end + 1
 WHERE extract(month FROM simulation_start) = 12
   AND extract(day FROM simulation_start) = 31
   AND simulation_end = (simulation_start + 1) + interval '1 year' - interval '2 days';
