import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { App } from '../../src/App';
import type { Inbox, Session } from '../../shared/types';
const connected: Session = {
  providers: { google: true, github: true },
  user: { id: '1', name: 'Lacko', provider: 'github' },
  github: { connected: true, login: 'lacko' },
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
  it('shows only Google/GitHub login and hides workspace until authenticated', async () => {
    mockApi({
      ...connected,
      user: null,
      github: { connected: false, login: null },
      providers: { google: false, github: false },
    });
    render(<App />);
    expect(screen.getByText('Checking sign-in options…')).toBeVisible();
    await screen.findByText('Google sign-in is not configured yet.');
    expect(
      screen.getByRole('button', { name: 'Sign in with Google' }),
    ).toBeDisabled();
    expect(
      screen.getByRole('button', { name: 'Sign in with GitHub' }),
    ).toBeDisabled();
    expect(screen.queryByRole('navigation')).not.toBeInTheDocument();
    expect(screen.queryByRole('textbox')).not.toBeInTheDocument();
    expect(window.location.pathname).toBe('/login');
  });
  it('offers exactly two configured sign-in providers and preserves a safe destination', async () => {
    window.history.replaceState({}, '', '/login?returnTo=/pull-requests/mine');
    mockApi({ ...connected, user: null });
    render(<App />);
    expect(
      await screen.findByRole('link', { name: 'Sign in with Google' }),
    ).toHaveAttribute('href', '/auth/google?returnTo=%2Fpull-requests%2Fmine');
    expect(
      screen.getByRole('link', { name: 'Sign in with GitHub' }),
    ).toHaveAttribute('href', '/auth/github?returnTo=%2Fpull-requests%2Fmine');
    expect(screen.queryByRole('textbox')).not.toBeInTheDocument();
  });
  it('lets Google users connect GitHub without treating sign-in as repository access', async () => {
    mockApi({
      ...connected,
      user: { id: '1', name: 'Lacko Google', provider: 'google' },
      github: { connected: false, login: null },
    });
    render(<App />);
    await screen.findByText('Connect your GitHub account');
    expect(screen.getByText('Google account')).toBeVisible();
    expect(
      screen.getByRole('link', { name: 'Connect GitHub' }),
    ).toHaveAttribute('href', '/auth/github?intent=connect');
    expect(fetch).not.toHaveBeenCalledWith('/api/inbox', expect.anything());
  });
  it('shows only the two pull request subpages and loads authored PRs separately', async () => {
    mockApi();
    vi.mocked(fetch).mockImplementation(async (path) =>
      response(
        path === '/api/session'
          ? connected
          : path === '/api/my-pulls'
            ? {
                ...inbox,
                pulls: [
                  {
                    ...base,
                    id: 4,
                    title: 'My own change',
                    author: 'lacko',
                    group: null,
                    personal: false,
                    teams: [],
                    changedSinceReview: false,
                    uncertain: false,
                  },
                ],
              }
            : inbox,
      ),
    );
    render(<App />);
    await screen.findByText('Fix authorization');
    for (const label of [
      'Publishing',
      'Results',
      'AI agents',
      'Review settings',
    ])
      expect(
        screen.queryByRole('button', { name: label }),
      ).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole('link', { name: 'My pull requests' }));
    expect(await screen.findByText('My own change')).toBeVisible();
    expect(screen.queryByText('Fix authorization')).not.toBeInTheDocument();
    expect(screen.queryByRole('tablist')).not.toBeInTheDocument();
    expect(window.location.pathname).toBe('/pull-requests/mine');
    expect(
      screen.getByRole('link', { name: 'My pull requests' }),
    ).toHaveAttribute('aria-current', 'page');
    fireEvent.click(screen.getByRole('link', { name: 'Review requests' }));
    await screen.findByText('Fix authorization');
    expect(screen.getByRole('tablist')).toBeVisible();
  });
  it('directly opens the authored page and handles empty results and filtering', async () => {
    window.history.replaceState({}, '', '/pull-requests/mine');
    mockApi(connected, { ...inbox, pulls: [], warnings: [] });
    vi.mocked(fetch).mockImplementation(async (path) =>
      response(
        path === '/api/session'
          ? connected
          : { ...inbox, pulls: [], warnings: [] },
      ),
    );
    render(<App />);
    expect(await screen.findByText('No open pull requests')).toBeVisible();
    expect(fetch).toHaveBeenCalledWith('/api/my-pulls', expect.anything());
    fireEvent.change(
      screen.getByRole('textbox', { name: 'Filter pull requests' }),
      { target: { value: 'missing' } },
    );
    expect(screen.getByText('No matching pull requests')).toBeVisible();
  });
  it('shows a sign-in explanation on the authored page', async () => {
    window.history.replaceState({}, '', '/pull-requests/mine');
    mockApi({ ...connected, user: null });
    render(<App />);
    expect(await screen.findByText('Welcome to AI Buddy')).toBeVisible();
  });
  it('does not replace a new page with a late response from the old page', async () => {
    let resolveInbox!: (value: Response) => void;
    const late = new Promise<Response>((resolve) => {
      resolveInbox = resolve;
    });
    vi.stubGlobal(
      'fetch',
      vi.fn(async (path: string) =>
        path === '/api/session'
          ? response(connected)
          : path === '/api/inbox'
            ? late
            : response({ ...inbox, pulls: [] }),
      ),
    );
    render(<App />);
    await waitFor(() =>
      expect(fetch).toHaveBeenCalledWith('/api/inbox', expect.anything()),
    );
    fireEvent.click(screen.getByRole('link', { name: 'My pull requests' }));
    await screen.findByText('No open pull requests');
    resolveInbox(response(inbox));
    await waitFor(() =>
      expect(screen.getByText('No open pull requests')).toBeVisible(),
    );
    expect(screen.queryByText('Fix authorization')).not.toBeInTheDocument();
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
    window.history.replaceState({}, '', '/login?auth=failed');
    mockApi({ ...connected, user: null });
    render(<App />);
    expect(screen.getByRole('alert')).toHaveTextContent(
      'Sign-in was cancelled or could not be completed',
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
      'We couldn’t check sign-in availability.',
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
    if (error === 'github_unauthorized')
      expect(
        screen.getByRole('link', { name: 'Reconnect GitHub' }),
      ).toHaveAttribute('href', '/auth/github?intent=connect');
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
