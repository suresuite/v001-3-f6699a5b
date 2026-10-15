import { memo } from "react";
import { rowPropsEqual, type MemoRowProps } from "./rowMemo";

/**
 * One memoized data row. A row repaints only when `env` or `own` changed, which
 * is what makes an edit to one cell repaint one row instead of all of them.
 *
 * THE RISK IS A MISSING INPUT: a value `renderRow` reads that is in neither list
 * leaves a row showing yesterday's cell. `stagePolicyTableRowMemo.test.ts`
 * resolves every binding `renderRow` reaches and fails on one that is in neither.
 */
export const MemoRow = memo(function MemoRow({ render }: MemoRowProps) {
  return <>{render()}</>;
}, rowPropsEqual);
