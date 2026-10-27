/**
 * §4 D313 follow-up — the Product-level metrics tables show 10 rows by default and
 * offer 10 / 20 / 50 / All, for materials and suppliers alike.
 */
import { describe, expect, it } from "vitest";
import { renderToStaticMarkup } from "react-dom/server";
import { createElement } from "react";
import { NetworkMetricsTable, PAGE_SIZES } from "../NetworkMetricsTable";

const rows = (n: number, prefix: string) =>
  Array.from({ length: n }, (_, i) => ({
    id: `${prefix}${i}`, uid: `${prefix}${i}`, name: `${prefix}${i}`, flow: 100 - i,
    degree_centrality: 0.1, weighted_degree_centrality: 0.1, eigenvector_centrality: 0.1,
    betweenness_centrality: (100 - i) / 1000, closeness_centrality: 0.4, prominence: 0.2,
    connection_count: 3, metrics_source: "store" as const, hash_is_current: true,
  }));

const bodyRows = (html: string) => (html.match(/<tbody[\s\S]*<\/tbody>/)?.[0].match(/<tr/g) ?? []).length;

describe("NetworkMetricsTable — rows per page", () => {
  it("shows 10 of many by default, and says which 10", () => {
    const html = renderToStaticMarkup(createElement(NetworkMetricsTable, { metrics: rows(367, "M") }));
    expect(bodyRows(html)).toBe(10);
    expect(html).toContain("10 of 367 purchased materials, highest betweenness centrality first.");
  });

  it("offers 10, 20, 50 and All", () => {
    expect([...PAGE_SIZES]).toEqual(["10", "20", "50", "all"]);
    const html = renderToStaticMarkup(createElement(NetworkMetricsTable, { metrics: rows(65, "S"), echelon: "supplier" }));
    for (const label of [">10<", ">20<", ">50<", ">All (65)<"]) expect(html).toContain(label);
    expect(html).toContain("Nexus Suppliers");
    expect(html).toContain("Supplier Name");
  });

  it("offers no selector when every row already fits", () => {
    const html = renderToStaticMarkup(createElement(NetworkMetricsTable, { metrics: rows(7, "S"), echelon: "supplier" }));
    expect(bodyRows(html)).toBe(7);
    expect(html).not.toContain("All (7)");
  });
});
