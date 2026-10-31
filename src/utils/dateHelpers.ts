/**
 * Date utility functions for simulation date handling
 */

/**
 * Get the first day of the current year
 */
export function getCurrentYearStart(): Date {
  const currentYear = new Date().getFullYear();
  return new Date(currentYear, 0, 1); // January 1st
}

/**
 * Get the last day of the current year
 */
export function getCurrentYearEnd(): Date {
  const currentYear = new Date().getFullYear();
  return new Date(currentYear, 11, 31); // December 31st
}

/**
 * Get default simulation date range for current year
 */
export function getDefaultSimulationDateRange(): { start: Date; end: Date } {
  return {
    start: getCurrentYearStart(),
    end: getCurrentYearEnd()
  };
}

/**
 * Format date for database (YYYY-MM-DD) — the calendar day the user PICKED.
 *
 * A date picker yields local midnight; `toISOString()` converted that to UTC
 * first, so east of Greenwich (UTC+1 … UTC+14) a picked 4 Jan was stored as
 * 3 Jan. Since `simulation_start` is run week 0 (PLAN.md §4 D318), that moved
 * every calendar-entered disruption by a day. Local Y-M-D is the day picked.
 */
export function formatDateForDatabase(date: Date | null | undefined): string | null {
  if (!date || Number.isNaN(date.getTime())) return null;
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

/**
 * A stored `YYYY-MM-DD` as a picker's Date (local midnight of that day).
 * `new Date('2027-01-04')` is UTC midnight, which west of Greenwich is 3 Jan.
 */
export function parseDateFromDatabase(value: string | null | undefined): Date | undefined {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(value ?? ''));
  return m ? new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3])) : undefined;
}

/**
 * Get fallback dates when database dates are null
 */
export function getFallbackSimulationDates(
  startDate: string | null | undefined,
  endDate: string | null | undefined
): { start: Date; end: Date } {
  const defaults = getDefaultSimulationDateRange();
  
  return {
    start: parseDateFromDatabase(startDate) ?? defaults.start,
    end: parseDateFromDatabase(endDate) ?? defaults.end
  };
}