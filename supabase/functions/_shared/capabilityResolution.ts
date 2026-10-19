/** Reject incomplete resolver results instead of turning absent limits into unlimited spend. */
export function validAiResolution(value: unknown): boolean {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const c = value as Record<string, unknown>;
  if (typeof c.is_super_admin !== "boolean" || !c.features || typeof c.features !== "object" || Array.isArray(c.features)) return false;
  if (!Object.values(c.features).every(v => typeof v === "boolean")) return false;
  const models = c.models as Record<string, unknown> | undefined;
  const b = c.budgets as Record<string, unknown> | undefined;
  if (!models || typeof models.all_allowed !== "boolean" || !Array.isArray(models.allowed_codes)
    || !models.allowed_codes.every(v => typeof v === "string") || !b || typeof b !== "object") return false;
  const limits = ["monthly_usd", "daily_usd", "rpd"];
  const usage = ["mtd_cost_usd", "today_cost_usd", "today_requests"];
  return [...limits, ...usage].every(k => k in b &&
    ((limits.includes(k) && b[k] === null) || (typeof b[k] === "number" && Number.isFinite(b[k]) && Number(b[k]) >= 0)));
}
