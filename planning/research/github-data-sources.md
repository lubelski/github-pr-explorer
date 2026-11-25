# GitHub data sources for the sync layer

Research for `github-pr-explorer`, a native macOS app that renders every screen from a local index of pull request data. This file says what each GitHub source can supply, how fast, and at what cost. Written 2026-11-25.

Every claim is tagged. "Verified" means it was checked here with a command, and the command and output are in "Verified here". "Docs" means it was read in GitHub's documentation, with the URL in "Read, not verified". "Believed" means no source was found. Measurements were taken against public repositories with one user token on one afternoon, so treat the numbers as indications, not guarantees.

## Top findings

1. **Conditional REST requests are free, and that makes per-resource polling viable.** A 304 response left `x-ratelimit-remaining` unchanged on every endpoint tested: PR list, single PR, reviews, review comments, timeline, check runs, combined status, notifications (verified). The docs agree (docs). What is not known is whether 304s count against the secondary limit of 900 REST points per minute. That decides how many resources can be polled per minute.

2. **GraphQL point cost is not the constraint. Server time is.** One aliased query covering 20 repos and 174 open PRs cost 1 point for `number updatedAt headRefOid`, 2 points for the check rollup state and 1 point for `reviewDecision`, but the last two took 7.4 and 8.5 seconds. Combining them with labels and review requests gave "Resource limits for this query exceeded" on 175 nodes, and adding `mergeable` gave a 502 after about 10 seconds (verified). GitHub ends queries at 10 seconds and charges extra points for timeouts (docs). So the sync layer must split computed fields (mergeability, check rollup, review decision) into small batches. It cannot fetch "everything for every PR" in one query.

3. **Polling cannot hold 200 PRs to 30 seconds on everything, mainly because of checks.** Lightweight change detection is cheap: about 120 GraphQL points an hour, or a free `git ls-remote` (see question 6). But a check finishing did not move the PR's `updatedAt` in the one case observed (verified, one sample). So check state has to be polled per head commit, which is 400 REST requests per 30 seconds for 200 PRs. That is about 840 a minute, too close to the 900-a-minute secondary limit if 304s count, and too slow if requests are sent serially as GitHub asks. Near-real-time checks need push: webhooks through a relay.

4. **Webhooks need a server, and every relay option has a catch.** `gh webhook forward` is for testing only and allows one forwarder per repo or org (docs). Repo and org webhooks need admin rights. Failed deliveries are not retried automatically, and can be redelivered only for 3 days (docs). The clean design is a GitHub App, whose webhooks for every installation go to one URL, feeding a small hosted relay that pushes to the desktop app over WebSocket or server-sent events. But installing an app on an org needs an org owner (docs). For orgs where that will not happen, the app has to fall back to polling.

5. **The `gh` CLI token is the easiest token to start with, and the only common one that reads notifications.** It is an OAuth app token with `repo, read:org, gist, workflow` scopes (verified). The GitHub CLI is a "privileged" OAuth app, so org OAuth restrictions do not block it (docs). The Notifications API supports only classic-style tokens (docs), and fine-grained PATs do not list notifications or the Checks API (docs). A fine-grained PAT is also limited to one org per token (docs). GitHub App user tokens are the long-term answer for orgs that install the app, but they are believed not to read notifications.

Two smaller facts also shape the design. GraphQL's changed-files type has no patch field, so per-file patches come from REST or git (verified). And a local partial clone fetches all PR head refs of a small repo in about 1 second and computes diffs locally in 0.03 to 0.4 seconds (verified).

## Data kinds by source

Columns: GraphQL API, REST API, `gh` CLI, local git clone, webhooks (via relay), web page scraping. `gh` is a client for REST and GraphQL with the same costs, so its column only notes what it adds.

| Data | GraphQL | REST | `gh` CLI | Local git | Webhooks | Web scraping |
|---|---|---|---|---|---|---|
| Open PR list across many repos, filter and sort fields | Yes. One aliased query for 20 repos cost 1 point with minimal fields (verified). `search(type:ISSUE)` across repos cost 1 point (verified). Search caps at 1,000 results (docs). | Yes. `GET /repos/{o}/{r}/pulls` per repo, 100 per page, ETag, 304 free (verified). Search API 30 a minute (docs). | Yes, `gh pr list`, `gh search prs`. Same costs. | Partly. `ls-remote refs/pull/*/head` gives numbers and head SHAs only, includes closed PRs (verified). No titles or state. | Partly. `pull_request` events for changes, not an initial list. | Possible, but no reason to. |
| Title, body (markdown and HTML), labels, milestone, assignees, linked issues | Yes. `body`, `bodyHTML`, labels, assignees, `closingIssuesReferences` (verified). | Yes. `application/vnd.github.html+json` or `full+json` adds `body_html` (docs). Linked issues not in the PR object (believed). | Yes. | No. | Yes, `pull_request` edited, labeled, assigned and similar (docs). | Not needed. |
| Reviews, requested reviewers and teams, review decision | Yes. `reviews`, `reviewRequests` with User or Team, `asCodeOwner`, `reviewDecision` (verified). `reviewDecision` is slow over many PRs (verified). | Yes. `/pulls/{n}/reviews`, `requested_reviewers` in the PR object (verified). Review decision is not a REST field (believed). | Yes. | No. | Yes. `pull_request_review`, `pull_request` review_requested (docs). | Not needed. |
| Review threads and comments, resolved state, outdated state | Yes. `reviewThreads { isResolved isOutdated comments }` (verified). About 0.6 points per PR at 50 threads by 10 comments (verified). | Partly. `/pulls/{n}/comments` has comments but not thread resolved state (believed). | Yes. | No. | Yes. `pull_request_review_thread` resolved and unresolved, `pull_request_review_comment` (docs). | Not needed. |
| Checks, commit statuses, required checks, branch protection and ruleset results | Partly. `statusCheckRollup` with `CheckRun.isRequired(pullRequestNumber:)` and `StatusContext` (verified). Rollup over 174 PRs took 7.4 s (verified). `baseRef.rules` and `branchProtectionRule` readable (verified). | Yes. `/commits/{sha}/check-runs`, `/commits/{sha}/status`, `/rules/branches/{b}` (verified). Check runs per ref cover only the 1,000 most recent suites (docs). Fine-grained PATs are not listed for check runs (docs). | Yes, `gh pr checks`. | No. | Yes. `check_run`, `check_suite`, `status` (docs). Repo and org hooks get only created and completed for check runs (docs). | Partly. The merge box shows rule evaluation in prose. |
| Mergeability, merge state, merge queue position | Yes. `mergeable`, `mergeStateStatus`, `mergeQueueEntry { position estimatedTimeToMerge }` (verified). Slow, about 5 s for 34 PRs, and 502 for 174 at once (verified). | Partly. `mergeable`, `mergeable_state`. Null while GitHub computes in the background (docs, and seen `unknown` on a merged PR, verified). No queue position (believed). | Yes. | Partly. A trial merge shows conflicts, not rules or checks. | Partly. `pull_request` enqueued and dequeued (docs). `merge_group` is app-only (docs). No event for mergeability changes (believed). | Partly. |
| Changed files, per-file patches, full diff | Partly. `files { path additions deletions changeType viewerViewedState }`. No patch field (verified). | Yes. `/pulls/{n}/files` with `patch`, max 3,000 files (docs). Full diff via `application/vnd.github.diff` (verified, 3,179 bytes for a 3-file PR). | Yes, `gh pr diff`. | Yes, and fastest. 0.37 s first diff with lazy blob fetch, 0.03 s after (verified). | No. `synchronize` says the head moved (docs). | No. |
| Timeline of events | Yes. `timelineItems` (verified totals). | Yes. `/issues/{n}/timeline`, ETag, 304 free (verified). | Partly. | Partly. Commits and force-push history if refs are kept. | Partly, as separate events. | Not needed. |
| CODEOWNERS and which owners a PR touches | Partly. `Repository.codeowners` exists (verified by introspection). `ReviewRequest.asCodeOwner` (verified). No per-file owner field (verified). | Partly. File contents via the contents API, `/codeowners/errors` (verified). | Partly. | Yes. Read the base branch's file and match paths locally (verified file read). | Partly, `push` to the base branch. | The files tab shows owners per file (believed). |
| Commits | Yes. `commits` connection. | Yes. `/pulls/{n}/commits`, max 250 (docs). | Yes. | Yes, and complete. `git log base...head` (verified). | Partly. `synchronize` and `push`. | Not needed. |

## Question 2: learning about changes quickly without a server

**Conditional requests.** Most REST endpoints return an `ETag`, many a `Last-Modified` (docs). A 304 did not reduce `x-ratelimit-remaining` on any endpoint tested (verified). The docs say a 304 "does not count against your primary rate limit" (docs). Not known: whether 304s count toward the 900 points per minute secondary limit, and how quickly a list ETag changes after a field inside it changes. The PR list response also carried `Cache-Control: private, max-age=60` (verified), which hints that list responses may be cached for up to 60 seconds. GraphQL is POST-only and has no conditional requests (believed).

**Notifications API.** `GET /notifications` returned `X-Poll-Interval: 60` and a `Last-Modified` header (verified). A 304 leaves the rate limit untouched, and the interval can grow under load (docs). It covers only threads the user is subscribed to, with reasons like `review_requested` and `subscribed` (docs). It supports only classic-style tokens with `notifications` or `repo` scope (docs). It worked with the `gh` OAuth token (verified). Good for "something happened to a PR I care about", within about 60 seconds. Not good for checks, and not good for repos the user does not watch.

**Events API.** `/repos/{o}/{r}/events` returned `X-Poll-Interval: 60` and `Cache-Control: max-age=300` (verified). Docs say latency is "anywhere from 30s to 6h", the API "is not built to serve real-time use cases", and it holds at most 300 events from the last 30 days (docs). Usable as a cheap hint, not as a source of truth. Its real delay was not measured here.

**Atom feeds.** `github.com/cli/cli/commits/trunk.atom` and `releases.atom` returned 200. `pulls.atom` returned 406, and `pull/15111.atom` redirected to a "new pull request" URL (verified). There is no PR feed.

**GraphQL `updatedAt` ordering.** `pullRequests(orderBy:{field:UPDATED_AT, direction:DESC})` works and is cheap (verified). A poll can stop reading when it reaches a PR not updated since the last poll. But in one observed case a check run completed 6 minutes after the PR's `updatedAt` (verified, one sample). So `updatedAt` probably does not cover checks, and may not cover mergeability changes.

**`git ls-remote`.** Listing `refs/pull/*` for `cli/cli` returned 5,568 refs in 0.46 s (verified). This shows new pushes to any PR by comparing head SHAs, uses git over HTTPS and not the REST API, and is believed not to count against the API rate limit.

**Webhooks.** Events cover everything the sync layer needs: `pull_request` with synchronize, review_requested, enqueued, dequeued, auto_merge_enabled, plus `pull_request_review`, `pull_request_review_comment`, `pull_request_review_thread` resolved and unresolved, `check_run`, `check_suite`, `status` and `issue_comment` (docs). `merge_group` is app-only (docs). Payloads over 25 MB are dropped (docs). The receiver must answer within 10 seconds (docs). Failed deliveries are not redelivered automatically, and redelivery works only for the last 3 days (docs). A desktop app has no reachable endpoint, so it needs a relay.

**Relay options.**
- `gh webhook forward` (the `cli/gh-webhook` extension). For testing and development only, one user at a time per repo or org, and org hooks need `admin:org_hook` scope (docs). Not a product path.
- smee.io style relays receive payloads and forward them over server-sent events (docs). The public smee service makes no promises. Anyone with the channel URL can read the payloads (believed).
- A small hosted relay of our own, reached by the app over WebSocket or server-sent events. This works best paired with a GitHub App, since one app webhook URL receives events for every installation (believed, standard GitHub App design). It is the only option here that can give 30-second freshness on checks. It is also a server to run.
- Repo or org webhooks created by the user. Each needs admin on that repo or owner on that org (believed), so it only works for the user's own repos.

**GitHub's own web page.** A logged-out fetch of a PR page contained `data-channel` attributes with signed, base64 channel names such as `pull_request:<id>`, `pull_request:<id>:timeline`, `pull_request_review:<id>` and `repo:<id>:commit:<sha>` (verified). This is GitHub's internal live-update ("alive") WebSocket system. It is undocumented, the channel names are signed and time-stamped, and using it from a third-party app would be fragile and likely against the spirit of the terms. Treat it as proof of what events exist, not as a source.

## Question 3: what a local git clone gives

Measured on `cli/go-gh` (781 KB repo), all verified:

| Step | Time | Disk |
|---|---|---|
| Bare partial clone, `--filter=blob:none` | about 1 s | 536 KB |
| Bare full clone | about 1 s | 1.0 MB |
| Fetch `+refs/pull/*/head` into the partial clone, 238 refs | about 1 s | 888 KB total |
| Same fetch again, nothing new | under 1 s | none |
| First `git diff --stat` of a PR, blobs fetched on demand | 0.37 s | small |
| Same diff again | 0.03 s | none |

The local diff matched the API (3 files, +3, -3). The base branch's `.github/CODEOWNERS` was readable locally. GitHub also serves `refs/pull/*/merge` refs (24 on `go-gh`), the test merge commits for open, mergeable PRs (verified).

What git gives better than the API: full diffs and per-file patches with no 3,000 file cap, any diff view (per commit, between pushes), blame, CODEOWNERS matching, `.gitattributes` for generated files, and commit history beyond the API's 250-commit limit. Its costs: a clone per repo, and fetch time that grows with repo size. `cli/cli` is about 84 MB on GitHub (`size` field) with 5,568 PR refs, and larger repos were not measured. Partial clone helps a lot because history without blobs is small, and blobs arrive only for the files actually diffed. Fetching every PR ref of a big monorepo will still pull many trees and commits. A safer default is to fetch only the head refs of open PRs the user cares about.

## Question 4: what only the web page shows

| Item | API situation | Confidence |
|---|---|---|
| Code owners per changed file in the files tab | No per-file owner field (verified by introspection). Compute it from CODEOWNERS locally. | High that the API lacks it. Medium that the web shows it per file (believed). |
| Syntax-highlighted and rich diffs (images, rendered markdown, notebooks) | API and git give plain patches only. Render locally. | High |
| Prose explanation of why merge is blocked, naming the rule or check | API gives `mergeStateStatus` enums, `viewerCannotUpdateReasons`, required flags on checks, and rules per branch (verified). The exact combined explanation has to be rebuilt. | Medium |
| Live updates while viewing | Internal WebSocket channels exist (verified). No public API. | High |
| Large or generated files collapsed with "Load diff" | REST omits patches for very large files (believed). Generated status comes from `.gitattributes`, readable with git. | Low |
| Unread or new-since-last-visit markers | `isReadByViewer` exists on PRs (verified by introspection). Per-comment "new" markers are not in the API (believed). | Low |

Almost everything else on the PR page is available through GraphQL, including viewed-file state (`viewerViewedState`), suggested reviewers, merge queue position and estimated time (all verified as fields). Scraping looks worth it only for the merge-box prose, and probably not even there.

## Question 5: authentication

| | `gh` CLI token | Fine-grained PAT | OAuth App, device flow | GitHub App, user token |
|---|---|---|---|---|
| What it is | OAuth token of GitHub's own CLI app. Here: `gho_` prefix, scopes `gist, read:org, repo, workflow` (verified). | Token the user makes, limited to one owner (user or org), chosen repos and permissions (docs). | Our own OAuth app. Classic scopes. Device flow needs no client secret (docs for apps, believed same for OAuth apps). | Our own GitHub App. Token is the intersection of app permissions, user permissions and installed accounts (docs). Expires in 8 hours, refresh token lasts 6 months (docs). |
| Reads all PR data above | Yes, everything tested worked (verified). | Mostly. Pulls, reviews, merge, CODEOWNERS errors, branch rules, search are listed (docs). Check runs and notifications are not (docs). | Yes, with `repo` scope (believed). | Yes for installed repos with read permissions on pull requests, contents, checks, statuses (believed). Notifications believed not available. |
| Many orgs | Yes. | One org per token, so one token per org (docs). | Yes, if each org allows it. | Only orgs where the app is installed (docs). |
| Rate limit | User's 5,000 REST per hour and 5,000 GraphQL points, shared with all the user's other tools (docs). | Same shared user budget (docs). | Same shared user budget (docs). | User's limit, 15,000 if the app is owned by an Enterprise Cloud org (docs). Installation tokens get a separate 5,000 to 12,500, but need the app's private key, so only a server can use them (believed). |
| Can write (approve, comment, merge) | Yes, with `repo` scope (believed). | Yes, with write permissions (docs list POST and PUT on reviews and merge). | Yes, with `repo` scope (believed). | Yes, if the app has write permissions and the user can write (docs). |
| What an org admin must do | Nothing. GitHub CLI is a privileged OAuth app that org restrictions do not block (docs). SAML SSO orgs may need the token authorized (believed). | Approve the token if the org requires approval. Until then it reads only public resources (docs). Orgs can block fine-grained PATs (docs). | Approve the app. OAuth app restrictions are on by default for new orgs (docs). | Install the app. Only org owners can, or repo admins for their repos if the app asks no org permissions (docs). Members can request it (docs). |
| Risk | Depends on another app's login. Breaks on `gh auth logout`. Scopes are broad. | Users must make and rotate tokens by hand. | Blocked in many orgs. | Needs a server for webhooks to pay off. Needs install per org. |

Suggested order: start with the `gh` token for the first build, add a GitHub App for orgs that will install it (and for webhooks), and keep a fine-grained PAT as a manual fallback.

## Question 6: rate limits and the cost of 200 PRs fresh to 30 seconds

**Budgets (docs).**
- REST, user token: 5,000 requests per hour. GitHub App installation: at least 5,000, plus 50 per repo and 50 per org user beyond 20, capped at 12,500, or 15,000 on Enterprise Cloud.
- GraphQL, user: 5,000 points per hour. Installation: 5,000 base with the same scaling to 12,500, or 10,000 on Enterprise Cloud.
- Search: 30 requests per minute.
- Secondary limits: 100 concurrent requests across REST and GraphQL, 900 points per minute per REST endpoint, 2,000 points per minute for GraphQL, 90 seconds of CPU per minute with at most 60 for GraphQL. REST GET costs 1 point, mutations 5. Requests over 10 seconds are killed with 502 or 504 and cost extra points.
- GitHub asks for serial requests, not concurrent ones, and at least 1 second between writes.

**GraphQL cost.** Add up the requests each connection would need if it filled its `first` or `last`, divide by 100, round, minimum 1 (docs). Measured (verified): one repo, 10 PRs, with files(100), timeline(50), threads(50) by comments(10) cost 6 points. 20 PRs cost 12. 20 repos by 10 PRs with only `number updatedAt headRefOid` cost 1. The same with reviews(20), threads(50) by comments(10) cost 104 points for 174 PRs. The 500,000-node limit was never the problem.

**Setup.** 20 repos, 10 open PRs each, 200 PRs. Fresh within 30 seconds means 120 cycles an hour.

1. **Full GraphQL refresh every cycle.** About 0.6 points per PR for reviews and threads (104 / 174), so about 120 points per cycle. 120 x 120 = 14,400 points an hour against 5,000. About 2.9 times over budget, before adding checks and merge state, which time out when combined anyway. Not possible.

2. **GraphQL change detection, then targeted refetch.** One minimal aliased query per cycle costs 1 point (verified, 2.2 s), so 120 points an hour, 2.4% of the budget. Adding rollup state (2 points), review decision (1 point) and mergeability in batches of about 35 PRs (1 point each, so 6) gives about 10 points per cycle, 1,200 points an hour, 24% of the budget. Then, if 10 PRs change per cycle at 0.6 points each, add 6 points a cycle, 720 an hour. Total about 1,900 points an hour, 38%. The catch is time: rollup plus review decision plus mergeability took about 7 + 8 + 30 seconds of server time per cycle (verified, timings above). That is longer than the 30-second cycle and close to the 60 seconds of GraphQL CPU allowed per minute, if wall time is mostly CPU time (not known).

3. **REST with ETags.** Per cycle: 20 list requests, plus 200 check-run and 200 status requests by head SHA, so 420 requests per 30 seconds, 840 per minute. Primary cost is only the 200 responses, since 304s are free (verified). If 304s count toward the 900 points per minute secondary limit, this is 93% of it. At about 0.3 to 0.4 s per request (verified), 420 serial requests take about 150 seconds, five times the cycle. Holding 30 seconds would need about 6 parallel requests, against GitHub's advice.

4. **Free signals.** Notifications every 60 seconds, 20 repo event feeds every 60 seconds, and `git ls-remote` per repo all cost nothing on a 304 or are outside the API. They catch most human activity within a minute, but not checks. Events can lag up to 6 hours.

**What it implies.** Thirty-second freshness for everything, for 200 PRs, is not reachable by polling with one user token. It is reachable for "did anything change" (option 2's minimal query, or `ls-remote`). The sync layer should be tiered: a cheap global change detector every 30 seconds, full detail refetched only for PRs that changed, check and merge state polled often only for PRs on screen or marked important and slowly for the rest, and webhooks through a relay where an org allows a GitHub App. The user's budget is shared with `gh`, editors and other tools (docs), and a decrement from another consumer was seen during testing (verified). Budget for at most half of it.

## Question 7: terms on automated access and scraping

GitHub's Acceptable Use Policies define scraping as "extracting information from our Service via an automated process" and say it "does not refer to the collection of information through our API". They allow scraping of public information for research (with open-access publication) and archiving, and forbid using GitHub information for spam or selling personal information (https://docs.github.com/en/site-policy/acceptable-use-policies/github-acceptable-use-policies#7-information-usage-restrictions). The same policies forbid "excessive automated bulk activity". The Terms of Service section H says excessive API use can lead to suspension at GitHub's sole discretion, and forbids sharing tokens to exceed rate limits (https://docs.github.com/en/site-policy/github-terms/github-terms-of-service#h-api-terms). Nothing found allows scraping logged-in pages for a product, so scraping should stay a last resort for data that no API supplies, at human-like rates, for the user's own view.

## Verified here

All on 2026-11-25, with the `gh` CLI (2.103.3) logged in as the owner, against public repositories. Token values were never printed.

1. **A 304 is free against the primary limit.**
   `gh api -i 'repos/cli/cli/pulls?per_page=1'`, then the same with `-H "If-None-Match: <etag>"` twice, then without.
   `200 OK`, `X-Ratelimit-Remaining: 4979` / `304 Not Modified`, `4979` / `304 Not Modified`, `4979` / `200 OK`, `4978`.
   Also seen: `Cache-Control: private, max-age=60, s-maxage=60`, `X-Github-Api-Version-Selected: 2022-11-28`.

2. **304 on per-PR endpoints.** Same method on `cli/cli` PR 15111. `commits/{sha}/check-runs` 4868 to 4868, `commits/{sha}/status` 4867 to 4867, `pulls/15111` 4866 to 4866, `pulls/15111/reviews` 4865 to 4865, `issues/15111/timeline` 4862 to 4862, all 304. `pulls/15111/comments` first went 4864 to 4863, then five repeats stayed at 4861, so the first drop came from another consumer of the same budget.

3. **Poll interval headers.** `gh api -i 'notifications?per_page=1'`: `X-Poll-Interval: 60`, `Last-Modified` present, `X-Ratelimit-Resource: core`. `gh api -i 'repos/cli/cli/events?per_page=1'`: `X-Poll-Interval: 60`, `Cache-Control: private, max-age=300`. `users/<login>/received_events`: `X-Poll-Interval: 60`.

4. **Budgets.** `gh api rate_limit`: core limit 5000, graphql 5000, search 30, code_search 10.

5. **GraphQL `used` counter is inconsistent.** Repeated `{rateLimit{cost used remaining}}` returned `used: 42` three times, then a query in between returned `used: 156`, then `42` again. Cost-1 queries did not always move `used`. Do not rely on exact counter values.

6. **GraphQL costs.** Single repo `cli/cli`, open PRs with labels(10), reviewRequests(10), reviews(10), reviewThreads(20) by comments(5), rollup contexts(30): `cost 5`. With files(100), timelineItems(50), reviewThreads(50) by comments(10), contexts(50): 10 PRs `cost 6, nodeCount 7820`, 20 PRs `cost 12`, 30 PRs `cost 17` in 4 s, 50 PRs `502 Bad Gateway` after 11 s.

7. **GraphQL across 20 repos, 10 PRs each, 174 PRs returned.** Repos: cli/cli, cli/go-gh, cli/oauth, cli/gh-extension-precompile, github/docs, github/gitignore, github/linguist, github/copilot.vim, microsoft/vscode, microsoft/TypeScript, golang/go, rust-lang/rust, nodejs/node, facebook/react, vercel/next.js, kubernetes/kubernetes, python/cpython, apple/swift, swiftlang/swift-format, Homebrew/brew.
   - `number updatedAt headRefOid`: cost 1, 2.2 s, no errors.
   - `commits(last:1){...statusCheckRollup{state}}`: cost 2, 7.4 s.
   - `reviewDecision`: cost 1, 8.5 s.
   - labels(10), reviewRequests(10), isDraft: cost 4, 3.3 s.
   - reviews(20), reviewThreads(50) by comments(10): cost 104, 3.7 s.
   - The first four combined: cost 6, 10.4 s, 175 errors `Resource limits for this query exceeded.`
   - `mergeable mergeStateStatus`: `502 Bad Gateway` after 10.7 s. For the first 5 repos (34 PRs): cost 1, 5.1 s. For `cli/cli` alone (10 PRs): 1.5 s.

8. **Cross-repo search.** `search(type:ISSUE, query:"is:pr is:open repo:cli/cli repo:cli/go-gh", first:50)`: `cost 1`, `issueCount 76`.

9. **PR fields.** On `cli/cli` PR 12000 (merged): `bodyHTML` 4,817 characters, `mergeable UNKNOWN`, `baseRef.rules` `[COPILOT_CODE_REVIEW]`, `branchProtectionRule null`, timeline total 46. REST for the same PR: `mergeable null`, `mergeable_state "unknown"`. Five recent open PRs: `CONFLICTING/DIRTY` once and `MERGEABLE/BLOCKED` four times. `gh api repos/cli/cli/rules/branches/trunk` returned `["copilot_code_review"]`. `gh api repos/cli/cli/codeowners/errors` returned `{"errors":[]}`.

10. **Schema facts by introspection.** `PullRequestChangedFile` fields: `additions changeType deletions path viewerViewedState`, no patch. `ReviewRequest` fields include `asCodeOwner`. `Repository` has `codeowners`, `rulesets`, `mergeQueue`, `branchProtectionRules`. `PullRequest` has 114 fields, including `isReadByViewer`, `mergeQueueEntry`, `suggestedReviewers`, `viewerCannotUpdateReasons`. `MergeQueueEntry` accepts `position estimatedTimeToMerge`.

11. **Check completion versus `updatedAt`.** Among the 15 most recently updated open PRs on `cli/cli`, PR 14846 had `updatedAt 2026-10-28T02:11:55Z` and a check completed at `02:18:06Z`. One sample.

12. **Diff size.** `gh api repos/cli/cli/pulls/15111 -H 'Accept: application/vnd.github.diff'`: `200`, `Content-Length: 3179`, `ETag` present.

13. **REST PR list fields.** `pulls` objects include `assignees, auto_merge, draft, labels, milestone, requested_reviewers, merge_commit_sha`. 56 open PRs on `cli/cli`.

14. **Token type.** `gh auth token` matched the `gho_` prefix (OAuth app user token). `gh api -i user`: `X-Oauth-Scopes: gist, read:org, repo, workflow`. Notifications endpoint worked with it.

15. **Atom feeds.** `curl` status: `commits/trunk.atom` 200, `releases.atom` 200, `pulls.atom` 406, `pull/15111.atom` 302 to `/pull/new/15111.atom`.

16. **Web page live channels.** `curl` of `https://github.com/cli/cli/pull/15111` logged out, 348,974 bytes. 15 `data-channel` attributes. Decoded payloads include `{"c":"pull_request:5406301962","t":...}`, `pull_request:5406301962:timeline`, `pull_request_review:5986391264`, `repo:212613049:commit:<sha>`. Strings `alive_channel`, `aliveChannels` present.

17. **Git.** In `research-data-sources/` under the scratchpad: `git clone --bare --filter=blob:none https://github.com/cli/go-gh.git` about 1 s, 536 KB. Full bare clone about 1 s, 1.0 MB. `git fetch origin '+refs/pull/*/head:refs/remotes/pr/*'` about 1 s, 238 refs, 888 KB total, repeat under 1 s. `git ls-remote origin 'refs/pull/*/merge'` 24 refs. PR 331 `git diff --stat` 0.37 s then 0.03 s, `3 files changed, 3 insertions(+), 3 deletions(-)`, same as API. `.github/CODEOWNERS` read locally: `* @cli/code-reviewers`. `git ls-remote https://github.com/cli/cli.git 'refs/pull/*'` 5,568 refs in 0.46 s. API `size` field: cli/cli 83,715 KB, cli/go-gh 781 KB.

## Read, not verified

- REST primary limits, secondary limits, point values, 100 concurrent requests, 900 REST and 2,000 GraphQL points per minute, CPU time limits: https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api
- GraphQL limits, cost algorithm, node limit 500,000, first/last 1 to 100, 10-second timeout with extra points charged: https://docs.github.com/en/graphql/overview/rate-limits-and-query-limits-for-the-graphql-api
- 304 does not count against the primary limit, make requests serially, wait 1 second between writes, prefer webhooks: https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api
- Events latency 30 s to 6 h, 300 events, 30 days, ETag polling: https://docs.github.com/en/rest/activity/events
- Notifications `Last-Modified` polling, `X-Poll-Interval`, reasons, classic tokens only: https://docs.github.com/en/rest/activity/notifications
- PR files max 3,000, PR commits max 250, `mergeable` null while computed, HTML media types: https://docs.github.com/en/rest/pulls/pulls
- Check runs: only GitHub Apps write, 1,000 most recent suites per ref: https://docs.github.com/en/rest/checks/runs
- Search 30 per minute, 1,000 results, 256 characters, 5 operators: https://docs.github.com/en/rest/search/search
- Timeline endpoint and event types: https://docs.github.com/en/rest/issues/timeline
- Fine-grained PAT endpoint list (pulls, reviews, merge, codeowners errors, branch rules, search listed. Check runs and notifications not found): https://docs.github.com/en/rest/authentication/endpoints-available-for-fine-grained-personal-access-tokens
- Fine-grained PAT limits, one owner per token, org approval, pending tokens read public only: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens
- GitHub App user token scope: https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/authenticating-with-a-github-app-on-behalf-of-a-user
- GitHub App device flow, 8-hour tokens, 6-month refresh tokens, no client secret in device flow: https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-user-access-token-for-a-github-app
- Who can install a GitHub App on an org, members can request: https://docs.github.com/en/apps/using-github-apps/installing-a-github-app-from-a-third-party
- OAuth app access restrictions on by default for new orgs: https://docs.github.com/en/organizations/managing-oauth-access-to-your-organizations-data/about-oauth-app-access-restrictions
- GitHub CLI is a privileged OAuth app that restrictions do not block: https://docs.github.com/en/apps/oauth-apps/using-oauth-apps/privileged-oauth-apps
- CODEOWNERS locations, base branch rule, 3 MB limit, syntax limits: https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners
- Webhook events, actions, app-only events, 25 MB cap: https://docs.github.com/en/webhooks/webhook-events-and-payloads
- Webhook 10-second response: https://docs.github.com/en/webhooks/using-webhooks/best-practices-for-using-webhooks
- No automatic redelivery, 3-day window: https://docs.github.com/en/webhooks/testing-and-troubleshooting-webhooks/redelivering-webhooks
- `gh webhook forward` testing only, one at a time: https://docs.github.com/en/webhooks/testing-and-troubleshooting-webhooks/using-the-github-cli-to-forward-webhooks-for-testing
- smee delivers over server-sent events: https://smee.io/
- Scraping and API terms: https://docs.github.com/en/site-policy/acceptable-use-policies/github-acceptable-use-policies and https://docs.github.com/en/site-policy/github-terms/github-terms-of-service#h-api-terms

## Believed, no source

- Git operations over HTTPS (`ls-remote`, `fetch`) do not count against the REST or GraphQL rate limits.
- A GitHub App's user token cannot read the Notifications API.
- The REST PR object has no review decision, no linked issues and no merge queue position. REST review comments do not carry thread resolved state.
- There is no webhook event for a change in mergeability.
- GraphQL has no conditional requests.
- REST omits `patch` for very large files and refuses full diffs beyond some size. The exact thresholds were not found.
- The PR files tab shows code owners per file.
- Repo and org webhooks need admin on the repo or owner on the org to create.
- Tokens used against SAML SSO orgs, including the `gh` token, must be authorized for SSO.
- The device flow for OAuth apps needs no client secret, as for GitHub Apps.
- The 60-second `max-age` on list responses means a list ETag can stay stale for up to a minute after a change.

## Suggested probes

1. **Do 304s count toward the secondary limit?** Send 1,000 conditional requests in 60 seconds, serially, at one endpoint and watch for 403 or 429 with `retry-after`. One hour. Settles whether ETag polling of checks scales.
2. **How fast do ETags change?** On a test repo the owner controls, change a label, add a review comment, finish a check, and poll the PR list, the PR, and check runs every 2 seconds with ETags. Record seconds to new ETag. Two hours. Settles whether list polling can be the change detector, and the `max-age=60` question.
3. **What moves `updatedAt`?** Same test repo: record `updatedAt` before and after a check finishing, a status posted, a review thread resolved, a base branch push that changes mergeability. One hour. Settles whether the cheap GraphQL detector misses checks.
4. **Events API real delay.** Make 10 changes on the test repo and time their arrival on `/repos/{o}/{r}/events` and `/notifications`. One hour, then a second run on a busy afternoon.
5. **Batch size for computed fields.** Find the largest batch of PRs for `mergeable`, `statusCheckRollup` and `reviewDecision` that stays under 5 seconds, across repo sizes, and check whether timed-out queries drain points. Two hours. Settles the GraphQL plan.
6. **Fine-grained PAT and GitHub App reads.** Make a fine-grained PAT and a test GitHub App on a test org and confirm which of these work: GraphQL `statusCheckRollup`, REST check runs, notifications. Half a day, needs the owner to create the tokens.
7. **Webhook relay latency.** A GitHub App on a test repo with a tiny hosted relay pushing over server-sent events to a local client. Measure event-to-client time and behaviour across a laptop sleep. One day, needs the owner to approve a hosted service.
8. **Clone cost on a large repo.** Partial bare clone and open-PR head fetch of one large repo the owner works in, to get disk and time for a realistic case. One hour, needs approval for the download size.
