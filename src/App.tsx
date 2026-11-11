import { useEffect, useState, useRef } from 'react';
import {
  GitPullRequest,
  Inbox as InboxIcon,
  UserRound,
  Bot,
  RefreshCw,
  GitBranch as Github,
  ExternalLink,
  LogOut,
  Search,
  CircleAlert,
} from 'lucide-react';
import type { Group, Inbox, Session } from '../shared/types';

const sections = {
  inbox: {
    label: 'Review requests',
    icon: InboxIcon,
    path: '/pull-requests/review-requests',
    title: 'Your review inbox',
    description: 'Personal and team review requests, in one place.',
  },
  mine: {
    label: 'My pull requests',
    icon: UserRound,
    path: '/pull-requests/mine',
    title: 'My pull requests',
    description: 'Your open pull requests across accessible repositories.',
  },
} as const;
type Page = keyof typeof sections;
const pageFromPath = (): Page =>
  window.location.pathname === sections.mine.path ? 'mine' : 'inbox';
const groups: { id: Group; label: string }[] = [
  { id: 'awaiting', label: 'Awaiting my review' },
  { id: 'waiting', label: 'Reviewed · waiting' },
  { id: 'requested-again', label: 'Review requested again' },
];
const messages: Record<string, string> = {
  unauthenticated: 'Your session has expired. Sign in to GitHub again.',
  github_unauthorized:
    'GitHub access has expired or been revoked. Sign in again.',
  github_permissions:
    'GitHub access is incomplete. Check the app installation and organization approval.',
  rate_limited: 'GitHub is limiting requests. Wait a minute before refreshing.',
  github_unavailable: 'GitHub is unavailable. Please try again.',
};
async function api<T>(path: string, method = 'GET'): Promise<T> {
  const response = await fetch(path, { method, credentials: 'same-origin' });
  if (!response.ok) {
    const body = (await response.json().catch(() => ({}))) as {
      error?: string;
    };
    throw new Error(body.error || 'service_unavailable');
  }
  return response.json() as Promise<T>;
}
export function App() {
  const [section, setSection] = useState<Page>(pageFromPath);
  const [group, setGroup] = useState<Group>('awaiting');
  const [session, setSession] = useState<Session | null>(null);
  const [inbox, setInbox] = useState<Inbox | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [filter, setFilter] = useState('');
  const [loggingOut, setLoggingOut] = useState(false);
  const current = sections[section];
  const requestId = useRef(0);
  function changePage(page: Page) {
    if (page === section) return;
    requestId.current++;
    setInbox(null);
    setLoading(true);
    setSection(page);
  }
  async function load(page: Page = section) {
    const id = ++requestId.current;
    setLoading(true);
    setError('');
    try {
      const value = await api<Session>('/api/session');
      if (id !== requestId.current) return;
      setSession(value);
      const data = value.user
        ? await api<Inbox>(page === 'mine' ? '/api/my-pulls' : '/api/inbox')
        : null;
      if (id === requestId.current) setInbox(data);
    } catch (cause) {
      if (id === requestId.current)
        setError(
          cause instanceof Error ? cause.message : 'service_unavailable',
        );
    } finally {
      if (id === requestId.current) setLoading(false);
    }
  }
  useEffect(() => {
    const onPopState = () => changePage(pageFromPath());
    window.addEventListener('popstate', onPopState);
    return () => window.removeEventListener('popstate', onPopState);
  }, [section]);
  useEffect(() => {
    setInbox(null);
    setFilter('');
    void load(section);
  }, [section]);
  async function logout() {
    setLoggingOut(true);
    try {
      await api('/api/logout', 'POST');
      requestId.current++;
      setLoading(false);
      setSession((value) => (value ? { ...value, user: null } : value));
      setInbox(null);
      setError('');
    } catch {
      setError('Could not sign out. Please try again.');
    } finally {
      setLoggingOut(false);
    }
  }
  const rows =
    inbox?.pulls.filter(
      (pr) =>
        (section === 'mine' || pr.group === group) &&
        `${pr.title} ${pr.repository} ${pr.author} #${pr.number}`
          .toLowerCase()
          .includes(filter.toLowerCase()),
    ) ?? [];
  return (
    <div className="shell">
      <aside>
        <a className="brand" href="/">
          <Bot size={22} />
          <span>
            AI Buddy<small>DEVELOPER TOOLS</small>
          </span>
        </a>
        <div className="workspace-label">TOOLS</div>
        <nav aria-label="Main navigation">
          <div className="nav-parent">
            <GitPullRequest size={16} />
            Pull requests
          </div>
          {Object.entries(sections).map(([key, value]) => {
            const Icon = value.icon;
            return (
              <a
                key={key}
                href={value.path}
                aria-current={section === key ? 'page' : undefined}
                onClick={(event) => {
                  if (
                    event.button !== 0 ||
                    event.metaKey ||
                    event.ctrlKey ||
                    event.shiftKey ||
                    event.altKey
                  )
                    return;
                  event.preventDefault();
                  window.history.pushState({}, '', value.path);
                  changePage(key as Page);
                }}
              >
                <Icon size={16} />
                {value.label}
              </a>
            );
          })}
        </nav>
        <div className="account">
          <Github size={17} />
          <span>
            {session?.user?.login ?? 'GitHub not connected'}
            <small>
              {session?.user
                ? 'Connected account'
                : 'Connect your account to begin'}
            </small>
          </span>
          {session?.user && (
            <button
              className="icon-button"
              onClick={() => void logout()}
              disabled={loggingOut}
              aria-label="Sign out"
            >
              <LogOut size={16} />
            </button>
          )}
        </div>
      </aside>
      <main>
        <div className="breadcrumb">
          Pull requests <span>/</span> {current.label}
        </div>
        <header>
          <div>
            <h1 id="page-title">{current.title}</h1>
            <p className="intro">{current.description}</p>
          </div>
          {
            <button
              className="secondary"
              disabled={loading || !session?.user}
              onClick={() => void load()}
            >
              <RefreshCw size={15} className={loading ? 'spinning' : ''} />
              Refresh
            </button>
          }
        </header>
        {
          <>
            {section === 'inbox' && (
              <div
                className="tabs"
                role="tablist"
                aria-label="Review request groups"
              >
                {groups.map((item) => (
                  <button
                    key={item.id}
                    id={`tab-${item.id}`}
                    role="tab"
                    aria-selected={group === item.id}
                    aria-controls="pull-list"
                    tabIndex={group === item.id ? 0 : -1}
                    onKeyDown={(event) => {
                      const index = groups.findIndex(
                        (entry) => entry.id === item.id,
                      );
                      const next =
                        event.key === 'ArrowRight'
                          ? (index + 1) % groups.length
                          : event.key === 'ArrowLeft'
                            ? (index + groups.length - 1) % groups.length
                            : event.key === 'Home'
                              ? 0
                              : event.key === 'End'
                                ? groups.length - 1
                                : null;
                      if (next === null) return;
                      event.preventDefault();
                      setGroup(groups[next].id);
                      document
                        .getElementById(`tab-${groups[next].id}`)
                        ?.focus();
                    }}
                    onClick={() => setGroup(item.id)}
                  >
                    {item.label}
                    <span className="count">
                      {inbox
                        ? inbox.pulls.filter((pr) => pr.group === item.id)
                            .length
                        : '—'}
                    </span>
                    <span className="sr-only">
                      {group === item.id ? ' (selected)' : ''}
                    </span>
                  </button>
                ))}
              </div>
            )}
            <div className="filter-bar">
              <label className="search">
                <Search size={16} />
                <span className="sr-only">Filter pull requests</span>
                <input
                  placeholder="Filter by title, repository or author…"
                  value={filter}
                  onChange={(event) => setFilter(event.target.value)}
                />
              </label>
              <span className="muted">
                {section === 'mine'
                  ? 'Authored by you'
                  : 'Personal & team requests'}
              </span>
            </div>
            {error && (
              <div role="alert" className="notice">
                <CircleAlert size={17} />
                <span>
                  {messages[error] ?? 'Something went wrong. Please try again.'}
                </span>
                <button
                  className="secondary"
                  onClick={() => void load()}
                  disabled={loading}
                >
                  Try again
                </button>
                {['unauthenticated', 'github_unauthorized'].includes(error) && (
                  <a className="primary" href="/auth/github">
                    Sign in again
                  </a>
                )}
              </div>
            )}
            {new URLSearchParams(window.location.search).get('auth') ===
              'failed' && (
              <div role="alert" className="notice">
                GitHub sign-in was cancelled or failed. Please try again.
              </div>
            )}
            {inbox?.warnings.map((warning) => (
              <div className="notice" role="status" key={warning}>
                <CircleAlert size={17} />
                <span>{warning}</span>
              </div>
            ))}
            <section
              id="pull-list"
              role={section === 'inbox' ? 'tabpanel' : 'region'}
              aria-labelledby={
                section === 'inbox' ? `tab-${group}` : 'page-title'
              }
              aria-busy={loading}
            >
              {loading ? (
                <div className="empty" role="status">
                  <RefreshCw className="spinning" size={24} />
                  <h2>Loading your workspace</h2>
                  <p>Checking your GitHub connection and pull requests.</p>
                </div>
              ) : !session?.user ? (
                <div className="empty">
                  <div className="empty-icon">
                    <Github size={25} />
                  </div>
                  <h2>
                    {section === 'mine'
                      ? 'Keep track of your pull requests'
                      : 'Bring your review queue into focus'}
                  </h2>
                  <p>
                    {section === 'mine'
                      ? 'Sign in with GitHub to see the pull requests you have opened.'
                      : 'Sign in with GitHub to see requests for you and your teams.'}
                  </p>
                  {session?.configured ? (
                    <a className="primary" href="/auth/github">
                      <Github size={16} />
                      Sign in with GitHub
                    </a>
                  ) : (
                    <>
                      <button className="primary" disabled>
                        GitHub connection not configured
                      </button>
                      <p className="muted">
                        Your workspace administrator needs to configure GitHub
                        sign-in.
                      </p>
                    </>
                  )}
                </div>
              ) : rows.length ? (
                <div className="pulls">
                  {rows.map((pr) => (
                    <article className="pull-row" key={pr.id}>
                      <GitPullRequest className="pr-icon" size={19} />
                      <div className="pull-content">
                        <a
                          href={pr.url}
                          target="_blank"
                          rel="noreferrer"
                          className="pull-title"
                        >
                          {pr.title}
                          <ExternalLink size={13} />
                        </a>
                        <div className="metadata">
                          <span>
                            {pr.repository}{' '}
                            <span className="mono">#{pr.number}</span>
                          </span>
                          <span>by {pr.author}</span>
                          {pr.draft && <span className="badge">Draft</span>}
                          {pr.reviewState && (
                            <span>
                              {pr.reviewState
                                .toLowerCase()
                                .replaceAll('_', ' ')}
                            </span>
                          )}
                        </div>
                      </div>
                      <div className="pull-state">
                        {pr.personal && (
                          <span className="badge">Personal request</span>
                        )}
                        {pr.teams.map((team) => (
                          <span className="badge" key={team}>
                            Team · {team}
                          </span>
                        ))}
                        {pr.changedSinceReview && (
                          <span className="badge warning">
                            New commits since review
                          </span>
                        )}
                        {pr.uncertain && (
                          <span className="badge warning">
                            Request timing unconfirmed
                          </span>
                        )}
                        <time dateTime={pr.updatedAt}>
                          {new Date(pr.updatedAt).toLocaleDateString()}
                        </time>
                      </div>
                    </article>
                  ))}
                </div>
              ) : (
                !error && (
                  <div className="empty">
                    <InboxIcon size={26} />
                    <h2>
                      {filter
                        ? 'No matching pull requests'
                        : section === 'mine'
                          ? 'No open pull requests'
                          : 'You’re all caught up here'}
                    </h2>
                    <p>
                      {filter
                        ? 'Try a different title, repository or author.'
                        : section === 'mine'
                          ? 'Your open pull requests will appear here.'
                          : 'No pull requests in this review group.'}
                    </p>
                  </div>
                )
              )}
            </section>
            <footer>
              <span>
                {loading
                  ? 'Syncing…'
                  : inbox
                    ? `Last synced ${new Date(inbox.syncedAt).toLocaleTimeString()}`
                    : 'Not synced'}{' '}
                · Refresh to check for updates
              </span>
              {session?.installUrl && (
                <a href={session.installUrl} target="_blank" rel="noreferrer">
                  Manage GitHub access <ExternalLink size={12} />
                </a>
              )}
            </footer>
          </>
        }
      </main>
    </div>
  );
}
