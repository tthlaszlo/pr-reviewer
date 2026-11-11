// @vitest-environment node
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { beforeEach, afterEach, describe, expect, it, vi } from 'vitest';
import { buildApp } from '../../server/app';
import { readConfig, readPort } from '../../server/config';
import { decrypt, encrypt, hashToken } from '../../server/crypto';
import { GitHub, GitHubError } from '../../server/github';
import { Google } from '../../server/google';
import type {
  StoredSession,
  Store,
  LoginFlow,
  GitHubConnection,
} from '../../server/store';
import type { Provider } from '../../shared/types';
const key = 'ab'.repeat(32);
const config = readConfig({
  APP_URL: 'http://localhost:3000',
  GITHUB_CLIENT_ID: 'id',
  GITHUB_CLIENT_SECRET: 'secret',
  GOOGLE_CLIENT_ID: 'google-id',
  GOOGLE_CLIENT_SECRET: 'google-secret',
  TOKEN_ENCRYPTION_KEY: key,
});
const googleUser = { id: '1', name: 'Lacko', provider: 'google' as const };
const signedIn = (): StoredSession => ({
  user: googleUser,
  github: {
    login: 'lacko',
    encryptedToken: encrypt('token', key),
    expiresAt: Date.now() + 60000,
  },
});
class MemoryStore implements Store {
  states = new Map<string, LoginFlow>();
  sessions = new Map<string, StoredSession>();
  async ready() {}
  async close() {}
  async saveState(state: string, flow: LoginFlow) {
    this.states.set(state, flow);
  }
  async consumeState(state: string) {
    const value = this.states.get(state) ?? null;
    this.states.delete(state);
    return value;
  }
  async identify(provider: Provider, subject: string, name: string) {
    return { id: `${provider}:${subject}`, name, provider };
  }
  async saveSession(id: string, value: StoredSession) {
    this.sessions.set(id, value);
  }
  async getSession(id: string) {
    return this.sessions.get(id) ?? null;
  }
  async setGitHub(id: string, value: GitHubConnection | null) {
    const session = this.sessions.get(id);
    if (session) session.github = value;
  }
  async deleteSession(id: string) {
    this.sessions.delete(id);
  }
}
describe('HTTP authentication boundaries', () => {
  let root: string, store: MemoryStore, github: GitHub, google: Google;
  let app: Awaited<ReturnType<typeof buildApp>>;
  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), 'ai-buddy-'));
    await writeFile(join(root, 'index.html'), '<h1>AI Buddy</h1>');
    store = new MemoryStore();
    github = new GitHub();
    google = new Google();
    app = await buildApp({ clientRoot: root, config, store, github, google });
  });
  afterEach(async () => {
    await app.close();
    await rm(root, { recursive: true });
    vi.restoreAllMocks();
  });
  it('provides health, safe error responses and security headers', async () => {
    expect((await app.inject('/healthz')).json()).toEqual({ status: 'ok' });
    vi.spyOn(store, 'ready').mockRejectedValue(new Error('secret'));
    expect((await app.inject('/healthz')).statusCode).toBe(503);
    const login = await app.inject('/login');
    expect(login.statusCode).toBe(200);
    expect(login.body).toContain('AI Buddy');
    expect(login.headers['cache-control']).toBe('no-store');
    expect(login.headers['content-security-policy']).toContain(
      "frame-ancestors 'none'",
    );
    expect(login.headers['x-content-type-options']).toBe('nosniff');
  });
  it.each(['/', '/pull-requests/review-requests', '/pull-requests/mine'])(
    'guards %s and preserves the allowed destination',
    async (path) => {
      const response = await app.inject(path);
      expect(response.statusCode).toBe(302);
      expect(response.headers.location).toMatch(/^\/login\?returnTo=/);
      await store.saveSession('valid', signedIn());
      expect(
        (await app.inject({ url: path, cookies: { session: 'valid' } }))
          .statusCode,
      ).toBe(200);
    },
  );
  it.each(['/api/inbox', '/api/my-pulls'])(
    'requires a session for %s',
    async (path) => {
      expect((await app.inject(path)).statusCode).toBe(401);
    },
  );
  it.each([
    '/api/missing',
    '/auth/password',
    '/auth/email',
    '/auth/guest',
    '/missing.js',
  ])('does not provide another sign-in method at %s', async (path) => {
    expect((await app.inject(path)).statusCode).toBe(404);
  });
  it('reports exactly Google and GitHub availability without exposing tokens', async () => {
    expect((await app.inject('/api/session')).json()).toEqual({
      providers: { google: true, github: true },
      user: null,
      github: { connected: false, login: null },
      installUrl: null,
    });
    await store.saveSession('valid', signedIn());
    const response = await app.inject({
      url: '/api/session',
      cookies: { session: 'valid' },
    });
    expect(response.json().user).toEqual(googleUser);
    expect(response.body).not.toContain('encryptedToken');
    expect(
      (
        await app.inject({
          url: '/login?returnTo=https://evil.example',
          cookies: { session: 'valid' },
        })
      ).headers.location,
    ).toBe('/pull-requests/review-requests');
    expect(
      (
        await app.inject({
          url: '/login?returnTo=/pull-requests/mine',
          cookies: { session: 'valid' },
        })
      ).headers.location,
    ).toBe('/pull-requests/mine');
  });
  it.each(['google', 'github'] as const)(
    'authenticates %s with PKCE, state, rotation and stable identity',
    async (provider) => {
      await store.saveSession('previous', signedIn());
      const start = await app.inject(
        `/auth/${provider}?returnTo=/pull-requests/mine`,
      );
      const url = new URL(start.headers.location!);
      const state = url.searchParams.get('state')!;
      const flow = store.states.get(state)!;
      expect(url.searchParams.get('code_challenge_method')).toBe('S256');
      expect(url.searchParams.get('code_challenge')).toHaveLength(43);
      expect(start.cookies[0]).toMatchObject({
        name: `oauth_${provider}`,
        httpOnly: true,
        sameSite: 'Lax',
      });
      vi.spyOn(github, 'exchange').mockResolvedValue({
        accessToken: 'private-token',
        ttl: 3600,
      });
      vi.spyOn(github, 'user').mockResolvedValue({
        id: 42,
        login: 'lacko',
        name: 'Lacko',
      });
      vi.spyOn(google, 'login').mockResolvedValue({
        subject: 'google-sub',
        name: 'Lacko',
      });
      const response = await app.inject({
        url: `/auth/${provider}/callback?code=code&state=${state}`,
        cookies: { [`oauth_${provider}`]: state, session: 'previous' },
      });
      expect(response.headers.location).toBe('/pull-requests/mine');
      const id = response.cookies.find((c) => c.name === 'session')!.value;
      expect(id).not.toBe('previous');
      expect(await store.getSession('previous')).toBeNull();
      const value = (await store.getSession(id))!;
      expect(value.user.provider).toBe(provider);
      if (provider === 'google') {
        expect(url.searchParams.get('scope')).toBe('openid profile');
        expect(url.searchParams.get('nonce')).toBe(flow.nonce);
        expect(value.github).toBeNull();
        expect(google.login).toHaveBeenCalledWith(
          'code',
          config.googleClientId,
          config.googleClientSecret,
          `${config.appUrl}/auth/google/callback`,
          flow.verifier,
          flow.nonce,
        );
      } else {
        expect(value.user.id).toBe('github:42');
        expect(decrypt(value.github!.encryptedToken, key)).toBe(
          'private-token',
        );
        expect(github.exchange).toHaveBeenCalledWith(
          'code',
          config.clientId,
          config.clientSecret,
          `${config.appUrl}/auth/github/callback`,
          flow.verifier,
        );
      }
      expect(
        (
          await app.inject({
            url: `/auth/${provider}/callback?code=code&state=${state}`,
            cookies: { [`oauth_${provider}`]: state },
          })
        ).headers.location,
      ).toBe('/login?auth=failed');
    },
  );
  it('connects GitHub to a Google identity without replacing that identity', async () => {
    await store.saveSession('google-session', {
      user: googleUser,
      github: null,
    });
    const start = await app.inject({
      url: '/auth/github?intent=connect',
      cookies: { session: 'google-session' },
    });
    const state = new URL(start.headers.location!).searchParams.get('state')!;
    expect(store.states.get(state)!.sessionHash).toBe(
      hashToken('google-session'),
    );
    vi.spyOn(github, 'exchange').mockResolvedValue({
      accessToken: 'token',
      ttl: 3600,
    });
    vi.spyOn(github, 'user').mockResolvedValue({ id: 42, login: 'lacko' });
    const response = await app.inject({
      url: `/auth/github/callback?state=${state}&code=x`,
      cookies: { session: 'google-session', oauth_github: state },
    });
    const id = response.cookies.find((c) => c.name === 'session')!.value;
    expect((await store.getSession(id))!.user).toEqual(googleUser);
    expect((await store.getSession(id))!.github!.login).toBe('lacko');
  });
  it('rejects connection callbacks from another session or after logout', async () => {
    expect(
      (await app.inject('/auth/github?intent=connect')).headers.location,
    ).toBe('/login');
    for (const oldId of ['other', '']) {
      await store.saveSession('original', { user: googleUser, github: null });
      const start = await app.inject({
        url: '/auth/github?intent=connect',
        cookies: { session: 'original' },
      });
      const state = new URL(start.headers.location!).searchParams.get('state')!;
      await store.saveSession('other', signedIn());
      expect(
        (
          await app.inject({
            url: `/auth/github/callback?state=${state}&code=x`,
            cookies: { session: oldId, oauth_github: state },
          })
        ).headers.location,
      ).toBe('/login?auth=failed');
    }
  });
  it.each(['google', 'github'] as const)(
    'rejects invalid/cancelled/cross-provider %s callbacks',
    async (provider) => {
      for (const query of [
        '',
        '?error=access_denied',
        '?code=x',
        '?code=x&state=wrong',
      ])
        expect(
          (await app.inject(`/auth/${provider}/callback${query}`)).headers
            .location,
        ).toBe('/login?auth=failed');
      const state = 'cross';
      await store.saveState(state, {
        provider: provider === 'google' ? 'github' : 'google',
        verifier: 'v',
        nonce: 'n',
        returnTo: '/',
        sessionHash: null,
      });
      expect(
        (
          await app.inject({
            url: `/auth/${provider}/callback?code=x&state=${state}`,
            cookies: { [`oauth_${provider}`]: state },
          })
        ).headers.location,
      ).toBe('/login?auth=failed');
    },
  );
  it.each(['google', 'github'] as const)(
    'handles %s provider failure without leaking secrets',
    async (provider) => {
      const start = await app.inject(
        `/auth/${provider}?returnTo=//evil.example`,
      );
      const state = new URL(start.headers.location!).searchParams.get('state')!;
      vi.spyOn(github, 'exchange').mockRejectedValue(new Error('secret'));
      vi.spyOn(google, 'login').mockRejectedValue(new Error('secret'));
      const result = await app.inject({
        url: `/auth/${provider}/callback?code=x&state=${state}`,
        cookies: { [`oauth_${provider}`]: state },
      });
      expect(result.headers.location).toBe('/login?auth=failed');
      expect(result.body).not.toContain('secret');
    },
  );
  it('keeps a Google session after a failed GitHub connection', async () => {
    await store.saveSession('valid', { user: googleUser, github: null });
    const start = await app.inject({
      url: '/auth/github?intent=connect',
      cookies: { session: 'valid' },
    });
    const state = new URL(start.headers.location!).searchParams.get('state')!;
    vi.spyOn(github, 'exchange').mockRejectedValue(new Error('secret'));
    expect(
      (
        await app.inject({
          url: `/auth/github/callback?code=x&state=${state}`,
          cookies: { oauth_github: state, session: 'valid' },
        })
      ).headers.location,
    ).toBe('/pull-requests/review-requests?connection=failed');
    expect(await store.getSession('valid')).not.toBeNull();
  });
  it.each([
    ['/api/inbox', 'reviews'],
    ['/api/my-pulls', 'authored'],
  ] as const)(
    'scopes %s to the connected GitHub account',
    async (path, mode) => {
      await store.saveSession('valid', signedIn());
      vi.spyOn(github, 'inbox').mockResolvedValue({
        pulls: [],
        warnings: [],
        syncedAt: 'now',
      });
      expect(
        (await app.inject({ url: path, cookies: { session: 'valid' } }))
          .statusCode,
      ).toBe(200);
      expect(github.inbox).toHaveBeenCalledWith('token', 'lacko', mode);
    },
  );
  it('requires a live GitHub connection even for authenticated Google users', async () => {
    await store.saveSession('valid', { user: googleUser, github: null });
    expect(
      (
        await app.inject({ url: '/api/inbox', cookies: { session: 'valid' } })
      ).json(),
    ).toEqual({ error: 'github_connection_required' });
    const expired = signedIn();
    expired.github!.expiresAt = 0;
    await store.saveSession('valid', expired);
    expect(
      (
        await app.inject({ url: '/api/session', cookies: { session: 'valid' } })
      ).json().github.connected,
    ).toBe(false);
    expect(
      (await app.inject({ url: '/api/inbox', cookies: { session: 'valid' } }))
        .statusCode,
    ).toBe(403);
  });
  it.each([
    ['github_unauthorized', 401],
    ['rate_limited', 429],
    ['github_permissions', 403],
    ['github_unavailable', 502],
  ] as const)('maps %s and preserves app identity', async (code, status) => {
    await store.saveSession('valid', signedIn());
    vi.spyOn(github, 'inbox').mockRejectedValue(new GitHubError(status, code));
    expect(
      (await app.inject({ url: '/api/inbox', cookies: { session: 'valid' } }))
        .statusCode,
    ).toBe(status);
    expect((await store.getSession('valid'))!.user).toEqual(googleUser);
    if (code === 'github_unauthorized')
      expect((await store.getSession('valid'))!.github).toBeNull();
  });
  it('protects logout and deletes the complete session', async () => {
    await store.saveSession('valid', signedIn());
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
    const result = await app.inject({
      method: 'POST',
      url: '/api/logout',
      headers: { origin: config.appUrl },
      cookies: { session: 'valid' },
    });
    expect(result.statusCode).toBe(200);
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
  it('handles unavailable providers and internal failures safely', async () => {
    await app.close();
    app = await buildApp({ clientRoot: root, store, config: readConfig({}) });
    for (const provider of ['google', 'github'])
      expect((await app.inject(`/auth/${provider}`)).headers.location).toBe(
        '/login?auth=unavailable',
      );
    vi.spyOn(store, 'getSession').mockRejectedValue(
      new Error('database-secret'),
    );
    expect(
      (
        await app.inject({ url: '/api/session', cookies: { session: 'valid' } })
      ).json(),
    ).toEqual({ error: 'service_unavailable' });
  });
  it('uses secure cookies in HTTPS deployments', async () => {
    await app.close();
    app = await buildApp({
      clientRoot: root,
      store,
      config: { ...config, secure: true, appUrl: 'https://buddy.example' },
    });
    expect((await app.inject('/auth/google')).cookies[0].secure).toBe(true);
  });
});

describe('configuration and cryptography', () => {
  it.each([
    { GOOGLE_CLIENT_ID: 'id' },
    { GOOGLE_CLIENT_SECRET: 'secret' },
    {
      GOOGLE_CLIENT_ID: 'id',
      GOOGLE_CLIENT_SECRET: 'secret',
      TOKEN_ENCRYPTION_KEY: 'bad',
    },
  ])('rejects invalid Google provider configuration %j', (env) => {
    expect(() => readConfig(env)).toThrow();
  });

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
