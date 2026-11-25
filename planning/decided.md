# Decided

What is settled for github-pr-explorer. [PLAN.md](../PLAN.md) has what is being worked on and what is still open. [ideas.md](ideas.md) has ideas.

- The name is `github-pr-explorer`
  - The repo, the folder, and later the app and bundle all use it in full.
- It is a native Mac app
  - Swift, for the current macOS only. The owner asked for "fully native".
- It starts fresh
  - `github-pr-watch-menubar` is an earlier app on a related problem. The owner said on 2026-11-25 to set that work aside and not build on it. Nothing here depends on it.
- Design comes before code
  - The owner asked for ideas to be tried in Figma before anything is built. He reacted to the first rows on 2026-11-25, so building has started. He has not yet chosen between rows.
- Build on mock data first
  - The owner asked on 2026-11-25 for lots of mock data, to help work on the app and to get building started before sync exists.
  - The mock data is the same placeholder world the Figma rows use: the org `acme`, its repos and people, and pull request `acme/api #4826` as the worked example.
- Pull requests are merged by whoever wrote them
  - The owner said on 2026-11-25 that sessions and their subagents may merge as they work, because the app has no users until he installs it.
- The vision and the plan are separate files
  - `VISION.md` holds what does not change. `PLAN.md` holds what does. The owner asked for this split.
