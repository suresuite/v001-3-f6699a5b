/**
 * THE GATE ON ROW MEMOIZATION.
 *
 * `StagePolicyTable` repaints a data row only when `rowEnv` (what every row
 * reads) or the row's `own` list moved. A value `renderRow` reads that is in
 * neither would leave a row showing a stale cell, and nothing at runtime would
 * say so. So this resolves — with the type checker, through every closure
 * `renderRow` calls — each binding of the component that `renderRow` reaches,
 * and fails on one that is not accounted for.
 *
 * Event-time handlers are the boundary: a binding made with `useLatestCallback`
 * runs the latest closure when called, so what it reads is not a render input.
 */
import { describe, expect, it } from "vitest";
import ts from "typescript";
import path from "node:path";

const FILE = path.resolve(__dirname, "../StagePolicyTable.tsx");

interface Analysis {
  /** Non-function bindings of the component that `renderRow` reads, directly or
   *  through the closures it calls. */
  reached: Set<string>;
  env: Set<string>;
  own: Set<string>;
}

function analyse(): Analysis {
  const program = ts.createProgram([FILE], {
    jsx: ts.JsxEmit.Preserve,
    noEmit: true,
    target: ts.ScriptTarget.ES2022,
    module: ts.ModuleKind.ESNext,
    moduleResolution: ts.ModuleResolutionKind.Bundler,
    skipLibCheck: true,
    baseUrl: path.resolve(__dirname, "../../../.."),
    paths: { "@/*": ["src/*"] },
  });
  const sf = program.getSourceFile(FILE)!;
  const checker = program.getTypeChecker();

  let comp!: ts.FunctionDeclaration;
  const find = (n: ts.Node) => {
    if (ts.isFunctionDeclaration(n) && n.name?.text === "StagePolicyTable") comp = n;
    ts.forEachChild(n, find);
  };
  find(sf);

  const inside = (d: ts.Node, node: ts.Node) => d.pos >= node.pos && d.end <= node.end;
  const fnVars = new Map<string, ts.VariableDeclaration>();
  const decls = new Map<string, ts.VariableDeclaration>();
  const collect = (n: ts.Node) => {
    if (ts.isVariableDeclaration(n) && ts.isIdentifier(n.name) && inside(n, comp)) {
      decls.set(n.name.text, n);
      const init = n.initializer;
      if (init && (ts.isArrowFunction(init) || ts.isFunctionExpression(init))) fnVars.set(n.name.text, n);
    }
    ts.forEachChild(n, collect);
  };
  collect(comp);

  const renderRow = fnVars.get("renderRow")!.initializer!;

  // Names inside a `useLatestCallback(...)` initializer are an event-time boundary.
  const isLatest = (d: ts.VariableDeclaration) =>
    !!d.initializer &&
    ts.isCallExpression(d.initializer) &&
    ts.isIdentifier(d.initializer.expression) &&
    d.initializer.expression.text === "useLatestCallback";

  const reached = new Set<string>();
  const visited = new Set<string>();
  const scan = (node: ts.Node) => {
    const walk = (n: ts.Node) => {
      if (ts.isIdentifier(n)) {
        const sym =
          n.parent && ts.isShorthandPropertyAssignment(n.parent) && n.parent.name === n
            ? checker.getShorthandAssignmentValueSymbol(n.parent)
            : checker.getSymbolAtLocation(n);
        const d = sym?.declarations?.[0];
        if (
          d && inside(d, comp) && !inside(d, node) && d.getSourceFile() === sf &&
          (ts.isBindingElement(d) || ts.isVariableDeclaration(d) || ts.isParameter(d))
        ) {
          const name = n.text;
          if (ts.isVariableDeclaration(d) && isLatest(d)) {
            // event-time boundary
          } else if (ts.isVariableDeclaration(d) && fnVars.get(name) === d) {
            if (!visited.has(name)) {
              visited.add(name);
              scan(d.initializer!);
            }
          } else {
            reached.add(name);
          }
        }
      }
      ts.forEachChild(n, walk);
    };
    walk(node);
  };
  scan(renderRow);

  const arrayNames = (arr: ts.Node): Set<string> => {
    const out = new Set<string>();
    const w = (n: ts.Node) => {
      if (ts.isIdentifier(n)) out.add(n.text);
      ts.forEachChild(n, w);
    };
    w(arr);
    return out;
  };

  // rowEnv = useMemo(() => ({}), [ ...deps ])
  const envDecl = decls.get("rowEnv")!;
  const envCall = envDecl.initializer as ts.CallExpression;
  const env = arrayNames(envCall.arguments[1]);

  // renderRowMemo's `own={[ ... ]}`
  const memoDecl = fnVars.get("renderRowMemo")!;
  let own = new Set<string>();
  const findOwn = (n: ts.Node) => {
    if (ts.isJsxAttribute(n) && n.name.getText() === "own" && n.initializer) own = arrayNames(n.initializer);
    ts.forEachChild(n, findOwn);
  };
  findOwn(memoDecl.initializer!);

  return { reached, env, own };
}

/** Bindings `renderRow` may reach that are NOT inputs, each with the reason. */
const NOT_AN_INPUT: Record<string, string> = {
  keyWidths: "derived from keyDefs in the same render (`keyDefs.map(d => d.w)`); keyDefs is in rowEnv",
  isDayField: "a pure regex over a field name, re-created each render; it reads no state",
  deleteOverride: "called only inside resetRow (a latest-callback); its truthiness is `hasDeleteOverride`, in rowEnv",
  reloadRows: "called only inside assignSupplier (a latest-callback)",
};

/** Reached through a flag that IS in `own`, because the flag is the answer. */
const VIA_OWN_FLAG: Record<string, string> = {
  newSupplierFor: "compared as `editingNewSupplier` (is THIS row the one being typed into), in `own`",
  dataRows: "only through rowNeedsAttention / groupHasPrimary, whose results are in `own`",
  primaryGroups: "only through groupHasPrimary / rowNeedsAttention, whose results are in `own`",
};

describe("StagePolicyTable row memoization", () => {
  const a = analyse();

  it("finds renderRow's inputs (guards the analysis itself)", () => {
    expect(a.reached.size).toBeGreaterThan(25);
    expect(a.reached.has("overrides")).toBe(true);
    expect(a.reached.has("drafts")).toBe(true);
    expect(a.env.has("overrides")).toBe(true);
    expect(a.own.has("rowNeedsAttention")).toBe(true);
  });

  it("accounts for every binding renderRow reads", () => {
    const setter = /^set[A-Z]/;
    const unaccounted = [...a.reached].filter(
      (n) => !a.env.has(n) && !a.own.has(n) && !setter.test(n) && !(n in NOT_AN_INPUT) && !(n in VIA_OWN_FLAG),
    );
    expect(
      unaccounted,
      `renderRow reads ${unaccounted.join(", ")}, which is in neither rowEnv nor a row's own list: ` +
        "a memoized row would show a stale cell. Add it to the rowEnv deps (or to renderRowMemo's `own`).",
    ).toEqual([]);
  });

  it("the row-state flags are what stands in for the cross-row reads", () => {
    for (const fn of ["rowNeedsAttention", "groupHasPrimary", "hasOverride"]) {
      expect(a.own.has(fn), fn).toBe(true);
    }
  });

  it("would notice an input dropped from the list", () => {
    const withoutOverrides = [...a.reached].filter(
      (n) => !new Set([...a.env].filter((x) => x !== "overrides")).has(n) && !a.own.has(n) &&
        !/^set[A-Z]/.test(n) && !(n in NOT_AN_INPUT) && !(n in VIA_OWN_FLAG),
    );
    expect(withoutOverrides).toContain("overrides");
  });
});
