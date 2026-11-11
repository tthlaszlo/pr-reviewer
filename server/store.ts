import pg from 'pg';
import { hashToken } from './crypto.js';
import type { Account, Provider } from '../shared/types.js';

export type GitHubConnection = {
  login: string;
  encryptedToken: string;
  expiresAt: number;
};
export type StoredSession = { user: Account; github: GitHubConnection | null };
export type LoginFlow = {
  provider: Provider;
  verifier: string;
  nonce: string;
  returnTo: string;
  sessionHash: string | null;
};
export interface Store {
  ready(): Promise<void>;
  saveState(state: string, flow: LoginFlow): Promise<void>;
  consumeState(state: string): Promise<LoginFlow | null>;
  identify(provider: Provider, subject: string, name: string): Promise<Account>;
  saveSession(id: string, value: StoredSession, ttl: number): Promise<void>;
  getSession(id: string): Promise<StoredSession | null>;
  setGitHub(id: string, value: GitHubConnection | null): Promise<void>;
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
      ALTER TABLE oauth_states ADD COLUMN IF NOT EXISTS data jsonb;
      CREATE TABLE IF NOT EXISTS sessions (id text PRIMARY KEY, login text, token text, expires_at timestamptz NOT NULL);
      ALTER TABLE sessions ALTER COLUMN login DROP NOT NULL, ALTER COLUMN token DROP NOT NULL;
      ALTER TABLE sessions ADD COLUMN IF NOT EXISTS data jsonb;
      CREATE TABLE IF NOT EXISTS app_users (id bigserial PRIMARY KEY, provider text NOT NULL, subject text NOT NULL, name text NOT NULL, UNIQUE(provider, subject));
      DELETE FROM sessions WHERE data IS NULL OR expires_at <= now();
      DELETE FROM oauth_states WHERE data IS NULL OR expires_at <= now();`);
  }
  async ready() {
    await this.pool.query('SELECT 1');
  }
  async saveState(state: string, flow: LoginFlow) {
    await this.pool.query('DELETE FROM oauth_states WHERE expires_at <= now()');
    await this.pool.query(
      "INSERT INTO oauth_states (id, expires_at, data) VALUES ($1, now() + interval '10 minutes', $2)",
      [hashToken(state), JSON.stringify(flow)],
    );
  }
  async consumeState(state: string): Promise<LoginFlow | null> {
    const result = await this.pool.query(
      'DELETE FROM oauth_states WHERE id=$1 RETURNING data, expires_at > now() AS valid',
      [hashToken(state)],
    );
    return result.rows[0]?.valid ? result.rows[0].data : null;
  }
  async identify(
    provider: Provider,
    subject: string,
    name: string,
  ): Promise<Account> {
    const result = await this.pool.query(
      'INSERT INTO app_users (provider, subject, name) VALUES ($1,$2,$3) ON CONFLICT (provider,subject) DO UPDATE SET name=EXCLUDED.name RETURNING id::text, name, provider',
      [provider, subject, name],
    );
    return result.rows[0];
  }
  async saveSession(id: string, value: StoredSession, ttl: number) {
    await this.pool.query('DELETE FROM sessions WHERE expires_at <= now()');
    await this.pool.query(
      "INSERT INTO sessions (id, data, expires_at) VALUES ($1,$2,now() + $3 * interval '1 second')",
      [hashToken(id), JSON.stringify(value), ttl],
    );
  }
  async getSession(id: string): Promise<StoredSession | null> {
    const result = await this.pool.query(
      'SELECT data FROM sessions WHERE id=$1 AND expires_at > now()',
      [hashToken(id)],
    );
    return result.rows[0]?.data ?? null;
  }
  async setGitHub(id: string, value: GitHubConnection | null) {
    await this.pool.query(
      "UPDATE sessions SET data=jsonb_set(data,'{github}',$2::jsonb) WHERE id=$1 AND expires_at > now()",
      [hashToken(id), JSON.stringify(value)],
    );
  }
  async deleteSession(id: string) {
    await this.pool.query('DELETE FROM sessions WHERE id=$1', [hashToken(id)]);
  }
  async close() {
    await this.pool.end();
  }
}
