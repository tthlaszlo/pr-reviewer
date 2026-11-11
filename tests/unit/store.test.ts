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
    await store.saveState(state);
    expect(await store.consumeState(state)).toBe(true);
    expect(await store.consumeState(state)).toBe(false);
    await store.saveState(state);
    await pool.query(
      "UPDATE oauth_states SET expires_at=now()-interval '1 second' WHERE id=$1",
      [hashToken(state)],
    );
    expect(await store.consumeState(state)).toBe(false);
    await store.saveState(randomToken());
  });
  it('stores only hashed session IDs and scopes each session', async () => {
    const id = randomToken(),
      other = randomToken();
    const value = { login: 'lacko', encryptedToken: 'encrypted' };
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
    await store.saveSession(id, { login: 'old', encryptedToken: 'token' }, -1);
    expect(await store.getSession(id)).toBeNull();
    const next = randomToken();
    await store.saveSession(next, { login: 'next', encryptedToken: 'new' }, 60);
    expect(
      (await pool.query('SELECT id FROM sessions WHERE id=$1', [hashToken(id)]))
        .rowCount,
    ).toBe(0);
    await store.deleteSession(next);
  });
});
