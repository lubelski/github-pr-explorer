import Foundation
import Testing
@testable import GitHubPRExplorerCore

/// The sync against a fake GitHub built from hand-written fixtures. Nothing here touches the
/// network, the real `gh`, or the real Application Support folder.
@Suite struct GitHubSyncTests {
    let github = FakeGitHub()
    let clock = TestClock()
    let storage = InMemoryIndexStorage()
    let log = UpdateLog()

    func sync(token: Result<String, GitHubAccessError> = .success(FakeGitHub.token),
              storage: (any GitHubIndexStorage)? = nil) -> GitHubSync {
        let clock = clock
        let log = log
        return GitHubSync(transport: github, tokenProvider: FixedTokenProvider(token), storage: storage ?? self.storage,
                          now: { clock.now }, onUpdate: { log.append($0) })
    }

    static let api101 = PullRequestReference(parsing: "acme/api#101")!
    static let web55 = PullRequestReference(parsing: "acme/web#55")!

    @Test func theFirstSyncFillsTheIndexFromEveryTier() async throws {
        let sync = sync()
        let status = await sync.run(.full)
        #expect(status.problem == nil)
        #expect(status.accountLogin == "robin-quill")
        #expect(status.pullRequestCount == 2)
        #expect(status.detailedCount == 2)
        #expect(status.lastSuccessAt == clock.now)

        let index = await sync.index
        #expect(index.viewer.person.displayName == "Robin Quill")
        #expect(index.viewer.teams.map(\.handle) == ["@acme/security"])
        let pr = try #require(index.pullRequest(Self.api101))

        // The list pass.
        #expect(pr.title == "Refresh sessions before they expire")
        #expect(pr.author.displayName == "Sam Rivera")
        #expect(pr.labels.map(\.name) == ["security"])
        #expect(pr.reviewRequests.map(\.reviewer.handle) == ["@robin-quill", "@acme/security"])
        #expect(pr.reviewRequests[1].isCodeOwnerRequest)
        // The request's time comes from its timeline event.
        #expect(pr.reviewRequests[0].requestedAt == MockWorld.date("2026-11-24T09:01:00Z"))
        #expect(pr.isReviewRequested(from: index.viewer))

        // Detail.
        #expect(pr.body.hasPrefix("Sessions now refresh"))
        #expect(pr.milestone?.title == "December")
        #expect(pr.linkedIssues.map(\.number) == [99])
        #expect(pr.reviews.map(\.state) == [.changesRequested], "dismissed and pending reviews are left out")
        #expect(pr.commits.count == 2)
        #expect(pr.commits[1].author.login == "Sam Rivera", "a commit with no GitHub account keeps its author's name")
        #expect(pr.reviewThreads.count == 2)
        #expect(pr.reviewThreads[0].quotedLine == "  const early = now + 60_000")
        #expect(pr.reviewThreads[1].line == 3 && pr.reviewThreads[1].side == .left && pr.reviewThreads[1].isOutdated)
        #expect(pr.reviewThreads[1].startedBy == GitHubMapping.ghost)
        #expect(pr.comments.first?.author.isBot == true)
        #expect(pr.timeline.map(\.kind) == [.opened, .reviewRequested, .commented, .pushedCommits, .reviewed])
        #expect(pr.timeline.first { $0.kind == .pushedCommits }?.summary == "Sam Rivera pushed 2 commits")

        // Computed fields.
        #expect(pr.checks.map(\.name) == ["unit-tests", "e2e-chrome", "coverage"])
        #expect(pr.checks.map(\.state) == [.passed, .failed, .passed])
        #expect(pr.checks[1].failureSummary == "2 tests failed")
        #expect(pr.reviewDecision == .changesRequested)
        #expect(pr.mergeState.mergeability == .mergeable)
        #expect(pr.mergeState.blockedReasons.contains(.requiredChecksFailing))
        #expect(pr.statusSentence(for: index.viewer, now: clock.now).state == .blocked)

        // Files from REST, with code owners from CODEOWNERS.
        #expect(pr.files.map(\.path) == ["auth/session.ts", "auth/logo.png", "auth/new-name.ts"])
        #expect(pr.files[0].patch?.contains("const early") == true)
        #expect(pr.files[0].parsedPatch != nil)
        #expect(pr.files[1].isBinary)
        #expect(pr.files[2].changeKind == .renamed && pr.files[2].previousPath == "auth/old.ts" && !pr.files[2].isBinary)
        #expect(pr.codeOwners.map(\.pattern) == ["/auth/"])
        #expect(pr.codeOwners.first?.owners == ["@acme/security", "@robin-quill"])

        // Every section says where it came from and when.
        #expect(pr.provenance.metadata == SectionProvenance(source: .graphQLAPI, fetchedAt: clock.now))
        #expect(pr.provenance.files.source == .restAPI)
        for section in PullRequestSection.allCases { #expect(pr.provenance[section].isFetched, "\(section)") }

        // The token went only into the Authorization header.
        #expect(github.sent.allSatisfy { $0.authorization == "bearer \(FakeGitHub.token)" })
        #expect(storage.saveCount >= 2)
        let viewer55 = try #require(index.pullRequest(Self.web55))
        #expect(viewer55.mergeState.mergeability == .unknown)
        #expect(viewer55.checks.first?.state == .running)
    }

    @Test func theRequestsComeInTiersAndInSmallBatches() async throws {
        let sync = sync()
        let status = await sync.run(.full)
        #expect(github.count(.viewer) == 1)
        #expect(github.count(.teams) == 1)
        #expect(github.count(.search) == GitHubQueries.involvementSearches.count)
        #expect(github.count(.detail) == 1)
        #expect(github.count(.computed) == 1)
        #expect(github.count(.files) == 2)
        #expect(github.count(.codeOwners) == 2)
        #expect(status.lastRun.restRequests == 2)
        #expect(status.lastRun.graphQLRequests == github.sent.count - 2)
        #expect(status.lastRun.graphQLPoints > 0)
        #expect(status.rateLimits["graphql"]?.remaining == 4900)
        #expect(status.rateLimits["core"]?.limit == 5000)
        // The list pass asks for no computed fields.
        for search in github.sent.filter({ $0.kind == .search }) {
            #expect(!search.body.contains("statusCheckRollup") && !search.body.contains("mergeable"))
        }
    }

    @Test func aSecondSyncWithNothingChangedReadsOnlyTheList() async throws {
        let sync = sync()
        await sync.run(.full)
        github.clearSent()
        clock.advance(300)
        let status = await sync.run(.full)
        #expect(status.problem == nil)
        #expect(github.count(.viewer) == 0, "the viewer is kept for hours")
        #expect(github.count(.detail) == 0)
        #expect(github.count(.files) == 0)
        // Only the pull request with a running check and unknown mergeability is asked again.
        let computed = github.sent.filter { $0.kind == .computed }
        #expect(computed.count == 1)
        #expect(computed.first?.body.contains("PR_kwDOAcmeWeb55") == true)
        #expect(computed.first?.body.contains("PR_kwDOAcmeApi101") == false)
    }

    @Test func aChangedPullRequestGetsItsDetailAgainAndUnchangedFilesCostNothing() async throws {
        let sync = sync()
        await sync.run(.full)
        github.clearSent()
        clock.advance(300)
        github.searchEdits = [("\"updatedAt\": \"2026-11-25T17:40:00Z\"", "\"updatedAt\": \"2026-11-25T18:03:00Z\"")]
        let status = await sync.run(.full)
        #expect(github.count(.detail) == 1)
        let detail = try #require(github.sent.first { $0.kind == .detail })
        #expect(detail.body.contains("nodes(ids:"))
        let files = github.sent.filter { $0.kind == .files }
        #expect(files.count == 1)
        #expect(files.first?.ifNoneMatch == "\"etag-files-api-101.json\"")
        #expect(status.lastRun.restNotModified == 1)
        #expect(status.lastRun.restPoints == 0)
        let pr = try #require(await sync.index.pullRequest(Self.api101))
        #expect(pr.files.count == 3, "a 304 keeps the files")
    }

    @Test func watchedRepositoriesAddEveryOpenPullRequest() async throws {
        let sync = sync()
        await sync.configure(watchedRepositories: [Repository(owner: "acme", name: "docs")], interval: 300)
        await sync.run(.full)
        let index = await sync.index
        #expect(index.allPullRequests.count == 3)
        let docs = try #require(index.pullRequest(PullRequestReference(parsing: "acme/docs#7")!))
        #expect(docs.isDraft)
        #expect(docs.author == GitHubMapping.ghost)
        #expect(github.sent.contains { $0.kind == .repository && $0.body.contains("\"owner\":\"acme\"") })
    }

    @Test func aWatchedRepositoryThatIsNotFoundIsAWarningNotAFailure() async throws {
        github.watchedRepositoryFixture = "repository-missing.json"
        let sync = sync()
        await sync.configure(watchedRepositories: [Repository(owner: "acme", name: "nowhere")], interval: 300)
        let status = await sync.run(.full)
        #expect(status.problem == nil)
        #expect(status.warnings.contains { $0.contains("acme/nowhere") })
        #expect(status.pullRequestCount == 2)
    }

    @Test func aPullRequestThatLeavesTheListLeavesTheIndex() async throws {
        let sync = sync()
        await sync.run(.full)
        github.overrides[.search] = { _ in (200, FakeGitHub.fixture("search-empty.json"), [:]) }
        clock.advance(300)
        let status = await sync.run(.full)
        #expect(status.pullRequestCount == 0)
        #expect(await sync.index.allPullRequests.isEmpty)
    }

    @Test func aRequestFetchesOnePullRequestWithoutTheListPass() async throws {
        let sync = sync()
        await sync.run(.full)
        github.clearSent()
        let id = try #require(await sync.index.pullRequest(Self.web55)?.id)
        // Asked within a minute of its last fetch, it is not fetched again.
        await sync.requestSooner(id)
        await sync.run(.focused)
        #expect(github.sent.isEmpty)
        clock.advance(120)
        await sync.requestSooner(id)
        await sync.run(.focused)
        #expect(github.count(.search) == 0)
        #expect(github.count(.detail) == 1)
        #expect(github.count(.computed) == 1)
        #expect(github.count(.files) == 1)
        #expect(github.sent.first { $0.kind == .detail }?.body.contains("PR_kwDOAcmeWeb55") == true)
    }

    @Test func aBatchTooHeavyForGitHubIsSplit() async throws {
        github.overrides[.computed] = { sent in
            if sent.body.contains("pr1:") {
                return (200, Data(#"{"data": null, "errors": [{"message": "Resource limits for this query exceeded."}]}"#.utf8), [:])
            }
            // One at a time, answer with the matching pull request's fields as pr0.
            let full = try! JSONSerialization.jsonObject(with: FakeGitHub.fixture("computed.json")) as! [String: Any]
            let data = full["data"] as! [String: Any]
            let wanted = sent.body.contains("PR_kwDOAcmeApi101") ? data["pr0"]! : data["pr1"]!
            let body = try! JSONSerialization.data(withJSONObject: ["data": ["pr0": wanted, "rateLimit": data["rateLimit"]!]])
            return (200, body, [:])
        }
        let sync = sync()
        let status = await sync.run(.full)
        #expect(status.problem == nil)
        #expect(github.count(.computed) == 3)
        let pr = try #require(await sync.index.pullRequest(Self.api101))
        #expect(pr.checks.count == 3)
    }

    // MARK: Problems

    @Test func ghMissingOrSignedOutSendsNothingAndKeepsTheLastData() async throws {
        let first = sync()
        await first.run(.full)
        let saved = try #require(try storage.load())
        github.clearSent()

        for (error, expected) in [(GitHubAccessError.ghMissing, GitHubSyncProblem.ghMissing), (.signedOut, .signedOut)] {
            let sync = sync(token: .failure(error))
            await sync.loadSaved()
            let status = await sync.run(.full)
            #expect(status.problem == expected)
            #expect(status.hasLogin == false)
            #expect(github.sent.isEmpty)
            #expect(await sync.index.allPullRequests.count == saved.pullRequests.count)
            #expect(log.last?.index.allPullRequests.count == 2, "the window keeps showing the last data")
        }
    }

    @Test func offlineKeepsTheLastData() async throws {
        let sync = sync()
        await sync.run(.full)
        github.failure = URLError(.notConnectedToInternet)
        clock.advance(300)
        let status = await sync.run(.full)
        #expect(status.problem == .offline)
        #expect(status.lastSuccessAt == FakeGitHub.now)
        #expect(await sync.index.allPullRequests.count == 2)
        #expect(SyncStatusSummary(status: status, now: clock.now).text == "Offline")
        #expect(SyncStatusSummary(status: status, now: clock.now).help.contains("Showing what was synced 5 min ago."))
    }

    @Test func aRateLimitedAnswerStopsTheSyncUntilTheReset() async throws {
        github.overrides[.search] = { _ in (403, Data(#"{"message": "API rate limit exceeded"}"#.utf8), ["x-ratelimit-remaining": "0"]) }
        let sync = sync()
        let status = await sync.run(.full)
        #expect(status.problem == .rateLimited(until: github.resetAt))
        github.clearSent()
        clock.advance(60)
        let again = await sync.run(.full)
        #expect(github.sent.isEmpty, "no request before the reset")
        #expect(again.problem == .rateLimited(until: github.resetAt))
        #expect(SyncStatusSummary(status: again, now: clock.now).text == "Rate limited, back in 59 min")
    }

    @Test func aSecondaryLimitWaitsAsLongAsGitHubAsks() async throws {
        github.overrides[.search] = { _ in (429, Data(#"{"message": "You have exceeded a secondary rate limit."}"#.utf8), ["retry-after": "120"]) }
        let status = await sync().run(.full)
        #expect(status.problem == .rateLimited(until: clock.now.addingTimeInterval(120)))
    }

    @Test func theSyncStopsItselfWithTooLittleOfTheLimitLeft() async throws {
        github.remaining = 400 // under a tenth of 5,000
        let sync = sync()
        let status = await sync.run(.full)
        #expect(status.problem == .budgetPaused(until: github.resetAt))
        // The first answer said how little was left, and nothing more was sent.
        #expect(github.sent.count == 1)
    }

    @Test func theSyncSpendsAtMostHalfOfTheLimit() async throws {
        // A limit so small that the first run's own spending reaches half of it.
        github.limit = 8
        github.remaining = 8
        let sync = sync()
        let status = await sync.run(.full)
        #expect(status.problem == .budgetPaused(until: github.resetAt))
        #expect(status.lastRun.graphQLPoints <= 5)
    }

    @Test func theTokenIsNeverInTheStatusTheSnapshotOrAnError() async throws {
        github.overrides[.detail] = { _ in (500, Data(#"{"message": "Server Error"}"#.utf8), [:]) }
        let sync = sync()
        let status = await sync.run(.full)
        guard case .failed(let message)? = status.problem else { Issue.record("expected a failure"); return }
        #expect(!message.contains(FakeGitHub.token))
        let snapshot = try #require(try storage.load())
        let text = String(decoding: try GitHubPRExplorerJSON.encoder().encode(snapshot), as: UTF8.self)
        #expect(!text.contains(FakeGitHub.token))
        #expect(!text.contains("bearer"))
        #expect(GitHubCLITokenProvider.redacted("bad token gho_abc123XYZ here") == "bad token [token removed] here")
    }

    // MARK: The saved snapshot

    @Test func theSnapshotIsSavedAndOpensBeforeTheFirstFetch() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "github-pr-explorer-index-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = JSONFileIndexStorage(folder: folder)
        #expect(try storage.load() == nil)
        await sync(storage: storage).run(.full)
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "github.json").path))
        let attributes = try FileManager.default.attributesOfItem(atPath: storage.location.path)
        #expect((attributes[.posixPermissions] as? Int) == 0o600)

        // A new sync, as at the next launch, shows the snapshot before sending anything.
        github.clearSent()
        let reopened = UpdateLog()
        let clock = clock
        let next = GitHubSync(transport: github, tokenProvider: FixedTokenProvider(.success(FakeGitHub.token)), storage: storage,
                              now: { clock.now }, onUpdate: { reopened.append($0) })
        #expect(await next.loadSaved() == nil)
        #expect(github.sent.isEmpty)
        let update = try #require(reopened.last)
        #expect(update.index.allPullRequests.count == 2)
        #expect(update.status.accountLogin == "robin-quill")
        #expect(update.status.phase == .idle)
        #expect(update.index.pullRequest(Self.api101)?.files.count == 3)

        // Deleting it is safe: the next sync builds it again.
        try FileManager.default.removeItem(at: folder)
        let fresh = GitHubSync(transport: github, tokenProvider: FixedTokenProvider(.success(FakeGitHub.token)), storage: storage, now: { clock.now })
        #expect(await fresh.loadSaved() == nil)
        #expect(await fresh.run(.full).pullRequestCount == 2)
    }

    @Test func anUnreadableSnapshotIsReportedAndBuiltAgain() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "github-pr-explorer-index-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: folder.appending(path: "github.json"))
        let sync = sync(storage: JSONFileIndexStorage(folder: folder))
        #expect(await sync.loadSaved() != nil)
        #expect(await sync.run(.full).pullRequestCount == 2)
    }

    @Test func theIndexFolderIsBesideTheConfigurationFolderNotInIt() {
        let index = JSONFileIndexStorage.defaultFolder.standardizedFileURL.path
        let config = ConfigurationStore.defaultFolder.standardizedFileURL.path
        #expect(!index.hasPrefix(config))
        #expect(URL(filePath: index).deletingLastPathComponent() == URL(filePath: config).deletingLastPathComponent())
    }
}

@Suite struct GitHubMappingTests {
    @Test func checkStates() {
        func run(_ status: String, _ conclusion: String? = nil) -> CheckState {
            GitHubMapping.checkState(GHCheckContext(__typename: "CheckRun", status: status, conclusion: conclusion))
        }
        #expect(run("QUEUED") == .queued)
        #expect(run("PENDING") == .queued)
        #expect(run("IN_PROGRESS") == .running)
        #expect(run("COMPLETED", "SUCCESS") == .passed)
        #expect(run("COMPLETED", "FAILURE") == .failed)
        #expect(run("COMPLETED", "TIMED_OUT") == .failed)
        #expect(run("COMPLETED", "SKIPPED") == .skipped)
        #expect(run("COMPLETED", "NEUTRAL") == .skipped)
        #expect(run("COMPLETED", "CANCELLED") == .cancelled)
        func status(_ state: String) -> CheckState { GitHubMapping.checkState(GHCheckContext(__typename: "StatusContext", state: state)) }
        #expect(status("SUCCESS") == .passed)
        #expect(status("ERROR") == .failed)
        #expect(status("PENDING") == .running)
    }

    @Test func codeOwnersFileLines() {
        let rules = GitHubMapping.codeOwnerRules("# top\n\n*.md @acme/docs\n/infra/ @acme/ops # ops\nlonely\n")
        #expect(rules == [CodeOwnerRule(pattern: "*.md", owners: ["@acme/docs"]), CodeOwnerRule(pattern: "/infra/", owners: ["@acme/ops"]),
                          CodeOwnerRule(pattern: "lonely", owners: [])])
    }

    @Test func quotedLineIsTheHunksLastLine() {
        #expect(GitHubMapping.quotedLine("@@ -1 +1 @@\n-old\n+new") == "new")
        #expect(GitHubMapping.quotedLine(nil) == "")
    }

    @Test func aNodeIDIsNeverPutIntoAQueryUnlessItLooksLikeOne() {
        let query = GitHubQueries.computed(ids: ["PR_kwDOAbc123", "\") { evil }"])
        #expect(query.contains("PR_kwDOAbc123"))
        #expect(!query.contains("evil"))
    }

    @Test func ghIsFoundInHomebrewBeforeThePath() {
        let found = GitHubCLILocator.find(environment: ["PATH": "/usr/bin:/somewhere/bin"]) { $0 == "/somewhere/bin/gh" || $0 == "/usr/local/bin/gh" }
        #expect(found?.path == "/usr/local/bin/gh")
        let fromPath = GitHubCLILocator.find(environment: ["PATH": "/usr/bin:/somewhere/bin"]) { $0 == "/somewhere/bin/gh" }
        #expect(fromPath?.path == "/somewhere/bin/gh")
        #expect(GitHubCLILocator.find(environment: [:]) { _ in false } == nil)
    }

    @Test func freshnessSaysWhenSectionsAreNotFetchedYet() {
        let now = MockWorld.now
        var provenance = Provenance.uniform(.graphQLAPI, fetchedAt: now.addingTimeInterval(-120))
        #expect(Freshness(provenance: provenance, now: now).summary == "Synced 2 min ago")
        provenance.files = .notFetched
        let partial = Freshness(provenance: provenance, now: now)
        #expect(partial.summary == "Details not fetched yet")
        #expect(partial.oldestAge == 120)
        #expect(partial.details.contains("files: not fetched yet"))
        let none = Provenance(metadata: .notFetched, checks: .notFetched, reviews: .notFetched, files: .notFetched, threads: .notFetched, timeline: .notFetched)
        #expect(Freshness(provenance: none, now: now).summary == "Not fetched yet")
    }

    @Test func statusSummaries() {
        let now = MockWorld.now
        var status = GitHubSyncStatus()
        #expect(SyncStatusSummary(status: status, now: now).text == "Not synced yet")
        status.phase = .listing
        #expect(SyncStatusSummary(status: status, now: now).text == "Syncing…")
        status.phase = .idle
        status.lastSuccessAt = now.addingTimeInterval(-180)
        #expect(SyncStatusSummary(status: status, now: now).text == "Synced 3 min ago")
        for (problem, text) in [(GitHubSyncProblem.ghMissing, "gh not found"), (.signedOut, "Signed out of gh"), (.offline, "Offline"),
                                (.budgetPaused(until: now.addingTimeInterval(1800)), "Paused for the rate limit, back in 30 min")] {
            status.problem = problem
            let summary = SyncStatusSummary(status: status, now: now)
            #expect(summary.text == text)
            #expect(summary.isProblem)
        }
    }
}
