/** Atomic, bounded counters. No email addresses or passwords enter Redis. */
export async function allowLogin(
  email: string, ip: string,
  config: { url: string; token: string }, request = fetch,
): Promise<boolean> {
  if (!config.url || !config.token) throw new Error("Login throttle unavailable");
  const hash = async (value: string) => Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value))))
    .map(b => b.toString(16).padStart(2, "0")).join("");
  const script = "local n=redis.call('INCR',KEYS[1]); if n==1 then redis.call('EXPIRE',KEYS[1],ARGV[1]) end; return n";
  const counters = [
    [`login:account:${await hash(email.trim().toLowerCase())}`, 900, 10],
    [`login:ip:${await hash(ip)}`, 60, 30],
    ["login:global", 60, 1000],
  ] as const;
  for (const [key, seconds, limit] of counters) {
    const res = await request(config.url, { method: "POST", headers: { Authorization: `Bearer ${config.token}`, "Content-Type": "application/json" },
      body: JSON.stringify(["EVAL", script, 1, key, seconds]) });
    if (!res.ok) throw new Error("Login throttle unavailable");
    const body = await res.json();
    if (!Number.isInteger(body.result) || body.result < 1 || body.error) throw new Error("Login throttle unavailable");
    if (body.result > limit) return false;
  }
  return true;
}
