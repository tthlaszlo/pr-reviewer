// @vitest-environment node
import { describe, expect, it, vi } from 'vitest';
import { classify, GitHub } from '../../server/github';

const pull = {
  id: 1,
  number: 10,
  title: 'Fix authorization',
  html_url: 'https://github.com/acme/api/pull/10',
  user: { login: 'author' },
  updated_at: '2026-11-11T12:00:00Z',
  draft: false,
  state: 'open',
  head: { sha: 'new' },
  requested_reviewers: [{ login: 'lacko' }],
  requested_teams: [] as { id: number }[],
};
const review = {
  user: { login: 'lacko' },
  state: 'APPROVED',
  submitted_at: '2026-11-10T12:00:00Z',
  commit_id: 'old',
};
const team = { id: 42, slug: 'backend', organization: { login: 'acme' } };
const request = {
  event: 'review_requested',
  created_at: '2026-11-11T12:00:00Z',
  requested_reviewer: { login: 'lacko' },
};
const classifyPR = (
  p = pull,
  reviews = [] as (typeof review)[],
  events = [] as (typeof request)[],
) => classify(p, reviews, events, 'lacko', [team], 'acme/api');
const json = (value: unknown, status = 200, headers?: Record<string, string>) =>
  new Response(JSON.stringify(value), { status, headers });

describe('review classification', () => {
  it('recognizes personal requests case-insensitively', () => {
    expect(
      classifyPR({ ...pull, requested_reviewers: [{ login: 'LACKO' }] }),
    ).toMatchObject({
      group: 'awaiting',
      personal: true,
      reviewState: null,
      teams: [],
    });
  });
  it('recognizes team requests without requiring a personal invitation', () => {
    expect(
      classifyPR({
        ...pull,
        requested_reviewers: [],
        requested_teams: [{ id: 42 }],
      }),
    ).toMatchObject({
      group: 'awaiting',
      personal: false,
      teams: ['acme/backend'],
    });
  });
  it('does not mistake a teammate review or a pending draft for my submitted review', () => {
    expect(
      classifyPR(pull, [
        { ...review, user: { login: 'other' } },
        {
          ...review,
          state: 'PENDING',
          submitted_at: null,
        } as unknown as typeof review,
      ]),
    ).toMatchObject({ group: 'awaiting' });
  });
  it('keeps reviewed PRs after the review request disappears and flags new commits', () => {
    expect(
      classifyPR({ ...pull, requested_reviewers: [] }, [review]),
    ).toMatchObject({ group: 'waiting', changedSinceReview: true });
    expect(
      classifyPR({ ...pull, requested_reviewers: [], head: { sha: 'old' } }, [
        review,
      ]),
    ).toMatchObject({ changedSinceReview: false });
  });
  it('identifies requests made after my latest submitted review', () => {
    expect(classifyPR(pull, [review], [request])).toMatchObject({
      group: 'requested-again',
      uncertain: false,
    });
    const later = { ...review, submitted_at: '2026-11-12T12:00:00Z' };
    expect(classifyPR(pull, [review, later], [request])).toMatchObject({
      group: 'waiting',
      uncertain: false,
    });
  });
  it('recognizes team re-requests and ignores unrelated history', () => {
    const result = classify(
      { ...pull, requested_reviewers: [], requested_teams: [{ id: 42 }] },
      [review],
      [
        {
          event: 'review_requested',
          created_at: request.created_at,
          requested_team: { id: 42 },
        },
      ],
      'lacko',
      [team],
      'acme/api',
    );
    expect(result?.group).toBe('requested-again');
    expect(
      classifyPR(
        pull,
        [review],
        [{ ...request, requested_reviewer: { login: 'other' } }],
      )?.group,
    ).toBe('waiting');
    expect(
      classifyPR(pull, [review], [{ ...request, event: 'committed' }])?.group,
    ).toBe('waiting');
  });
  it('does not confuse a removed personal re-request with a standing team request', () => {
    expect(
      classifyPR(
        { ...pull, requested_reviewers: [], requested_teams: [{ id: 42 }] },
        [review],
        [request],
      ),
    ).toMatchObject({ group: 'waiting', uncertain: true });
    expect(classifyPR(pull, [review], [])).toMatchObject({
      group: 'waiting',
      uncertain: true,
    });
  });
  it('ignores closed and irrelevant PRs', () => {
    expect(classifyPR({ ...pull, state: 'closed' })).toBeNull();
    expect(
      classifyPR({
        ...pull,
        requested_reviewers: [],
        requested_teams: [{ id: 99 }],
      }),
    ).toBeNull();
  });
});

describe('GitHub integration', () => {
  it('finds only my open PRs without fetching team membership or review history', async () => {
    const fetcher = vi.fn<typeof fetch>(async (input) => {
      const url = String(input);
      if (url.includes('/search/issues')) {
        expect(decodeURIComponent(url)).toContain('is:pr is:open author:lacko');
        return json({
          total_count: 3,
          incomplete_results: false,
          items: [1, 2, 3].map((number) => ({
            repository_url: 'https://api.github.com/repos/acme/api',
            number,
          })),
        });
      }
      const number = Number(url.split('/').at(-1));
      return json({
        ...pull,
        id: number,
        number,
        user: { login: number === 2 ? 'other' : 'LACKO' },
        state: number === 3 ? 'closed' : 'open',
      });
    });
    const result = await new GitHub(fetcher).inbox(
      'token',
      'lacko',
      'authored',
    );
    expect(result.pulls).toHaveLength(1);
    expect(result.pulls[0]).toMatchObject({
      id: 1,
      author: 'LACKO',
      group: null,
      teams: [],
      personal: false,
    });
    expect(
      fetcher.mock.calls.some(([url]) =>
        /user\/teams|reviews|timeline/.test(String(url)),
      ),
    ).toBe(false);
  });

  it('exchanges codes, caps session duration and fetches user identity', async () => {
    const fetcher = vi
      .fn<typeof fetch>()
      .mockResolvedValueOnce(
        json({ access_token: 'token', expires_in: 999999 }),
      )
      .mockResolvedValueOnce(json({ login: 'lacko' }));
    const github = new GitHub(fetcher);
    expect(
      await github.exchange(
        'code',
        'id',
        'secret',
        'http://localhost/callback',
      ),
    ).toEqual({ accessToken: 'token', ttl: 28800 });
    expect(await github.user('token')).toEqual({ login: 'lacko' });
    expect(fetcher.mock.calls[0][1]?.body).toContain('redirect_uri');
    expect(fetcher.mock.calls[1][1]?.headers).toMatchObject({
      Authorization: 'Bearer token',
    });
  });
  it('supports non-expiring tokens with an eight-hour local session', async () => {
    expect(
      await new GitHub(
        vi.fn().mockResolvedValue(json({ access_token: 'token' })),
      ).exchange('c', 'i', 's', 'u'),
    ).toEqual({ accessToken: 'token', ttl: 28800 });
  });
  it.each([{ error: 'bad_code' }, {}])(
    'rejects unsuccessful exchange %j',
    async (value) => {
      await expect(
        new GitHub(vi.fn().mockResolvedValue(json(value))).exchange(
          'c',
          'i',
          's',
          'u',
        ),
      ).rejects.toMatchObject({ code: 'github_unauthorized' });
    },
  );
  it.each([
    [401, {}, 'github_unauthorized'],
    [403, {}, 'github_permissions'],
    [404, {}, 'github_permissions'],
    [429, {}, 'rate_limited'],
    [403, { 'x-ratelimit-remaining': '0' }, 'rate_limited'],
    [403, { 'retry-after': '60' }, 'rate_limited'],
    [500, {}, 'github_unavailable'],
  ] as const)('maps upstream HTTP %i', async (status, headers, code) => {
    await expect(
      new GitHub(vi.fn().mockResolvedValue(json({}, status, headers))).user(
        't',
      ),
    ).rejects.toMatchObject({ code });
  });
  it('handles network failures and invalid JSON', async () => {
    await expect(
      new GitHub(vi.fn().mockRejectedValue(new Error('offline'))).user('t'),
    ).rejects.toMatchObject({ code: 'github_unavailable' });
    await expect(
      new GitHub(vi.fn().mockResolvedValue(new Response('bad'))).user('t'),
    ).rejects.toMatchObject({ code: 'github_unavailable' });
  });
  it('deduplicates search results, paginates history and keeps reviewed PRs', async () => {
    let reviewPages = 0;
    const fetcher = vi.fn<typeof fetch>(async (input) => {
      const url = new URL(String(input));
      if (url.pathname === '/user/teams') return json([team]);
      if (url.pathname === '/search/issues')
        return json({
          total_count: 2,
          incomplete_results: false,
          items: [
            {
              repository_url: 'https://api.github.com/repos/acme/api',
              number: 10,
            },
            {
              repository_url: 'https://api.github.com/repos/acme/api',
              number: 11,
            },
          ],
        });
      if (url.pathname.endsWith('/reviews')) {
        reviewPages++;
        return json(
          url.searchParams.get('page') === '1'
            ? Array.from({ length: 100 }, () => review)
            : [],
        );
      }
      if (url.pathname.endsWith('/timeline')) return json([request]);
      return json({
        ...pull,
        id: Number(url.pathname.split('/').at(-1)),
        requested_reviewers: [],
        updated_at: url.pathname.endsWith('11')
          ? '2026-11-12T00:00:00Z'
          : pull.updated_at,
      });
    });
    const data = await new GitHub(fetcher).inbox('token', 'lacko');
    expect(data.pulls).toHaveLength(2);
    expect(data.pulls[0].id).toBe(11);
    expect(data.pulls.every((pr) => pr.group === 'waiting')).toBe(true);
    expect(reviewPages).toBe(4);
    expect(data.warnings).toEqual([]);
    expect(
      fetcher.mock.calls.some(([url]) =>
        decodeURIComponent(String(url)).includes(
          'team-review-requested:acme/backend',
        ),
      ),
    ).toBe(true);
  });
  it('reports unavailable team membership and partial search results', async () => {
    const fetcher = vi.fn<typeof fetch>(async (input) => {
      if (String(input).includes('/user/teams')) return json({}, 403);
      return json({ total_count: 1001, incomplete_results: true, items: [] });
    });
    const data = await new GitHub(fetcher).inbox('t', 'lacko');
    expect(data.pulls).toEqual([]);
    expect(data.warnings).toHaveLength(2);
  });
  it('reports missing repository permissions without pretending that sync was complete', async () => {
    const fetcher = vi.fn<typeof fetch>(async (input) => {
      const url = String(input);
      if (url.includes('/user/teams')) return json([]);
      if (url.includes('/search/issues'))
        return json({
          total_count: 1,
          incomplete_results: false,
          items: [
            {
              repository_url: 'https://api.github.com/repos/acme/api',
              number: 10,
            },
          ],
        });
      return json({}, 404);
    });
    expect(
      (await new GitHub(fetcher).inbox('t', 'lacko')).warnings[0],
    ).toContain('Cannot read acme/api#10');
  });
  it('propagates token expiry and rejects unexpected repository URLs', async () => {
    await expect(
      new GitHub(vi.fn().mockResolvedValue(json({}, 401))).inbox('t', 'lacko'),
    ).rejects.toMatchObject({ code: 'github_unauthorized' });
    const fetcher = vi.fn<typeof fetch>(async (input) =>
      String(input).includes('/user/teams')
        ? json([])
        : json({
            total_count: 1,
            items: [
              {
                repository_url: 'https://evil.example/repos/acme/api',
                number: 1,
              },
            ],
          }),
    );
    await expect(new GitHub(fetcher).inbox('t', 'lacko')).rejects.toMatchObject(
      { code: 'github_unavailable' },
    );
    expect(
      fetcher.mock.calls.every(([url]) =>
        String(url).startsWith('https://api.github.com/'),
      ),
    ).toBe(true);
  });
  it('propagates non-permission errors during PR enrichment', async () => {
    const fetcher = vi.fn<typeof fetch>(async (input) => {
      if (String(input).includes('/user/teams')) return json([]);
      if (String(input).includes('/search/issues'))
        return json({
          total_count: 1,
          items: [
            {
              repository_url: 'https://api.github.com/repos/acme/api',
              number: 1,
            },
          ],
        });
      return json({}, 500);
    });
    await expect(new GitHub(fetcher).inbox('t', 'lacko')).rejects.toMatchObject(
      { code: 'github_unavailable' },
    );
  });
});
