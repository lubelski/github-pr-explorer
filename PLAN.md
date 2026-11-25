# Plan

The current plan for github-pr-explorer. It changes as we learn. [VISION.md](VISION.md) holds what does not change, and [planning/decided.md](planning/decided.md) holds what is settled.

Last updated 2026-11-25.

## Where we are

Phase 0. Nothing is built. The vision is drafted and waiting for the owner, seven design rows are in Figma waiting for the owner, and two research files are in `planning/research/`.

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

## Phases

Estimates are agent build time. The calendar is set by how fast the owner can react to designs and probes.

| Phase | What | Status |
|---|---|---|
| 0 | Write the idea down and try layouts in Figma | In progress. Judgment call, budget, 2 review rounds, known by the owner's first pass over the Figma rows. |
| 1 | Probes (below) | Not started. Field-checked, finish line, 1 to 2 days of build time, known by the end of the sync cost probe. |
| 2 | Index and sync core as a library with tests and a command-line tool, no window | Not estimated. Depends on phase 1. |
| 3 | A window that lists and opens pull requests from the index, with a fixed default layout | Not estimated. |
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
