import { describe, expect, it } from "vitest";
import {
  dateToRunWeek,
  formatIsoWeek,
  isoWeekMonday,
  isoWeekOf,
  isoWeekToRunWeek,
  isoWeeksInYear,
  isoYearsInHorizon,
  parseCalendarDate,
  parseIsoWeek,
  runWeekBoundReason,
  runWeekRange,
  runWeekStart,
  runWeekToIsoWeek,
} from "../calendarWeeks";
import { disruptionWeeks } from "../runWindow";

describe("calendarWeeks (§4 D318)", () => {
  it("run week 0 is the project start; week t is 7t days later", () => {
    expect(runWeekStart("2027-01-04", 0)).toBe("2027-01-04");
    expect(runWeekStart("2027-01-04", 25)).toBe("2027-06-28");
    expect(runWeekRange("2027-01-04", 1)).toEqual({ first: "2027-01-11", last: "2027-01-17" });
  });

  it("crosses a DST change without moving a day", () => {
    // Europe and the US both change clocks in March and October/November.
    expect(runWeekStart("2027-03-01", 4)).toBe("2027-03-29");
    expect(runWeekStart("2027-10-25", 1)).toBe("2027-11-01");
    expect(dateToRunWeek("2027-03-01", "2027-03-29")).toBe(4);
  });

  it("a date maps to the run week that contains it, and round-trips", () => {
    expect(dateToRunWeek("2027-01-04", "2027-01-04")).toBe(0);
    expect(dateToRunWeek("2027-01-04", "2027-01-10")).toBe(0);
    expect(dateToRunWeek("2027-01-04", "2027-01-11")).toBe(1);
    expect(dateToRunWeek("2027-01-04", "2027-01-03")).toBe(-1);
    for (let t = 0; t < 520; t += 37) {
      expect(dateToRunWeek("2027-01-07", runWeekStart("2027-01-07", t))).toBe(t);
    }
  });

  it("ISO 8601 numbering at year boundaries", () => {
    expect(isoWeekOf("2027-01-01")).toEqual({ year: 2026, week: 53 });
    expect(isoWeekOf("2027-01-04")).toEqual({ year: 2027, week: 1 });
    expect(isoWeeksInYear(2026)).toBe(53);
    expect(isoWeeksInYear(2027)).toBe(52);
    expect(isoWeekMonday({ year: 2027, week: 1 })).toBe("2027-01-04");
    expect(isoWeekMonday({ year: 2026, week: 53 })).toBe("2026-12-28");
    expect(formatIsoWeek({ year: 2027, week: 6 })).toBe("2027-W06");
    expect(parseIsoWeek("2027-W26")).toEqual({ year: 2027, week: 26 });
    expect(parseIsoWeek("2027-W53")).toBeNull();
    expect(parseIsoWeek("2026-W53")).toEqual({ year: 2026, week: 53 });
  });

  it("an ISO week maps to the run week holding its Monday", () => {
    // Monday start: one to one.
    expect(isoWeekToRunWeek("2027-01-04", { year: 2027, week: 26 })).toBe(25);
    expect(runWeekToIsoWeek("2027-01-04", 25)).toEqual({ year: 2027, week: 26 });
    // Thursday start: the Monday of 2027-W26 (28 Jun) lies in the run week
    // that began Thu 24 Jun.
    expect(isoWeekToRunWeek("2027-01-07", { year: 2027, week: 26 })).toBe(24);
    expect(runWeekRange("2027-01-07", 24)).toEqual({ first: "2027-06-24", last: "2027-06-30" });
  });

  it("lists every ISO year a long run touches", () => {
    expect(isoYearsInHorizon("2027-01-04", 52)).toEqual([2027]);
    expect(isoYearsInHorizon("2027-01-04", 156)).toEqual([2027, 2028, 2029]);
    expect(isoYearsInHorizon("2027-01-04", 520).length).toBe(10);
  });

  it("refuses out-of-range starts with a reason instead of clamping", () => {
    expect(runWeekBoundReason("2027-01-04", 0, { min: 1, horizonWeeks: 52 }, "4 Jan 2027")).toMatch(/before run week 1/);
    expect(runWeekBoundReason("2027-01-04", 52, { min: 1, horizonWeeks: 52 }, "2028-W01")).toMatch(/after the run ends/);
    expect(runWeekBoundReason("2027-01-04", 25, { min: 1, horizonWeeks: 52 }, "x")).toBeNull();
  });

  it("agrees with the engine's rule: a run week stored as days runs as that week", () => {
    for (const t of [1, 2, 25, 51, 300]) expect(disruptionWeeks(t * 7, 7).startWeek).toBe(t);
  });

  it("rejects malformed dates", () => {
    expect(parseCalendarDate("2027-02-30")).toBeNaN();
    expect(parseCalendarDate("")).toBeNaN();
    expect(parseCalendarDate("2027-02-28T00:00:00Z")).toBe(Date.UTC(2027, 1, 28));
  });
});
