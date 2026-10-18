import { useCallback, useRef } from "react";

/**
 * A callback with a stable identity that always runs the LATEST closure.
 *
 * The grid's rows are memoized (`MemoRow`), so the closure a row's event handlers
 * were created in can be several renders old. A handler that reads state at call
 * time (`onCellChange` reads every row's draft to keep one primary per group;
 * `resetRow` reads the saved overrides) must therefore not be captured from
 * that render: it goes through this, so a memoized row calls the current one.
 */
export function useLatestCallback<A extends unknown[], R>(fn: (...args: A) => R): (...args: A) => R {
  const ref = useRef(fn);
  ref.current = fn;
  return useCallback((...args: A) => ref.current(...args), []);
}

export interface MemoRowProps {
  /** The grid's own `renderRow` closure — a new function every render, and
   *  deliberately NOT compared. */
  render: () => React.ReactNode;
  /** Identity token for everything the grid's rows read in common. */
  env: unknown;
  /** This row's own inputs, compared one by one with `Object.is`. */
  own: readonly unknown[];
}

/** Two renders of a row are the same when the env token and every own input are. */
export function rowPropsEqual(a: MemoRowProps, b: MemoRowProps): boolean {
  return a.env === b.env && a.own.length === b.own.length && a.own.every((v, i) => Object.is(v, b.own[i]));
}
