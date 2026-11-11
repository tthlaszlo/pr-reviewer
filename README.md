# AI Buddy

AI Buddy is a workspace for AI-assisted developer tools. Its first tool is a focused inbox for GitHub pull request reviews. Personal and team requests are grouped into **Awaiting my review**, **Reviewed · waiting**, and **Review requested again**. The interface follows the [Focus design system](docs/DESIGN_SYSTEM.md).

The Pull requests navigation contains two subpages: **Review requests** (`/pull-requests/review-requests`) and **My pull requests** (`/pull-requests/mine`). The latter lists open PRs authored by the signed-in user, independently of review invitations. Review configuration, AI agents, results, and publishing have no menu entries. This version never runs an AI review or posts to GitHub.

## Local development

Prerequisites: Docker Engine with Docker Compose. No local Node.js or PostgreSQL installation is required.

```sh
cp .env.example .env
docker compose up --build -d --wait
```

Open [localhost:3000](http://localhost:3000). Without GitHub credentials the app starts in a disconnected state. Source changes under `src`, `server`, and `shared` reload automatically. Rebuild after dependency or other configuration changes.

```sh
docker compose logs -f app
docker compose stop
docker compose start
docker compose down
```

`stop`/`down` retain the database volume. `docker compose down --volumes` permanently deletes local sessions and OAuth state. The database is only reachable inside the Compose network; the web port binds to localhost.

If changing `APP_PORT`, also change `APP_URL` and the registered callback URL to the same port.

## GitHub sign-in

Create a **GitHub App** under GitHub Settings → Developer settings → GitHub Apps. For local use:

| Setting                  | Value                                                                                   |
| ------------------------ | --------------------------------------------------------------------------------------- |
| Homepage URL             | `http://localhost:3000`                                                                 |
| Callback URL             | `http://localhost:3000/auth/github/callback`                                            |
| Webhooks                 | Disabled; synchronization is manual in this version                                     |
| Repository permissions   | **Pull requests: Read-only**, **Issues: Read-only** (timeline), **Metadata: Read-only** |
| Organization permissions | **Members: Read-only**                                                                  |
| User token expiration    | Enabled                                                                                 |

Set `GITHUB_CLIENT_ID` and `GITHUB_CLIENT_SECRET` in `.env`. Generate the encryption key inside Docker:

```sh
docker compose run --rm --no-deps app node -e "console.log(require('node:crypto').randomBytes(32).toString('hex'))"
```

Copy the generated value into `TOKEN_ENCRYPTION_KEY`. Keep this key stable across deployments. Rotating it invalidates existing encrypted tokens; clear sessions when rotating. Never commit `.env` or credentials.

Optionally set `GITHUB_INSTALL_URL` to `https://github.com/apps/YOUR-APP/installations/new` so users can reach the app's installation settings from the inbox. Install the app on the accounts and repositories it should read, obtain any required organization approval, then sign in. Access is the intersection of the user's rights, app permissions, and installed repositories. A successful sign-in does not guarantee access to every organization. Search can also omit inaccessible repositories without returning an error.

Authentication uses the app's user authorization flow, not an installation token acting as a bot. No private key is needed for this implementation. Tokens remain server-side, encrypted with AES-256-GCM. Session cookies are HttpOnly and SameSite=Lax; HTTPS deployments also use Secure cookies. OAuth state is browser-bound, expires after ten minutes, and is consumed once. Session IDs and OAuth states are hashed in PostgreSQL. Sessions expire at token expiration or eight hours, whichever is sooner; sign in again after expiry. Automatic token refresh is intentionally not implemented.

Sources: [GitHub App user authorization](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-user-access-token-for-a-github-app), [GitHub App permissions](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/choosing-permissions-for-a-github-app).

## Inbox behavior

- Search discovers current personal/team requests and open PRs previously reviewed by the signed-in user. Explicit searches for each accessible team supplement the personal search. Duplicate PRs are merged.
- Classification uses current requested reviewers/teams, submitted reviews, and timeline review-request events. Pending reviews and other people's reviews do not count as the user's submitted review.
- A relevant request after the latest submitted review moves the PR into **Review requested again**. New commits alone do not. New commits get a separate badge.
- If a current request has no corresponding accessible timeline event, the PR shows **Request timing unconfirmed** rather than claiming a confirmed re-request.
- Closed PRs are removed on refresh. PRs already reviewed remain visible while open even when they no longer have a current review request.
- Results are fetched on sign-in/page load and the **Refresh** button. They are not background-polled or persisted. PostgreSQL stores only sessions and temporary OAuth state.
- GitHub search caps results at 1,000 per query. List endpoints are paginated up to 10,000 entries; truncation and partial search results produce explicit warnings. A warning means counts may be incomplete. The app does not treat a synchronization error as an empty successful inbox.
- Team history uses **current** accessible memberships. Historical memberships and organizations not installed/authorized for the app cannot be reconstructed by this version.

## Tests and checks

All commands run inside Docker:

```sh
# Formatting, TypeScript, unit/integration tests, coverage, production build,
# and Chromium tests against the compiled production frontend/backend.
docker compose --profile test run --build --rm test

# Focused commands, after building the test image:
docker compose --profile test run --rm test npm test
docker compose --profile test run --rm test npm run typecheck
```

Tests use an isolated temporary PostgreSQL service (`db-test`), never the development database. Browser tests and HTTP integration tests use simulated GitHub responses; a real GitHub App is required to validate the final account/organization authorization flow. No personal GitHub token is needed by CI.

Coverage gates: 90% statements/lines/functions and 80% branches across application components, auth routes, GitHub integration, configuration, encryption, and database storage. The process entrypoint is exercised by browser tests and the production-container smoke check. CI runs the Docker verification suite and builds/smoke-tests the production image on every PR and on `main`.

## Sevalla

The root `Dockerfile` defaults to its final **production** stage: a non-root Node.js process serving the frontend and API together. Docker Compose is the local orchestration file; Sevalla builds the Dockerfile directly.

1. Create a managed PostgreSQL database on Sevalla.
2. Create an application from this repository, production branch `main`, build strategy **Dockerfile**, path `Dockerfile`, context repository root. Use the image's default start command.
3. Configure `APP_URL` to the public **HTTPS** origin, `DATABASE_URL` to the managed database's private connection URL, and the GitHub settings/encryption key described above as runtime secrets. Never use the local Compose database password in production.
4. Configure the web process port consistently with `PORT` (default 8080). The process listens on `0.0.0.0` and honors an injected `PORT`.
5. Configure an HTTP readiness check at `/healthz`. It verifies PostgreSQL connectivity. Initial schema creation runs during application startup.
6. Register the production GitHub callback as `https://YOUR-DOMAIN/auth/github/callback`. A separate GitHub App for local development avoids sharing production secrets.
7. Deploy merged, green `main` commits. PR preview deployments should use their own database and GitHub App credentials/callback, or remain in disconnected mode.

No local persistent disk is required. Session and OAuth state survive restarts in PostgreSQL. API/auth responses disable caching. Do not enable edge caching for these routes. In this first version, runtime rate limits are per process and schema initialization assumes an initial single-instance deployment. Before enabling multiple replicas, move schema initialization into a serialized migration job and add shared rate limiting.

AI subscription hosting is not implemented: the later provider design must account for hosted-service authentication restrictions instead of copying local CLI sessions onto Sevalla.

Sources: [Sevalla Dockerfile builds](https://docs.sevalla.com/applications/builds/dockerfile), [Sevalla networking](https://docs.sevalla.com/applications/networking), [Sevalla database connections](https://docs.sevalla.com/databases/connect).

## Contribution workflow

Follow [AGENTS.md](AGENTS.md). Every development change goes through its own feature branch and PR. Do not push development changes directly to `main`. Require the **Docker verification** CI check before merging; repository administrators should enable branch protection for `main` with pull requests and passing checks required. Merge only reviewed, stable changes.

## Existing local databases

When upgrading from the original `pr-reviewer` Compose project, set `DATABASE_VOLUME=pr-reviewer_database` in your existing `.env` to reuse its database. Stop the previous stack with `docker compose -p pr-reviewer stop app db` before starting AI Buddy to release the web port. The default for new installations is `ai-buddy_database`.
