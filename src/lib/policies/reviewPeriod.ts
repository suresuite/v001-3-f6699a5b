// The periodic-review period T, entered and shown in WEEKS on /policies.
//
// The stored field is `review_period_days` (schemas.ts, the registry, saved
// policy versions and every hash that binds them), so the grid converts at ONE
// boundary: this module. The engine steps in whole weeks and the mapper turns
// the stored days into weeks (`project_map.py::_review_weeks`: nearest week, at
// least 1, at most 13) — the helpers here apply the same rule so the number a
// planner reads is the review cadence the run uses, never a fraction of it.
import { UNIT_DAYS } from "../../../supabase/functions/_shared/grading";

/** The engine's range for a review period, in weeks (`_review_weeks` clamp). */
export const REVIEW_WEEKS_MIN = 1;
export const REVIEW_WEEKS_MAX = 13;

const DAYS_PER_WEEK = UNIT_DAYS.week;

/** Whole weeks the engine reviews on for a stored `review_period_days`. */
export function reviewPeriodWeeks(days: number): number {
  const weeks = Math.floor(days / DAYS_PER_WEEK + 0.5);
  return Math.min(REVIEW_WEEKS_MAX, Math.max(REVIEW_WEEKS_MIN, weeks));
}

/** The stored `review_period_days` for a number of weeks typed on the grid. */
export function reviewPeriodDays(weeks: number): number {
  return reviewPeriodWeeks(weeks * DAYS_PER_WEEK) * DAYS_PER_WEEK;
}
