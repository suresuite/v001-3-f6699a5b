import { describe, expect, it, vi } from "vitest";

vi.mock("@/integrations/supabase/client", () => ({ supabase: {} }));
import {
  anchorDrift,
  calendarReading,
  engineEvent,
  keepRunWeek,
  reanchor,
  startFromDate,
  startFromIsoWeek,
  startModeOf,
  withStart,
  type ScheduleEvent,
} from "../startAnchor";
import { demandAnchorNote, earliestPeriodStart, formatCalendarDate } from "../calendarWeeks";

const ev = (over: Partial<ScheduleEvent> = {}): ScheduleEvent => ({
  target: "supplier:S1",
  target_type: "node",
  start_day: 140,
  duration_days: 28,
  magnitude_pct: 100,
  ...over,
});
const bounds = { min: 1, horizonWeeks: 52 };

describe("a disruption start entered in calendar time (§4 D318)", () => {
  it("an ISO week stores the run week in days and keeps what was entered", () => {
    const r = startFromIsoWeek("2027-01-04", { year: 2027, week: 26 }, 140, bounds);
    expect(r).toEqual({
      startDay: 175,
      anchor: { kind: "iso_week", value: "2027-W26", project_start: "2027-01-04" },
    });
  });

  it("a date stores the run week that contains it", () => {
    const r = startFromDate("2027-01-04", "2027-07-01", 140, bounds);
    expect(r).toEqual({ startDay: 175, anchor: { kind: "date", value: "2027-07-01", project_start: "2027-01-04" } });
  });

  it("an unchanged week never rewrites a stored day count that is not whole weeks", () => {
    const r = startFromIsoWeek("2027-01-04", { year: 2027, week: 18 }, 120, bounds); // 120 d rounds to week 17
    expect("startDay" in r && r.startDay).toBe(120);
  });

  it("refuses a start outside the run instead of clamping", () => {
    expect(startFromDate("2027-01-04", "2027-01-05", 140, bounds)).toEqual({ reason: expect.stringMatching(/before run week 1/) });
    expect(startFromIsoWeek("2027-01-04", { year: 2028, week: 2 }, 140, bounds)).toEqual({ reason: expect.stringMatching(/after the run ends/) });
  });

  it("a run-week edit drops the anchor; a calendar edit sets it", () => {
    const a = { kind: "date" as const, value: "2027-07-01", project_start: "2027-01-04" };
    const anchored = withStart(ev(), 175, a);
    expect(anchored.start_anchor).toEqual(a);
    expect(startModeOf(anchored)).toBe("date");
    const plain = withStart(anchored, 182);
    expect("start_anchor" in plain).toBe(false);
    expect(startModeOf(plain)).toBe("run_week");
  });

  it("states every reading of a start", () => {
    // Dates follow the viewer's locale; the run week and ISO week do not.
    expect(calendarReading("2027-01-04", 175)).toBe(
      `Run week 25 · 2027-W26 · ${formatCalendarDate("2027-06-28", false)} – ${formatCalendarDate("2027-07-04")}`,
    );
    expect(calendarReading(null, 175)).toBe("Run week 25");
  });

  it("says when the project start moved, and moves nothing until asked", () => {
    const e = withStart(ev(), 175, { kind: "iso_week", value: "2027-W26", project_start: "2027-01-04" });
    expect(anchorDrift(e, "2027-01-04")).toBeNull();
    const d = anchorDrift(e, "2027-02-01");
    expect(d?.runWeek).toBe(25);
    expect(d?.nowIsoWeek).toBe("2027-W30");
    expect(d?.movedRunWeek).toBe(21);
    expect(d?.message).toMatch(/run week 25 is now 2027-W30/);

    const kept = keepRunWeek(e);
    expect(kept.start_day).toBe(175);
    expect(kept.start_anchor).toBeUndefined();

    const moved = reanchor(e, "2027-02-01", bounds);
    expect(moved).toMatchObject({ start_day: 147, start_anchor: { value: "2027-W26", project_start: "2027-02-01" } });
  });

  it("re-anchoring refuses a calendar entry the new start puts before the run", () => {
    const e = withStart(ev(), 14, { kind: "date", value: "2027-01-18", project_start: "2027-01-04" });
    expect(reanchor(e, "2027-01-15", bounds)).toEqual({ reason: expect.stringMatching(/before run week 1/) });
  });

  it("the engine's view of an event carries no anchor", () => {
    const e = withStart(ev(), 175, { kind: "date", value: "2027-07-01", project_start: "2027-01-04" });
    expect(engineEvent(e)).toEqual(ev({ start_day: 175 }));
  });

  it("names the demand calendar when it starts elsewhere", () => {
    expect(earliestPeriodStart([{ period_start: "2027-02-01" }, { period_start: "2027-01-11" }, {}])).toBe("2027-01-11");
    expect(demandAnchorNote("2027-01-04", "2027-01-11")).toContain(`Demand forecasts start ${formatCalendarDate("2027-01-11")}`);
    expect(demandAnchorNote("2027-01-04", "2027-01-04")).toBeNull();
    expect(demandAnchorNote("2027-01-04", null)).toBeNull();
  });
});
