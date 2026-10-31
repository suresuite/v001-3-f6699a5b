import { describe, expect, it } from "vitest";
import { endForWeeks, horizonMismatch, projectWindow, windowBoundReason, windowHorizonDays } from "../projectWindow";
import { horizonWeeksOf } from "@/lib/policies/deliverySchedule";
import { HORIZON_WEEKS } from "../planningTime";
import { formatDateForDatabase, parseDateFromDatabase } from "@/utils/dateHelpers";

// PLAN.md §4 D318 — the project window is the one authored run length.
describe("projectWindow", () => {
  it("the default calendar year is 52 weeks; a three-year window is 156", () => {
    expect(projectWindow("2027-01-01", "2027-12-31")).toMatchObject({ days: 364, weeks: 52, boundReason: null });
    const w = projectWindow("2027-01-04", endForWeeks("2027-01-04", 156))!;
    expect(w.weeks).toBe(156);
    expect(windowHorizonDays(w)).toBe(1092);
  });

  it("a window that is not whole weeks rounds up: the run covers the end date", () => {
    expect(projectWindow("2027-01-04", "2027-12-27")!.weeks).toBe(51); // 357 d, exactly 51
    expect(projectWindow("2027-01-04", "2027-12-29")!.weeks).toBe(52); // 359 d
    expect(projectWindow("2027-01-04", "2028-01-05")!.weeks).toBe(53);
  });

  it("states the engine's bounds instead of hiding its clamp", () => {
    expect(windowBoundReason(HORIZON_WEEKS.min - 1)).toMatch(/at least 52/);
    expect(windowBoundReason(HORIZON_WEEKS.max + 1)).toMatch(/at most 520/);
    expect(windowBoundReason(HORIZON_WEEKS.max)).toBeNull();
    const short = projectWindow("2027-01-04", "2027-06-30")!;
    expect(short.engineWeeks).toBe(52);
    expect(short.boundReason).toMatch(/shorter than the engine runs/);
  });

  it("is null for a missing or backwards window", () => {
    expect(projectWindow(null, "2027-12-31")).toBeNull();
    expect(projectWindow("2027-12-31", "2027-01-01")).toBeNull();
  });

  it("the /policies schedule length is the same rule", () => {
    for (const [s, e] of [["2027-01-04", "2029-12-31"], ["2026-01-01", "2026-01-10"], ["2027-01-01", "2027-12-31"]]) {
      expect(horizonWeeksOf(s, e)).toBe(projectWindow(s, e)!.weeks);
    }
  });

  it("a scenario that runs another length says so", () => {
    const w = projectWindow("2027-01-04", endForWeeks("2027-01-04", 156))!;
    expect(horizonMismatch(364, w)).toMatch(/^Runs 52 wk; the project window is 156 wk/);
    expect(horizonMismatch(1092, w)).toBeNull();
    expect(horizonMismatch(364, null)).toBeNull();
  });
});

describe("project dates are the day picked, in every time zone", () => {
  it("round-trips a stored date through the picker's local Date", () => {
    for (const d of ["2027-01-04", "2027-03-28", "2027-10-31", "2028-02-29"]) {
      expect(formatDateForDatabase(parseDateFromDatabase(d))).toBe(d);
    }
    expect(formatDateForDatabase(new Date(2027, 0, 4))).toBe("2027-01-04");
    expect(parseDateFromDatabase(null)).toBeUndefined();
  });
});
