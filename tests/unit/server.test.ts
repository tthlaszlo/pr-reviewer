// @vitest-environment node
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { beforeEach, afterEach, describe, expect, it, vi } from 'vitest';
import { buildApp } from '../../server/app';
import { readConfig, readPort } from '../../server/config';
import { decrypt, encrypt } from '../../server/crypto';
import { GitHub, GitHubError } from '../../server/github';
import type { StoredSession, Store } from '../../server/store';

const key = 'ab'.repeat(32);
const config = readConfig({
  APP_URL: 'http://localhost:3000',
  GITHUB_CLIENT_ID: 'id',
  GITHUB_CLIENT_SECRET: 'secret',
  TOKEN_ENCRYPTION_KEY: key,
});
class MemoryStore implements Store {
  states = new Set<string>();
  sessions = new Map<string, StoredSession>();
  async ready() {}
  async close() {}
  async saveState(value: string) {
    this.states.add(value);
  }
  async consumeState(value: string) {
    return this.states.delete(value);
  }
  async saveSession(id: string, value: StoredSession) {
    this.sessions.set(id, value);
  }
  async getSession(id: string) {
    return this.sessions.get(id) ?? null;
  }
  async deleteSession(id: string) {
    this.sessions.delete(id);
  }
}

describe('HTTP application and authentication', () => {
  let root: string;
  let app: Awaited<ReturnType<typeof buildApp>>;
  let store: MemoryStore;
  let github: GitHub;
  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), 'ai-buddy-'));
    await writeFile(join(root, 'index.html'), '<h1>AI Buddy</h1>');
    store = new MemoryStore();
    github = new GitHub();
    app = await buildApp({ clientRoot: root, config, store, github });
  });
  afterEach(async () => {
    await app.close();
    await rm(root, { recursive: true });
    vi.restoreAllMocks();
  });
  it('serves both subpage URLs directly', async () => {
    for (const path of [
      '/pull-requests/review-requests',
      '/pull-requests/mine',
    ]) {
      const result = await app.inject(path);
      expect(result.statusCode).toBe(200);
      expect(result.body).toBe('<h1>AI Buddy</h1>');
    }
  });
  it('scopes authored PR requests to the authenticated user', async () => {
    expect((await app.inject('/api/my-pulls')).statusCode).toBe(401);
    await store.saveSession('valid', {
      login: 'lacko',
      encryptedToken: encrypt('token', key),
    });
    vi.spyOn(github, 'inbox').mockResolvedValue({
      pulls: [],
      warnings: [],
      syncedAt: '2026-11-11T10:00:00Z',
    });
    const result = await app.inject({
      url: '/api/my-pulls',
      cookies: { session: 'valid' },
    });
    expect(result.statusCode).toBe(200);
    expect(github.inbox).toHaveBeenCalledWith('token', 'lacko', 'authored');
    expect(result.headers['cache-control']).toBe('no-store');
  });
  it('checks database readiness and serves the frontend with security headers', async () => {
    expect((await app.inject('/healthz')).json()).toEqual({ status: 'ok' });
    vi.spyOn(store, 'ready').mockRejectedValue(new Error('secret error'));
    expect((await app.inject('/healthz')).statusCode).toBe(503);
    const response = await app.inject('/');
    expect(response.statusCode).toBe(200);
    expect(response.body).toBe('<h1>AI Buddy</h1>');
    expect(response.headers['content-security-policy']).toContain(
      "frame-ancestors 'none'",
    );
    expect(response.headers['x-content-type-options']).toBe('nosniff');
  });
  it.each(['/api/missing', '/missing.js'])(
    'returns 404 for %s',
    async (path) => {
      expect((await app.inject(path)).statusCode).toBe(404);
    },
  );
  it('returns an anonymous session and rejects inbox access', async () => {
    const result = await app.inject('/api/session');
    expect(result.json()).toEqual({
      configured: true,
      user: null,
      installUrl: null,
    });
    expect(result.headers['cache-control']).toBe('no-store');
    expect((await app.inject('/api/inbox')).statusCode).toBe(401);
  });
  it('authenticates through single-use state, encrypts tokens and rotates sessions', async () => {
    await store.saveSession('previous', {
      login: 'old',
      encryptedToken: 'old',
    });
    const start = await app.inject('/auth/github');
    const location = new URL(start.headers.location!);
    expect(location.origin).toBe('https://github.com');
    const state = location.searchParams.get('state')!;
    expect(start.cookies[0]).toMatchObject({
      name: 'oauth_state',
      httpOnly: true,
      sameSite: 'Lax',
    });
    vi.spyOn(github, 'exchange').mockResolvedValue({
      accessToken: 'private-token',
      ttl: 3600,
    });
    vi.spyOn(github, 'user').mockResolvedValue({ login: 'lacko' });
    const response = await app.inject({
      url: `/auth/github/callback?code=code&state=${state}`,
      cookies: { oauth_state: state, session: 'previous' },
    });
    expect(response.headers.location).toBe('/');
    const id = response.cookies.find((c) => c.name === 'session')!.value;
    expect(await store.getSession('previous')).toBeNull();
    const saved = await store.getSession(id);
    expect(saved!.encryptedToken).not.toContain('private-token');
    expect(decrypt(saved!.encryptedToken, key)).toBe('private-token');
    expect(
      (
        await app.inject({ url: '/api/session', cookies: { session: id } })
      ).json().user,
    ).toEqual({ login: 'lacko' });
    expect(
      (
        await app.inject({
          url: `/auth/github/callback?code=code&state=${state}`,
          cookies: { oauth_state: state },
        })
      ).headers.location,
    ).toBe('/?auth=failed');
  });
  it.each(['', '?error=access_denied', '?code=x', '?code=x&state=wrong'])(
    'rejects invalid callbacks %s',
    async (query) => {
      expect(
        (await app.inject(`/auth/github/callback${query}`)).headers.location,
      ).toBe('/?auth=failed');
    },
  );
  it('handles failed token exchange without leaking details', async () => {
    await store.saveState('valid');
    vi.spyOn(github, 'exchange').mockRejectedValue(new Error('secret token'));
    const response = await app.inject({
      url: '/auth/github/callback?code=x&state=valid',
      cookies: { oauth_state: 'valid' },
    });
    expect(response.headers.location).toBe('/?auth=failed');
    expect(response.body).not.toContain('secret');
  });
  it('returns inbox data only for the authenticated user', async () => {
    await store.saveSession('valid', {
      login: 'lacko',
      encryptedToken: encrypt('token', key),
    });
    const data = { pulls: [], warnings: [], syncedAt: '2026-11-11T10:00:00Z' };
    vi.spyOn(github, 'inbox').mockResolvedValue(data);
    expect(
      (
        await app.inject({ url: '/api/inbox', cookies: { session: 'valid' } })
      ).json(),
    ).toEqual(data);
    expect(github.inbox).toHaveBeenCalledWith('token', 'lacko', 'reviews');
  });
  it.each([
    ['github_unauthorized', 401],
    ['rate_limited', 429],
    ['github_permissions', 403],
    ['github_unavailable', 502],
  ] as const)('maps %s errors', async (code, status) => {
    await store.saveSession('valid', {
      login: 'lacko',
      encryptedToken: encrypt('token', key),
    });
    vi.spyOn(github, 'inbox').mockRejectedValue(new GitHubError(status, code));
    const response = await app.inject({
      url: '/api/inbox',
      cookies: { session: 'valid' },
    });
    expect(response.statusCode).toBe(status);
    expect(response.json()).toEqual({ error: code });
    if (status === 401) expect(await store.getSession('valid')).toBeNull();
  });
  it('hides internal failures', async () => {
    vi.spyOn(store, 'getSession').mockRejectedValue(
      new Error('database secret'),
    );
    const response = await app.inject({
      url: '/api/session',
      cookies: { session: 'valid' },
    });
    expect(response.statusCode).toBe(503);
    expect(response.json()).toEqual({ error: 'service_unavailable' });
  });
  it('protects logout from cross-site requests and invalidates the session', async () => {
    await store.saveSession('valid', {
      login: 'lacko',
      encryptedToken: 'token',
    });
    expect(
      (
        await app.inject({
          method: 'POST',
          url: '/api/logout',
          headers: { origin: 'https://evil.example' },
          cookies: { session: 'valid' },
        })
      ).statusCode,
    ).toBe(403);
    const response = await app.inject({
      method: 'POST',
      url: '/api/logout',
      headers: { origin: config.appUrl },
      cookies: { session: 'valid' },
    });
    expect(response.json()).toEqual({ ok: true });
    expect(await store.getSession('valid')).toBeNull();
    expect(
      (
        await app.inject({
          method: 'POST',
          url: '/api/logout',
          headers: { origin: config.appUrl },
        })
      ).statusCode,
    ).toBe(200);
  });
  it('allows a workspace without configured GitHub credentials', async () => {
    await app.close();
    app = await buildApp({ clientRoot: root, store, config: readConfig({}) });
    expect((await app.inject('/auth/github')).statusCode).toBe(503);
    expect((await app.inject('/api/session')).json().configured).toBe(false);
  });
  it('sets Secure cookies on HTTPS deployments', async () => {
    await app.close();
    app = await buildApp({
      clientRoot: root,
      store,
      config: { ...config, secure: true, appUrl: 'https://review.example' },
    });
    expect((await app.inject('/auth/github')).cookies[0].secure).toBe(true);
  });
});

describe('configuration and cryptography', () => {
  it('uses defaults and accepts deployment values', () => {
    expect(readPort(undefined)).toBe(3001);
    expect(readConfig({}).configured).toBe(false);
    expect(
      readConfig({
        APP_URL: 'https://example.com',
        GITHUB_INSTALL_URL:
          'https://github.com/apps/reviewer/installations/new',
      }).installUrl,
    ).toContain('reviewer');
  });
  it.each(['1', '8080', '65535'])('accepts port %s', (port) => {
    expect(readPort(port)).toBe(Number(port));
  });
  it.each(['', 'abc', '3.5', '-1', '0', '65536', '8080oops', ' 3000'])(
    'rejects port %s',
    (port) => {
      expect(() => readPort(port)).toThrow();
    },
  );
  it.each([
    { NODE_ENV: 'production', APP_URL: 'http://example.com' },
    { APP_URL: 'ftp://example.com' },
    { APP_URL: 'https://example.com/path' },
    { APP_URL: 'https://user:password@example.com' },
    { APP_URL: 'https://example.com?test=1' },
    { APP_URL: 'https://example.com#x' },
    { GITHUB_CLIENT_ID: 'x' },
    { GITHUB_CLIENT_SECRET: 'x' },
    {
      GITHUB_CLIENT_ID: 'x',
      GITHUB_CLIENT_SECRET: 'y',
      TOKEN_ENCRYPTION_KEY: 'bad',
    },
    { GITHUB_INSTALL_URL: 'https://evil.example/apps/test/installations/new' },
  ])('rejects invalid configuration %j', (env) => {
    expect(() => readConfig(env)).toThrow();
  });
  it('encrypts with randomized authenticated encryption', () => {
    const a = encrypt('private-token', key),
      b = encrypt('private-token', key);
    expect(a).not.toBe(b);
    expect(decrypt(a, key)).toBe('private-token');
    expect(() => decrypt(a, 'cd'.repeat(32))).toThrow();
    expect(() => decrypt(a.slice(0, -5) + 'AAAA', key)).toThrow();
  });
});
