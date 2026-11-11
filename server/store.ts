import pg from 'pg';
import { hashToken } from './crypto.js';

export type StoredSession = { login: string; encryptedToken: string };
export interface Store {
  ready(): Promise<void>;
  saveState(state: string): Promise<void>;
  consumeState(state: string): Promise<boolean>;
  saveSession(id: string, value: StoredSession, ttl: number): Promise<void>;
  getSession(id: string): Promise<StoredSession | null>;
  deleteSession(id: string): Promise<void>;
  close(): Promise<void>;
}

export class PostgresStore implements Store {
  private pool: pg.Pool;
  constructor(url: string) {
    this.pool = new pg.Pool({
      connectionString: url,
      connectionTimeoutMillis: 5000,
    });
  }
  async migrate() {
    await this.pool
      .query(`CREATE TABLE IF NOT EXISTS oauth_states (id text PRIMARY KEY, expires_at timestamptz NOT NULL);
      CREATE TABLE IF NOT EXISTS sessions (id text PRIMARY KEY, login text NOT NULL, token text NOT NULL, expires_at timestamptz NOT NULL)`);
  }
  async ready() {
    await this.pool.query('SELECT 1');
  }
  async saveState(state: string) {
    await this.pool.query('DELETE FROM oauth_states WHERE expires_at <= now()');
    await this.pool.query(
      "INSERT INTO oauth_states VALUES ($1, now() + interval '10 minutes')",
      [hashToken(state)],
    );
  }
  async consumeState(state: string) {
    const result = await this.pool.query(
      'DELETE FROM oauth_states WHERE id=$1 RETURNING expires_at > now() AS valid',
      [hashToken(state)],
    );
    return result.rows[0]?.valid === true;
  }
  async saveSession(id: string, value: StoredSession, ttl: number) {
    await this.pool.query('DELETE FROM sessions WHERE expires_at <= now()');
    await this.pool.query(
      "INSERT INTO sessions VALUES ($1,$2,$3,now() + $4 * interval '1 second')",
      [hashToken(id), value.login, value.encryptedToken, ttl],
    );
  }
  async getSession(id: string): Promise<StoredSession | null> {
    const result = await this.pool.query(
      'SELECT login, token FROM sessions WHERE id=$1 AND expires_at > now()',
      [hashToken(id)],
    );
    const row = result.rows[0];
    return row ? { login: row.login, encryptedToken: row.token } : null;
  }
  async deleteSession(id: string) {
    await this.pool.query('DELETE FROM sessions WHERE id=$1', [hashToken(id)]);
  }
  async close() {
    await this.pool.end();
  }
}
