import { createHash } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import type { Config } from './config.js';
import type { Store, StoredSession } from './store.js';
import { hashToken, randomToken, encrypt } from './crypto.js';
import type { GitHub } from './github.js';
import type { Google } from './google.js';

const pages = ['/pull-requests/review-requests', '/pull-requests/mine'];
export const safeReturnTo = (value?: string) =>
  pages.includes(value || '') ? value! : pages[0];

export function registerAuth(
  app: FastifyInstance,
  config: Config,
  store: Store,
  github: GitHub,
  google: Google,
) {
  const cookies = {
    path: '/',
    httpOnly: true,
    sameSite: 'lax' as const,
    secure: config.secure,
  };
  for (const provider of ['google', 'github'] as const) {
    const stateCookie = `oauth_${provider}`;
    app.get<{ Querystring: { returnTo?: string; intent?: string } }>(
      `/auth/${provider}`,
      async (request, reply) => {
        if (!config.providers[provider])
          return reply.redirect('/login?auth=unavailable');
        const connect =
          provider === 'github' && request.query.intent === 'connect';
        if (
          connect &&
          (!request.cookies.session ||
            !(await store.getSession(request.cookies.session)))
        )
          return reply.redirect('/login');
        const state = randomToken(),
          verifier = randomToken(),
          nonce = randomToken();
        await store.saveState(state, {
          provider,
          verifier,
          nonce,
          returnTo: safeReturnTo(request.query.returnTo),
          sessionHash: connect ? hashToken(request.cookies.session!) : null,
        });
        const url = new URL(
          provider === 'github'
            ? 'https://github.com/login/oauth/authorize'
            : 'https://accounts.google.com/o/oauth2/v2/auth',
        );
        const params: Record<string, string> = {
          client_id:
            provider === 'github' ? config.clientId : config.googleClientId,
          redirect_uri: `${config.appUrl}/auth/${provider}/callback`,
          state,
          code_challenge: createHash('sha256')
            .update(verifier)
            .digest('base64url'),
          code_challenge_method: 'S256',
        };
        if (provider === 'google')
          Object.assign(params, {
            response_type: 'code',
            scope: 'openid profile',
            nonce,
            prompt: 'select_account',
          });
        url.search = new URLSearchParams(params).toString();
        return reply
          .setCookie(stateCookie, state, { ...cookies, maxAge: 600 })
          .redirect(url.href);
      },
    );
    app.get<{ Querystring: { code?: string; state?: string; error?: string } }>(
      `/auth/${provider}/callback`,
      async (request, reply) => {
        const { code, state, error } = request.query;
        reply.clearCookie(stateCookie, cookies);
        if (
          !config.providers[provider] ||
          error ||
          typeof code !== 'string' ||
          !code ||
          typeof state !== 'string' ||
          !state ||
          state !== request.cookies[stateCookie]
        )
          return reply.redirect('/login?auth=failed');
        const flow = await store.consumeState(state);
        if (!flow || flow.provider !== provider)
          return reply.redirect('/login?auth=failed');
        const oldId = request.cookies.session;
        const previous = oldId ? await store.getSession(oldId) : null;
        if (
          flow.sessionHash &&
          (!oldId || hashToken(oldId) !== flow.sessionHash || !previous)
        )
          return reply.redirect('/login?auth=failed');
        try {
          let value: StoredSession;
          if (provider === 'google') {
            const identity = await google.login(
              code,
              config.googleClientId,
              config.googleClientSecret,
              `${config.appUrl}/auth/google/callback`,
              flow.verifier,
              flow.nonce,
            );
            value = {
              user: await store.identify(
                'google',
                identity.subject,
                identity.name,
              ),
              github: null,
            };
          } else {
            const token = await github.exchange(
              code,
              config.clientId,
              config.clientSecret,
              `${config.appUrl}/auth/github/callback`,
              flow.verifier,
            );
            const identity = await github.user(token.accessToken);
            value = {
              user: flow.sessionHash
                ? previous!.user
                : await store.identify(
                    'github',
                    String(identity.id),
                    identity.name || identity.login,
                  ),
              github: {
                login: identity.login,
                encryptedToken: encrypt(
                  token.accessToken,
                  config.encryptionKey,
                ),
                expiresAt: Date.now() + token.ttl * 1000,
              },
            };
          }
          const id = randomToken();
          await store.saveSession(id, value, 28800);
          if (oldId) await store.deleteSession(oldId);
          return reply
            .setCookie('session', id, { ...cookies, maxAge: 28800 })
            .redirect(flow.returnTo);
        } catch {
          return reply.redirect(
            flow.sessionHash
              ? `${flow.returnTo}?connection=failed`
              : '/login?auth=failed',
          );
        }
      },
    );
  }
}
