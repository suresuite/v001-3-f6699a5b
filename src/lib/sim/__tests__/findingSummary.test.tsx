import { describe, expect, it } from "vitest";
import { renderToStaticMarkup } from "react-dom/server";
import { FindingsPanel, type Finding } from "@/components/sim/RunGate";
import { findingSummary } from "../findingSummary";

const warning = "inbound_logistics.unit_price is unset for 24 row(s) — the engine will apply its neutral default (1). Missing prices distort procurement spend.";

describe("compact gate findings", () => {
  it("keeps the exact default and full affected count in view", () => {
    expect(findingSummary(warning)).toBe("inbound_logistics.unit_price · 24 rows missing. Using default (1).");
    expect(findingSummary(warning.replace("(1).", "(0.30)."))).toContain("default (0.30)");
    expect(findingSummary("materials.cost is derived for 195 row(s) via volume-weighted inbound prices — set the master value only to override.")).toBe("materials.cost · Derived from project data for 195 rows.");
  });

  it("names missing data and signals its fallback", () => {
    expect(findingSummary("products.demand_cv is missing for 1 row(s) (required by P-P.3): Safety-stock sizing needs variability. Fallback: scenario CV, then 0.30.")).toBe("products.demand_cv · Missing in 1 row. Fallback applies; see details.");
  });

  it("leaves unfamiliar messages intact", () => {
    const message = "Forecast ends before the run; the last value is repeated.";
    expect(findingSummary(message)).toBe(message);
  });

  it("puts explanations and affected ids in closed details, keeping fixes and blockers visible", () => {
    const findings: Finding[] = [
      { id: "warn", severity: "warn", message: warning, field: "inbound_logistics.unit_price", hint: "Affected: SUP-009" },
      { id: "block", severity: "block", message: "A supplier is required.", hint: "Affected: MAT-1" },
    ];
    const html = renderToStaticMarkup(<FindingsPanel findings={findings} source="pre-run check" warns={1} acknowledged={false} renderFix={() => <a href="/project-manager">Fix data</a>} />);
    const details = html.match(/<details\b[^>]*>[\s\S]*?<\/details>/g) ?? [];
    expect(details).toHaveLength(1);
    expect(details[0]).not.toMatch(/<details[^>]*\bopen\b/);
    expect(details[0]).toContain(warning);
    expect(details[0]).toContain("Affected: SUP-009");
    const visible = html.replace(details[0], "");
    expect(visible).toContain("Using default (1)");
    expect(visible).toContain("Fix data");
    expect(visible).toContain("A supplier is required.");
    expect(visible).toContain("Affected: MAT-1");
  });
});
