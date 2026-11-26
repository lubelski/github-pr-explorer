import Foundation
import Testing
@testable import GitHubPRExplorerCore

/// `acme/api #4826` must match the Figma designs exactly.
@Suite struct WorkedExampleTests {
    let world = MockWorld.standard
    var pr: PullRequest { world.index.pullRequest(MockWorld.workedExample)! }

    @Test func itExists() {
        #expect(world.index.pullRequest(MockWorld.workedExample) != nil)
    }

    @Test func title() { #expect(pr.title == "Move session refresh into the auth middleware") }
    @Test func author() { #expect(pr.author == MockCast.samRivera) }
    @Test func branches() {
        #expect(pr.headBranch == "session-refresh-middleware")
        #expect(pr.baseBranch == "main")
    }
    @Test func openAndNotDraft() {
        #expect(pr.state == .open)
        #expect(!pr.isDraft)
    }
    @Test func additions() { #expect(pr.additions == 212) }
    @Test func deletions() { #expect(pr.deletions == 87) }
    @Test func nineFiles() { #expect(pr.files.count == 9) }
    @Test func twelveCommits() { #expect(pr.commits.count == 12) }
    @Test func headCommitIsTheLastCommit() { #expect(pr.headCommitID == pr.commits.last?.id) }

    @Test(arguments: [
        ("auth/session.ts", 64, 31),
        ("auth/middleware.ts", 48, 12),
        ("auth/middleware.test.ts", 71, 4),
        ("api/routes/login.ts", 9, 28),
        ("docs/auth.md", 12, 3),
    ])
    func namedFile(path: String, additions: Int, deletions: Int) throws {
        let file = try #require(pr.files.first { $0.path == path })
        #expect(file.additions == additions)
        #expect(file.deletions == deletions)
    }

    @Test func theOtherFourFilesSumToEightAndNine() {
        let named: Set = ["auth/session.ts", "auth/middleware.ts", "auth/middleware.test.ts", "api/routes/login.ts", "docs/auth.md"]
        let others = pr.files.filter { !named.contains($0.path) }
        #expect(others.count == 4)
        #expect(others.reduce(0) { $0 + $1.additions } == 8)
        #expect(others.reduce(0) { $0 + $1.deletions } == 9)
    }

    @Test func everyPatchParsesToItsDeclaredCounts() throws {
        for file in pr.files {
            let patch = try PatchParser.parse(try #require(file.patch))
            #expect(patch.additions == file.additions, "\(file.path)")
            #expect(patch.deletions == file.deletions, "\(file.path)")
        }
    }

    @Test func languagesAreTypeScriptOrMarkdown() {
        #expect(pr.files.allSatisfy { $0.path.hasSuffix(".ts") || $0.path.hasSuffix(".md") })
    }

    @Test func fourteenChecks() { #expect(pr.checks.count == 14) }
    @Test func twelveChecksPassed() { #expect(pr.checks.count { $0.state == .passed } == 12) }
    @Test func oneCheckFailed() { #expect(pr.checks.count { $0.state == .failed } == 1) }
    @Test func oneCheckRunning() { #expect(pr.checks.count { $0.state == .running } == 1) }

    @Test func e2eChromeFailedAsRequired() throws {
        let check = try #require(pr.checks.first { $0.name == "e2e-chrome" })
        #expect(check.state == .failed)
        #expect(check.isRequired)
        #expect(check.failureSummary == "2 tests failed")
        #expect(check.duration == TimeInterval(6 * 60 + 12))
    }

    @Test func buildDockerStartedFourMinutesBeforeNow() throws {
        let check = try #require(pr.checks.first { $0.name == "build-docker" })
        #expect(check.state == .running)
        #expect(check.startedAt == world.now.addingTimeInterval(-4 * 60))
        #expect(check.finishedAt == nil)
    }

    @Test func checkSummaryPutsFailedFirst() {
        #expect(pr.checkSummary.text == "1 failed, 1 running, 12 passed")
    }

    @Test func adaApprovedTwoHoursBeforeNow() throws {
        let review = try #require(pr.reviews.first { $0.reviewer == MockCast.adaPark })
        #expect(review.state == .approved)
        #expect(review.submittedAt == world.now.addingTimeInterval(-2 * 3600))
    }

    @Test func joApprovedOneHourBeforeNow() throws {
        let review = try #require(pr.reviews.first { $0.reviewer == MockCast.joLindqvist })
        #expect(review.state == .approved)
        #expect(review.submittedAt == world.now.addingTimeInterval(-3600))
    }

    @Test func securityTeamRequestedAndPending() {
        #expect(pr.reviewRequests.count == 1)
        #expect(pr.reviewRequests.first?.reviewer == .team(MockCast.securityTeam))
        #expect(pr.reviewDecision == .reviewRequired)
    }

    @Test func reviewIsRequestedFromTheViewer() {
        #expect(world.viewer.isMember(of: MockCast.securityTeam))
        #expect(pr.isReviewRequested(from: world.viewer))
    }

    @Test func threeUnresolvedThreads() {
        #expect(pr.reviewThreads.count == 3)
        #expect(pr.unresolvedThreads.count == 3)
    }

    @Test func adaThreadOnMiddlewareLine112WithSamReply() throws {
        let thread = try #require(pr.reviewThreads.first { $0.path == "auth/middleware.ts" })
        #expect(thread.line == 112)
        #expect(thread.comments.first?.author == MockCast.adaPark)
        #expect(thread.comments.first?.body == "Does this refresh run before the rate limiter? If not, one request can be counted twice.")
        #expect(thread.comments.count == 2)
        #expect(thread.comments.last?.author == MockCast.samRivera)
    }

    @Test func joThreadOnSessionLine118() throws {
        let thread = try #require(pr.reviewThreads.first { $0.path == "auth/session.ts" })
        #expect(thread.line == 118)
        #expect(thread.comments.first?.author == MockCast.joLindqvist)
        #expect(thread.comments.first?.body == "Should near-expiry be a config value instead of 5 minutes hard-coded?")
    }

    @Test func maxThreadOnLoginLine27() throws {
        let thread = try #require(pr.reviewThreads.first { $0.path == "api/routes/login.ts" })
        #expect(thread.line == 27)
        #expect(thread.comments.first?.author == MockCast.maxChen)
        #expect(thread.comments.first?.body == "Is removing this refresh safe for the single sign-on callback route?")
    }

    @Test func threadsQuoteTheLineTheyPointAt() throws {
        for thread in pr.reviewThreads {
            let file = try #require(pr.files.first { $0.path == thread.path })
            let patch = try #require(file.parsedPatch)
            let line = try #require(patch.line(number: thread.line, side: thread.side), "\(thread.path):\(thread.line)")
            #expect(line.text == thread.quotedLine)
        }
    }

    /// The designs show threads needing the viewer. The viewer is asked to review as
    /// `@acme/security`, which owns `auth/`, so the two threads there need them. Max's thread on
    /// `api/routes/login.ts` is outside what security owns and waits on the author.
    @Test func twoThreadsNeedTheViewerAsCodeOwner() {
        let needing = pr.threadsNeedingAttention(from: world.viewer)
        #expect(needing.map(\.path) == ["auth/middleware.ts", "auth/session.ts"])
        #expect(pr.isReviewOfPathRequested(from: world.viewer, path: "auth/session.ts"))
        #expect(!pr.isReviewOfPathRequested(from: world.viewer, path: "api/routes/login.ts"))
        // Someone who is not asked to review, and not in any thread, is not asked about the files.
        let other = Viewer(person: MockCast.tomasReyes, teams: [])
        #expect(!pr.isReviewOfPathRequested(from: other, path: "auth/session.ts"))
        #expect(pr.threadsNeedingAttention(from: other).isEmpty)
    }

    @Test func thirtyOneTimelineEvents() { #expect(pr.timeline.count == 31) }
    @Test func seventeenFromBots() { #expect(pr.botTimelineEvents.count == 17) }
    @Test func fourteenFromPeople() { #expect(pr.humanTimelineEvents.count == 14) }
    @Test func botEventsAreFromDeployPreviewAndCoverage() {
        let logins = Set(pr.botTimelineEvents.map(\.actor.login))
        #expect(logins == ["deploy-preview-bot", "coverage-bot"])
    }

    @Test func codeOwnersMatchTheThreeAuthFiles() {
        #expect(pr.codeOwners == [CodeOwnerMatch(pattern: "auth/**", owners: ["@acme/security"],
                                                  paths: ["auth/session.ts", "auth/middleware.ts", "auth/middleware.test.ts"])])
    }

    @Test func bodyHasFourOrFiveSentencesAndAChecklist() {
        let paragraphs = pr.body.components(separatedBy: "\n\n")
        let sentences = paragraphs[0].components(separatedBy: ". ").count
        #expect((4...5).contains(sentences))
        #expect(pr.body.contains("- [x] "))
        #expect(pr.body.contains("- [ ] "))
    }

    @Test func statusSentence() {
        let status = pr.statusSentence(for: world.viewer, now: world.now)
        #expect(status.symbol == .cross)
        #expect(status.state == .blocked)
        #expect(status.sentence == "Blocked: e2e-chrome failed, 3 threads unresolved. Review requested from you.")
        #expect(status.text == "✕ Blocked: e2e-chrome failed, 3 threads unresolved. Review requested from you.")
    }
}
