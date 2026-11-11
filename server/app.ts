import Fastify, { LogController } from 'fastify';
import fastifyStatic from '@fastify/static';
import cookie from '@fastify/cookie';
import rateLimit from '@fastify/rate-limit';
import type { Config } from './config.js';
import type { Store } from './store.js';
import { decrypt } from './crypto.js';
import { Google } from './google.js';
import { registerAuth, safeReturnTo } from './auth.js';
import { GitHub, GitHubError } from './github.js';

export async function buildApp(options: {
  clientRoot: string;
  config: Config;
  store: Store;
  github?: GitHub;
  google?: Google;
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
    const pathname = request.url.split('?')[0];
    if (
      pathname.startsWith('/api') ||
      pathname.startsWith('/auth') ||
      pathname === '/' ||
      pathname === '/login' ||
      pathname.startsWith('/pull-requests/')
    )
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
      providers: config.providers,
      user: user?.user ?? null,
      github: {
        connected: Boolean(user?.github && user.github.expiresAt > Date.now()),
        login: user?.github?.login ?? null,
      },
      installUrl: config.installUrl,
    };
  });
  registerAuth(app, config, store, github, options.google ?? new Google());
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
        if (!user.github || user.github.expiresAt <= Date.now())
          return reply.code(403).send({ error: 'github_connection_required' });
        try {
          return await github.inbox(
            decrypt(user.github.encryptedToken, config.encryptionKey),
            user.github.login,
            mode,
          );
        } catch (error) {
          if (
            error instanceof GitHubError &&
            error.code === 'github_unauthorized'
          ) {
            await store.setGitHub(request.cookies.session!, null);
          }
          throw error;
        }
      },
    );
  }
  await app.register(fastifyStatic, { root: clientRoot });
  app.get<{ Querystring: { returnTo?: string } }>(
    '/login',
    async (request, reply) => {
      if (await session(request.cookies.session))
        return reply.redirect(safeReturnTo(request.query.returnTo));
      return reply.header('Cache-Control', 'no-store').sendFile('index.html');
    },
  );
  for (const path of [
    '/',
    '/pull-requests/review-requests',
    '/pull-requests/mine',
  ]) {
    app.get(path, async (request, reply) => {
      if (!(await session(request.cookies.session)))
        return reply.redirect(
          `/login?returnTo=${encodeURIComponent(safeReturnTo(path))}`,
        );
      return reply.header('Cache-Control', 'no-store').sendFile('index.html');
    });
  }
  return app;
}
