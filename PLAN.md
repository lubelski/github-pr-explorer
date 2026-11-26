# Plan

The current plan for github-pr-explorer. It changes as we learn. [VISION.md](VISION.md) holds what does not change, and [planning/decided.md](planning/decided.md) holds what is settled.

Last updated 2026-11-25, after the first window.

## Where we are

Phase 0, with the first code in. The vision is drafted and waiting for the owner, the design rows in Figma are waiting for the owner, and two research files are in `planning/research/`. The core library, a large deterministic mock world of 298 placeholder pull requests, and `github-pr-explorer-ctl` are built and tested, so views can be built with no network and no sign-in.

The first window is built on the mock world (MAC-46): the open pull requests in a searchable list, and the page drawn as blocks from a layout document, with "Decision first" and "Tabbed" built in. It is for the owner to judge rows 1 and 2 as a running app. The actions do nothing yet, the header is fixed above the tabs, and there is no sync, Edit Layout, layout rules, or diff. The icon, Sparkle, and releases are MAC-47.

The owner's first look at the window brought small changes (MAC-55): the app's name shows once, centered; freshness, the version and commit, and the layout menu sit at the right end of the title bar; the footer is gone; the list's width can be dragged; and a row above the list picks one of three fixed views, "Needs my review", "Mine" and "Everything open". The views are plain predicates until the filter language exists.

## What the research says

Both files were written by research agents on 2026-11-25. Each keeps what it checked apart from what it only read. Nobody has re-checked them yet.

From [planning/research/prior-art.md](planning/research/prior-art.md):

- **Reviewing outside the browser is a crowded field.** It lists at least eight apps that do it, most new in 2026, including Linear Diffs and Pulldog, a native Mac app with rule-based queries and local data. Finishing a review without a browser does not set this app apart.
- **Nobody found lets a team rearrange the pull request page or pick a layout by rule.** Blocks and rules are the gap. The nearest model is outside code review: Salesforce record pages, assigned by record type and profile.
- **A local index is rare, and nobody publishes how they sync GitHub data.** Linear's sync engine is the design to read first.
- **GitHub is fixing the same pains.** A virtualized diff view, a dashboard with saved views, and a new Overview page all shipped or previewed in 2026.

From [planning/research/github-data-sources.md](planning/research/github-data-sources.md):

- **A conditional REST request that returns 304 is free.** It left the rate limit unchanged on every endpoint tried. Whether it counts toward the 900-a-minute secondary limit is not known.
- **For GraphQL the limit is server time, not points.** One query over 174 pull requests cost 1 or 2 points but took 7 to 8 seconds for check state, and failed when computed fields were combined. Computed fields have to be fetched in small batches.
- **Polling cannot keep checks fresh to 30 seconds for 200 pull requests.** Noticing that something changed is cheap. Check state is the gap, because a check finishing did not move the pull request's `updatedAt` in the one case observed. Fast checks need webhooks, which means a GitHub App and a small hosted relay, and an org owner has to install the app.
- **The `gh` login reads everything and is the easiest start.**
- **A local partial clone is fast.** It fetched 238 pull request heads in about 1 second and computed a diff in under half a second. GraphQL has no per-file patch at all.

## The shape we expect

This is a proposal, not a decision. It names the parts so the phases below have something to point at.

```
GitHub ──▶ sources ──▶ sync ──▶ index ──▶ filter ──▶ layout ──▶ window
           (APIs, gh,           (on this   (one       (blocks,
            clone, push,         Mac)       language)  rules)
            web page)              ▲
                                   └── actions (applied here first, then sent)
```

- **Sources.** Each way of getting data from GitHub sits behind one interface. A source says what facts it can supply and what each costs.
- **Sync.** Decides what to fetch, from which source, and when. It is the only part that uses the network.
- **Index.** A local database with full-text search. Each fact records its source and fetch time.
- **Filter.** One language for conditions over the index. Search, saved views, and layout rules compile to it.
- **Layout.** A layout is a document that places blocks on a page and its tabs. Rules map a filter to a layout.
- **Actions.** Approve, comment, and merge apply to the index at once, are sent to GitHub in the background, and are put back if GitHub refuses.

## Teams' own facts and actions, and agent support

Added 2026-11-25 from the owner's note. The vision now has both as principles. This is the proposed shape, not a decision.

The owner's example: a bot posts a comment with a checkbox, and ticking it starts an expensive CI run. The app should let a team turn that into a "Run expensive CI" button without the app knowing anything about that bot.

That example is three parts, and each is something a team writes in a file:

- **A fact.** A rule that reads what the index already holds and produces a named value on the pull request. Here: "the comment by `ci-bot` that contains this text has its checkbox unticked" becomes `expensive_ci.requested = false`. Because it is a fact in the index, search, saved views, and layout rules can all filter on it.
- **An action.** A name, a label, a filter that says when it is offered, and an effect on GitHub. Here: "tick that checkbox." Effects come from a short list: edit a comment, post a comment, add or remove a label, re-run a check, start a workflow. It goes through the same queue as Approve, so it shows at once and is put back if GitHub refuses.
- **A place.** The action is a button in the Actions block or in a block of the team's own, and the fact can be shown in any block. The layout decides where.

Most cases should need no code, only a pattern and an effect from the list. For the rest, a fact or an action can be a script: a program that gets the pull request as JSON and answers with facts or with an effect to carry out.

Agent support is the same idea seen from outside:

- **Files.** Views, layouts, rules, facts, and actions each live as plain files in one configuration folder, in a format with a published schema. The app watches the folder and reloads. A file that does not validate is not applied: the app keeps the last good version and shows the problem.
- **A command line.** `github-pr-explorer` can validate the configuration, run a filter against the index, show a pull request with its facts, say which layout rule matched and why, and run an action. An agent uses it to check its own work.
- **MCP.** The same operations as tools, so an agent in a chat can do them without a shell.
- **History.** Every change to the folder is kept, whoever made it. The command line lists versions, shows what changed, and restores one.

## Phases

Estimates are agent build time. The calendar is set by how fast the owner can react to designs and probes.

| Phase | What | Status |
|---|---|---|
| 0 | Write the idea down and try layouts in Figma | In progress. Judgment call, budget, 2 review rounds, known by the owner's first pass over the Figma rows. |
| 1 | Probes (below) | Not started. Field-checked, finish line, 1 to 2 days of build time, known by the end of the sync cost probe. |
| 2 | Index and sync core as a library with tests and a command-line tool, no window | Not estimated. Depends on phase 1. |
| 3 | A window that lists and opens pull requests from the index, with a fixed default layout | Started on mock data: the list and the page from two built-in layouts. Needs the index from phase 2. |
| 4 | Blocks, layouts as documents, and Edit Layout | Not estimated. |
| 5 | Layout rules, on the shared filter language | Not estimated. |
| 6 | Actions: comment, approve, merge | Not estimated. |

Phases 2 to 6 get ranges after the probes, because the probes decide how hard sync and Edit Layout are.

- **Build time vs. wait time.** Phase 0 and 1 are a few hours of build time each. The wait is the owner's review of designs and probe results.
- **Long-lead items.** None known yet. If push needs a GitHub App or a hosted relay, registering it is one.
- **Review load.** About an hour of the owner's time for the Figma rows and the open questions below, and about an hour for the vision.

## Probes

Each probe is timeboxed and its only output is a narrower range or an answer. Results go in `planning/research/`.

1. **Sync cost.** The research answered the first half: polling everything to 30 seconds does not fit the budget. What is left is probes 1, 2, 3, and 5 in the data sources file: whether 304s count toward the secondary limit, how fast ETags change, what moves `updatedAt`, and the batch size for computed fields. Field-checked, about 6 hours, needs a test repo the owner controls.
2. **Push through a relay.** A GitHub App on a test repo with a small hosted relay. Measure the time from event to app, and what happens across a laptop sleep. Field-checked, about a day, needs the owner's yes to a hosted piece (question 3).
3. **Index speed.** Load 10,000 pull requests with bodies and comments into a local database. Search and filter must answer in under 10 ms. Self-checking.
4. **Diff from a local clone.** Compute and draw a 5,000-line diff natively from a partial clone, and compare the time and the result with the API's patches. Field-checked.
5. **Description without a web view.** Draw a real pull request body natively: tables, images, task lists, collapsed sections. Judgment call.
6. **Edit Layout feel.** A throwaway window where blocks drag between positions and tabs. Judgment call, budget of 2 review rounds.
7. **The checkbox bot, end to end from files.** With the index in place, write the owner's example as a fact and an action in configuration files, have an agent do it from a one-sentence request using only the command line, and see what it could not do. Field-checked, half a day, after phase 2.

## Open questions for the owner

Each has a recommendation. An answer moves to `planning/decided.md`.

1. **Who is it for first?** You alone, a team you are on, or the public. This decides sign-in, how layouts are shared, and how much setup is tolerable.
   Recommendation: you and one team, signing in with the `gh` login.
2. **Does the first usable version write to GitHub?** The vision says a review finishes here.
   Recommendation: yes for comment and approve, merge later. Read-only first would test the index but not the idea.
3. **Is a hosted piece acceptable for push?** Webhooks need a reachable endpoint.
   Recommendation: yes, as an option. The research says checks cannot be fresh to 30 seconds without it. The app still has to work by polling alone, for orgs that will not install a GitHub App.
4. **Does the diff belong in the first version?** You said "the diff (if we still care)".
   Recommendation: it is a block like any other, built after the page works without it.
5. **May the description be drawn by a web view?** GitHub's bodies are HTML in practice.
   Recommendation: try native first in probe 5. A web view for one block's content is different from embedding github.com, but it should be your call.
6. **Where do a team's layouts and rules live?** In the app with export and import, or as files in the team's repo.
   Recommendation: a plain file format from the start, and decide the location later.
7. **How far does scraping go?** It can break without notice and GitHub's terms limit it.
   Recommendation: use it only for facts no API supplies, and behind the same source interface so it can be turned off.
8. **Is the repository public?** The shared Mac app scheme says public. It was created private on 2026-11-25 because the vision is unapproved.
   Recommendation: make it public when the vision is approved.
9. **What happens to `github-pr-watch-menubar`?** It is set aside for now.
   Recommendation: leave it running as it is, and revisit once this app has an index, since notifying could then come from here.

10. **Does the research change the vision's emphasis?** If reviewing outside the browser is common and team-arranged pages are not, the blocks and rules are what this app is for, and the index is what makes them fast.
    Recommendation: keep all six principles, and say in the identity lines that the page a team arranges for itself is the point. Worth an hour with Pulldog and Linear Diffs first.

11. **What format are the configuration files?** It has to be easy for a person to read, easy for an agent to write correctly, and checkable against a schema.
    Recommendation: JSON with a published JSON Schema, one file per thing. Agents write it reliably and the schema catches mistakes. TOML reads better by eye, so this is a taste call.
12. **How is configuration history kept?** You asked for something minimal, built in from the start.
    Recommendation: the configuration folder is a local git repository and the app commits every valid change. That gives history, diffs, and restore for free, agents already know git, and a team can later share the folder by adding a remote.
13. **May a shared configuration run scripts?** A script from a teammate's configuration is code running on your Mac.
    Recommendation: patterns and listed effects run without asking. A script runs only after the person has approved that exact file, and is asked again when it changes.
14. **How much is "90%"?** Sign-in and macOS permission prompts cannot be done by an agent.
    Recommendation: the rule is that everything except sign-in and permission grants can be done from files, the command line, or MCP.

## Design rows in Figma

File: https://www.figma.com/design/XslUM40a0h5IXEs7tXtAqZ

| Row | What it tests | Owner's call |
|---|---|---|
| 1 | The pull request page, decision first | Not reviewed |
| 2 | The pull request page, three panes with tabs | Not reviewed |
| 3 | Finding a pull request from the local index | Not reviewed |
| 4 | Edit Layout | Not reviewed |
| 5 | Layout rules | Not reviewed |
| 6 | Freshness, pending actions, and offline | Not reviewed |
| 7 | Block catalogue | Not reviewed |
| 8 | The diff as a pane that slides in over the pull request, after the pane stack in `mac-os-agent`'s Settings. A second answer to row 2. | Not reviewed |
