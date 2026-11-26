import Foundation
import Testing
@testable import GitHubPRExplorerCore

@Suite struct BlockContentTests {
    let world = MockWorld.standard
    var workedExample: PullRequest { world.index.pullRequest(MockWorld.workedExample)! }

    // MARK: Files

    @Test func filesGroupByFolderInFirstAppearanceOrder() {
        let pr = workedExample
        let all = FileGroups(files: pr.files, codeOwners: pr.codeOwners)
        #expect(all.groups.map(\.folder) == ["auth/", "api/routes/", "docs/", "api/", ""])
        #expect(all.groups[0].files.map(\.path) == ["auth/session.ts", "auth/middleware.ts", "auth/middleware.test.ts"])
        #expect(all.groups[1].files.map(\.path) == ["api/routes/login.ts", "api/routes/logout.ts", "api/routes/account.ts"])
        #expect(all.hiddenFileCount == 0)
    }

    @Test func filesLimitMatchesTheDesign() {
        // Figma row 1: auth/ with three files, api/routes/login.ts, docs/auth.md, "4 more files +8 −9".
        let pr = workedExample
        let five = FileGroups(files: pr.files, codeOwners: pr.codeOwners, limit: 5)
        #expect(five.groups.map(\.folder) == ["auth/", "api/routes/", "docs/"])
        #expect(five.groups.map { $0.files.count } == [3, 1, 1])
        #expect(five.hiddenFileCount == 4)
        #expect(five.hiddenAdditions == 8)
        #expect(five.hiddenDeletions == 9)
    }

    @Test func onlyFoldersWithOneSharedOwnerAreMarked() {
        let pr = workedExample
        let groups = FileGroups(files: pr.files, codeOwners: pr.codeOwners).groups
        #expect(groups.first { $0.folder == "auth/" }?.owners == ["@acme/security"])
        #expect(groups.filter { $0.folder != "auth/" }.allSatisfy { $0.owners.isEmpty })
    }

    @Test func folderAndFileNames() {
        #expect(FileGroups.folder(of: "a/b/c.ts") == "a/b/")
        #expect(FileGroups.folder(of: "README.md") == "")
        #expect(FileGroups.fileName(of: "a/b/c.ts") == "c.ts")
        #expect(ChangedFile(path: "x", changeKind: .added, additions: 3, deletions: 1, patch: nil).additionShare == 0.75)
        #expect(ChangedFile(path: "x", changeKind: .added, additions: 0, deletions: 0, isBinary: true, patch: nil).additionShare == nil)
    }

    @Test func largePullRequestGroupsEveryFile() throws {
        let large = try #require(world.pullRequests.first { $0.files.count >= 100 })
        let groups = FileGroups(files: large.files, codeOwners: large.codeOwners)
        #expect(groups.groups.reduce(0) { $0 + $1.files.count } == large.files.count)
        #expect(Set(groups.groups.map(\.folder)).count == groups.groups.count)
    }

    // MARK: Checks

    @Test func checksFailedThenRunningThenPassedCollapsed() {
        let groups = CheckGroups(checks: workedExample.checks)
        #expect(groups.attention.map(\.name) == ["e2e-chrome", "build-docker"])
        #expect(groups.collapsed.map(\.title) == ["12 passed"])
        #expect(CheckGroups.detail(for: groups.attention[0], now: world.now) == "2 tests failed")
        #expect(CheckGroups.detail(for: groups.attention[1], now: world.now) == "running 4 min")
    }

    @Test func checkOrderCoversEveryState() {
        let states: [CheckState] = [.passed, .skipped, .queued, .cancelled, .running, .failed, .passed]
        let checks = states.enumerated().map { Check(name: "c\($0.offset)", state: $0.element, isRequired: false) }
        let groups = CheckGroups(checks: checks)
        #expect(groups.attention.map(\.state) == [.failed, .running, .queued, .cancelled])
        #expect(groups.collapsed.map(\.state) == [.passed, .skipped])
        #expect(groups.collapsed[0].checks.map(\.name) == ["c0", "c6"])
        #expect(CheckGroups(checks: []).attention.isEmpty && CheckGroups(checks: []).collapsed.isEmpty)
    }

    // MARK: Reviewers

    @Test func reviewersMatchTheDesign() {
        let rows = ReviewerRow.rows(for: workedExample, viewer: world.viewer)
        #expect(rows.map(\.name) == ["Ada Park", "Jo Lindqvist", "@acme/security"])
        #expect(rows.map(\.stateText) == ["approved", "approved", "requested, you"])
        #expect(rows[2].isCodeOwnerRequest)
    }

    @Test func reviewerAskedAgainShowsOnceAsRequested() {
        let ada = MockCast.adaPark
        let now = world.now
        var pr = workedExample
        pr.reviews = [
            Review(id: "1", reviewer: ada, state: .changesRequested, submittedAt: now.addingTimeInterval(-7200)),
            Review(id: "2", reviewer: ada, state: .commented, submittedAt: now.addingTimeInterval(-3600)),
            Review(id: "3", reviewer: MockCast.joLindqvist, state: .approved, submittedAt: now.addingTimeInterval(-60)),
        ]
        pr.reviewRequests = [ReviewRequest(reviewer: .person(ada), requestedAt: now)]
        let rows = ReviewerRow.rows(for: pr, viewer: world.viewer)
        #expect(rows.map(\.name) == ["Jo Lindqvist", "Ada Park"])
        #expect(rows.map(\.state) == [.approved, .requested])
    }

    // MARK: Threads

    @Test func threadsUnresolvedFirst() {
        let threads = world.pullRequests.flatMap(\.threadsUnresolvedFirst)
        #expect(!threads.isEmpty)
        for pr in world.pullRequests {
            let ordered = pr.threadsUnresolvedFirst
            #expect(ordered.count == pr.reviewThreads.count)
            let rank = ordered.map { $0.isResolved ? 2 : ($0.isOutdated ? 1 : 0) }
            #expect(rank == rank.sorted(), "\(pr.reference)")
        }
    }

    // MARK: Activity

    @Test func activityHidesBotsNewestFirst() {
        let feed = ActivityFeed(timeline: workedExample.timeline, showsBots: false)
        #expect(feed.events.count == 14)
        #expect(feed.hiddenBotCount == 17)
        #expect(feed.events.first?.summary == "Sam Rivera pushed 1 commit")
        #expect(feed.events.last?.summary == "Sam Rivera opened this pull request")
        #expect(feed.events.allSatisfy { !$0.isFromBot })
        #expect(feed.botLogins == ["deploy-preview-bot", "coverage-bot"])
    }

    @Test func activityShowsBotsAndLimits() {
        let feed = ActivityFeed(timeline: workedExample.timeline, showsBots: true, limit: 5)
        #expect(feed.events.count == 5)
        #expect(feed.hiddenEarlierCount == 26)
        #expect(feed.hiddenBotCount == 0)
        let times = feed.events.map(\.occurredAt)
        #expect(times == times.sorted(by: >))
    }

    @Test func longTimelineStaysSmallByDefault() throws {
        let long = try #require(world.pullRequests.first { $0.timeline.count >= 250 })
        let feed = ActivityFeed(timeline: long.timeline, showsBots: false, limit: 6)
        #expect(feed.events.count <= 6)
        #expect(feed.hiddenBotCount == long.botTimelineEvents.count)
    }

    // MARK: Merge, freshness and time

    @Test func mergeReasons() throws {
        #expect(workedExample.mergeUnavailableReason == "Merge is unavailable until checks pass")
        let draft = try #require(world.index.pullRequest(PullRequestReference(parsing: "acme/api#4774")!))
        #expect(draft.mergeUnavailableReason == "Merge is unavailable while this is a draft")
        let ready = try #require(world.index.pullRequest(PullRequestReference(parsing: "acme/api#4819")!))
        #expect(ready.mergeUnavailableReason == nil)
        let queued = try #require(world.pullRequests.first { $0.state == .open && $0.mergeState.mergeQueuePosition != nil })
        #expect(queued.mergeUnavailableReason?.hasPrefix("In the merge queue") == true)
    }

    @Test func freshnessUsesTheOldestSection() {
        let freshness = Freshness(provenance: workedExample.provenance, now: world.now)
        #expect(freshness.summary == "Synced 3 min ago")
        #expect(freshness.details.first == "files: 3 min ago, local clone")
        #expect(freshness.details.last == "timeline: 10 s ago, push")
    }

    @Test func relativeAges() {
        #expect(RelativeAge.ago(4) == "4 s ago")
        #expect(RelativeAge.ago(12 * 60 + 5) == "12 min ago")
        #expect(RelativeAge.ago(2 * 3600 + 59 * 60) == "2 h ago")
        #expect(RelativeAge.ago(3 * 86_400) == "3 d ago")
        #expect(RelativeAge.ago(-5) == "0 s ago")
        #expect(RelativeAge.duration(372) == "6 min 12 s")
        #expect(RelativeAge.duration(3900) == "1 h 5 min")
    }

    // MARK: Markdown

    @Test func workedExampleBodyHasAParagraphAndATaskList() {
        let blocks = MarkdownBlock.parse(workedExample.body)
        #expect(blocks.count == 5)
        guard case .paragraph(let text) = blocks[0] else { Issue.record("expected a paragraph"); return }
        #expect(text.hasPrefix("Session refresh lives in each route handler"))
        #expect(blocks[1] == .listItem(text: "Move the refresh into `authenticate`", checked: true, ordinal: nil, depth: 0))
        #expect(blocks[4] == .listItem(text: "Check the single sign-on callback on staging", checked: false, ordinal: nil, depth: 0))
        #expect(MarkdownBlock.firstText(blocks) == text)
    }

    @Test func richBodyBlocks() {
        let blocks = MarkdownBlock.parse(MockGenerated.richBody)
        #expect(blocks.first == .heading(level: 2, text: "What changed"))
        #expect(blocks.contains(.table(rows: [
            ["Column", "Before", "After"], ["Date", "Fixed width", "Fits content"],
            ["Amount", "Left aligned", "Right aligned"], ["Status", "Text", "Badge"],
        ])))
        #expect(blocks.contains(.image(alt: "The reports table with the sticky header",
                                       url: "https://assets.acme.example/pull-requests/reports-header.png")))
        #expect(blocks.contains(.summary("Why not a CSS-only fix")))
        #expect(blocks.contains(.code(language: "tsx", text: "<ReportsTable columns={columns} rows={rows} stickyHeader />")))
        #expect(!blocks.contains { if case .paragraph(let text) = $0 { text.contains("<details>") } else { false } })
        // Every kind of block, so the renders and the text selection see each one.
        #expect(blocks.contains(.heading(level: 3, text: "How to check it")))
        #expect(blocks.contains(.listItem(text: "Scroll the table and watch the header.", checked: nil, ordinal: 2, depth: 0)))
        #expect(blocks.contains(.listItem(text: "It should stay put, with the column menu still reachable.", checked: nil, ordinal: nil, depth: 1)))
        #expect(blocks.contains { if case .quote(let text) = $0 { text.hasPrefix("Ada Park asked") } else { false } })
        #expect(blocks.contains(.rule))
        #expect(blocks.last == .paragraph("The totals row is a follow-up."))
    }

    @Test func numberedItemsQuotesAndEmpty() {
        let blocks = MarkdownBlock.parse("1. One\n2. Two\n  - nested\n\n> quoted\n> more\n\n---")
        #expect(blocks == [
            .listItem(text: "One", checked: nil, ordinal: 1, depth: 0),
            .listItem(text: "Two", checked: nil, ordinal: 2, depth: 0),
            .listItem(text: "nested", checked: nil, ordinal: nil, depth: 1),
            .quote("quoted more"),
            .rule,
        ])
        #expect(MarkdownBlock.parse("").isEmpty)
        #expect(MarkdownBlock.parse("  \n\n").isEmpty)
    }
}
