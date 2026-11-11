# AI Buddy — project and development rules

## Starting work

- Planning and discussing rules do not, by themselves, authorize implementation.
- Start development only when the user explicitly requests it. Until then, perform only the planning or documentation task currently requested.
- Stay within the scope of the current request; do not start implementing future features ahead of time.

## Development and runtime environment

- A native macOS application that runs exclusively locally, targeting Apple Silicon ARM64; minimum macOS 14.
- Swift + SwiftUI, with a separate Swift Package for application logic and an Xcode project for the app and UI tests.
- Development and testing take place on macOS. Docker and Sevalla are no longer part of the product.
- Store tokens in macOS Keychain and the PR cache in a local SQLite database. Never commit or log secrets.
- Do not delete PostgreSQL volumes or local secrets from the old web version during the migration.

## Required design system

- Before designing or implementing any UI, read the [Focus design system](docs/DESIGN_SYSTEM.md) and follow its rules.
- The accepted design direction is **Focus**. The default appearance is light; the application's outer frame has a 15 px corner radius.
- New screens, components, states and placeholders must use this design system. Extend the documented tokens and patterns for new elements rather than introducing a parallel visual style.
- Change the design direction and accepted defaults only at the user's explicit request. Update the design system documentation to reflect approved changes.

## Git and pull requests

- GitHub repository: https://github.com/tthlaszlo/pr-reviewer
- Each development change must use a separate branch and a separate pull request.
- Do not push development changes directly to `main`.
- Only stable, tested and verified changes may enter `main`, through a pull request.

## Testing

- Cover every implemented behavior with tests.
- Tests must verify functional requirements, relevant error handling and edge cases.
- Bug fixes must include a regression test that reproduces the bug.
- Run the tests and checks relevant to the change, and report their results when handing over the work.
- Never report a failed or unperformed check as successful.

## Product and current scope

- The product is named AI Buddy; its long-term goal is a shared workspace for multiple developer tools. The first tool supports partial automation of PR reviews.
- The PR list combines review requests sent to the user personally and through their teams.
- The required groups are: not yet reviewed by the user; already reviewed and the PR is waiting; requested to review again.
- Detailed review behavior and settings, AI agents, the results page and posting to GitHub will be designed and implemented later. Do not add separate navigation items for them yet.
- The future goal is to use the user's own Claude or ChatGPT subscriptions with specialist agents; integration details have not been finalized.
- Do not automatically treat earlier technology or GitHub login proposals as final decisions.

- The Pull requests tool has two subpages: personal/team review requests and the user's own open PRs. The three review groups remain on the first subpage.

## Native application and GitHub connection

- There is no application-level login, Google login, separate application account or server-side session.
- The workspace is available immediately after launch; connect to GitHub through the app's own OAuth device flow.
- One GitHub.com account is supported. Never bundle a client secret with the desktop application.
- Preserve the existing Focus appearance: Inter, a light interface, semantic colors and compact lists, with native macOS window controls.
- Run Swift tests and Xcode UI tests using the documented commands. If Xcode or OAuth configuration is missing, report the verification limitation accurately.
