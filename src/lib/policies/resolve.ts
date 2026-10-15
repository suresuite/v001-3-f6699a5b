import type { PolicyBundle, PolicyFamily } from "./schemas";

/** Shallow merge — sufficient for our flat policy shapes, except `ratios` map. */
export function mergePatch<T extends Record<string, unknown>>(base: T, patch: Partial<T>): T {
  if (!patch || typeof patch !== "object") return base;
  const out: Record<string, unknown> = { ...base };
  for (const [k, v] of Object.entries(patch)) {
    if (v === undefined) continue;
    if (k === "ratios" && v && typeof v === "object") {
      out[k] = { ...(base as Record<string, unknown>)[k] as object, ...(v as object) };
    } else {
      out[k] = v;
    }
  }
  return out as T;
}

export interface OverrideRow {
  scope: "node" | "edge";
  target_key: string;
  family: PolicyFamily;
  patch: Record<string, unknown>;
}

/**
 * The overrides that target ONE key, in list order — from an index built once
 * per override LIST.
 *
 * Every cell of the grid asks "what is saved for this row?", and answering it
 * with `overrides.some/filter(o => o.target_key === key)` made one render
 * O(cells × overrides). The index is keyed on the array's identity, so a save
 * (which replaces the list) rebuilds it, and guarded by length, so a list grown
 * in place does too. Within a key the order is the list's own, which is the
 * order `effectivePolicy` merges patches in.
 */
interface TargetIndex {
  len: number;
  byKey: Map<string, OverrideRow[]>;
}
const TARGET_INDEX = new WeakMap<readonly OverrideRow[], TargetIndex>();
const NO_OVERRIDES: readonly OverrideRow[] = [];

export function overridesForTarget(
  overrides: readonly OverrideRow[],
  targetKey: string,
): readonly OverrideRow[] {
  let idx = TARGET_INDEX.get(overrides);
  if (!idx || idx.len !== overrides.length) {
    const byKey = new Map<string, OverrideRow[]>();
    for (const o of overrides) {
      const bucket = byKey.get(o.target_key);
      if (bucket) bucket.push(o);
      else byKey.set(o.target_key, [o]);
    }
    idx = { len: overrides.length, byKey };
    TARGET_INDEX.set(overrides, idx);
  }
  return idx.byKey.get(targetKey) ?? NO_OVERRIDES;
}

/**
 * Return the effective policy for a given node or edge by merging the project
 * default with all overrides that target it.
 */
export function effectivePolicy(
  defaults: PolicyBundle,
  overrides: OverrideRow[],
  scope: "node" | "edge",
  targetKey: string,
): PolicyBundle {
  const out: PolicyBundle = { ...defaults };
  for (const o of overridesForTarget(overrides, targetKey)) {
    if (o.scope !== scope) continue;
    (out as unknown as Record<string, unknown>)[o.family] = mergePatch(
      (defaults as unknown as Record<string, unknown>)[o.family] as Record<string, unknown>,
      o.patch as Record<string, unknown>,
    );
  }
  return out;
}

/** Field-level diff for the "deviates from default" badge. */
export function diffFields(
  base: Record<string, unknown>,
  patch: Record<string, unknown>,
): string[] {
  if (!patch || typeof patch !== "object") return [];
  const changed: string[] = [];
  for (const [k, v] of Object.entries(patch)) {
    if (v === undefined) continue;
    if (JSON.stringify(base?.[k]) !== JSON.stringify(v)) changed.push(k);
  }
  return changed;
}
