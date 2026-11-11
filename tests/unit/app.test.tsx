import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { App } from '../../src/App';
import type { Inbox, Session } from '../../shared/types';
const connected: Session = {
  configured: true,
  user: { login: 'lacko' },
  installUrl: 'https://github.com/apps/reviewer/installations/new',
};
const base = {
  id: 1,
  number: 42,
  title: 'Fix authorization',
  url: 'https://github.com/acme/api/pull/42',
  repository: 'acme/api',
  author: 'alice',
  updatedAt: '2026-11-11T10:00:00Z',
  draft: true,
  personal: true,
  teams: ['acme/backend'],
  reviewState: 'CHANGES_REQUESTED',
  changedSinceReview: true,
  uncertain: true,
};
const inbox: Inbox = {
  pulls: [
    { ...base, group: 'awaiting' },
    {
      ...base,
      id: 2,
      title: 'Improve search',
      group: 'waiting',
      personal: false,
      teams: [],
      reviewState: null,
      draft: false,
      changedSinceReview: false,
      uncertain: false,
    },
    { ...base, id: 3, group: 'requested-again' },
  ],
  warnings: ['Team access is incomplete.'],
  syncedAt: '2026-11-11T10:00:00Z',
};
const response = (data: unknown, ok = true) =>
  ({ ok, json: async () => data }) as Response;
function mockApi(session: Session = connected, data: Inbox = inbox) {
  return vi.stubGlobal(
    'fetch',
    vi.fn(async (path: string) =>
      response(
        path === '/api/session'
          ? session
          : path === '/api/inbox'
            ? data
            : { ok: true },
      ),
    ),
  );
}
beforeEach(() => {
  window.history.replaceState({}, '', '/');
});
afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

describe('workspace', () => {
  it('supports tab arrows, wrapping, Home and End with one tab stop', async () => {
    mockApi();
    render(<App />);
    await screen.findByText('Fix authorization');
    const first = screen.getByRole('tab', { name: /Awaiting my review/ });
    const last = screen.getByRole('tab', { name: /Review requested again/ });
    fireEvent.keyDown(first, { key: 'ArrowLeft' });
    expect(last).toHaveFocus();
    expect(last).toHaveAttribute('tabindex', '0');
    fireEvent.keyDown(last, { key: 'ArrowRight' });
    expect(first).toHaveFocus();
    fireEvent.keyDown(first, { key: 'End' });
    expect(last).toHaveFocus();
    fireEvent.keyDown(last, { key: 'Home' });
    expect(first).toHaveFocus();
    fireEvent.keyDown(first, { key: 'Escape' });
    expect(first).toHaveFocus();
  });
  it('shows loading, then a disconnected inbox with unknown counts', async () => {
    mockApi({ configured: false, user: null, installUrl: null });
    render(<App />);
    expect(screen.getByText('Loading your workspace')).toBeVisible();
    await screen.findByRole('button', {
      name: 'GitHub connection not configured',
    });
    expect(screen.getAllByText('—')).toHaveLength(3);
    expect(screen.getByRole('button', { name: 'Refresh' })).toBeDisabled();
  });
  it('offers configured GitHub sign-in without fabricating any PRs', async () => {
    mockApi({ ...connected, user: null });
    render(<App />);
    expect(
      await screen.findByRole('link', { name: 'Sign in with GitHub' }),
    ).toHaveAttribute('href', '/auth/github');
    expect(screen.queryByText('Fix authorization')).not.toBeInTheDocument();
  });
  it.each([
    ['Review settings', 'Review settings'],
    ['AI agents', 'AI agents'],
    ['Results', 'Review results'],
    ['Publishing', 'Publish a review'],
  ])('opens the %s placeholder and returns', async (label, title) => {
    mockApi();
    render(<App />);
    await screen.findByText('Fix authorization');
    const button = screen.getByRole('button', { name: label });
    fireEvent.click(button);
    expect(button).toHaveAttribute('aria-current', 'page');
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent(title);
    expect(
      screen.getByText(
        'This feature is a placeholder. No reviews are run or posted.',
      ),
    ).toBeVisible();
    fireEvent.click(screen.getByRole('button', { name: 'Pull requests' }));
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent(
      'Your review inbox',
    );
  });
  it('renders real PR details, group counts and separate commit/request flags', async () => {
    mockApi();
    render(<App />);
    await screen.findByText('Fix authorization');
    expect(screen.getByText('Personal request')).toBeVisible();
    expect(screen.getByText('Team · acme/backend')).toBeVisible();
    expect(screen.getByText('New commits since review')).toBeVisible();
    expect(screen.getByText('Request timing unconfirmed')).toBeVisible();
    expect(screen.getByText('Draft')).toBeVisible();
    expect(
      screen.getByRole('link', { name: 'Fix authorization' }),
    ).toHaveAttribute('href', base.url);
    expect(screen.getByText('Team access is incomplete.')).toBeVisible();
    fireEvent.click(screen.getByRole('tab', { name: /Reviewed · waiting/ }));
    expect(screen.getByText('Improve search')).toBeVisible();
    expect(screen.queryByText('Personal request')).not.toBeInTheDocument();
    fireEvent.click(
      screen.getByRole('tab', { name: /Review requested again/ }),
    );
    expect(screen.getByText('Fix authorization')).toBeVisible();
  });
  it('filters by repository, author, number and title and distinguishes empty states', async () => {
    mockApi();
    render(<App />);
    await screen.findByText('Fix authorization');
    const input = screen.getByRole('textbox', { name: 'Filter pull requests' });
    for (const value of ['ACME', 'alice', '#42', 'authorization']) {
      fireEvent.change(input, { target: { value } });
      expect(screen.getByText('Fix authorization')).toBeVisible();
    }
    fireEvent.change(input, { target: { value: 'missing' } });
    expect(screen.getByText('No matching pull requests')).toBeVisible();
    fireEvent.change(input, { target: { value: '' } });
    fireEvent.click(screen.getByRole('button', { name: 'Refresh' }));
    await screen.findByText('Fix authorization');
  });
  it('shows an empty group with known zero counts', async () => {
    mockApi(connected, { ...inbox, pulls: [], warnings: [] });
    render(<App />);
    expect(await screen.findByText('You’re all caught up here')).toBeVisible();
    expect(screen.getAllByText('0')).toHaveLength(3);
  });
  it('shows authentication cancellation', async () => {
    window.history.replaceState({}, '', '/?auth=failed');
    mockApi({ ...connected, user: null });
    render(<App />);
    expect(screen.getByRole('alert')).toHaveTextContent(
      'GitHub sign-in was cancelled or failed',
    );
    await screen.findByRole('link', { name: 'Sign in with GitHub' });
  });
  it('handles network failure and retry', async () => {
    vi.stubGlobal(
      'fetch',
      vi
        .fn()
        .mockRejectedValueOnce(new Error('offline'))
        .mockResolvedValue(response({ ...connected, user: null })),
    );
    render(<App />);
    expect(await screen.findByRole('alert')).toHaveTextContent(
      'Something went wrong',
    );
    fireEvent.click(screen.getByRole('button', { name: 'Try again' }));
    await screen.findByRole('link', { name: 'Sign in with GitHub' });
    expect(screen.queryByRole('alert')).not.toBeInTheDocument();
  });
  it.each([
    'unauthenticated',
    'github_unauthorized',
    'github_permissions',
    'rate_limited',
    'github_unavailable',
  ])('shows actionable %s errors', async (error) => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async (path: string) =>
        path === '/api/session'
          ? response(connected)
          : response({ error }, false),
      ),
    );
    render(<App />);
    await screen.findByRole('alert');
    if (['unauthenticated', 'github_unauthorized'].includes(error))
      expect(
        screen.getByRole('link', { name: 'Sign in again' }),
      ).toHaveAttribute('href', '/auth/github');
    expect(
      screen.queryByText('You’re all caught up here'),
    ).not.toBeInTheDocument();
  });
  it('handles malformed errors and non-Error failures', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValueOnce({
        ok: false,
        json: async () => {
          throw new Error('bad json');
        },
      }),
    );
    const { unmount } = render(<App />);
    await screen.findByRole('alert');
    unmount();
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue('offline'));
    render(<App />);
    await screen.findByRole('alert');
  });
  it('signs out and clears previously loaded private PRs', async () => {
    mockApi();
    render(<App />);
    await screen.findByText('Fix authorization');
    fireEvent.click(screen.getByRole('button', { name: 'Sign out' }));
    await screen.findByRole('link', { name: 'Sign in with GitHub' });
    expect(screen.queryByText('Fix authorization')).not.toBeInTheDocument();
    expect(fetch).toHaveBeenCalledWith(
      '/api/logout',
      expect.objectContaining({ method: 'POST' }),
    );
  });
  it('keeps the account visible if logout fails', async () => {
    mockApi();
    render(<App />);
    await screen.findByText('Fix authorization');
    vi.mocked(fetch).mockRejectedValueOnce(new Error('offline'));
    fireEvent.click(screen.getByRole('button', { name: 'Sign out' }));
    await waitFor(() => expect(screen.getByRole('alert')).toBeVisible());
    expect(screen.getByRole('button', { name: 'Sign out' })).toBeEnabled();
  });
});
