# github-pr-explorer

A native macOS app for finding, reading, and deciding on GitHub pull requests without the web page.

The core library, a large set of mock data, and a first window are built. The window lists the open pull requests and draws a pull request's page as blocks from a layout, all from the mock data, with no network and no sign-in. This repository also holds the vision, the plan, and the research.

## The idea

- **A local index.** The app keeps a copy of the pull requests you care about on this Mac. Every screen reads from that copy, so opening and searching never wait on the network.
- **A sync layer.** It fills the index from GitHub by whatever source is fastest for each fact, and records how fresh each fact is.
- **A page made of blocks.** The description, checks, reviewers, files, diff, and threads are each a block. Press Edit Layout and every block can be dragged to a new place or a new tab.
- **Rules that pick the layout.** A team can give one repo one page and another repo a different one, down to who is reviewing or which file tree was touched. A rule is a filter, the same kind search uses.

## Running it

Build and test the package. It needs the current Xcode and macOS.

```sh
swift build
swift test
```

`github-pr-explorer-ctl` reads the built-in mock world. List pull requests, show one, or export the world as JSON:

```sh
swift run github-pr-explorer-ctl pull-requests list --repo acme/api --state open
swift run github-pr-explorer-ctl pull-requests list --search "session refresh"
swift run github-pr-explorer-ctl pull-request show acme/api#4826
swift run github-pr-explorer-ctl pull-request show acme/api#4826 --json
swift run github-pr-explorer-ctl mock-data export /tmp/github-pr-explorer-mock
```

Each command takes `--help`.

### The app

`scripts/bundle.sh` builds and signs `build/github-pr-explorer.app`. It does not install or launch it. Run the bundle rather than `swift run`, which draws in the old look.

```sh
scripts/bundle.sh
```

`scripts/render-previews.sh` draws states of the window to PNG files in `build/renders`, light and dark, without putting a window on screen. Use it for pull request evidence.

```sh
scripts/render-previews.sh                            # every state
scripts/render-previews.sh --list                     # the state names
scripts/render-previews.sh page-4826-decision-first   # one state
scripts/render-previews.sh --pr 3 page-4826-decision-first   # attach to pull request 3
```

## Where things are

| File | What it holds |
|---|---|
| [VISION.md](VISION.md) | What the app is for and what a change is judged against. It changes rarely, and only with the owner. |
| [PLAN.md](PLAN.md) | What is being worked on now, what comes next, and the open questions. It changes freely. |
| [planning/decided.md](planning/decided.md) | What is settled, and how each settled part behaves. |
| [planning/ideas.md](planning/ideas.md) | Ideas the owner has raised. None is a plan. |
| [planning/research/](planning/research/) | What was learned about GitHub's data sources and about existing tools. |
| [AGENTS.md](AGENTS.md) | How to work in this repository. |
| [Sources/GitHubPRExplorerCore/](Sources/GitHubPRExplorerCore/) | The models, the status sentence, the index protocol, and the mock world in `Mock/`. |
| [Sources/GitHubPRExplorerCore/Layout/](Sources/GitHubPRExplorerCore/Layout/) | Page layouts as JSON documents, and the two built-in layouts. |
| [Sources/GitHubPRExplorerCore/Blocks/](Sources/GitHubPRExplorerCore/Blocks/) | What each block shows, worked out without SwiftUI. |
| [Sources/github-pr-explorer/](Sources/github-pr-explorer/) | The app: the window, one view per block, and the offscreen renders. |
| [Sources/github-pr-explorer-ctl/](Sources/github-pr-explorer-ctl/) | The command line tool. |
| [scripts/](scripts/) | `bundle.sh` and `render-previews.sh`. |
| [Tests/GitHubPRExplorerCoreTests/](Tests/GitHubPRExplorerCoreTests/) | Tests for both, with Swift Testing. |

The designs are in Figma: https://www.figma.com/design/XslUM40a0h5IXEs7tXtAqZ

The work is tracked in Linear: https://linear.app/interstellar-cafe/project/github-pr-explorer-b2c923a159c1
