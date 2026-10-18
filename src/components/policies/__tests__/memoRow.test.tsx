import { describe, expect, it } from "vitest";
import { renderToStaticMarkup } from "react-dom/server";
import { createElement } from "react";
import { MemoRow } from "../memoRow";
import { rowPropsEqual, type MemoRowProps } from "../rowMemo";

const props = (over: Partial<MemoRowProps> = {}): MemoRowProps => ({
  render: () => null,
  env: {},
  own: [1, "a"],
  ...over,
});

describe("rowPropsEqual", () => {
  it("ignores the render closure, which is new every render", () => {
    const env = {};
    expect(rowPropsEqual(props({ env, render: () => "a" }), props({ env, render: () => "b" }))).toBe(true);
  });

  it("repaints when the env token moves", () => {
    expect(rowPropsEqual(props({ env: {} }), props({ env: {} }))).toBe(false);
  });

  it("repaints when any own input moves, and only then", () => {
    const env = {};
    const row = { key: "r" };
    expect(rowPropsEqual(props({ env, own: [row, 1] }), props({ env, own: [row, 1] }))).toBe(true);
    expect(rowPropsEqual(props({ env, own: [row, 1] }), props({ env, own: [row, 2] }))).toBe(false);
    expect(rowPropsEqual(props({ env, own: [row, 1] }), props({ env, own: [{ key: "r" }, 1] }))).toBe(false);
    expect(rowPropsEqual(props({ env, own: [row] }), props({ env, own: [row, 1] }))).toBe(false);
  });

  it("treats NaN as unchanged, as Object.is does", () => {
    const env = {};
    expect(rowPropsEqual(props({ env, own: [NaN] }), props({ env, own: [NaN] }))).toBe(true);
  });
});

describe("MemoRow", () => {
  it("renders what its render function returns", () => {
    const html = renderToStaticMarkup(
      createElement("table", null, createElement("tbody", null,
        createElement(MemoRow, { env: {}, own: [], render: () => createElement("tr", null, createElement("td", null, "cell")) }))),
    );
    expect(html).toContain("<td>cell</td>");
  });
});
