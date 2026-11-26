# github-pr-explorer

Read `README.md` first for what the product is, then `VISION.md` for what a change is judged against, then `PLAN.md` for what is being worked on now.

## Vision and plan are separate on purpose

- `VISION.md` holds the invariants. It has no roadmap and no feature list. Do not change it without the owner. When a change seems to go against it, say so in the pull request and hold it.
- `PLAN.md` holds the current plan: the phase we are in, the probes, and the open questions. Change it whenever the plan changes, in the same pull request as the work.
- `planning/decided.md` records what is settled. When an open question in `PLAN.md` gets an answer, move it there in the same pull request.
- `planning/ideas.md` holds ideas. An idea is not a plan until the owner says so.
- `planning/research/` holds findings. Each file keeps what was verified apart from what was only read or believed.

Apply the two tests at the end of `VISION.md` to every proposal before writing it up.

## Product rules

These follow from the vision. They are here so a session does not have to derive them.

- A view never calls the network. It reads the index. Only the sync layer talks to GitHub.
- The index is a cache. Deleting it must always be safe.
- Every fact in the index records its source and when it was fetched.
- There is one filter language. Do not add a second way to express a condition for a new feature.
- A new piece of pull request information is a new block. Do not give anything a fixed place on the page.
- Every setting is a plain file in the configuration folder. Settings in the app writes those files. Nothing configurable lives only in the window or in preferences.
- Whatever can be configured can also be read and changed from the command line and over MCP. Add those in the same pull request as the setting.
- Configuration lives in `~/Library/Application Support/github-pr-explorer/config/`, read and written only through `ConfigurationStore`. Tests and renders always pass a temporary folder and never touch the real one.
- Do not build one team's automation into the app. Give teams the parts: a fact drawn from the pull request, an action, a block.
- Native Swift for the current macOS only. Prefer SwiftUI, and use AppKit where SwiftUI cannot do the job. No embedded web page of github.com.
- Name things in full: `github-pr-explorer`, not an abbreviation.

## Main is test-in-production

Until the app has real users, `main` is test-in-production (owner's direction, 2026-11-25). A merge to `main` that touches a file that ships (`Sources/`, `Resources/`, `Package.swift`, `Package.resolved`, `scripts/bundle.sh`, `scripts/release.sh`) is built, notarized, and released to the owner's Macs within minutes by `mac-app-release-poller`, with no review step between the merge and the release.

- So `main` must always build, pass its tests, and launch. Run `swift build`, `swift test`, `scripts/bundle.sh`, and the renders the change touches before you merge.
- A change you are not sure of goes behind a switch that is off by default, or waits in its pull request.
- This posture ends when the app has real users, meaning anyone other than the owner running a release. Revisit this rule then, before the first such user gets a release: a review gate, a beta channel, or both.

## Working here

- Work in a numbered worktree under `.wt/` (for example `.wt/wt-01`), on a branch. Keep the primary checkout on `main`.
- Commit and push as you work, and open a pull request early.
- Merge your own pull requests as you work, squashed, once the checks you can run pass. This goes for subagents too. The app has no users until the owner installs it on his Mac (owner's direction, 2026-11-25).
- Still hold a pull request for the owner when it changes what `VISION.md` says, or when it sets up anything on his Mac.
- Build against mock data. The core library carries a large, fixed set of placeholder pull requests, and every view must work from it with no network and no sign-in. When a feature needs a case the mock data lacks, add the case in the same pull request (owner's direction, 2026-11-25).
- The app follows the scheme the owner's other Mac apps share: a Swift package with a core library, an app target, and tests, `scripts/bundle.sh`, Sparkle updates, `scripts/release.sh`, and an icon drawn in Swift. `mac-os-agent` is the reference to copy from. Only `AppUpdater.swift` imports Sparkle.
- Never cut a release by hand, push a tag, or publish a GitHub Release unless the owner asks. `scripts/release.sh --check` and `--dry-run` publish nothing.
- Use placeholder names in designs, fixtures, screenshots, and test data: the org `acme`, people such as Ada Park and Sam Rivera. Never real people, repos, or pull requests.

## Designs

The Figma file is https://www.figma.com/design/XslUM40a0h5IXEs7tXtAqZ

- A design page reads top to bottom as rows. Each row is one comparison, left to right: Current, Proposed, and an optional Reference.
- A new option is a new row below, not a new column.
- States of one option sit side by side inside its cell.
- Link the Figma row from the ticket and the pull request it belongs to.

## Tickets

Work is ticketed in Linear, in the `github-pr-explorer` project on the Mac Apps team: https://linear.app/interstellar-cafe/project/github-pr-explorer-b2c923a159c1

- An issue states the problem and what done looks like, for someone with none of today's context.
- Find the issue before starting, or file it. Name it in the pull request.
- Linear tracks the work. `PLAN.md` and `planning/` record what is decided and what is open.
