// Profiles are display caches. Only this credential is attached to requests.
interface BrowserSession { access_token: string; expires_at: number; sub: string }
let session: BrowserSession | null = null;
try {
  session = JSON.parse(sessionStorage.getItem('browser_session') ?? 'null');
} catch { session = null; }

export function currentMintedToken(): string | null {
  if (!session || typeof session.expires_at !== 'number' || !Number.isFinite(session.expires_at) || session.expires_at <= Date.now() / 1000) return null;
  return typeof session.access_token === 'string' ? session.access_token : null;
}
export function currentSessionSubject(): string | null {
  return currentMintedToken() ? session?.sub ?? null : null;
}
export function setBrowserSession(value: BrowserSession | null): void {
  session = value;
  try {
    if (value) sessionStorage.setItem('browser_session', JSON.stringify(value));
    else sessionStorage.removeItem('browser_session');
  } catch { /* In-memory sessions still work when site storage is blocked. */ }
}
export function clearMintedToken(): void { setBrowserSession(null); }
