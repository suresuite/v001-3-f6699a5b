/**
 * T is typed and shown in weeks on /policies and stored as `review_period_days`.
 * These helpers must agree with the mapper's `_review_weeks` (nearest whole
 * week, at least 1, at most 13) — the grid may not show a cadence the run does
 * not use.
 */
import { describe, expect, it } from "vitest";
import { reviewPeriodDays, reviewPeriodWeeks } from "../reviewPeriod";

describe("reviewPeriodWeeks (stored days → the cadence the engine uses)", () => {
  it("is exact for whole weeks", () => {
    expect(reviewPeriodWeeks(7)).toBe(1);
    expect(reviewPeriodWeeks(28)).toBe(4);
    expect(reviewPeriodWeeks(56)).toBe(8);
  });

  it("rounds to the nearest week like the mapper (60 d → 9 wk, the observed run)", () => {
    expect(reviewPeriodWeeks(60)).toBe(9);
    expect(reviewPeriodWeeks(8)).toBe(1);
    expect(reviewPeriodWeeks(12)).toBe(2);
  });

  it("never goes below one week or above thirteen", () => {
    expect(reviewPeriodWeeks(0)).toBe(1);
    expect(reviewPeriodWeeks(1)).toBe(1);
    expect(reviewPeriodWeeks(400)).toBe(13);
  });
});

describe("reviewPeriodDays (weeks typed → stored days)", () => {
  it("stores whole weeks as days", () => {
    expect(reviewPeriodDays(8)).toBe(56);
    expect(reviewPeriodDays(1)).toBe(7);
  });

  it("round-trips through the display", () => {
    for (const weeks of [1, 2, 4, 8, 13]) {
      expect(reviewPeriodWeeks(reviewPeriodDays(weeks))).toBe(weeks);
    }
  });

  it("keeps a typed fraction to the whole week the engine would use", () => {
    expect(reviewPeriodDays(1.4)).toBe(7);
    expect(reviewPeriodDays(1.5)).toBe(14);
    expect(reviewPeriodDays(0)).toBe(7);
  });
});
