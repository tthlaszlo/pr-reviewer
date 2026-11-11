// @vitest-environment node
import { generateKeyPairSync, createSign } from 'node:crypto';
import { OAuth2Client } from 'google-auth-library';
import { CertificateFormat } from 'google-auth-library/build/src/auth/oauth2client.js';
import { describe, expect, it, vi } from 'vitest';
import { Google } from '../../server/google';

const { privateKey, publicKey } = generateKeyPairSync('rsa', {
  modulusLength: 2048,
});
const certificate = publicKey
  .export({ type: 'spki', format: 'pem' })
  .toString();
function signed(claims: Record<string, unknown> = {}, wrongSignature = false) {
  const now = Math.floor(Date.now() / 1000);
  const header = Buffer.from(
    JSON.stringify({ alg: 'RS256', kid: 'test' }),
  ).toString('base64url');
  const body = Buffer.from(
    JSON.stringify({
      iss: 'https://accounts.google.com',
      aud: 'client',
      sub: 'stable-google-sub',
      name: 'Lacko',
      nonce: 'nonce',
      iat: now,
      exp: now + 3600,
      ...claims,
    }),
  ).toString('base64url');
  const data = `${header}.${body}`;
  const signature = createSign('RSA-SHA256')
    .update(data)
    .sign(privateKey)
    .toString('base64url');
  return `${data}.${wrongSignature ? 'invalid' : signature}`;
}
function provider(token: string) {
  const verifier = new OAuth2Client();
  vi.spyOn(verifier, 'getFederatedSignonCertsAsync').mockResolvedValue({
    certs: { test: certificate },
    format: CertificateFormat.PEM,
  });
  const fetcher = vi
    .fn<typeof fetch>()
    .mockResolvedValue(new Response(JSON.stringify({ id_token: token })));
  return { google: new Google(fetcher, verifier), fetcher };
}
describe('Google OIDC verification', () => {
  it('verifies a signed identity and binds token exchange to redirect URI and PKCE', async () => {
    const { google, fetcher } = provider(signed());
    expect(
      await google.login(
        'code',
        'client',
        'secret',
        'https://buddy.example/auth/google/callback',
        'verifier',
        'nonce',
      ),
    ).toEqual({ subject: 'stable-google-sub', name: 'Lacko' });
    const body = fetcher.mock.calls[0][1]!.body as URLSearchParams;
    expect(body.get('code_verifier')).toBe('verifier');
    expect(body.get('grant_type')).toBe('authorization_code');
    expect(body.get('redirect_uri')).toBe(
      'https://buddy.example/auth/google/callback',
    );
  });
  it.each([
    { aud: 'another-app' },
    { iss: 'https://evil.example' },
    { exp: Math.floor(Date.now() / 1000) - 1000 },
    { nonce: 'another-attempt' },
    { sub: '' },
    { nonce: undefined },
  ])('rejects invalid signed claims %j', async (claims) => {
    await expect(
      provider(signed(claims)).google.login(
        'c',
        'client',
        's',
        'u',
        'v',
        'nonce',
      ),
    ).rejects.toThrow();
  });
  it('rejects a forged signature', async () => {
    await expect(
      provider(signed({}, true)).google.login(
        'c',
        'client',
        's',
        'u',
        'v',
        'nonce',
      ),
    ).rejects.toThrow();
  });
  it('uses a fallback display name without requiring an email address', async () => {
    expect(
      await provider(signed({ name: undefined })).google.login(
        'c',
        'client',
        's',
        'u',
        'v',
        'nonce',
      ),
    ).toEqual({ subject: 'stable-google-sub', name: 'Google account' });
  });
  it.each([
    new Response('{}', { status: 400 }),
    new Response('{}'),
    new Response('invalid json'),
  ])('rejects bad token responses', async (response) => {
    await expect(
      new Google(vi.fn().mockResolvedValue(response)).login(
        'c',
        'client',
        's',
        'u',
        'v',
        'nonce',
      ),
    ).rejects.toThrow();
  });
  it('rejects provider network failure', async () => {
    await expect(
      new Google(vi.fn().mockRejectedValue(new Error('offline'))).login(
        'c',
        'client',
        's',
        'u',
        'v',
        'nonce',
      ),
    ).rejects.toThrow();
  });
});
