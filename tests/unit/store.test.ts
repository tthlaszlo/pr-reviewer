// @vitest-environment node
import { beforeAll, afterAll, describe, expect, it } from 'vitest';
import pg from 'pg';
import { PostgresStore } from '../../server/store';
import { hashToken, randomToken } from '../../server/crypto';

const url = process.env.DATABASE_URL!;
const store = new PostgresStore(url);
const pool = new pg.Pool({ connectionString: url });
beforeAll(async () => {
  await store.migrate();
  await store.migrate();
});
afterAll(async () => {
  await store.close();
  await pool.end();
});
describe('PostgreSQL persistence', () => {
  it('checks readiness', async () => {
    await expect(store.ready()).resolves.toBeUndefined();
  });
  it('consumes OAuth state once and rejects expired states', async () => {
    const state = randomToken();
    await store.saveState(state, {
      provider: 'google',
      verifier: 'v',
      nonce: 'n',
      returnTo: '/',
      sessionHash: null,
    });
    expect(await store.consumeState(state)).toMatchObject({
      provider: 'google',
      nonce: 'n',
    });
    expect(await store.consumeState(state)).toBeNull();
    await store.saveState(state, {
      provider: 'google',
      verifier: 'v',
      nonce: 'n',
      returnTo: '/',
      sessionHash: null,
    });
    await pool.query(
      "UPDATE oauth_states SET expires_at=now()-interval '1 second' WHERE id=$1",
      [hashToken(state)],
    );
    expect(await store.consumeState(state)).toBeNull();
    await store.saveState(randomToken(), {
      provider: 'github',
      verifier: 'v',
      nonce: 'n',
      returnTo: '/',
      sessionHash: null,
    });
  });
  it('stores only hashed session IDs and scopes each session', async () => {
    const id = randomToken(),
      other = randomToken();
    const value = {
      user: { id: '1', name: 'Lacko', provider: 'google' as const },
      github: null,
    };
    await store.saveSession(id, value, 60);
    expect(await store.getSession(id)).toEqual(value);
    expect(await store.getSession(other)).toBeNull();
    expect(
      (await pool.query('SELECT id FROM sessions WHERE id=$1', [id])).rowCount,
    ).toBe(0);
    await store.deleteSession(id);
    expect(await store.getSession(id)).toBeNull();
  });
  it('rejects expired sessions and cleans up on login', async () => {
    const id = randomToken();
    await store.saveSession(
      id,
      { user: { id: '1', name: 'Old', provider: 'google' }, github: null },
      -1,
    );
    expect(await store.getSession(id)).toBeNull();
    const next = randomToken();
    await store.saveSession(
      next,
      { user: { id: '2', name: 'Next', provider: 'github' }, github: null },
      60,
    );
    expect(
      (await pool.query('SELECT id FROM sessions WHERE id=$1', [hashToken(id)]))
        .rowCount,
    ).toBe(0);
    await store.deleteSession(next);
  });
  it('keeps stable provider subjects separate and updates display names', async () => {
    const sub = randomToken();
    const first = await store.identify('google', sub, 'First');
    const next = await store.identify('google', sub, 'Next');
    const other = await store.identify('github', sub, 'Next');
    expect(next.id).toBe(first.id);
    expect(next.name).toBe('Next');
    expect(other.id).not.toBe(first.id);
  });
  it('updates a connection without changing the login identity', async () => {
    const id = randomToken();
    const user = { id: '1', provider: 'google' as const, name: 'Lacko' };
    await store.saveSession(id, { user, github: null }, 60);
    const connection = {
      login: 'github-user',
      encryptedToken: 'encrypted',
      expiresAt: Date.now() + 1000,
    };
    await store.setGitHub(id, connection);
    expect(await store.getSession(id)).toEqual({ user, github: connection });
    await store.setGitHub(id, null);
    expect((await store.getSession(id))!.github).toBeNull();
    await store.deleteSession(id);
  });
  it('invalidates legacy login-only sessions during migration', async () => {
    const id = hashToken(randomToken());
    await pool.query(
      "INSERT INTO sessions (id, login, token, expires_at) VALUES ($1, 'legacy', 'old-token', now() + interval '1 hour')",
      [id],
    );
    await store.migrate();
    expect(
      (await pool.query('SELECT id FROM sessions WHERE id=$1', [id])).rowCount,
    ).toBe(0);
  });
});
