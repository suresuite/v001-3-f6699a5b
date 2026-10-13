/**
 * The committed ACCURATE_Tron upload files (scripts/accurate_tron/csv) are what a
 * user uploads through /project-manager. They are checked here by the SAME
 * contract-driven validator `ingest-file` runs, so a file that would be refused
 * on upload fails CI instead — and every column it carries must map to a column
 * of its target (an unmapped header would be kept and silently mean nothing).
 */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { parseCsv } from "../../../../supabase/functions/_shared/csvParse";
import { validateRows } from "../../../../supabase/functions/_shared/ingestValidate";
import { INGEST_DATASETS } from "../../../../supabase/functions/_shared/ingestSpec.generated";

const DIR = join(__dirname, "../../../../scripts/accurate_tron/csv");
const FILES: Record<string, string> = {
  "suppliers.csv": "item_master_suppliers",
  "materials.csv": "item_master_materials",
  "products.csv": "item_master_products",
  "customers.csv": "item_master_customers",
  "bom_single_level.csv": "bom_single_level",
  "inbound_logistic.csv": "inbound_logistics",
  "outbound_logistic.csv": "outbound_logistics",
};

describe("ACCURATE_Tron upload files pass the ingest contract", () => {
  for (const [file, dataset] of Object.entries(FILES)) {
    it(`${file} → ${dataset}`, () => {
      const spec = INGEST_DATASETS[dataset];
      expect(spec, dataset).toBeDefined();
      const result = validateRows(parseCsv(readFileSync(join(DIR, file), "utf8")), spec);
      const findings = [
        ...result.fileFindings,
        ...result.rows.flatMap((r) => r.findings),
      ].filter((f) => f.level !== "warn" || f.code !== "at_warning_threshold");
      expect(findings.slice(0, 5)).toEqual([]);
      expect(result.rows.length).toBeGreaterThan(0);
    });
  }

  it("every id is a pseudonym", () => {
    const ids = /^(PRD|MAT|SUP|CUST)-\d+$/;
    for (const file of Object.keys(FILES)) {
      const { headers, rows } = parseCsv(readFileSync(join(DIR, file), "utf8"));
      headers.forEach((h, i) => {
        if (!h?.endsWith("_id")) return;
        for (const r of rows) expect(r.cells[i], `${file}:${h}`).toMatch(ids);
      });
    }
  });
});
