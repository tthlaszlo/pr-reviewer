# AI Buddy

A local macOS workspace for developer tools, starting with GitHub pull requests. Built with Swift and SwiftUI for **Apple Silicon, macOS 14+**. No application login or hosted backend.

- **Review requests:** personal/team invitations grouped into awaiting review, reviewed/waiting and requested again.
- **My pull requests:** your own open PRs, independently fetched.
- Filter, manual refresh, draft/review/new-commit badges and visible partial-result warnings.
- Local SQLite cache and macOS Keychain credentials. Cached data remains visible with a stale indicator when GitHub is unavailable.

AI reviews, agents, review settings, results and publishing are planned separately.

## Build and run

Install full Xcode and select it (`sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer`). Open `AIBuddy.xcodeproj`, choose the **AIBuddy** scheme and **My Mac**, then Run. Command-line equivalent:

```sh
scripts/build-app.sh
open .build/xcode/Build/Products/Release/AIBuddy.app
```

For compatible Command Line Tools installations, a local app can also be packaged without full Xcode:

```sh
scripts/build-local.sh
open .build/local/AIBuddy.app
```

If the default SDK is incompatible, supply the path of an installed compatible SDK, for example `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk scripts/build-local.sh`. This does not replace Xcode for UI tests. The local fallback reads `GITHUB_CLIENT_ID` from the environment, not the Xcode configuration file.

## Connect GitHub

1. In [GitHub Developer settings](https://github.com/settings/developers), register an **OAuth App** and enable **Device Flow**. A local desktop app has no OAuth callback handler; if registration requires a callback URL, use `http://127.0.0.1` as an unused placeholder. Do not create or embed a client secret for this flow.
2. Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and set the public client ID. Alternatively run `GITHUB_CLIENT_ID=your_client_id scripts/build-app.sh` (or `build-local.sh`).
3. Launch AI Buddy, choose **Connect GitHub**, copy the code and choose **Open GitHub** to approve it. Codes expire; approval can be cancelled or retried.

Without a configured client ID the app opens normally and explains why connection is unavailable. There is no Google, password or guest login. One GitHub.com account is supported.

The OAuth scopes are `repo` (including private PRs) and `read:org` (team membership). GitHub's repo scope also permits writes; AI Buddy currently only reads PR data. Organization OAuth restrictions or SSO may require additional approval. Device flow needs no server or client secret. See [GitHub's device-flow documentation](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps#device-flow).

To switch accounts, disconnect first and approve the next connection with the intended browser account. Disconnect deletes the local token and all cached PRs. It does not revoke the OAuth grant on GitHub; use GitHub Settings → Applications for that. Keychain failures are reported, not silently ignored.

## Verification

```sh
swift test --enable-code-coverage
scripts/verify.sh
```

The full script requires Xcode and runs core tests, XCTest UI tests and the Release build. UI tests inject an isolated DEBUG-only fixture graph: no real GitHub token, production Keychain or persistent data is used. The CI uses a standard ARM64 macOS runner. No signing account is needed for these builds.

Regenerate the checked-in project with `python3 scripts/generate-project.py` after adding app source files. CI checks that regeneration is clean.

## Data and development

PR snapshots are stored in `~/Library/Application Support/AI Buddy/inbox.sqlite`, scoped by stable GitHub user ID and PR page. Credentials are stored only in macOS Keychain under `com.aibuddy.desktop.github`. No telemetry or server synchronization is included. Inter is bundled under its [SIL Open Font License](Sources/AIBuddy/Resources/Inter-OFL.txt).

Work on feature branches and open a PR; `main` accepts stable, tested changes. The native app replaces the earlier React/Fastify/PostgreSQL/Docker deployment. Existing PostgreSQL volumes and ignored local `.env` files are left untouched; old web sessions are not imported. The repository name remains `pr-reviewer`.

See [architecture](docs/ARCHITECTURE.md), [Focus design](docs/DESIGN_SYSTEM.md) and [project rules](AGENTS.md).
