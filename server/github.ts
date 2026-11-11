import type { Inbox, PullRequest } from '../shared/types.js';

export class GitHubError extends Error {
  constructor(
    public status: number,
    public code: string,
  ) {
    super(code);
  }
}
type User = { login: string };
type Team = { id: number; slug: string; organization: { login: string } };
type Review = {
  user: User;
  state: string;
  submitted_at: string | null;
  commit_id: string;
};
type Event = {
  event: string;
  created_at: string;
  requested_reviewer?: User;
  requested_team?: { id: number };
};
type Pull = {
  id: number;
  number: number;
  title: string;
  html_url: string;
  user: User;
  updated_at: string;
  draft: boolean;
  state: string;
  head: { sha: string };
  requested_reviewers: User[];
  requested_teams: { id: number }[];
};
type SearchItem = { number: number; repository_url: string };
type SearchResult = {
  total_count: number;
  incomplete_results: boolean;
  items: SearchItem[];
};

export function classify(
  pull: Pull,
  reviews: Review[],
  events: Event[],
  login: string,
  teams: Team[],
  repository: string,
): PullRequest | null {
  if (pull.state !== 'open') return null;
  const personal = pull.requested_reviewers.some(
    (u) => u.login.toLowerCase() === login.toLowerCase(),
  );
  const requestedTeams = teams.filter((team) =>
    pull.requested_teams.some((t) => t.id === team.id),
  );
  const review = reviews
    .filter(
      (r) =>
        r.user.login.toLowerCase() === login.toLowerCase() &&
        r.state !== 'PENDING' &&
        r.submitted_at,
    )
    .sort(
      (a, b) => Date.parse(b.submitted_at!) - Date.parse(a.submitted_at!),
    )[0];
  const requested = personal || requestedTeams.length > 0;
  if (!review && !requested) return null;
  const relevantRequests = events.filter(
    (event) =>
      event.event === 'review_requested' &&
      ((personal &&
        event.requested_reviewer?.login.toLowerCase() ===
          login.toLowerCase()) ||
        requestedTeams.some((t) => t.id === event.requested_team?.id)),
  );
  const newRequest = relevantRequests.some(
    (event) =>
      !review ||
      Date.parse(event.created_at) > Date.parse(review.submitted_at!),
  );
  return {
    id: pull.id,
    number: pull.number,
    title: pull.title,
    url: pull.html_url,
    repository,
    author: pull.user.login,
    updatedAt: pull.updated_at,
    draft: pull.draft,
    group: !review
      ? 'awaiting'
      : requested && newRequest
        ? 'requested-again'
        : 'waiting',
    personal,
    teams: requestedTeams.map((t) => `${t.organization.login}/${t.slug}`),
    reviewState: review?.state ?? null,
    changedSinceReview: Boolean(review && review.commit_id !== pull.head.sha),
    uncertain: Boolean(review && requested && relevantRequests.length === 0),
  };
}

export class GitHub {
  constructor(private fetcher: typeof fetch = fetch) {}
  async request<T>(
    url: string,
    token?: string,
    body?: Record<string, string>,
  ): Promise<T> {
    let response: Response;
    try {
      response = await this.fetcher(url, {
        method: body ? 'POST' : 'GET',
        redirect: 'error',
        signal: AbortSignal.timeout(15000),
        headers: {
          Accept: 'application/json',
          ...(token
            ? {
                Authorization: `Bearer ${token}`,
                'X-GitHub-Api-Version': '2022-11-28',
              }
            : {}),
          ...(body ? { 'Content-Type': 'application/json' } : {}),
        },
        ...(body ? { body: JSON.stringify(body) } : {}),
      });
    } catch {
      throw new GitHubError(502, 'github_unavailable');
    }
    if (!response.ok) {
      const rateLimited =
        response.status === 429 ||
        (response.status === 403 &&
          (response.headers.get('x-ratelimit-remaining') === '0' ||
            response.headers.has('retry-after')));
      throw new GitHubError(
        response.status,
        rateLimited
          ? 'rate_limited'
          : response.status === 401
            ? 'github_unauthorized'
            : response.status === 403 || response.status === 404
              ? 'github_permissions'
              : 'github_unavailable',
      );
    }
    try {
      return (await response.json()) as T;
    } catch {
      throw new GitHubError(502, 'github_unavailable');
    }
  }
  async exchange(
    code: string,
    clientId: string,
    clientSecret: string,
    redirectUri: string,
  ) {
    const token = await this.request<{
      access_token?: string;
      expires_in?: number;
      error?: string;
    }>('https://github.com/login/oauth/access_token', undefined, {
      code,
      client_id: clientId,
      client_secret: clientSecret,
      redirect_uri: redirectUri,
    });
    if (!token.access_token || token.error)
      throw new GitHubError(401, 'github_unauthorized');
    return {
      accessToken: token.access_token,
      ttl: Math.min(token.expires_in ?? 28800, 28800),
    };
  }
  user(token: string) {
    return this.request<User>('https://api.github.com/user', token);
  }

  async inbox(token: string, login: string): Promise<Inbox> {
    const warnings = new Set<string>();
    const list = async <T>(path: string): Promise<T[]> => {
      const items: T[] = [];
      for (let page = 1; page <= 100; page++) {
        const batch = await this.request<T[]>(
          `https://api.github.com${path}${path.includes('?') ? '&' : '?'}per_page=100&page=${page}`,
          token,
        );
        items.push(...batch);
        if (batch.length < 100) return items;
      }
      warnings.add(
        'Some GitHub history exceeded the pagination limit; classification may be incomplete.',
      );
      return items;
    };
    let teams: Team[] = [];
    try {
      teams = await list<Team>('/user/teams');
    } catch (error) {
      if (
        !(error instanceof GitHubError) ||
        error.code !== 'github_permissions'
      )
        throw error;
      warnings.add(
        'Team membership is unavailable. Check organization approval and Members read permission. Team requests may be missing.',
      );
    }
    const candidates = new Map<string, SearchItem>();
    const queries = [
      `is:pr is:open review-requested:${login}`,
      `is:pr is:open reviewed-by:${login}`,
      ...teams.map(
        (t) =>
          `is:pr is:open team-review-requested:${t.organization.login}/${t.slug}`,
      ),
    ];
    for (const query of queries) {
      for (let page = 1; page <= 10; page++) {
        const result = await this.request<SearchResult>(
          `https://api.github.com/search/issues?q=${encodeURIComponent(query)}&per_page=100&page=${page}`,
          token,
        );
        if (result.incomplete_results || result.total_count > 1000)
          warnings.add(
            'GitHub search returned partial results. Some pull requests may be missing.',
          );
        for (const item of result.items)
          candidates.set(`${item.repository_url}/${item.number}`, item);
        if (page * 100 >= result.total_count || result.items.length < 100)
          break;
      }
    }
    const pulls: PullRequest[] = [];
    const pending = [...candidates.values()];
    const worker = async () => {
      while (pending.length) {
        const item = pending.shift()!;
        const match =
          /^https:\/\/api\.github\.com\/repos\/([\w.-]+\/[\w.-]+)$/.exec(
            item.repository_url,
          );
        if (!match) throw new GitHubError(502, 'github_unavailable');
        const repository = match[1];
        const path = `/repos/${repository}`;
        try {
          const pull = await this.request<Pull>(
            `https://api.github.com${path}/pulls/${item.number}`,
            token,
          );
          const reviews = await list<Review>(
            `${path}/pulls/${item.number}/reviews`,
          );
          const events = await list<Event>(
            `${path}/issues/${item.number}/timeline`,
          );
          const classified = classify(
            pull,
            reviews,
            events,
            login,
            teams,
            repository,
          );
          if (classified) pulls.push(classified);
        } catch (error) {
          if (
            !(error instanceof GitHubError) ||
            error.code !== 'github_permissions'
          )
            throw error;
          warnings.add(
            `Cannot read ${repository}#${item.number}. Check repository access and Pull requests/Issues read permissions.`,
          );
        }
      }
    };
    await Promise.all(
      Array.from({ length: Math.min(3, pending.length) }, worker),
    );
    pulls.sort((a, b) => Date.parse(b.updatedAt) - Date.parse(a.updatedAt));
    return {
      pulls,
      warnings: [...warnings],
      syncedAt: new Date().toISOString(),
    };
  }
}
