import Fastify, { LogController } from 'fastify';
import fastifyStatic from '@fastify/static';
import cookie from '@fastify/cookie';
import rateLimit from '@fastify/rate-limit';
import type { Config } from './config.js';
import type { Store } from './store.js';
import { decrypt, encrypt, randomToken } from './crypto.js';
import { GitHub, GitHubError } from './github.js';

export async function buildApp(options: {
  clientRoot: string;
  config: Config;
  store: Store;
  github?: GitHub;
  logger?: boolean;
}) {
  const { config, store, clientRoot } = options;
  const github = options.github ?? new GitHub();
  const app = Fastify({
    logger: options.logger ?? false,
    logController: new LogController({ disableRequestLogging: true }),
  });
  await app.register(cookie);
  await app.register(rateLimit, { max: 120, timeWindow: '1 minute' });
  const cookieOptions = {
    path: '/',
    httpOnly: true,
    sameSite: 'lax' as const,
    secure: config.secure,
  };
  const session = (id?: string) =>
    id ? store.getSession(id) : Promise.resolve(null);
  app.addHook('onSend', async (request, reply) => {
    reply.header('X-Content-Type-Options', 'nosniff');
    reply.header('Referrer-Policy', 'no-referrer');
    reply.header(
      'Content-Security-Policy',
      "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self'; connect-src 'self'; font-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'",
    );
    if (request.url.startsWith('/api') || request.url.startsWith('/auth'))
      reply.header('Cache-Control', 'no-store');
  });
  app.setErrorHandler((error, _request, reply) => {
    if (error instanceof GitHubError) {
      return reply
        .code(
          error.code === 'github_unauthorized'
            ? 401
            : error.code === 'rate_limited'
              ? 429
              : error.code === 'github_permissions'
                ? 403
                : 502,
        )
        .send({ error: error.code });
    }
    const limited =
      error instanceof Error &&
      'statusCode' in error &&
      error.statusCode === 429;
    app.log.error(
      { name: error instanceof Error ? error.name : 'UnknownError' },
      'Request failed',
    );
    return reply
      .code(limited ? 429 : 503)
      .send({ error: limited ? 'rate_limited' : 'service_unavailable' });
  });
  app.get('/healthz', async (_request, reply) => {
    try {
      await store.ready();
      return { status: 'ok' };
    } catch {
      return reply.code(503).send({ status: 'unavailable' });
    }
  });
  app.get('/api/session', async (request) => {
    const user = await session(request.cookies.session);
    return {
      configured: config.configured,
      user: user ? { login: user.login } : null,
      installUrl: config.installUrl,
    };
  });
  app.get('/auth/github', async (_request, reply) => {
    if (!config.configured)
      return reply.code(503).send({ error: 'github_not_configured' });
    const state = randomToken();
    await store.saveState(state);
    const url = new URL('https://github.com/login/oauth/authorize');
    url.search = new URLSearchParams({
      client_id: config.clientId,
      redirect_uri: `${config.appUrl}/auth/github/callback`,
      state,
    }).toString();
    return reply
      .setCookie('oauth_state', state, { ...cookieOptions, maxAge: 600 })
      .redirect(url.href);
  });
  app.get<{ Querystring: { code?: string; state?: string; error?: string } }>(
    '/auth/github/callback',
    async (request, reply) => {
      const { code, state, error } = request.query;
      reply.clearCookie('oauth_state', cookieOptions);
      if (
        !config.configured ||
        error ||
        !code ||
        !state ||
        state !== request.cookies.oauth_state ||
        !(await store.consumeState(state))
      ) {
        return reply.redirect('/?auth=failed');
      }
      try {
        const token = await github.exchange(
          code,
          config.clientId,
          config.clientSecret,
          `${config.appUrl}/auth/github/callback`,
        );
        const user = await github.user(token.accessToken);
        const id = randomToken();
        await store.saveSession(
          id,
          {
            login: user.login,
            encryptedToken: encrypt(token.accessToken, config.encryptionKey),
          },
          token.ttl,
        );
        if (request.cookies.session)
          await store.deleteSession(request.cookies.session);
        return reply
          .setCookie('session', id, { ...cookieOptions, maxAge: token.ttl })
          .redirect('/');
      } catch {
        return reply.redirect('/?auth=failed');
      }
    },
  );
  app.post('/api/logout', async (request, reply) => {
    if (request.headers.origin !== config.appUrl)
      return reply.code(403).send({ error: 'invalid_origin' });
    if (request.cookies.session)
      await store.deleteSession(request.cookies.session);
    return reply.clearCookie('session', cookieOptions).send({ ok: true });
  });
  for (const [path, mode] of [
    ['/api/inbox', 'reviews'],
    ['/api/my-pulls', 'authored'],
  ] as const) {
    app.get(
      path,
      { config: { rateLimit: { max: 10, timeWindow: '1 minute' } } },
      async (request, reply) => {
        const user = await session(request.cookies.session);
        if (!user) return reply.code(401).send({ error: 'unauthenticated' });
        try {
          return await github.inbox(
            decrypt(user.encryptedToken, config.encryptionKey),
            user.login,
            mode,
          );
        } catch (error) {
          if (
            error instanceof GitHubError &&
            error.code === 'github_unauthorized'
          ) {
            await store.deleteSession(request.cookies.session!);
            reply.clearCookie('session', cookieOptions);
          }
          throw error;
        }
      },
    );
  }
  await app.register(fastifyStatic, { root: clientRoot });
  for (const path of [
    '/pull-requests/review-requests',
    '/pull-requests/mine',
  ]) {
    app.get(path, (_request, reply) => reply.sendFile('index.html'));
  }
  return app;
}
