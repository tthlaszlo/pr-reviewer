import { OAuth2Client } from 'google-auth-library';

export class Google {
  constructor(
    private fetcher: typeof fetch = fetch,
    private verifier: Pick<OAuth2Client, 'verifyIdToken'> = new OAuth2Client({
      transporterOptions: { timeout: 15000 },
    }),
  ) {}
  async login(
    code: string,
    clientId: string,
    clientSecret: string,
    redirectUri: string,
    verifier: string,
    nonce: string,
  ) {
    const response = await this.fetcher('https://oauth2.googleapis.com/token', {
      method: 'POST',
      redirect: 'error',
      signal: AbortSignal.timeout(15000),
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        code,
        client_id: clientId,
        client_secret: clientSecret,
        redirect_uri: redirectUri,
        grant_type: 'authorization_code',
        code_verifier: verifier,
      }),
    });
    if (!response.ok) throw new Error('Google authentication failed');
    const token = (await response.json()) as { id_token?: string };
    if (!token.id_token) throw new Error('Missing Google identity');
    const ticket = await this.verifier.verifyIdToken({
      idToken: token.id_token,
      audience: clientId,
    });
    const payload = ticket.getPayload();
    if (
      !payload?.sub ||
      (payload as unknown as { nonce?: string }).nonce !== nonce
    )
      throw new Error('Invalid Google identity');
    return { subject: payload.sub, name: payload.name || 'Google account' };
  }
}
