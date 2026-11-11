# AI Buddy — native macOS architecture

AI Buddy is a local Swift/SwiftUI application for Apple Silicon, minimum macOS 14. There is no application account, web server, hosted database or cloud deployment. GitHub requests still require network access.

## Boundaries

- **AIBuddy:** SwiftUI views with Focus semantic tokens and bundled Inter. AppKit opens verified GitHub URLs and handles the clipboard. A narrow dependency factory supplies production services or isolated DEBUG-only UI-test fixtures.
- **BuddyCore:** typed models, pure review classification, GitHub REST client, OAuth device flow and the main-actor Workspace coordinator. GitHubServing, GitHubAuthorization, HTTPTransport, CredentialStoring and InboxStoring are replaceable test boundaries. Async networking and actor-isolated persistence keep blocking I/O off the UI actor.
- **Storage:** SQLite via Apple's system library; account-ID/page-scoped JSON snapshots and timestamps. Keychain stores the GitHub token and stable identity. Tokens never enter SQLite, preferences or logs. Files live in `~/Library/Application Support/AI Buddy/`; the cache directory/database use owner-only permissions.

## GitHub

A public client ID configures an OAuth App with device flow enabled. No secret, redirect server or CLI session is needed. Scopes are `repo read:org`; repo is broad and permits writing, but this version only uses read-only REST calls. Device polling follows the provided interval, adds five seconds on slow_down and stops on cancellation/expiry. HTTP redirects are rejected; API URLs and browser verification URLs are restricted to GitHub.

Search combines personal requests, requested teams and submitted reviews, with deduplication. Pagination/search limits and missing team/repository permissions are visible warnings. Authored PRs have independent discovery and do not fetch teams or review history. Classification uses the latest submitted own review, current personal/team requests and relevant timeline events; new commits and uncertain history are separate flags.

Workspace restores a Keychain credential and its account-scoped cache, then refreshes both pages. Manual refresh preserves old data on failure and marks it stale. Connection generations prevent late responses from reintroducing a disconnected account. Connecting is explicit; disconnect removes local credentials and cached data, without revoking GitHub's authorization grant. To revoke that grant, use GitHub Settings → Applications.

## Build and delivery

The checked-in Xcode project consumes the local BuddyCore package. `scripts/generate-project.py` regenerates the project deterministically without third-party tools. Swift Package Manager also builds the SwiftUI executable, allowing a local `.app` through `scripts/build-local.sh` on compatible Command Line Tools installations. Xcode is required for UI tests.

The ARM64 macOS CI runs core tests, isolated UI tests, and a Release app build. UI fixtures are DEBUG-only and never touch production Keychain or disk. Initial distribution is a local unsigned/ad-hoc `.app`; Developer ID signing, notarization, DMG and updating are deferred. There is no migration of web sessions or PostgreSQL data; old data is left untouched.

AI execution, provider setup, agent processes, review settings/results/posting, Enterprise and concurrent accounts are outside this version. Later tools can reuse connections and storage through explicit services; no plugin framework is introduced now.
