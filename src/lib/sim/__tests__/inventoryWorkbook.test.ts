/**
 * The inventory explorer's workbook — every sheet, in order, from a REAL
 * inspection run, with the record first and the explorer's limits inside it.
 */
import { describe, expect, it } from "vitest";
import * as XLSX from "xlsx";
import type { ReproducibilityRecord } from "@/lib/trust/reproducibilityRecord";
import RUN from "./fixtures/inventoryInspectionRun.json";
import {
  EXPLORER_LIMITS,
  NOT_STOCKED,
  flatBom,
  materialTable,
  materialUse,
  productTable,
  snapshotInputs,
  suppliersByMaterial,
  usersByMaterial,
  type ItemSeriesRow,
} from "../inventoryExplorer";
import {
  USE_MEASURE,
  buildInventoryWorkbook,
  inventoryFileName,
  itemMeasures,
  uniqueSheetNames,
} from "../inventoryWorkbook";

const rows = RUN.item_series as unknown as ItemSeriesRow[];
const W0 = RUN.warmup_detected_at as number;
const inputs = snapshotInputs(RUN.snapshot);
const bom = flatBom(inputs.bom ?? [], inputs.bom_multi_level ?? []);
const use = materialUse(rows, bom);
const materials = materialTable(rows, use, W0, { suppliers: suppliersByMaterial(inputs.inbound ?? []), users: usersByMaterial(bom) });
const products = productTable(rows, W0);

const build = (scope: "selected" | "all", selected = [{ kind: "material" as const, id: "M1" }, { kind: "product" as const, id: "P_O" }]) =>
  buildInventoryWorkbook({ record: null, recordAbsentBecause: "test", materials, products, rows, use, selected, scope });

const aoa = (wb: XLSX.WorkBook, name: string) =>
  XLSX.utils.sheet_to_json<(string | number | null)[]>(wb.Sheets[name], { header: 1, defval: null });

describe("inventory workbook", () => {
  it("has every sheet, record first, one per selected item, then the long form", () => {
    const wb = build("selected");
    expect(wb.SheetNames).toEqual(["record", "materials", "products", "M M1", "FG P_O", "weekly"]);
  });

  it("states the explorer's own limits in the record — even when the record is absent", () => {
    const text = aoa(build("selected"), "record").flat().join(" ");
    for (const l of EXPLORER_LIMITS) expect(text).toContain(l.limit);
    expect(text).toContain("NOT SUPPLIED");
  });

  it("with a record, ships it first and appends the explorer's limits to the record's own", () => {
    const record = {
      projectId: "p", projectName: "Project", measuredAt: "2026-10-20T00:00:00Z", reproducible: true,
      headline: "reproducible", bindings: [], analyses: [],
      limits: [{ ref: "D1", limit: "the record's own limit", consequence: "c" }],
    } as unknown as ReproducibilityRecord;
    const wb = buildInventoryWorkbook({ record, materials, products, rows, use, selected: [], scope: "selected" });
    expect(wb.SheetNames[0]).toBe("record");
    const text = aoa(wb, "record").flat().join(" ");
    expect(text).toContain("REPRODUCIBILITY RECORD");
    expect(text).toContain("the record's own limit");
    for (const l of EXPLORER_LIMITS) expect(text).toContain(l.limit);
  });

  it("a make-to-order product's stock cells say so in words", () => {
    const sheet = aoa(build("selected"), "products");
    const o = sheet.find((r) => r[0] === "P_O")!;
    expect(o[2]).toBe("make-to-order");
    expect(o[3]).toBe(NOT_STOCKED);
    expect(sheet.find((r) => r[0] === "P_S")![3]).toBeCloseTo(products.find((p) => p.id === "P_S")!.avgFgOnHand!, 6);
  });

  it("a material's weekly sheet carries its derived use beside the engine's measures", () => {
    const head = aoa(build("selected"), "M M1")[0];
    expect(head).toEqual(expect.arrayContaining(["week", "on_hand", "in_transit", "orders", USE_MEASURE]));
  });

  it("the long sheet has one row per item × measure × week in scope", () => {
    const expected = (rs: ItemSeriesRow[]) =>
      rs.reduce((s, r) => s + itemMeasures(r, use).reduce((a, [, v]) => a + v.length, 0), 0);
    const all = aoa(build("all"), "weekly");
    expect(all.length - 1).toBe(expected(rows));
    expect(all[0]).toEqual(["week", "kind", "item", "measure", "value"]);
    const sel = aoa(build("selected"), "weekly");
    const picked = rows.filter((r) => (r.kind === "material" && r.item_id === "M1") || (r.kind === "product" && r.item_id === "P_O"));
    expect(sel.length - 1).toBe(expected(picked));
  });

  it("sheet names obey Excel's rules and stay unique after truncation", () => {
    const long = "x".repeat(40);
    const names = uniqueSheetNames([`M ${long}`, `M ${long}`, "a/b:c*d?[e]\\f"]);
    for (const n of names) {
      expect(n.length).toBeLessThanOrEqual(31);
      expect(n).not.toMatch(/[[\]:*?/\\]/);
    }
    expect(new Set(names.map((n) => n.toLowerCase())).size).toBe(names.length);
  });

  it("names the file by project, run and date", () => {
    expect(inventoryFileName("Acme Bikes / EU", "0123456789abcdef", new Date("2026-10-20T12:00:00Z")))
      .toBe("inventory-Acme-Bikes-EU-run-01234567-2026-10-20.xlsx");
  });

  it("round-trips through a real .xlsx write", () => {
    const wb = build("all");
    const back = XLSX.read(XLSX.write(wb, { type: "array", bookType: "xlsx" }), { type: "array" });
    expect(back.SheetNames).toEqual(wb.SheetNames);
  });
});
