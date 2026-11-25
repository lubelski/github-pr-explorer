# Prior art for github-pr-explorer

Research date: 2026-11-25. Every claim below cites the page it came from. Pages read at the source are listed in "Read at the source". Claims taken from search summaries, third-party pages, or memory are listed in "Second-hand or remembered".

## What changes what we should build

1. **Reviewing outside github.com is now a crowded field, and much of it is new in 2026.** At least eight native or desktop apps review GitHub pull requests end to end: Pulldog (native Mac, App Store), Lo (Electron, unreleased), review-man and Review Buddy (native Mac, open source), Pyor (web and desktop), GitHub's own Copilot app (desktop), Linear Diffs (inside Linear), and Graphite (web). Finishing a review without a browser is no longer a differentiator on its own. Pulldog is the closest existing product to the native Mac, local, review-to-merge part of the idea.
2. **Nobody we found lets a team rearrange the pull request page itself, or pick a layout by rule.** The nearest things are GitHub's docked side panels on Files changed (March 2026), reorderable inbox sections in Graphite and GitHub's dashboard, and Reviewable's per-repo settings and custom completion logic. The proven model for rule-picked layouts comes from outside code review: Salesforce Lightning record pages are assigned by app, record type, and profile, and each component can carry visibility filters. Jira lets admins drag fields per issue type. Ideas 3 and 4 appear to be the real gap.
3. **Few tools keep a real local index, and none publish a sync design for GitHub data.** Trailer (Core Data, GraphQL "v4" sync), Limn/pierre-review (SQLite via `gh`), Mergeable (browser storage), Neat (local only), and Pulldog (SwiftData, stated by the maker) store data locally. Linear Diffs relies on webhooks into Linear's servers and its docs admit state can be wrong when a webhook is missed. A desktop app with a user token cannot receive webhooks, so our sync has to be built on conditional requests (ETag and 304, which do not count against the rate limit) and GraphQL batching. That constraint should shape the design early.
4. **GitHub itself is moving fast on the same pains.** In 2026 it made the new Files changed page the default (January), shipped virtualization for huge diffs (April), made the pull requests dashboard GA with reorderable sections and saved views (July), shipped stacked PRs GA (October), and opened a new Overview page preview with merge readiness at the top (November). Anything we build should assume github.com keeps improving, and compete on speed, local search, and team-defined layouts rather than on fixing one GitHub bug.
5. **Linear is the obvious design reference twice over.** Its sync engine is the best-documented local-first client design in this space, and since May 2026 Linear also reviews GitHub pull requests (Diffs) with grouping, filters, guides, approve and merge. Study both before designing.

## Comparison table

Legend: Yes, Partial, No, or ? (could not confirm). "Local index" means it stores PR data on the device and reads from it. "Configurable layout" means the PR detail page itself can be rearranged.

| Tool | Kind | Maintained (latest seen) | Price | List and filter | Description and timeline | Diffs | Comment and approve | Merge | Checks | Local index | Configurable layout |
|---|---|---|---|---|---|---|---|---|---|---|---|
| gh-dash | Terminal UI (Go) | v4.26.3, 13 Nov 2026 | Free, open source | Yes, YAML sections | Partial, preview pane | Yes, via delta | Comment yes, approve ? | ? | ? | No mention | Sections and preview position only |
| GitHub CLI `gh pr` | Terminal commands | 2.106.0, 25 Nov 2026 | Free | Yes | Yes, `view` | Yes, `diff` | Yes, `comment`, `review` | Yes | Yes | No | No |
| GitHub Desktop | Electron app | ? | Free | Yes | Partial, commits only | Partial | No, says you cannot comment | No, sends you to github.com | Yes, can re-run | ? | No |
| GitHub Mobile | Native mobile | ? | Free | Yes | Yes | Yes | Yes | Yes | Yes | ? | No |
| GitHub Copilot app | Desktop app, Mac, Windows, Linux | GA 17 Jun 2026 | Copilot plans | Yes, filtering not described | Partial, summary and review activity | Yes | Comment yes, approve not stated | Agent merge | Yes | Partial, in-memory diff cache, metadata persists | No mention |
| github.com 2026 (dashboard, Files changed, Overview) | Web | Active, changes monthly | Free | Yes, saved views, reorder or hide sections | Yes | Yes | Yes | Yes | Yes | No | Docked panels only |
| Graphite | Web app, CLI, VS Code. Acquired by Cursor Dec 2025 | Active | Free tier, paid from about $20 per user per month | Yes, inbox sections with filters, drag to reorder | Yes | Yes | Yes | ? not described on PR page doc | Yes | No | Inbox only, PR page fixed |
| Linear Diffs | Inside Linear (web and desktop) | Launched 28 May 2026 | All Linear plans, Guides on paid plans | Yes, group, sort, filter, snooze | Partial, activity shown | Yes | Yes, syncs to GitHub | Yes | Partial, status only | Linear's own sync engine, PR data comes via webhooks | Review list grouping only |
| Reviewable | Web app | ? no dates on docs | Paid for private repos (not confirmed) | Yes, dashboard | Yes | Yes | Yes | Yes | Yes | No | Fonts, colors, custom stylesheet, per-repo settings and completion logic |
| CodeApprove | Web app | Could not confirm it still runs | ? | ? | ? | ? | ? | ? | ? | ? | ? |
| Pierre | Now infrastructure (Code Storage, Diffs library) | pierre.co redirects to pierre.computer | ? | No longer a PR review product on its site | | | | | | | |
| Limn (npm `pierre-review`, unrelated to Pierre) | Local web app via `npx` | Active, v0.1.122 on npm | Free, Pro $25 per user per month | Yes, six ranked tabs, rules and weights | ? | ? | Reply yes | Yes, on cards | Yes, red builds | Yes, SQLite on disk | Tab ranking rules only |
| Pulldog | Native Mac (SwiftUI, AppKit, SwiftData) | v5.0.1, 2026 | Free options, paid tiers not seen | Yes, rule-based smart queries | Yes | Yes, regex search across diffs | Yes | ? | Yes, pipelines | Stated by maker, design not published | Themes, collapsible sidebar |
| Lo | Electron, Mac first | Not released, active repo | Free, GPL-3.0 | Opens by URL, list ? | Partial, agent overview | Yes, revisions, moved code | Yes | Yes, with "why can't this merge" | ? | Local partial clone of the code | No mention |
| review-man | Native Mac (SwiftUI) | ? no dates shown | Free, open source | ? | ? | Yes | Yes, local drafts | ? | ? | Drafts and viewed marks only | Change canvas of file cards |
| Review Buddy | Native Mac (egui on GPU) | Early, 51 commits | Free, open source | Yes, inbox | Yes, summary screen | Yes | Yes | Yes | Yes, merge readiness | Local git worktrees | No |
| PR Pilot | Native Mac | ? | Free, open source | Yes, sidebar | ? | Yes, local | ? | ? | ? | ? | ? |
| Pyor | Web and desktop | Changelog to 3 Nov 2026 | Free for individuals, about $8 per user per month for orgs | Yes, saved views | ? | Yes, reordered by need | Yes | Yes per comparison post | Yes | Not mentioned | No |
| Stage | Web, AI chapters | Launched April 2026 (YC) | Free on public repos, paid private | ? | ? | Yes, as chapters | Yes, two-way sync (second-hand) | ? | ? | No, server side | No |
| Trailer | Native Mac (Swift), iOS lagging | 1.9.0, 29 Aug (year not shown) | Free, MIT | Yes, filters, per-repo display | Partial | No | No | No | Yes, statuses | Yes, Core Data, GraphQL sync | No |
| Gitify | Electron menu bar | v8.3.0, 25 Nov 2026 | Free, open source | Notifications | No | No | No | No | Yes, CI pills | ? | No |
| Neat | Mac menu bar | ? | Free | Notifications for GitHub and Linear | No | No | No | No | ? | Yes, "local-only data storage" | No |
| Pullbox | Native Mac | 2026, version not shown | Free | Yes, custom sections | No, opens browser | No | No | No | ? | Data stays on device | No |
| ReviewDesk | Mac menu bar (SwiftUI) | ? | ? | Review queue plus Jira status | No | No | No | No | ? | No backend | No |
| Mergeable | Web inbox, self-hostable | Last commits mid 2025 (second-hand) | Free, MIT | Yes, sections by search query | No | No | No | No | ? | Browser storage | Sections only |
| Octobox | Web, notifications | Page shows 2021 | Free for open source, $10 per user per month private | Notifications with CI and state filters | No | No | No | No | Yes | Server database (assumed, not stated) | No |
| Refined GitHub | Browser extension | 26.11.6, 6 Nov 2026 | Free | Adds filters | Adds activity filter | Tweaks | No new actions | No | No | No | Cleans and moves some chrome, no rearranging |
| VS Code GitHub Pull Requests | Editor extension | v0.182.0, 25 Nov 2026 | Free | Yes, configurable queries | Yes (not confirmed on page) | Yes | Yes | ? | ? | No | No |
| JetBrains GitHub plugin | IDE built-in | Current docs | With IDE | Yes, state, author, label, review status | Yes | Yes, review mode | Yes | Yes | ? | No | No |
| octo.nvim | Neovim plugin | Active, 1,743 commits | Free | Yes | Yes, timeline | Yes | Yes | Yes, merge queue | Yes | No, optional polling | Vim buffers |
| GitKraken | Electron Git client | ? | Paid | Launchpad PR list (not confirmed) | ? | ? | ? | ? | ? | ? | ? |
| Tower, Fork, Sublime Merge | Native Git clients | ? | Paid | No PR review found | | | | | | | |
| Zed | Native editor | Current docs | Free | No PR features in Git docs | | | | | | | |
| CodeRabbit, Copilot review, Greptile | AI bots that post comments | Active | Paid | Not a review surface | | | | | | | |

## Question 2: Local copies and sync

Tools that store PR data locally:

- **Trailer** keeps a Core Data store on the Mac and syncs from GitHub's GraphQL ("v4") API. Its release notes describe tunable paging, throttled query rates "to prevent failures due to server-side throttling", retries, and a one-time ID migration when GitHub changed node IDs. Its author also publishes TrailerQL, a Swift GraphQL builder that splits a batch of IDs across several queries to stay under GitHub's node limit. Neither repo describes the sync algorithm. Sources: https://github.com/ptsochantaris/trailer/releases, https://github.com/ptsochantaris/trailer-ql
- **Limn (`pierre-review`)** runs on your machine with `npx pierre-review`, uses your existing `gh` login, and keeps "a SQLite file on your disk" with no hosted backend. Source: https://cdn.jsdelivr.net/npm/pierre-review@0.1.122/public-landing/index.html
- **Mergeable** says "Data is all stored locally, in the browser storage." Source: https://raw.githubusercontent.com/pvcnt/mergeable/main/README.md
- **Neat** lists "local-only data storage". Source: https://neat.run/
- **Pulldog** is built on SwiftData and its maker says everything is stored locally and the app talks straight to GitHub and GitLab. Its site lists regex search across diffs, file names, and changed lines, which suggests a local index, but no design is published. Sources: https://www.producthunt.com/products/pulldog, https://www.natic.app/pulldog
- **Pullbox** says PR data "stays on your device and with GitHub". Source: https://apps.apple.com/us/app/pullbox/id6760965158
- **GitHub Copilot app** keeps PR metadata so the header and file tree repaint at once, holds the last few diffs in memory, and refreshes stale diffs in the background. It does not say whether anything is stored on disk. Source: https://github.blog/engineering/user-experience/rendering-huge-pull-requests-in-the-github-copilot-app
- **Lo, Review Buddy** keep local git checkouts or partial clones of the code, not an index of PR data. Sources: https://github.com/withlo/lo, https://github.com/dvlkv/review-buddy
- **Linear Diffs** stores PR data in Linear's own system, fed by a GitHub App. Its docs say "If a webhook is missed, the PR state can be wrong" and that editing the PR description on GitHub triggers a refresh. Source: https://linear.app/docs/diffs

What GitHub's API allows, which bounds any sync design:

- Conditional requests with `etag` and `if-none-match` return 304 when nothing changed, and "each 304 Not Modified response is fast and does not use your rate limit." Keep parameters identical between polls, since a different page or filter gives a different ETag. Honor `x-poll-interval` when present. GitHub recommends webhooks over polling where possible. Source: https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api
- GraphQL gives a user 5,000 points per hour, page sizes of 1 to 100, at most 500,000 nodes per call, 100 concurrent requests shared with REST, and 2,000 GraphQL points per minute per endpoint. Mutations cost 5 secondary points. Content creation is limited to about 80 per minute. Source: https://docs.github.com/en/graphql/overview/rate-limits-and-query-limits-for-the-graphql-api

No tool we found publishes a design for syncing GitHub PR data into a local index. That write-up would itself be new.

## Question 3: Rearranging the PR page, and layouts by rule

Within code review, nothing we found lets a user drag the blocks of a pull request page, define tabs, or choose a layout per repo, reviewer, or path.

The nearest things:

- **GitHub Files changed docked panels** (19 March 2026): Comments, Overview, Merge status, and Alerts open beside the diff. The changelog does not say they can be moved. Source: https://github.blog/changelog/2026-03-19-view-code-and-comments-side-by-side-in-pull-request-files-changed-page/
- **GitHub pull requests dashboard** (GA 9 July 2026): reorder or hide inbox sections, saved views from search queries. This is the list, not the PR page. Source: https://github.blog/changelog/2026-07-09-new-pull-requests-dashboard-is-now-generally-available/
- **GitHub Overview page** (public preview, November 2026): puts merge readiness and next actions at the top, with All, Unresolved, and Mine comment filters. Users can switch between it and the classic view, nothing more. Source: https://alternativeto.net/news/2026/11/github-previews-pull-request-overview-with-merge-readiness/
- **Graphite inbox**: sections with their own filters and repos, dragged to reorder. Its PR page doc describes a fixed layout. Sources: https://graphite.com/docs/customize-pr-inbox.md, https://graphite.com/docs/pr-page-overview.md
- **Linear Diffs**: group and subgroup reviews by status, author, repo, team, size, and priority, reorder the Created and To Review tabs, hide test or generated files in Guides. Source: https://linear.app/docs/diffs
- **Reviewable**: repo settings in a `.reviewable` directory or a master repo, "fully customizable logic" for when a review is complete, custom stylesheets. This is the only code review tool found with per-repo rules, though they decide completion rather than layout. Source: https://docs.reviewable.io/
- **Limn**: choose how tabs rank, set weights, and move card types between tabs. Source: https://cdn.jsdelivr.net/npm/pierre-review@0.1.122/public-landing/index.html
- **review-man** shows changed files as a zoomable canvas of cards, a different arrangement but not a user-defined one. Source: https://github.com/namuan/review-man

Outside code review, the closest models:

- **Salesforce Lightning App Builder**: record pages are built by dragging components, then activated as org default, app default, or by a combination of app, record type, and profile, per form factor. Each component can have visibility filters on field values, device, or user profile. This is close to ideas 3 and 4 combined and is worth studying for how admins reason about "which layout wins". Sources: https://trailhead.salesforce.com/content/learn/modules/lightning_app_builder/lightning_app_builder_recordpage, https://trailhead.salesforce.com/content/learn/modules/lightning_app_builder/add-visibility-rules-for-dynamic-pages-lab
- **Jira work item layout**: admins drag fields between description, context, and hidden sections, per work type. Types that share a screen scheme share a layout, a limit users complain about. Source: https://support.atlassian.com/jira-cloud-administration/docs/configure-issue-layout/
- Dashboards with draggable widgets (Azure DevOps dashboards, Grafana) and mail clients with configurable reading panes exist, but none were checked at the source for this report.

## Question 4: Local-first sync reading list

- **Linear, "Scaling the Linear Sync Engine"** (Tuomas Artman, 29 June 2023). How Linear's client sync engine evolved under scale and shaped its API. https://linear.app/now/scaling-the-linear-sync-engine
- **Tuomas Artman, React Helsinki talk on the sync engine.** The earlier talk the post above follows, explaining how the engine works. https://www.youtube.com/watch?v=WxK11RsLqp4&t=2175s
- **reverse-linear-sync-engine** (unofficial, praised by Linear's CTO as "probably the best documentation that exists"). Concrete detail on bootstrap, IndexedDB per model, an in-memory object pool, lazy hydration, a single monotonic `lastSyncId`, queued transactions, and delta packets over WebSocket. https://github.com/Aslam97/reverse-linear-sync-engine
- **Ink & Switch, "Local-first software"** (Kleppmann, Wiggins, van Hardenberg, McGranaghan, April 2019). The seven ideals, speed first, and the vocabulary everyone else uses. https://www.inkandswitch.com/essay/local-first/
- **Superhuman, "Architecting a web app to just work offline"**. Modifier queues that apply changes locally and synchronously, then replay against the server. This maps directly to optimistic review comments and approvals. https://blog.superhuman.com/architecting-a-web-app-to-just-work-offline-part-1/
- **Superhuman, "Building reliable apps on unreliable networks"**. How one failed request flips the app offline, with a 10 second wait before retry. https://blog.superhuman.com/building-reliable-apps-on-unreliable-networks/
- **Fastmail, "Building offline" series** (general architecture, mail storage, syncing changes back). A mail client with a server it does not fully control, close to our situation with GitHub. https://www.fastmail.com/blog/offline-architecture/ and https://fastmail.com/blog/offline-sync
- **GitHub, "The uphill climb of making diff lines performant"** (3 April 2026). Not sync, but the numbers for rendering huge diffs and why virtualization was needed. https://github.blog/engineering/architecture-optimization/the-uphill-climb-of-making-diff-lines-performant/
- **GitHub, "Rendering huge pull requests in the GitHub Copilot app"** (23 September 2026). How GitHub's own desktop app caches PR metadata and diffs and virtualizes comments. https://github.blog/engineering/user-experience/rendering-huge-pull-requests-in-the-github-copilot-app
- **GitHub REST best practices and GraphQL limits.** The real rules our sync must live within. https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api and https://docs.github.com/en/graphql/overview/rate-limits-and-query-limits-for-the-graphql-api

## Question 5: What people say is wrong with reviewing on github.com

1. **Large PRs made the page slow or unusable.** GitHub's own engineering blog says that on large pull requests "performance would noticeably decline", the JavaScript heap "could exceed 1 GB, DOM node counts surpassed 400,000", and interactions became "extremely sluggish or even unusable". (3 April 2026) https://github.blog/engineering/architecture-optimization/the-uphill-climb-of-making-diff-lines-performant/
2. **Files changed stops loading when comments pile up.** A PR with only 17 files but 190 review comments loaded 2 files and hung. 19 votes. (February 2022) https://github.com/orgs/community/discussions/11122
3. **No way to see all unresolved conversations.** Reviewers must click "Load more" repeatedly, which also breaks browser search, and hidden or outdated threads are hard to find. 277 votes, 59 participants, still open, last comment October 2026 says it is "still desperately needed". https://github.com/orgs/community/discussions/7638
4. **Force pushes break the review.** No line comments on force-push diffs, earlier versions cannot be compared, old comments do not carry over, and there is no "changes since my last review" view. 309 votes, unanswered since March 2021. https://github.com/orgs/community/discussions/3478
5. **Losing your place on long PRs.** After force pushes, new replies land in collapsed sections and there is no filter for threads you are in, so the reviewer re-reads the whole PR. (November 2022, small thread) https://github.com/orgs/community/discussions/39260
6. **Notification noise from team review requests.** Requesting a review from a team subscribes every member to every comment, with no way to unwatch a team. 459 votes, 52 participants. A GitHub notifications lead said in October 2025 a fix was still "a way off". https://github.com/orgs/community/discussions/15747
7. **Review requests get buried.** Linear's launch post for Diffs: "Review requests get buried in your email inbox and the queue offers no guidance on what is urgent", and large PRs are "reviewed in whatever order the filesystem produced the files". (28 May 2026) https://linear.app/now/code-review-should-be-fast
8. **AI bot comments drown the human review.** One developer counted 72 comments on one architectural PR, 37 from Copilot with the lowest signal. Vendors now market "without the comment spam". These are blogs, not large discussions. https://dev.to/adam-knitli/i-let-four-ai-code-reviews-fight-over-my-prs-17je, https://www.sonarsource.com/blog/ai-code-review-without-the-comment-spam/
9. **Very long timelines hide items.** One user had 1,317 hidden items and would need about 100 clicks to see them all. Refined GitHub's maintainer called auto-expanding "hostile to GitHub" because of page cost. https://github.com/community/community/discussions/128155, https://oss.issuehunt.io/r/sindresorhus/refined-github/issues/3814 (second-hand, see below)

## Question 6: The gap

What none of the tools we found does:

- Let a team rearrange the blocks of the pull request page, define its own tabs, and save that as a shared layout.
- Pick a layout automatically by rule (repo, reviewer, touched paths, code owner).
- Use one filter language for both search and layout rules.
- Publish how it keeps a local index of GitHub PR data in sync, and render every screen from it.

What is not a gap:

- Reviewing, approving, and merging without a browser. Pulldog, Review Buddy, review-man, Pyor, Lo, Linear Diffs, Graphite, the Copilot app, JetBrains, VS Code, octo.nvim, and `gh` all do some or all of it.
- A rule-based inbox. Pulldog smart queries, Graphite sections, GitHub saved views, Limn ranking rules, Mergeable, Pullbox, and gh-dash all do this.
- Fast rendering of huge diffs. GitHub, Lo, and Review Buddy all claim it.

How sure: fairly sure about the layout gap. I searched for it directly and read the docs of every major review surface, and found only fixed pages or panel toggles. Less sure that no small tool has it, since several 2026 apps (Pulldog, Pyor, PR Pilot, Review Buddy) have thin public docs and I did not install them. Pulldog is the one to check hands-on, since it calls itself "highly customizable". I am least sure about local indexes, because most tools do not say how they store data.

## Read at the source

| Claim | URL | Date of page or release |
|---|---|---|
| gh-dash is a Go TUI with YAML-defined PR and issue sections, diffs via delta, comment, checkout | https://github.com/dlvhdr/gh-dash | read 2026-11-25 |
| gh-dash latest v4.26.3, scratch sections in v4.26.0, bottom preview layout in v4.24.0 | https://github.com/dlvhdr/gh-dash/releases | 13 Nov 2026 |
| GitHub CLI 2.106.0 is latest | https://github.com/github/gh-cli/releases | 25 Nov 2026 |
| `gh pr` has list, view, diff, checks, comment, review, merge and more | https://cli.github.com/manual/gh_pr | read 2026-11-25 |
| Trailer is a Swift app for Mac and iOS, MIT, per-repo display settings and filters | https://github.com/ptsochantaris/trailer | read 2026-11-25 |
| Trailer 1.9.0 is macOS only, reworked Core Data access, earlier v4 API paging and retry changes | https://github.com/ptsochantaris/trailer/releases | 29 Aug, year not shown |
| TrailerQL batches IDs across queries to stay under node limits | https://github.com/ptsochantaris/trailer-ql | read 2026-11-25 |
| Lo is Electron, Mac first, unreleased, GPL-3.0, no backend, approve and merge, revisions, stacks | https://github.com/withlo/lo | read 2026-11-25 |
| review-man stores drafts and viewed marks locally, change canvas layout | https://github.com/namuan/review-man | read 2026-11-25 |
| Review Buddy draws diffs with egui, has merge, inbox, Claude features, no server | https://github.com/dvlkv/review-buddy | read 2026-11-25 |
| Pulldog v5.0.1, macOS 26.1+, App Store, smart queries, many providers, "highly customizable" | https://www.natic.app/pulldog | read 2026-11-25 |
| Linear Diffs covers diffs, threads, reviews synced to GitHub, merge, check status, grouping and filters, missed webhooks can leave state wrong | https://linear.app/docs/diffs | undated, read 2026-11-25 |
| Linear Diffs launch post and its complaints about review | https://linear.app/now/code-review-should-be-fast | 28 May 2026 |
| Graphite inbox sections can be filtered and dragged to reorder | https://graphite.com/docs/customize-pr-inbox.md | read 2026-11-25 |
| Graphite PR page sections, checks list, review shortcuts, no customization described | https://graphite.com/docs/pr-page-overview.md | read 2026-11-25 |
| pierre.co redirects to pierre.computer, which lists Code Storage and open-source Diffs, Trees, DiffsHub, no PR review product | https://pierre.computer/ | read 2026-11-25 |
| Limn (npm pierre-review) ranks work across repos, SQLite on disk via `gh`, rule settings, Pro $25 per user per month | https://cdn.jsdelivr.net/npm/pierre-review@0.1.122/public-landing/index.html | read 2026-11-25 |
| Pyor lists PRs with checks and reviewers, reorders files, thread inbox, desktop app, free for individuals | https://pyor.review/ | changelog Oct 25 to Nov 3 2026 |
| Gitify v8.3.0, Electron, notifications plus CI pills | https://github.com/gitify-app/gitify/releases | 25 Nov 2026 |
| Neat is a free menu bar app for GitHub and Linear notifications with local-only storage | https://neat.run/ | undated |
| Octobox notification triage, $10 per user per month for private | https://octobox.io/ | page shows 2021 |
| Pullbox is free, Mac only, custom sections, opens PRs in the browser, data stays on device | https://apps.apple.com/us/app/pullbox/id6760965158 | 2026 |
| Mergeable stores data in browser storage, sections by search query | https://raw.githubusercontent.com/pvcnt/mergeable/main/README.md | read 2026-11-25 |
| octo.nvim lists, reviews, approves, merges, shows checks, optional polling | https://github.com/pwntester/octo.nvim | read 2026-11-25 |
| VS Code GitHub Pull Requests latest v0.182.0 | https://github.com/microsoft/vscode-pull-request-github/releases | 25 Nov |
| JetBrains IDEs filter, review, approve, merge PRs | https://www.jetbrains.com/help/idea/work-with-github-pull-requests.html | read 2026-11-25 |
| Refined GitHub 26.11.6, moves the activity filter, dims viewed files, no page rearranging | https://github.com/refined-github/refined-github/releases | 6 Nov |
| GitHub Desktop cannot comment on PRs and sends you to GitHub to merge | https://docs.github.com/en/desktop/working-with-your-remote-repository-on-github-or-github-enterprise/viewing-a-pull-request-in-github-desktop | read 2026-11-25 |
| Zed's Git docs list no PR review features | https://zed.dev/docs/git | read 2026-11-25 |
| Reviewable has per-repo settings, custom completion logic, custom stylesheets | https://docs.reviewable.io/ | undated |
| GitHub Copilot app GA on macOS, Windows, Linux | https://github.blog/changelog/2026-06-17-github-copilot-app-generally-available | 17 Jun 2026 |
| Copilot app lists PRs, shows summary, Files changed, review, checks, agent merge | https://docs.github.com/en/copilot/how-tos/github-copilot-app/managing-issues-and-pull-requests | read 2026-11-25 |
| Copilot app keeps metadata, caches recent diffs in memory, virtualizes comments | https://github.blog/engineering/user-experience/rendering-huge-pull-requests-in-the-github-copilot-app | 23 Sep 2026 |
| GitHub diff performance numbers and admissions | https://github.blog/engineering/architecture-optimization/the-uphill-climb-of-making-diff-lines-performant/ | 3 Apr 2026 |
| Files changed docked panels | https://github.blog/changelog/2026-03-19-view-code-and-comments-side-by-side-in-pull-request-files-changed-page/ | 19 Mar 2026 |
| PR dashboard GA with reorder or hide sections and saved views | https://github.blog/changelog/2026-07-09-new-pull-requests-dashboard-is-now-generally-available/ | 9 Jul 2026 |
| Community discussions 7638, 3478, 39260, 11122, 15747 (votes and status as quoted above) | https://github.com/orgs/community/discussions/7638 and others in Question 5 | read 2026-11-25 |
| Conditional requests and 304s do not use rate limit, honor x-poll-interval | https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api | read 2026-11-25 |
| GraphQL limits | https://docs.github.com/en/graphql/overview/rate-limits-and-query-limits-for-the-graphql-api | read 2026-11-25 |
| Linear sync engine post | https://linear.app/now/scaling-the-linear-sync-engine | 29 Jun 2023 |
| Reverse-engineered Linear sync engine details | https://github.com/Aslam97/reverse-linear-sync-engine | read 2026-11-25 |
| Ink & Switch local-first essay and its seven ideals | https://www.inkandswitch.com/essay/local-first/ | Apr 2019 |

## Second-hand or remembered

These come from search summaries or third-party pages, not the tool's own site. Check before relying on them.

- Pulldog launched on Product Hunt in 2026, ranked fourth on 8 March 2026, is built with SwiftData, and stores everything locally (Product Hunt page, maker's words). https://www.producthunt.com/products/pulldog
- Graphite's pricing (free hobby tier, org repos from about $20 per user per month) comes from Pyor's comparison post, written by a competitor. https://pyor.review/blog/github-pr-review-alternatives
- Cursor agreed to acquire Graphite on 19 December 2025 and plans to keep it as a standalone product (Fortune, TechCrunch, Cursor blog via search). https://fortune.com/2025/12/19/cursor-ai-coding-startup-graphite-competition-heats-up/
- Stage is a YC Spring 2026 company that turns PRs into AI chapters, with two-way comment and approval sync and a Show HN in April 2026. https://www.ycombinator.com/launches/QQz-stage-code-review-platform-for-ai-generated-code
- GitHub stacked PRs entered public preview 30 July 2026 and became GA 6 October 2026. https://github.blog/changelog/2026-10-06-stacked-pull-requests-generally-available
- The GitHub Overview page preview is dated 5 November 2026 by AlternativeTo, while the changelog URL in search results reads 2026-12-05. The changelog itself was not opened. https://alternativeto.net/news/2026/11/github-previews-pull-request-overview-with-merge-readiness/
- The new Files changed page became the default on 22 January 2026, with large PRs up to 67 percent faster by 5 February 2026 (changelog titles via search). https://github.blog/changelog/2026-01-22-improved-pull-request-files-changed-page-on-by-default/
- PR Pilot (native Mac, sidebar of PRs, embedded Claude Code terminal) and ReviewDesk (menu bar, PRs and Jira, no backend) come from search snippets only. https://github.com/ordishs/PRPilot, https://reviewdeskapp.github.io/
- Gander (Rust, gpui, GitHub PRs and local diffs) is from a search snippet only. https://github.com/Plonq/pr-reviewer
- Mergeable has had no commits since June 2025, per a third-party directory. https://awesome.ecosyste.ms/projects/github.com%2Fpvcnt%2Fmergeable
- GitHub Mobile supports review, approve, merge, and shows checks and mergeability, from changelog snippets and store listings. https://github.blog/changelog/2024-04-09-introducing-enhanced-code-review-on-github-mobile
- CodeApprove's site returned only a title. A third-party listing from September 2026 shows a free tier and a custom-priced Pro tier. Whether it still runs is unconfirmed. https://toolradar.com/tools/codeapprove
- GitKraken Launchpad as a PR list: its help page returned 404. Remembered, not confirmed.
- Tower, Fork, and Sublime Merge: no PR review features found. Tower's help page returned 404. Sublime forum threads show users asking for PR integration. https://forum.sublimetext.com/t/checkout-pr/40495
- The 1,317 hidden items thread and the Refined GitHub maintainer's "hostile to GitHub" remark come from search summaries. https://github.com/community/community/discussions/128155
- Bot noise figures (72 comments, 37 from Copilot) are one developer's blog post. https://dev.to/adam-knitli/i-let-four-ai-code-reviews-fight-over-my-prs-17je
- Salesforce activation and visibility filter details come from Trailhead via search summaries, not read directly.
- Jira layout behavior comes from Atlassian docs and community threads via search summaries.
- Superhuman's offline architecture details come from search summaries of its blog posts.
- Reviewable's pricing for private repos is remembered, not confirmed.
