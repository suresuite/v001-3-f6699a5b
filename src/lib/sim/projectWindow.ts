/**
 * How long a run is — the project's simulation window, authored once
 * (PLAN.md §4 D318, WP 18.1; owner decision 2026-10-31).
 *
 * Before this, three things set a run's length and nothing compared them: the
 * project's start and end (which sized the /policies delivery schedule), each
 * scenario's `horizon_days` (what the engine runs) and the demand forecast. The
 * project window is now the authored length: a new scenario with no validated
 * world takes it, every week field is bounded by it, and a scenario whose
 * horizon differs says so. The engine's bounds are its own export
 * (`HORIZON_WEEKS`, the mapper's 52–520 week clamp), never a literal here.
 */
import { formatCalendarDate, isCalendarDate, parseCalendarDate } from "./calendarWeeks";
import registry from "@/lib/policies/registry.generated.json";
import { runWindow } from "./runWindow";

// The engine's tick and horizon bounds, from the mapper's export (the same
// values `planningTime` re-exports; read directly so /policies' pure helpers
// need no hook module).
const R = registry.run_window;
const DAYS_PER_WEEK: number = R.days_per_tick;
const HORIZON_WEEKS = { min: R.horizon_weeks_floor, max: R.horizon_weeks_ceiling } as const;

const DAY_MS = 86_400_000;

export interface ProjectWindow {
  start: string;
  end: string;
  /** whole days from start to end */
  days: number;
  /** whole weeks, rounded up: the run covers the end date */
  weeks: number;
  /** the weeks the engine will actually run (clamped to its bounds) */
  engineWeeks: number;
  /** why the engine runs a different length, or null */
  boundReason: string | null;
}

/** The window, or null when either date is missing, invalid or not after the start. */
export function projectWindow(start: string | null | undefined, end: string | null | undefined): ProjectWindow | null {
  if (!isCalendarDate(start) || !isCalendarDate(end)) return null;
  const days = Math.round((parseCalendarDate(end) - parseCalendarDate(start)) / DAY_MS);
  if (days <= 0) return null;
  const weeks = Math.ceil(days / DAYS_PER_WEEK);
  const engine = Math.min(HORIZON_WEEKS.max, Math.max(HORIZON_WEEKS.min, weeks));
  return {
    start,
    end,
    days,
    weeks,
    engineWeeks: engine,
    boundReason: windowBoundReason(weeks),
  };
}

/** Why the engine would not run `weeks` as given, or null. */
export function windowBoundReason(weeks: number): string | null {
  if (weeks < HORIZON_WEEKS.min) {
    return `${weeks} weeks is shorter than the engine runs — it runs at least ${HORIZON_WEEKS.min} weeks.`;
  }
  if (weeks > HORIZON_WEEKS.max) {
    return `${weeks} weeks is longer than the engine runs — it runs at most ${HORIZON_WEEKS.max} weeks.`;
  }
  return null;
}

/** The window's length as a scenario's `horizon_days`: whole engine weeks. */
export function windowHorizonDays(w: ProjectWindow): number {
  return w.engineWeeks * DAYS_PER_WEEK;
}

/** The end date a run of `weeks` from `start` reaches (the last day it covers). */
export function endForWeeks(start: string, weeks: number): string {
  return new Date(parseCalendarDate(start) + (weeks * DAYS_PER_WEEK - 1) * DAY_MS).toISOString().slice(0, 10);
}

/** "156 wk (4 Jan 2027 – 1 Jan 2030)". */
export function formatWindow(w: ProjectWindow): string {
  return `${w.weeks} wk (${formatCalendarDate(w.start)} – ${formatCalendarDate(w.end)})`;
}

/**
 * A scenario whose horizon is not the project window, said at the point of
 * display; null when they agree or there is no window.
 */
export function horizonMismatch(horizonDays: number, w: ProjectWindow | null): string | null {
  if (!w) return null;
  // The engine's own horizon rule (rounded and clamped), not a second copy.
  const runs = runWindow({ horizon_days: horizonDays, warmup_days: 0, warmup_mode: "auto" }).horizonWeeks;
  if (runs === w.engineWeeks) return null;
  return `Runs ${runs} wk; the project window is ${formatWindow(w)}.`;
}
