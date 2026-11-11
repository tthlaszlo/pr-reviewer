import { expect, test, type Page } from '@playwright/test';

const account = { id: '1', name: 'Lacko', provider: 'github' };
const session = {
  providers: { google: true, github: true },
  user: account,
  github: { connected: true, login: 'lacko' },
  installUrl: null,
};
const empty = { pulls: [], warnings: [], syncedAt: '2026-11-11T10:00:00Z' };
async function authenticated(page: Page) {
  await page.route('**/api/session', (route) =>
    route.fulfill({ json: session }),
  );
  await page.route('**/api/inbox', (route) => route.fulfill({ json: empty }));
  await page.route('**/api/my-pulls', (route) =>
    route.fulfill({ json: empty }),
  );
}
test('server protects all workspace pages and APIs and exposes only OAuth entry points', async ({
  request,
}) => {
  expect((await request.get('/healthz')).status()).toBe(200);
  for (const path of [
    '/',
    '/pull-requests/review-requests',
    '/pull-requests/mine',
  ]) {
    const response = await request.get(path, { maxRedirects: 0 });
    expect(response.status()).toBe(302);
    expect(response.headers().location).toMatch(/^\/login\?returnTo=/);
  }
  for (const path of ['/api/inbox', '/api/my-pulls'])
    expect((await request.get(path)).status()).toBe(401);
  for (const path of [
    '/auth/email',
    '/auth/password',
    '/auth/guest',
    '/api/missing',
  ])
    expect((await request.get(path)).status()).toBe(404);
  const response = await request.get('/api/session');
  expect(await response.json()).toEqual({
    providers: { google: false, github: false },
    user: null,
    github: { connected: false, login: null },
    installUrl: null,
  });
  expect(response.headers()['cache-control']).toBe('no-store');
});
test('renders an exclusive Google/GitHub login page in Focus design', async ({
  page,
}) => {
  await page.goto('/');
  await expect(page).toHaveURL(/\/login\?returnTo=/);
  await expect(page).toHaveTitle('AI Buddy');
  await expect(
    page.getByRole('heading', { name: 'Welcome to AI Buddy' }),
  ).toBeVisible();
  await expect(
    page.getByRole('button', { name: 'Sign in with Google' }),
  ).toBeDisabled();
  await expect(
    page.getByRole('button', { name: 'Sign in with GitHub' }),
  ).toBeDisabled();
  await expect(page.getByRole('textbox')).toHaveCount(0);
  await expect(page.getByRole('navigation')).toHaveCount(0);
  expect(
    await page
      .locator('.login-shell')
      .evaluate((el) => getComputedStyle(el).borderRadius),
  ).toBe('15px');
  expect(
    await page
      .locator('.login-shell')
      .evaluate((el) => getComputedStyle(el).backgroundColor),
  ).toBe('rgb(249, 249, 252)');
  await page.screenshot({
    path: 'test-results/login-desktop.png',
    fullPage: true,
  });
});
test('shows configured provider links and remembers the requested tool page', async ({
  page,
}) => {
  await page.route('**/api/session', (route) =>
    route.fulfill({
      json: {
        ...session,
        user: null,
        github: { connected: false, login: null },
      },
    }),
  );
  await page.goto('/pull-requests/mine');
  await expect(
    page.getByRole('link', { name: 'Sign in with Google' }),
  ).toHaveAttribute('href', '/auth/google?returnTo=%2Fpull-requests%2Fmine');
  await expect(
    page.getByRole('link', { name: 'Sign in with GitHub' }),
  ).toHaveAttribute('href', '/auth/github?returnTo=%2Fpull-requests%2Fmine');
  await page.getByRole('link', { name: 'Sign in with Google' }).focus();
  await expect(
    page.getByRole('link', { name: 'Sign in with Google' }),
  ).toBeFocused();
});
test('explains failed login and supports retry after an availability error', async ({
  page,
}) => {
  let fail = true;
  await page.route('**/api/session', (route) =>
    route.fulfill(
      fail
        ? { status: 503, json: { error: 'service_unavailable' } }
        : { json: { ...session, user: null } },
    ),
  );
  await page.goto('/login?auth=failed');
  await expect(
    page.getByText(
      'Sign-in was cancelled or could not be completed. Please try again.',
    ),
  ).toBeVisible();
  await expect(
    page.getByText('We couldn’t check sign-in availability.'),
  ).toBeVisible();
  fail = false;
  await page.getByRole('button', { name: 'Try again' }).click();
  await expect(
    page.getByRole('link', { name: 'Sign in with Google' }),
  ).toBeVisible();
});
test('keeps the login usable on mobile without horizontal scrolling', async ({
  page,
}) => {
  await page.setViewportSize({ width: 375, height: 812 });
  await page.goto('/login');
  await expect(
    page.getByRole('heading', { name: 'Welcome to AI Buddy' }),
  ).toBeVisible();
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth,
    ),
  ).toBe(true);
  await page.screenshot({
    path: 'test-results/login-mobile.png',
    fullPage: true,
  });
});
test('keeps authenticated subpage navigation and browser history working', async ({
  page,
}) => {
  await authenticated(page);
  await page.goto('/');
  await expect(page.getByRole('heading', { level: 1 })).toHaveText(
    'Your review inbox',
  );
  await page
    .getByRole('link', { name: 'My pull requests', exact: true })
    .click();
  await expect(page).toHaveURL(/\/pull-requests\/mine$/);
  await expect(page.getByRole('heading', { level: 1 })).toHaveText(
    'My pull requests',
  );
  await page.reload();
  await expect(page.getByRole('heading', { level: 1 })).toHaveText(
    'My pull requests',
  );
  await page.goBack();
  await expect(page.getByRole('heading', { level: 1 })).toHaveText(
    'Your review inbox',
  );
  await page.goForward();
  await expect(page.getByRole('heading', { level: 1 })).toHaveText(
    'My pull requests',
  );
});
test('Google login grants app access but requires a separate GitHub connection', async ({
  page,
}) => {
  let inboxRequests = 0;
  await page.route('**/api/session', (route) =>
    route.fulfill({
      json: {
        ...session,
        user: { ...account, provider: 'google' },
        github: { connected: false, login: null },
      },
    }),
  );
  await page.route('**/api/inbox', (route) => {
    inboxRequests++;
    return route.fulfill({ json: empty });
  });
  await page.route('**/api/logout', (route) =>
    route.fulfill({ json: { ok: true } }),
  );
  await page.goto('/');
  await expect(page.getByText('Google account', { exact: true })).toBeVisible();
  await expect(
    page.getByRole('link', { name: 'Connect GitHub' }),
  ).toHaveAttribute('href', '/auth/github?intent=connect');
  expect(inboxRequests).toBe(0);
  await page.getByRole('button', { name: 'Sign out' }).click();
  await expect(
    page.getByRole('heading', { name: 'Welcome to AI Buddy' }),
  ).toBeVisible();
  await expect(page.getByRole('navigation')).toHaveCount(0);
});
test('expired app sessions return to login and clear private PR content', async ({
  page,
}) => {
  await authenticated(page);
  await page.route('**/api/inbox', (route) =>
    route.fulfill({ status: 401, json: { error: 'unauthenticated' } }),
  );
  await page.goto('/');
  await expect(
    page.getByRole('heading', { name: 'Welcome to AI Buddy' }),
  ).toBeVisible();
  await expect(page.getByRole('navigation')).toHaveCount(0);
});
test('authenticated users can still list and filter authored PRs', async ({
  page,
}) => {
  await authenticated(page);
  await page.route('**/api/my-pulls', (route) =>
    route.fulfill({
      json: {
        ...empty,
        pulls: [
          {
            id: 9,
            number: 90,
            title: 'My authored change',
            url: 'https://github.com/acme/api/pull/90',
            repository: 'acme/api',
            author: 'lacko',
            updatedAt: '2026-11-11T10:00:00Z',
            draft: true,
            group: null,
            personal: false,
            teams: [],
            reviewState: null,
            changedSinceReview: false,
            uncertain: false,
          },
        ],
      },
    }),
  );
  await page.goto('/pull-requests/mine');
  await expect(page.getByText('My authored change')).toBeVisible();
  await page
    .getByRole('textbox', { name: 'Filter pull requests' })
    .fill('missing');
  await expect(page.getByText('No matching pull requests')).toBeVisible();
});
