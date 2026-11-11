import { expect, test } from '@playwright/test';

test('production build exposes health and honest anonymous session', async ({
  request,
}) => {
  const response = await request.get('/healthz');
  expect(response.status()).toBe(200);
  expect(await response.json()).toEqual({ status: 'ok' });
  expect((await request.get('/api/missing')).status()).toBe(404);
  expect((await request.get('/missing.js')).status()).toBe(404);
  expect((await request.get('/api/inbox')).status()).toBe(401);
  expect((await request.get('/api/my-pulls')).status()).toBe(401);
  expect((await request.get('/pull-requests/mine')).status()).toBe(200);
  expect((await request.get('/pull-requests/review-requests')).status()).toBe(
    200,
  );
  const session = await request.get('/api/session');
  expect(await session.json()).toEqual({
    configured: false,
    user: null,
    installUrl: null,
  });
  expect(session.headers()['cache-control']).toBe('no-store');
});

test('shows only pull request subpages and preserves Focus design', async ({
  page,
}) => {
  await page.goto('/');
  await expect(page).toHaveTitle('PR Reviewer');
  await expect(page.getByRole('heading', { level: 1 })).toHaveText(
    'Your review inbox',
  );
  for (const name of [
    'Publishing',
    'Results',
    'AI agents',
    'Review settings',
  ]) {
    await expect(
      page.getByRole('navigation').getByText(name, { exact: true }),
    ).toHaveCount(0);
  }
  expect(
    await page
      .locator('.shell')
      .evaluate((el) => getComputedStyle(el).borderRadius),
  ).toBe('15px');
  expect(
    await page
      .locator('.shell')
      .evaluate((el) => getComputedStyle(el).backgroundColor),
  ).toBe('rgb(249, 249, 252)');
  await page
    .getByRole('link', { name: 'My pull requests', exact: true })
    .click();
  await expect(page).toHaveURL(/\/pull-requests\/mine$/);
  await expect(page.getByRole('heading', { level: 1 })).toHaveText(
    'My pull requests',
  );
  await expect(page.getByRole('tablist')).toHaveCount(0);
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

test('keeps subpage navigation usable on mobile', async ({ page }) => {
  await page.setViewportSize({ width: 375, height: 812 });
  await page.goto('/pull-requests/mine');
  await page
    .getByRole('link', { name: 'Review requests', exact: true })
    .click();
  await expect(page.getByRole('heading', { level: 1 })).toHaveText(
    'Your review inbox',
  );
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth,
    ),
  ).toBe(true);
  await page.screenshot({ path: 'test-results/mobile.png', fullPage: true });
});

test('shows PRs, switches groups and filters without exposing tokens', async ({
  page,
}) => {
  await page.route('**/api/session', (route) =>
    route.fulfill({
      json: { configured: true, user: { login: 'lacko' }, installUrl: null },
    }),
  );
  await page.route('**/api/inbox', (route) =>
    route.fulfill({
      json: {
        pulls: [
          {
            id: 1,
            number: 42,
            title: 'Preserve permissions during migration',
            repository: 'acme/api',
            author: 'alice',
            url: 'https://github.com/acme/api/pull/42',
            updatedAt: '2026-11-11T10:00:00Z',
            draft: false,
            group: 'awaiting',
            personal: true,
            teams: ['acme/backend'],
            reviewState: null,
            changedSinceReview: false,
            uncertain: false,
          },
          {
            id: 2,
            number: 43,
            title: 'Handle failed synchronization',
            repository: 'acme/api',
            author: 'bob',
            url: 'https://github.com/acme/api/pull/43',
            updatedAt: '2026-11-11T10:00:00Z',
            draft: true,
            group: 'requested-again',
            personal: false,
            teams: ['acme/backend'],
            reviewState: 'CHANGES_REQUESTED',
            changedSinceReview: true,
            uncertain: false,
          },
        ],
        warnings: [],
        syncedAt: '2026-11-11T10:00:00Z',
      },
    }),
  );
  await page.goto('/');
  await expect(
    page.getByText('Preserve permissions during migration'),
  ).toBeVisible();
  await page.screenshot({ path: 'test-results/desktop.png', fullPage: true });
  await page
    .getByRole('textbox', { name: 'Filter pull requests' })
    .fill('missing');
  await expect(page.getByText('No matching pull requests')).toBeVisible();
  await page.getByRole('textbox', { name: 'Filter pull requests' }).fill('');
  await page.getByRole('tab', { name: /Review requested again/ }).click();
  await expect(page.getByText('Handle failed synchronization')).toBeVisible();
  await expect(page.getByText('New commits since review')).toBeVisible();
  await page.getByRole('tab', { name: /Reviewed · waiting/ }).click();
  await expect(page.getByText('You’re all caught up here')).toBeVisible();
});

test('makes tabs and actions accessible by keyboard', async ({ page }) => {
  await page.goto('/');
  const tab = page.getByRole('tab', { name: /Reviewed · waiting/ });
  await tab.focus();
  await page.keyboard.press('Enter');
  await expect(tab).toHaveAttribute('aria-selected', 'true');
  const button = page.getByRole('link', {
    name: 'My pull requests',
    exact: true,
  });
  await button.focus();
  await page.keyboard.press('Enter');
  await expect(page.getByRole('heading', { level: 1 })).toHaveText(
    'My pull requests',
  );
});

test('lists and filters only authored PRs on their dedicated page', async ({
  page,
}) => {
  await page.route('**/api/session', (route) =>
    route.fulfill({
      json: { configured: true, user: { login: 'lacko' }, installUrl: null },
    }),
  );
  await page.route('**/api/my-pulls', (route) =>
    route.fulfill({
      json: {
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
        warnings: [],
        syncedAt: '2026-11-11T10:00:00Z',
      },
    }),
  );
  await page.goto('/pull-requests/mine');
  await expect(page.getByText('My authored change')).toBeVisible();
  await expect(page.getByRole('tablist')).toHaveCount(0);
  await expect(page.getByText('Draft', { exact: true })).toBeVisible();
  await page
    .getByRole('textbox', { name: 'Filter pull requests' })
    .fill('missing');
  await expect(page.getByText('No matching pull requests')).toBeVisible();
  await page.getByRole('button', { name: 'Refresh' }).click();
  await expect(page.getByText('No matching pull requests')).toBeVisible();
  await page.getByRole('textbox', { name: 'Filter pull requests' }).fill('');
  await expect(page.getByText('My authored change')).toBeVisible();
  await page.screenshot({ path: 'test-results/my-pulls.png', fullPage: true });
});
