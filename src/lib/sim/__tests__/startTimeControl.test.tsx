import { describe, expect, it, vi } from "vitest";
import { renderToStaticMarkup } from "react-dom/server";

vi.mock("@/integrations/supabase/client", () => ({ supabase: {} }));
import { AnchorDriftNote, StartTimeControl } from "@/components/sim/DisruptionFields";

const base = { start_day: 175, target: "supplier:S1", target_type: "node" as const, duration_days: 28, magnitude_pct: 100 };
const noop = () => {};

// §4 D318 — the start-time control: run week, ISO week or date, through the project start.
describe("StartTimeControl", () => {
  it("without a project start, only the run week can be entered, and it says why", () => {
    const html = renderToStaticMarkup(<StartTimeControl event={base} onChange={noop} projectStart={null} horizonWeeks={52} />);
    expect(html.match(/disabled=""/g)?.length).toBe(2);
    expect(html).toContain("need the project’s simulation start");
    expect(html).toContain("Run week 25");
  });

  it("opens in the mode the start was entered with, showing what was entered", () => {
    const ev = { ...base, start_anchor: { kind: "date" as const, value: "2027-07-01", project_start: "2027-01-04" } };
    const html = renderToStaticMarkup(<StartTimeControl event={ev} onChange={noop} projectStart="2027-01-04" horizonWeeks={52} />);
    expect(html).toContain('type="date"');
    expect(html).toContain('value="2027-07-01"');
    expect(html).toContain("Run week 25 · 2027-W26");
  });

  it("an ISO-week entry lists the run's ISO years", () => {
    const ev = { ...base, start_anchor: { kind: "iso_week" as const, value: "2027-W26", project_start: "2027-01-04" } };
    const html = renderToStaticMarkup(<StartTimeControl event={ev} onChange={noop} projectStart="2027-01-04" horizonWeeks={156} />);
    for (const y of [2027, 2028, 2029]) expect(html).toContain(`<option value="${y}"`);
  });
});

describe("AnchorDriftNote", () => {
  it("is silent while the project start is unchanged, and offers both choices once it moves", () => {
    const ev = { ...base, start_anchor: { kind: "iso_week" as const, value: "2027-W26", project_start: "2027-01-04" } };
    expect(renderToStaticMarkup(<AnchorDriftNote event={ev} projectStart="2027-01-04" onChange={noop} />)).toBe("");
    const html = renderToStaticMarkup(<AnchorDriftNote event={ev} projectStart="2027-02-01" horizonWeeks={52} onChange={noop} />);
    expect(html).toContain("Keep run week 25");
    expect(html).toContain("Move to 2027-W26 (run week 21)");
  });
});
