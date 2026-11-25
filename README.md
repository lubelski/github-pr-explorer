# github-pr-explorer

A native macOS app for finding, reading, and deciding on GitHub pull requests without the web page.

Nothing is built yet. This repository holds the vision, the plan, and the research.

## The idea

- **A local index.** The app keeps a copy of the pull requests you care about on this Mac. Every screen reads from that copy, so opening and searching never wait on the network.
- **A sync layer.** It fills the index from GitHub by whatever source is fastest for each fact, and records how fresh each fact is.
- **A page made of blocks.** The description, checks, reviewers, files, diff, and threads are each a block. Press Edit Layout and every block can be dragged to a new place or a new tab.
- **Rules that pick the layout.** A team can give one repo one page and another repo a different one, down to who is reviewing or which file tree was touched. A rule is a filter, the same kind search uses.

## Where things are

| File | What it holds |
|---|---|
| [VISION.md](VISION.md) | What the app is for and what a change is judged against. It changes rarely, and only with the owner. |
| [PLAN.md](PLAN.md) | What is being worked on now, what comes next, and the open questions. It changes freely. |
| [planning/decided.md](planning/decided.md) | What is settled, and how each settled part behaves. |
| [planning/ideas.md](planning/ideas.md) | Ideas the owner has raised. None is a plan. |
| [planning/research/](planning/research/) | What was learned about GitHub's data sources and about existing tools. |
| [AGENTS.md](AGENTS.md) | How to work in this repository. |

The designs are in Figma: https://www.figma.com/design/XslUM40a0h5IXEs7tXtAqZ

The work is tracked in Linear: https://linear.app/interstellar-cafe/project/github-pr-explorer-b2c923a159c1
