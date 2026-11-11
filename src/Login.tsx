import { Bot, GitBranch, ArrowRight, ShieldCheck } from 'lucide-react';
import type { Session } from '../shared/types';

export function Login({
  session,
  loading,
  error,
  onRetry,
}: {
  session: Session | null;
  loading: boolean;
  error: string;
  onRetry: () => void;
}) {
  const returnTo = new URLSearchParams(window.location.search).get('returnTo');
  const target =
    returnTo === '/pull-requests/mine'
      ? returnTo
      : '/pull-requests/review-requests';
  const failed = new URLSearchParams(window.location.search).has('auth');
  return (
    <div className="login-shell">
      <header className="login-header">
        <a href="/login" className="brand">
          <Bot size={24} />
          <span>
            AI Buddy<small>DEVELOPER TOOLS</small>
          </span>
        </a>
        <span className="login-label">YOUR DEVELOPER WORKSPACE</span>
      </header>
      <main className="login-main">
        <div className="login-intro">
          <span className="login-kicker">
            LESS CONTEXT SWITCHING. MORE FOCUS.
          </span>
          <h1>
            Your tools.
            <br />
            One good companion.
          </h1>
          <p>
            A focused workspace for the work around your code. Start with pull
            requests, and keep everything close.
          </p>
          <div className="login-feature">
            <GitBranch size={20} />
            <div>
              <strong>Pull requests, together</strong>
              <span>Your review requests and your own PRs, in one place.</span>
            </div>
          </div>
        </div>
        <section
          className="login-card"
          aria-labelledby="login-title"
          aria-busy={loading}
        >
          <div className="login-card-icon">
            <Bot size={24} />
          </div>
          <h2 id="login-title">Welcome to AI Buddy</h2>
          <p>Sign in to your workspace.</p>
          {failed && (
            <div role="alert" className="notice">
              Sign-in was cancelled or could not be completed. Please try again.
            </div>
          )}
          {error && (
            <div role="alert" className="notice">
              We couldn’t check sign-in availability.
              <button className="secondary" onClick={onRetry}>
                Try again
              </button>
            </div>
          )}
          <div className="login-providers">
            {(['google', 'github'] as const).map((provider) => {
              const label = `Sign in with ${provider === 'google' ? 'Google' : 'GitHub'}`;
              const icon =
                provider === 'google' ? (
                  <svg
                    aria-hidden="true"
                    width="20"
                    height="20"
                    viewBox="0 0 48 48"
                  >
                    <path
                      fill="#4285F4"
                      d="M43.6 24.5c0-1.4-.1-2.8-.4-4.1H24v7.8h11a9.4 9.4 0 0 1-4.1 6.2v5h6.7c3.9-3.6 6-8.9 6-14.9Z"
                    />
                    <path
                      fill="#34A853"
                      d="M24 44c5.5 0 10.1-1.8 13.5-4.9l-6.7-5c-1.8 1.2-4.1 1.9-6.8 1.9-5.3 0-9.8-3.6-11.4-8.4H5.7v5.2A20.4 20.4 0 0 0 24 44Z"
                    />
                    <path
                      fill="#FBBC05"
                      d="M12.6 27.6a12.3 12.3 0 0 1 0-7.2v-5.2H5.7a20.3 20.3 0 0 0 0 17.6l6.9-5.2Z"
                    />
                    <path
                      fill="#EA4335"
                      d="M24 12c3 0 5.5 1 7.6 3l5.7-5.7A19.2 19.2 0 0 0 24 4 20.4 20.4 0 0 0 5.7 15.2l6.9 5.2C14.2 15.6 18.7 12 24 12Z"
                    />
                  </svg>
                ) : (
                  <GitBranch size={20} />
                );
              return session?.providers[provider] && !loading ? (
                <a
                  key={provider}
                  className="provider-button"
                  href={`/auth/${provider}?returnTo=${encodeURIComponent(target)}`}
                >
                  {icon}
                  {label}
                  <ArrowRight size={16} />
                </a>
              ) : (
                <button
                  key={provider}
                  className="provider-button"
                  disabled
                  aria-describedby={
                    loading ? 'login-loading' : `${provider}-availability`
                  }
                >
                  {icon}
                  {label}
                  <ArrowRight size={16} />
                </button>
              );
            })}
          </div>
          {loading ? (
            <p id="login-loading" role="status" className="muted">
              Checking sign-in options…
            </p>
          ) : (
            <div className="provider-availability">
              {session && !session.providers.google && (
                <p id="google-availability">
                  Google sign-in is not configured yet.
                </p>
              )}
              {session && !session.providers.github && (
                <p id="github-availability">
                  GitHub sign-in is not configured yet.
                </p>
              )}
            </div>
          )}
          <div className="login-footnote">
            <ShieldCheck size={16} />
            <span>
              Use your Google or GitHub account.
              <br />
              No separate password to remember.
            </span>
          </div>
        </section>
      </main>
      <footer className="login-footer">
        <span>AI Buddy</span>
        <span>A little less friction. A little more flow.</span>
      </footer>
    </div>
  );
}
