/** Compact presentation of known gate messages; unfamiliar messages stay intact.
 * Counts come from the message, since the gate caps its affected-id sample. */
export function findingSummary(message: string): string {
  const unset = message.match(/^(.+) is unset for (\d+) row\(s\) — the engine will apply its neutral default \((.+?)\)\. /);
  if (unset) {
    const [, field, count, value] = unset;
    return `${field} · ${count} ${count === "1" ? "row" : "rows"} missing. Using default (${value}).`;
  }
  const derived = message.match(/^(.+) is derived for (\d+) row\(s\) via /);
  if (derived) {
    const [, field, count] = derived;
    return `${field} · Derived from project data for ${count} ${count === "1" ? "row" : "rows"}.`;
  }
  const missing = message.match(/^(.+) is missing for (\d+) row\(s\) \(required by /);
  if (missing) {
    const [, field, count] = missing;
    return `${field} · Missing in ${count} ${count === "1" ? "row" : "rows"}.${message.includes(" Fallback: ") ? " Fallback applies; see details." : ""}`;
  }
  return message;
}
