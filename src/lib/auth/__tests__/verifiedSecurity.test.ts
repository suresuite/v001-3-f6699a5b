import { authorizeApiProject } from "../../../../supabase/functions/_shared/apiProjectScope";
import { describe, expect, it, vi } from 'vitest';
import { mintSessionToken } from '../../../../supabase/functions/_shared/mintSessionToken';
import { requireBrowser, requireInternal, requireProject, verifyBrowserToken } from '../../../../supabase/functions/_shared/verifiedSession';
import { authorizeCommand } from '../../../../supabase/functions/_shared/authorizeCommand';
import { validAiResolution } from '../../../../supabase/functions/_shared/capabilityResolution';
import { allowLogin } from '../../../../supabase/functions/_shared/loginThrottle';

const id = '11111111-2222-3333-4444-555555555555';
const env = { secret: 'isolated-test-signing-secret-1234567890', url: 'https://example.invalid' };
const mint = (over = {}) => mintSessionToken({ secret: env.secret, supabaseUrl: env.url, userId: id, email: 'user@example.invalid', ...over });
const request = (token: string) => new Request('https://example.invalid', { headers: { Authorization: `Bearer ${token}` } });
const profile = { is_active: true, access_expired: false };
const rights = { visible: true, capabilities: { simulation_lab: true, data_edit_policies: true } };
const resolver = (p: unknown = profile, r: unknown = rights) => ({ rpc: vi.fn(async (name: string) => ({ data: name === 'get_my_profile' ? p : r, error: null })) });

describe('verified browser identity', () => {
  it('accepts a correctly signed approved-user session and verifies its account status', async () => {
    const { access_token } = await mint();
    expect(await requireBrowser(request(access_token), resolver(), env)).toEqual({ id, email: 'user@example.invalid' });
  });
  it.each(['', 'public-anon-key', 'a.b.c'])('refuses anonymous and malformed credentials %s before account reads', async token => {
    const db = resolver();
    await expect(requireBrowser(request(token), db, env)).rejects.toMatchObject({ status: 401 });
    expect(db.rpc).not.toHaveBeenCalled();
  });
  it('rejects modified subjects, wrong signatures, issuer, expiry and future issue time', async () => {
    const good = await mint();
    const [h, p, s] = good.access_token.split('.');
    const payload = JSON.parse(atob(p));
    const forged = `${h}.${btoa(JSON.stringify({ ...payload, sub: 'forged' })).replace(/=/g, '')}.${s}`;
    const tokens = [forged, (await mint({ secret: 'wrong' })).access_token,
      (await mint({ supabaseUrl: 'https://other.invalid' })).access_token,
      (await mint({ now: 1 })).access_token,
      (await mint({ now: Math.floor(Date.now() / 1000) + 1000 })).access_token];
    for (const token of tokens) await expect(verifyBrowserToken(token, env.secret, env.url)).rejects.toMatchObject({ status: 401 });
  });
  it.each([
    { aud: 'other' }, { role: 'anon' }, { app_identity: 'local-profile' },
    { exp: '9999999999' }, { iat: null }, { nbf: Date.now() / 1000 + 600 },
  ])('rejects correctly signed credentials with invalid claims %j', async changed => {
    const { access_token } = await mint();
    const [header, encoded] = access_token.split('.');
    const payload = { ...JSON.parse(atob(encoded)), ...changed };
    const b64 = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes)).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
    const input = `${header}.${b64(new TextEncoder().encode(JSON.stringify(payload)))}`;
    const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(env.secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
    const signature = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(input));
    const db = resolver();
    await expect(requireBrowser(request(`${input}.${b64(new Uint8Array(signature))}`), db, env)).rejects.toMatchObject({ status: 401 });
    expect(db.rpc).not.toHaveBeenCalled();
  });
  it.each([null, {}, { is_active: false, access_expired: false }, { is_active: true, access_expired: true }])('refuses missing, suspended and expired accounts', async p => {
    await expect(requireBrowser(request((await mint()).access_token), resolver(p), env)).rejects.toMatchObject({ status: 403 });
  });
  it('rejects forged actor and email assertions', async () => {
    const req = request((await mint()).access_token);
    for (const asserted of [{ id: 'other' }, { email: 'other@example.invalid' }]) {
      await expect(requireBrowser(req, resolver(), env, asserted)).rejects.toMatchObject({ status: 403 });
    }
  });
  it('fails closed when account or rights resolution fails', async () => {
    const db = { rpc: async () => ({ data: null, error: { message: 'offline' } }) };
    await expect(requireBrowser(request((await mint()).access_token), db, env)).rejects.toMatchObject({ status: 403 });
    await expect(requireProject(db, { id, email: '' }, 'project')).rejects.toMatchObject({ status: 403 });
  });
});

describe('simulation authorization happens before service operations', () => {
  const cmd = (kind: string) => ({ project_id: 'project-a', kind, payload: { run_id: 'run-a' } });
  it.each(['experiment.run', 'experiment.cancel', 'experiment.add_reps', 'run.series_url', 'policy.changed'])('rejects cross-organization %s without resource reads', async kind => {
    const read = vi.fn();
    await expect(authorizeCommand(request((await mint()).access_token), cmd(kind), resolver(profile, { visible: false }), env, read)).rejects.toMatchObject({ status: 403 });
    expect(read).not.toHaveBeenCalled();
  });
  it.each(['experiment.cancel', 'experiment.add_reps', 'run.series_url'])('rejects a mismatched run/project for %s', async kind => {
    await expect(authorizeCommand(request((await mint()).access_token), cmd(kind), resolver(), env, async () => 'project-b')).rejects.toMatchObject({ status: 403 });
  });
  it('refuses viewers but admits authorized editors and admins through the same capability rule', async () => {
    const req = request((await mint()).access_token);
    await expect(authorizeCommand(req, cmd('experiment.run'), resolver(profile, { visible: true, capabilities: {} }), env, vi.fn())).rejects.toMatchObject({ status: 403 });
    expect((await authorizeCommand(req, cmd('experiment.run'), resolver(), env, vi.fn())).id).toBe(id);
  });
  it.each(['experiment.cancel', 'experiment.add_reps', 'run.series_url'])('admits an authorized matching project/run for %s', async kind => {
    const read = vi.fn(async () => 'project-a');
    expect((await authorizeCommand(request((await mint()).access_token), cmd(kind), resolver(), env, read)).id).toBe(id);
    expect(read).toHaveBeenCalledWith('simulation_runs', 'run-a');
  });
  it('rejects foreign scenarios before dispatch', async () => {
    await expect(authorizeCommand(request((await mint()).access_token), { ...cmd('experiment.run'), scenario_id: 'foreign' }, resolver(), env, async () => 'project-b')).rejects.toMatchObject({ status: 403 });
  });
});

describe('internal operations, AI resolution and login throttle', () => {
  it('only accepts the explicit scheduled service credential for internal operations', () => {
    expect(() => requireInternal(request('service-secret'), 'service-secret')).not.toThrow();
    for (const token of ['', 'anon', 'sk_scoped_api_key']) expect(() => requireInternal(request(token), 'service-secret')).toThrow();
    expect(() => requireInternal(request(''), '')).toThrow();
  });
  it('rejects missing and malformed AI capabilities and budgets', () => {
    const caps = { is_super_admin: false, features: { ai_chat: true }, models: { all_allowed: true, allowed_codes: [] }, budgets: { monthly_usd: null, daily_usd: 1, rpd: null, mtd_cost_usd: 0, today_cost_usd: 0, today_requests: 0 } };
    expect(validAiResolution(caps)).toBe(true);
    for (const bad of [null, {}, { ...caps, features: null }, { ...caps, is_super_admin: 'true' }, { ...caps, budgets: {} }, { ...caps, budgets: { ...caps.budgets, daily_usd: 'NaN' } }]) expect(validAiResolution(bad)).toBe(false);
  });
  it('throttles existing and unknown accounts equally, without sending addresses to Redis', async () => {
    const sent: string[] = [];
    const send = vi.fn(async (_url, init) => { sent.push(String(init?.body)); return new Response(JSON.stringify({ result: 11 })); }) as unknown as typeof fetch;
    for (const email of ['known@example.invalid', 'unknown@example.invalid']) expect(await allowLogin(email, 'ip', { url: 'https://redis.invalid', token: 'test' }, send)).toBe(false);
    expect(sent.join('')).not.toContain('@');
  });
  it('admits under-limit attempts and refuses unavailable or malformed throttles', async () => {
    const send = vi.fn(async () => new Response(JSON.stringify({ result: 1 }))) as unknown as typeof fetch;
    expect(await allowLogin('user@example.invalid', 'ip', { url: 'https://redis.invalid', token: 'test' }, send)).toBe(true);
    await expect(allowLogin('u', 'ip', { url: '', token: '' }, send)).rejects.toThrow();
    const broken = vi.fn(async () => new Response('{}')) as unknown as typeof fetch;
    await expect(allowLogin('u', 'ip', { url: 'https://redis.invalid', token: 'test' }, broken)).rejects.toThrow();
  });
});

describe('the separate scoped API-key path', () => {
  const key = { orgId: 'org-a', projectIds: ['project-a'] };
  it('preserves authorized org and scoped key access', async () => {
    const db = { rpc: vi.fn(async () => ({ data: true, error: null })) };
    await expect(authorizeApiProject(db, key, 'project-a')).resolves.toBeUndefined();
    await expect(authorizeApiProject(db, { ...key, projectIds: null }, 'project-a')).resolves.toBeUndefined();
    expect(db.rpc).toHaveBeenCalledWith('api_can_access_project', { p_org_id: 'org-a', p_project_id: 'project-a' });
  });
  it('refuses a same-organization project outside the key scope before service lookup', async () => {
    const db = { rpc: vi.fn() };
    await expect(authorizeApiProject(db, key, 'project-other')).rejects.toMatchObject({ status: 404 });
    expect(db.rpc).not.toHaveBeenCalled();
  });
  it.each([false, null, {}, 'true'])('refuses a foreign or malformed tenant resolution %j', async data => {
    await expect(authorizeApiProject({ rpc: async () => ({ data, error: null }) }, key, 'project-a')).rejects.toMatchObject({ status: 404 });
  });
  it('binds personal-key writes to the verified owner and project capability', async () => {
    const personal = { ...key, actorUserId: id };
    const db = { rpc: vi.fn(async (name: string) => ({ data: name === 'api_can_access_project' ? true : rights, error: null })) };
    await expect(authorizeApiProject(db, personal, 'project-a', 'data_edit_policies')).resolves.toBeUndefined();
    expect(db.rpc).toHaveBeenCalledWith('project_rights_for_user', { p_user_id: id, p_project_id: 'project-a' });
    const viewer = { rpc: async (name: string) => ({ data: name === 'api_can_access_project' ? true : { visible: true, capabilities: {} }, error: null }) };
    await expect(authorizeApiProject(viewer, personal, 'project-a', 'data_edit_policies')).rejects.toMatchObject({ status: 404 });
    await expect(authorizeApiProject(viewer, personal, 'project-a')).resolves.toBeUndefined();
  });
  it.each([null, {}, { visible: 'true' }])('refuses incomplete personal-key rights %j', async rights => {
    const db = { rpc: async (name: string) => ({ data: name === 'api_can_access_project' ? true : rights, error: null }) };
    await expect(authorizeApiProject(db, { ...key, actorUserId: id }, 'project-a')).rejects.toMatchObject({ status: 404 });
  });
  it('fails closed on resolver failures', async () => {
    await expect(authorizeApiProject({ rpc: async () => ({ data: true, error: { message: 'offline' } }) }, key, 'project-a')).rejects.toMatchObject({ status: 503 });
    await expect(authorizeApiProject({ rpc: async () => { throw Error('offline'); } }, key, 'project-a')).rejects.toMatchObject({ status: 503 });
  });
});
