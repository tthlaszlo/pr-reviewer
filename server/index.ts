import { resolve } from 'node:path';
import { buildApp } from './app.js';
import { readPort, readConfig } from './config.js';
import { PostgresStore } from './store.js';

const port = readPort(process.env.PORT);
const store = new PostgresStore(
  process.env.DATABASE_URL || 'postgres://reviewer:reviewer@db:5432/reviewer',
);
await store.migrate();
const app = await buildApp({
  clientRoot: resolve('dist/client'),
  logger: true,
  store,
  config: readConfig(),
});
app.addHook('onClose', () => store.close());

for (const signal of ['SIGINT', 'SIGTERM'] as const) {
  process.once(signal, () => {
    app.close().catch((error: unknown) => {
      app.log.error(error);
      process.exitCode = 1;
    });
  });
}

try {
  await app.listen({ port, host: '0.0.0.0' });
} catch (error) {
  app.log.error(error);
  process.exitCode = 1;
}
