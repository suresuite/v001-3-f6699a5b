/**
 * A disruption's start entered in calendar time (PLAN.md §4 D318, WP 18.1).
 *
 * `start_day` stays the stored truth the engine reads (`project_map._map_events`
 * reads `start_day` and nothing else about timing). When a user enters the start
 * as an ISO week or a date, the event also keeps WHAT they entered and the
 * project start it was converted against (`start_anchor`), so a later change of
 * the project start is shown rather than silently moving the event in either
 * the run or the calendar. The engine never reads `start_anchor`
 * (`scsim/tests/test_start_anchor_ignored.py`).
 */
import type { Scenario } from "@/hooks/useScenarios";
import {
  dateToRunWeek,
  formatCalendarDate,
  formatIsoWeek,
  formatRunWeekRange,
  isCalendarDate,
  isoWeekToRunWeek,
  parseIsoWeek,
  runWeekBoundReason,
  runWeekToIsoWeek,
  type IsoWeek,
} from "./calendarWeeks";
import { editWeeks, engineWeeks } from "./planningTime";

export type ScheduleEvent = Scenario["disruption_schedule"][number];

export interface StartAnchor {
  kind: "iso_week" | "date";
  /** what the user entered: "2027-W26" or "2027-06-28" */
  value: string;
  /** `projects.simulation_start` when it was entered */
  project_start: string;
}

export type StartMode = "run_week" | StartAnchor["kind"];

export interface StartBounds {
  min: number;
  horizonWeeks?: number;
}

export type AnchoredStart = { startDay: number; anchor: StartAnchor } | { reason: string };

/** The run week a stored anchor resolves to against `projectStart`. */
export function anchorRunWeek(anchor: StartAnchor, projectStart: string): number | null {
  if (anchor.kind === "date") return isCalendarDate(anchor.value) ? dateToRunWeek(projectStart, anchor.value) : null;
  const w = parseIsoWeek(anchor.value);
  return w ? isoWeekToRunWeek(projectStart, w) : null;
}

function anchored(
  anchor: StartAnchor,
  projectStart: string,
  currentDays: number,
  bounds: StartBounds,
  entered: string,
): AnchoredStart {
  const t = anchorRunWeek(anchor, projectStart);
  if (t === null) return { reason: `${entered} is not a valid ${anchor.kind === "date" ? "date" : "ISO week"}.` };
  const reason = runWeekBoundReason(projectStart, t, bounds, entered);
  return reason ? { reason } : { startDay: editWeeks(currentDays, t), anchor };
}

/** An ISO week typed by the user → the stored start and its anchor, or a reason. */
export function startFromIsoWeek(
  projectStart: string, week: IsoWeek, currentDays: number, bounds: StartBounds,
): AnchoredStart {
  const value = formatIsoWeek(week);
  return anchored({ kind: "iso_week", value, project_start: projectStart }, projectStart, currentDays, bounds, value);
}

/** A date picked by the user → the stored start and its anchor, or a reason. */
export function startFromDate(
  projectStart: string, date: string, currentDays: number, bounds: StartBounds,
): AnchoredStart {
  return anchored(
    { kind: "date", value: date, project_start: projectStart },
    projectStart, currentDays, bounds,
    isCalendarDate(date) ? formatCalendarDate(date) : date || "The date",
  );
}

/** The event with a new start; an anchor is set or, for a run week, removed. */
export function withStart(ev: ScheduleEvent, startDay: number, anchor?: StartAnchor): ScheduleEvent {
  const { start_anchor: _drop, ...rest } = ev;
  return anchor ? { ...rest, start_day: startDay, start_anchor: anchor } : { ...rest, start_day: startDay };
}

/** The mode an event opens in: the one it was entered with. */
export function startModeOf(ev: Pick<ScheduleEvent, "start_anchor">): StartMode {
  return ev.start_anchor?.kind ?? "run_week";
}

/** "Run week 25 · 2027-W26 · 28 Jun – 4 Jul 2027": every reading of a start. */
export function calendarReading(projectStart: string | null | undefined, startDay: number): string {
  const t = engineWeeks(startDay);
  if (!projectStart || !isCalendarDate(projectStart)) return `Run week ${t}`;
  return `Run week ${t} · ${formatIsoWeek(runWeekToIsoWeek(projectStart, t))} · ${formatRunWeekRange(projectStart, t)}`;
}

export interface AnchorDrift {
  entered: string;
  enteredStart: string;
  currentStart: string;
  runWeek: number;
  /** what the event's current run week is in today's calendar */
  nowIsoWeek: string;
  /** the run week the entered value lands in against today's start */
  movedRunWeek: number | null;
  message: string;
}

/**
 * The project start moved since the start was entered: say so, and what each
 * of the two honest choices would mean. Null when nothing moved.
 */
export function anchorDrift(ev: ScheduleEvent, projectStart: string | null | undefined): AnchorDrift | null {
  const a = ev.start_anchor;
  if (!a || !projectStart || !isCalendarDate(projectStart) || a.project_start === projectStart) return null;
  const runWeek = engineWeeks(ev.start_day);
  const entered = a.kind === "date" && isCalendarDate(a.value) ? formatCalendarDate(a.value) : a.value;
  const nowIsoWeek = formatIsoWeek(runWeekToIsoWeek(projectStart, runWeek));
  const movedRunWeek = anchorRunWeek(a, projectStart);
  const was = isCalendarDate(a.project_start) ? formatCalendarDate(a.project_start) : a.project_start;
  return {
    entered,
    enteredStart: a.project_start,
    currentStart: projectStart,
    runWeek,
    nowIsoWeek,
    movedRunWeek,
    message:
      `Entered as ${entered} with the project starting ${was}. The project now starts ` +
      `${formatCalendarDate(projectStart)}, so run week ${runWeek} is now ${nowIsoWeek}.`,
  };
}

/** "Keep run week N": the event stays where it runs, and stops claiming a date. */
export function keepRunWeek(ev: ScheduleEvent): ScheduleEvent {
  return withStart(ev, ev.start_day);
}

/** "Move to <entered>": the event follows its calendar entry, or a reason. */
export function reanchor(ev: ScheduleEvent, projectStart: string, bounds: StartBounds): ScheduleEvent | { reason: string } {
  const a = ev.start_anchor;
  if (!a) return ev;
  const r = anchored({ ...a, project_start: projectStart }, projectStart, ev.start_day, bounds, a.value);
  return "reason" in r ? r : withStart(ev, r.startDay, r.anchor);
}

/** An event as the engine sees it: the anchor is what the user typed, not an input. */
export function engineEvent<T extends Record<string, unknown>>(ev: T): Omit<T, "start_anchor"> {
  const { start_anchor: _drop, ...rest } = ev;
  return rest;
}
