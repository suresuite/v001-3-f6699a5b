/**
 * Run weeks ↔ calendar time, authored once (PLAN.md §4 D318, WP 18.1).
 *
 * The engine's clock is 0-based weekly ticks (`scsim/scsim/core/engine.py`,
 * `for t in range(start_week, horizon)`), and an event is active while
 * `start <= t < end`. The project's `simulation_start` is run week 0: run week
 * `t` is the seven days starting `simulation_start + 7t`. Warm-up weeks have
 * dates too — the warm-up is measured, not skipped, by the calendar.
 *
 * Every date here is a CALENDAR date (`YYYY-MM-DD`) handled in UTC, so a
 * daylight-saving change can never move a day. ISO 8601 week numbering:
 * weeks start Monday; week 1 holds the year's first Thursday.
 */
import { getISOWeek, getISOWeekYear, getISOWeeksInYear, setISOWeek, startOfISOWeek } from "date-fns";
import registry from "@/lib/policies/registry.generated.json";

// The engine tick, from the mapper's export — read here rather than through
// `planningTime`, which imports a React hook module this pure rule must not need.
const DAYS_PER_WEEK: number = registry.run_window.days_per_tick;

const DAY_MS = 86_400_000;

/** `YYYY-MM-DD` (or an ISO timestamp) → UTC midnight ms, or NaN. */
export function parseCalendarDate(value: string | null | undefined): number {
  if (!value) return NaN;
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(value));
  if (!m) return NaN;
  const ms = Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
  const d = new Date(ms);
  return d.getUTCMonth() === Number(m[2]) - 1 && d.getUTCDate() === Number(m[3]) ? ms : NaN;
}

/** UTC ms → `YYYY-MM-DD`. */
export function toCalendarDate(ms: number): string {
  return new Date(ms).toISOString().slice(0, 10);
}

/** date-fns works in local time; give it a local date with the same Y-M-D. */
const localOf = (ms: number) => {
  const d = new Date(ms);
  return new Date(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate());
};
const utcOf = (d: Date) => Date.UTC(d.getFullYear(), d.getMonth(), d.getDate());

/** True when `value` is a usable calendar date. */
export function isCalendarDate(value: string | null | undefined): value is string {
  return Number.isFinite(parseCalendarDate(value));
}

/** The first day of run week `t`: `projectStart + 7t` days. */
export function runWeekStart(projectStart: string, t: number): string {
  return toCalendarDate(parseCalendarDate(projectStart) + t * DAYS_PER_WEEK * DAY_MS);
}

/** The seven days of run week `t`, first and last (inclusive). */
export function runWeekRange(projectStart: string, t: number): { first: string; last: string } {
  const first = parseCalendarDate(projectStart) + t * DAYS_PER_WEEK * DAY_MS;
  return { first: toCalendarDate(first), last: toCalendarDate(first + (DAYS_PER_WEEK - 1) * DAY_MS) };
}

/** The run week a calendar date falls in (may be negative: before the start). */
export function dateToRunWeek(projectStart: string, date: string): number {
  const s = parseCalendarDate(projectStart);
  const d = parseCalendarDate(date);
  return Math.floor(Math.round((d - s) / DAY_MS) / DAYS_PER_WEEK);
}

export interface IsoWeek {
  year: number;
  week: number;
}

/** "2027-W26". */
export function formatIsoWeek(w: IsoWeek): string {
  return `${w.year}-W${String(w.week).padStart(2, "0")}`;
}

/** "2027-W26" → {year, week}, or null. */
export function parseIsoWeek(value: string | null | undefined): IsoWeek | null {
  const m = /^(\d{4})-W(\d{1,2})$/.exec(String(value ?? "").trim());
  if (!m) return null;
  const w = { year: Number(m[1]), week: Number(m[2]) };
  return w.week >= 1 && w.week <= isoWeeksInYear(w.year) ? w : null;
}

/** 52 or 53. */
export function isoWeeksInYear(year: number): number {
  return getISOWeeksInYear(new Date(year, 5, 15));
}

/** The ISO week a calendar date falls in. */
export function isoWeekOf(date: string): IsoWeek {
  const d = localOf(parseCalendarDate(date));
  return { year: getISOWeekYear(d), week: getISOWeek(d) };
}

/** The Monday of an ISO week, as a calendar date. */
export function isoWeekMonday(w: IsoWeek): string {
  // The 4th of January is always in ISO week 1 of its year.
  const d = setISOWeek(startOfISOWeek(new Date(w.year, 0, 4)), w.week);
  return toCalendarDate(utcOf(d));
}

/** The run week holding an ISO week's Monday. */
export function isoWeekToRunWeek(projectStart: string, w: IsoWeek): number {
  return dateToRunWeek(projectStart, isoWeekMonday(w));
}

/** The ISO week a run week starts in. */
export function runWeekToIsoWeek(projectStart: string, t: number): IsoWeek {
  return isoWeekOf(runWeekStart(projectStart, t));
}

/** The ISO years a run of `horizonWeeks` touches, for a year selector. */
export function isoYearsInHorizon(projectStart: string, horizonWeeks: number): number[] {
  const first = isoWeekOf(projectStart).year;
  const last = isoWeekOf(runWeekStart(projectStart, Math.max(0, horizonWeeks - 1))).year;
  return Array.from({ length: last - first + 1 }, (_, i) => first + i);
}

/** "24 Jun 2027" — a calendar date as a person reads it, independent of time zone. */
export function formatCalendarDate(date: string, withYear = true): string {
  return new Date(parseCalendarDate(date)).toLocaleDateString(undefined, {
    day: "numeric",
    month: "short",
    ...(withYear ? { year: "numeric" } : {}),
    timeZone: "UTC",
  });
}

/** "24 Jun – 30 Jun 2027": the days of run week `t`. */
export function formatRunWeekRange(projectStart: string, t: number): string {
  const { first, last } = runWeekRange(projectStart, t);
  return `${formatCalendarDate(first, false)} – ${formatCalendarDate(last)}`;
}

/**
 * Why run week `t` cannot be a disruption start, or null. Bounds are the
 * engine's (`start_week_min`, the horizon); out of range is refused with a
 * reason rather than clamped.
 */
export function runWeekBoundReason(
  projectStart: string,
  t: number,
  bounds: { min: number; horizonWeeks?: number },
  entered: string,
): string | null {
  if (t < bounds.min) {
    return `${entered} is before run week ${bounds.min} (starts ${formatCalendarDate(runWeekStart(projectStart, bounds.min))}).`;
  }
  if (bounds.horizonWeeks !== undefined && t >= bounds.horizonWeeks) {
    return `${entered} is after the run ends (its last week, run week ${bounds.horizonWeeks - 1}, starts ${formatCalendarDate(runWeekStart(projectStart, bounds.horizonWeeks - 1))}).`;
  }
  return null;
}

/** The earliest forecast bucket's start — the engine's demand week 0 — or null. */
export function earliestPeriodStart(buckets: readonly { period_start?: string | null }[]): string | null {
  let min: string | null = null;
  for (const b of buckets) {
    const p = b.period_start ? String(b.period_start).slice(0, 10) : null;
    if (p && isCalendarDate(p) && (min === null || p < min)) min = p;
  }
  return min;
}

/**
 * The engine has a second calendar anchor: demand week 0 is the earliest
 * forecast `period_start` (`datamap.forecast_series`). When it is not the
 * project start, a date entered here and the demand the engine draws for that
 * date are counted from different days — said at the point of entry (§5 T2).
 */
export function demandAnchorNote(projectStart: string | null | undefined, demandStart: string | null | undefined): string | null {
  if (!isCalendarDate(projectStart) || !isCalendarDate(demandStart) || projectStart === demandStart) return null;
  return (
    `Demand forecasts start ${formatCalendarDate(demandStart)}; the engine counts demand weeks from there, ` +
    `while dates here count from the project start, ${formatCalendarDate(projectStart)}.`
  );
}
