export function readPort(value: string | undefined): number {
  if (value === undefined) return 3001;
  if (!/^\d+$/.test(value))
    throw new Error('PORT must be an integer between 1 and 65535');
  const port = Number(value);
  if (port < 1 || port > 65535)
    throw new Error('PORT must be an integer between 1 and 65535');
  return port;
}

export function readConfig(env: NodeJS.ProcessEnv = process.env) {
  const appUrl = new URL(env.APP_URL || 'http://localhost:3000');
  if (env.NODE_ENV === 'production' && appUrl.protocol !== 'https:')
    throw new Error('Production APP_URL must use HTTPS');
  if (
    !['http:', 'https:'].includes(appUrl.protocol) ||
    appUrl.pathname !== '/' ||
    appUrl.search ||
    appUrl.hash ||
    appUrl.username ||
    appUrl.password
  )
    throw new Error('APP_URL must be an HTTP(S) origin');
  const clientId = env.GITHUB_CLIENT_ID || '';
  const clientSecret = env.GITHUB_CLIENT_SECRET || '';
  const googleClientId = env.GOOGLE_CLIENT_ID || '';
  const googleClientSecret = env.GOOGLE_CLIENT_SECRET || '';
  if (Boolean(googleClientId) !== Boolean(googleClientSecret))
    throw new Error('Set both GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET');
  const encryptionKey = env.TOKEN_ENCRYPTION_KEY || '';
  if (Boolean(clientId) !== Boolean(clientSecret))
    throw new Error('Set both GITHUB_CLIENT_ID and GITHUB_CLIENT_SECRET');
  if ((clientId || googleClientId) && !/^[a-fA-F0-9]{64}$/.test(encryptionKey))
    throw new Error(
      'TOKEN_ENCRYPTION_KEY must contain 64 hexadecimal characters',
    );
  const installUrl = env.GITHUB_INSTALL_URL || null;
  if (
    installUrl &&
    !/^https:\/\/github\.com\/apps\/[a-z0-9-]+\/installations\/new$/.test(
      installUrl,
    )
  )
    throw new Error('Invalid GITHUB_INSTALL_URL');
  return {
    appUrl: appUrl.origin,
    clientId,
    clientSecret,
    googleClientId,
    googleClientSecret,
    providers: { github: Boolean(clientId), google: Boolean(googleClientId) },
    encryptionKey,
    installUrl,
    configured: Boolean(clientId),
    secure: appUrl.protocol === 'https:',
  };
}
export type Config = ReturnType<typeof readConfig>;
