/**
 * §4 D197 — the project's default MTS / MTO is read ONE way: the way the grid
 * reads it (`list_projects`), which is the column the worker reads. The browser
 * run and the simulation-input export both go through this reader, and neither
 * is handed the policy's `fulfillment_strategy` string any more.
 */
import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { readProjectFulfillmentModel } from "../projectFulfillmentModel";

const table = (data: unknown, error: unknown = null) => ({
  select: () => ({ eq: () => ({ maybeSingle: async () => ({ data, error }) }) }),
});

describe("readProjectFulfillmentModel", () => {
  it("reads through list_projects when a user is known — what the grid shows", async () => {
    const sb = {
      rpc: async () => ({
        data: [
          { id: "other", supply_chain_model: "Make-To-Order" },
          { id: "p1", supply_chain_model: "Make-To-Stock" },
        ],
        error: null,
      }),
      from: () => table(null), // a direct select that returns NO ROW (approved_users auth)
    };
    expect(await readProjectFulfillmentModel(sb, "p1", { id: "u", email: "e@x" })).toBe("Make-To-Stock");
  });

  it("falls back to the table when no user is known", async () => {
    const sb = { rpc: async () => ({ data: [], error: null }), from: () => table({ supply_chain_model: "Make-To-Order" }) };
    expect(await readProjectFulfillmentModel(sb, "p1", null)).toBe("Make-To-Order");
  });

  it("falls back to the table when the project is not in the user's list", async () => {
    const sb = {
      rpc: async () => ({ data: [{ id: "zzz", supply_chain_model: "Make-To-Stock" }], error: null }),
      from: () => table({ supply_chain_model: "Make-To-Order" }),
    };
    expect(await readProjectFulfillmentModel(sb, "p1", { id: "u", email: null })).toBe("Make-To-Order");
  });

  it("unset or unreadable is null — the worker's own 'not set'", async () => {
    expect(await readProjectFulfillmentModel({ rpc: async () => ({ data: null, error: { message: "x" } }), from: () => table(null, { message: "x" }) }, "p1", { id: "u" })).toBeNull();
    expect(await readProjectFulfillmentModel({ rpc: async () => ({ data: [{ id: "p1", supply_chain_model: "  " }], error: null }), from: () => table(null) }, "p1", { id: "u" })).toBeNull();
    expect(await readProjectFulfillmentModel({ rpc: async () => { throw new Error("offline"); }, from: () => table(null) }, "p1", { id: "u" })).toBeNull();
    expect(await readProjectFulfillmentModel({ rpc: async () => ({ data: [], error: null }), from: () => table(null) }, null, { id: "u" })).toBeNull();
  });
});

describe("the two client paths use the reader, not the policy string", () => {
  const read = (p: string) => readFileSync(new URL(`../../../${p}`, import.meta.url), "utf8");

  it("the browser run takes the project's model, not fulfillment_strategy", () => {
    const src = read("components/policies/RunValidateStage.tsx");
    expect(src).toContain("readProjectFulfillmentModel(");
    expect(src).not.toMatch(/projectModel:\s*fulfillmentStrategy/);
  });

  it("the simulation-input export reads the column through the same reader", () => {
    const src = read("lib/policies/engineInputExport.ts");
    expect(src).toContain("readProjectFulfillmentModel(");
    expect(src).not.toMatch(/from\("projects"\)\.select\("supply_chain_model"\)/);
  });
});
