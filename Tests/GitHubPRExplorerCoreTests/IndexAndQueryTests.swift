import Foundation
import Testing
@testable import GitHubPRExplorerCore

@Suite struct IndexTests {
    let index = MockWorld.standard.index

    @Test func lookUpByIDAndByReference() throws {
        let pr = try #require(index.pullRequest(repository: MockCast.api, number: 4826))
        #expect(index.pullRequest(id: pr.id)?.reference == pr.reference)
        #expect(index.pullRequest(repository: MockCast.api, number: 999_999) == nil)
        #expect(index.pullRequest(id: "no such id") == nil)
    }

    @Test func allIsMostRecentlyUpdatedFirst() {
        let times = index.allPullRequests.map(\.updatedAt)
        #expect(times == times.sorted(by: >))
    }

    @Test func searchByNumber() {
        #expect(index.search("4826").map(\.number).contains(4826))
        #expect(index.search("#4826").first?.number == 4826)
        #expect(index.search("acme/api#4826").count == 1)
    }

    @Test func searchByTitleWordsIgnoringCase() {
        let results = index.search("SESSION refresh middleware")
        #expect(results.contains { $0.number == 4826 })
        #expect(results.allSatisfy { $0.title.lowercased().contains("session") || $0.files.contains { $0.path.contains("session") } })
    }

    @Test func searchByAuthorAndRepository() {
        let results = index.search("sam-rivera acme/web")
        #expect(!results.isEmpty)
        #expect(results.allSatisfy { $0.author == MockCast.samRivera && $0.repository == MockCast.web })
        #expect(!index.search("Ada Park").isEmpty)
    }

    @Test func searchByFilePath() {
        let results = index.search("auth/middleware.ts")
        #expect(results.contains { $0.number == 4826 })
        #expect(results.allSatisfy { pr in pr.files.contains { $0.path.contains("auth/middleware.ts") } || pr.title.contains("auth/middleware.ts") })
    }

    @Test func searchIgnoresAccents() {
        #expect(!index.search("日本語").isEmpty)
        #expect(index.search("render u e n").contains { $0.title.hasPrefix("Render ü") })
    }

    @Test func emptySearchReturnsEverything() {
        #expect(index.search("  ").count == index.allPullRequests.count)
    }

    @Test func searchWithNoMatch() {
        #expect(index.search("zzzz-no-such-thing").isEmpty)
    }
}

@Suite struct QueryTests {
    @Test func checkSummaryOrder() {
        let checks = [CheckState.passed, .running, .failed, .passed, .skipped, .queued, .cancelled].map {
            Check(name: "c", state: $0, isRequired: false)
        }
        let summary = CheckSummary(checks: checks)
        #expect(summary.entries.map(\.state) == [.failed, .running, .queued, .passed, .cancelled, .skipped])
        #expect(summary.text == "1 failed, 1 running, 1 queued, 2 passed, 1 cancelled, 1 skipped")
        #expect(summary.total == 7)
        #expect(CheckSummary(checks: []).text == "No checks")
    }

    static let viewer = MockCast.viewer
    static let now = MockWorld.now

    static func thread(_ authors: [Person], resolved: Bool = false, outdated: Bool = false, mention: Bool = false) -> ReviewThread {
        ReviewThread(id: "t", path: "a.ts", line: 1, isResolved: resolved, isOutdated: outdated, quotedLine: "x",
                     comments: authors.enumerated().map { index, person in
                         ReviewComment(id: "c\(index)", author: person, body: mention ? "cc @robin-quill" : "hm", createdAt: now)
                     })
    }

    @Test func threadOnTheViewersPullRequestNeedsThem() {
        #expect(Self.thread([MockCast.adaPark]).needsAttention(from: Self.viewer, pullRequestAuthor: Self.viewer.person))
    }

    @Test func threadTheViewerStartedNeedsThemOnceAnswered() {
        let author = MockCast.samRivera
        #expect(Self.thread([Self.viewer.person, author]).needsAttention(from: Self.viewer, pullRequestAuthor: author))
        #expect(!Self.thread([Self.viewer.person]).needsAttention(from: Self.viewer, pullRequestAuthor: author))
    }

    @Test func mentionNeedsTheViewer() {
        #expect(Self.thread([MockCast.adaPark], mention: true).needsAttention(from: Self.viewer, pullRequestAuthor: MockCast.samRivera))
    }

    @Test func unrelatedResolvedAndOutdatedThreadsDoNot() {
        let author = MockCast.samRivera
        #expect(!Self.thread([MockCast.adaPark]).needsAttention(from: Self.viewer, pullRequestAuthor: author))
        #expect(!Self.thread([MockCast.adaPark], resolved: true).needsAttention(from: Self.viewer, pullRequestAuthor: Self.viewer.person))
        #expect(!Self.thread([MockCast.adaPark], outdated: true).needsAttention(from: Self.viewer, pullRequestAuthor: Self.viewer.person))
    }

    @Test func timelineActorKinds() {
        func event(_ person: Person) -> TimelineEvent {
            TimelineEvent(id: "e", kind: .commented, actor: person, occurredAt: Self.now, summary: "")
        }
        #expect(event(MockCast.ciBot).actorKind == .bot)
        #expect(event(MockCast.agentOne).actorKind == .agent)
        #expect(event(MockCast.adaPark).actorKind == .person)
        #expect(event(MockCast.ciBot).isFromBot)
        #expect(!event(MockCast.agentOne).isFromBot)
    }

    @Test(arguments: [
        ("auth/**", "auth/session.ts", true),
        ("auth/**", "auth/deep/nested/file.ts", true),
        ("auth/**", "lib/auth/session.ts", false),
        ("*.tf", "modules/dns/main.tf", true),
        ("*.tf", "main.tf", true),
        ("*.tf", "main.tfvars", false),
        ("docs/", "docs/a/b.md", true),
        ("docs/", "src/docs/a.md", true),
        ("/docs/", "src/docs/a.md", false),
        ("src/*.ts", "src/a.ts", true),
        ("src/*.ts", "src/a/b.ts", false),
        ("**/fixtures/**", "test/fixtures/a.json", true),
        ("README.md", "packages/x/README.md", true),
    ])
    func codeOwnerPatterns(pattern: String, path: String, matches: Bool) {
        #expect(CodeOwners.pattern(pattern, matches: path) == matches)
    }

    @Test func lastMatchingCodeOwnerRuleWins() {
        let rules = [
            CodeOwnerRule(pattern: "src/**", owners: ["@acme/web-platform"]),
            CodeOwnerRule(pattern: "src/pages/billing/**", owners: ["@lena-okafor"]),
        ]
        let matches = CodeOwners.matches(rules: rules, paths: ["src/pages/billing/Page.tsx", "src/App.tsx", "README.md"])
        #expect(matches == [
            CodeOwnerMatch(pattern: "src/**", owners: ["@acme/web-platform"], paths: ["src/App.tsx"]),
            CodeOwnerMatch(pattern: "src/pages/billing/**", owners: ["@lena-okafor"], paths: ["src/pages/billing/Page.tsx"]),
        ])
    }

    @Test func seededGeneratorIsStable() {
        var first = SeededGenerator(seed: "same")
        var second = SeededGenerator(seed: "same")
        let a = (0..<20).map { _ in first.next() }
        let b = (0..<20).map { _ in second.next() }
        #expect(a == b)
        var known = SeededGenerator(seed: 0)
        // SplitMix64's first output for seed 0, from its reference implementation.
        #expect(known.next() == 0xe220_a839_7b1d_cdaf)
    }

    @Test func referencesParse() {
        #expect(PullRequestReference(parsing: "acme/api#4826") == PullRequestReference(repository: MockCast.api, number: 4826))
        #expect(PullRequestReference(parsing: "acme/api") == nil)
        #expect(PullRequestReference(parsing: "api#4826") == nil)
        #expect(PullRequestReference(parsing: "acme/api#x") == nil)
    }
}
