import Foundation
import Testing
@testable import GitHubPRExplorerCore

/// One case per state of the precedence documented on `StatusSentence`.
@Suite struct StatusSentenceTests {
    static let now = MockWorld.now
    static let viewer = MockCast.viewer
    static let other = MockCast.adaPark

    /// An open pull request that is ready to merge. Each test changes one thing.
    static func ready() -> PullRequest {
        PullRequest(
            id: "fixture", repository: MockCast.api, number: 1, title: "Fixture", author: MockCast.samRivera,
            headBranch: "fixture", headCommitID: String(repeating: "a", count: 40),
            createdAt: now.addingTimeInterval(-86_400), updatedAt: now.addingTimeInterval(-3600),
            reviews: [Review(id: "r1", reviewer: other, state: .approved, submittedAt: now.addingTimeInterval(-3600))],
            reviewDecision: .approved,
            checks: [
                Check(name: "lint", state: .passed, isRequired: true, startedAt: now.addingTimeInterval(-900), finishedAt: now.addingTimeInterval(-800)),
                Check(name: "e2e-chrome", state: .passed, isRequired: true, startedAt: now.addingTimeInterval(-900), finishedAt: now.addingTimeInterval(-500)),
                Check(name: "e2e-firefox", state: .passed, isRequired: false, startedAt: now.addingTimeInterval(-900), finishedAt: now.addingTimeInterval(-500)),
            ],
            provenance: .uniform(.mock, fetchedAt: now)
        )
    }

    static func status(_ pr: PullRequest) -> StatusSentence {
        StatusSentence(pullRequest: pr, viewer: viewer, now: now)
    }

    static func unresolvedThread(_ id: String) -> ReviewThread {
        ReviewThread(id: id, path: "a.ts", line: 1, quotedLine: "x",
                     comments: [ReviewComment(id: id + "c", author: other, body: "Why?", createdAt: now.addingTimeInterval(-600))])
    }

    @Test func readyToMerge() {
        let status = Self.status(Self.ready())
        #expect(status.state == .readyToMerge)
        #expect(status.text == "✓ Ready to merge")
        #expect(status.reasons.isEmpty)
    }

    @Test func merged() {
        var pr = Self.ready()
        pr.state = .merged
        pr.checks[0].state = .failed
        #expect(Self.status(pr).text == "✓ Merged")
    }

    @Test func closed() {
        var pr = Self.ready()
        pr.state = .closed
        #expect(Self.status(pr).text == "⊘ Closed without merging")
    }

    @Test func draftOutranksEverythingOpen() {
        var pr = Self.ready()
        pr.isDraft = true
        pr.mergeState.mergeability = .conflicting
        pr.reviewRequests = [ReviewRequest(reviewer: .person(Self.viewer.person), requestedAt: Self.now)]
        let status = Self.status(pr)
        #expect(status.state == .draft)
        #expect(status.text == "○ Draft")
        #expect(status.reasons.contains("draft"))
    }

    @Test func mergeQueueOutranksBlocked() {
        var pr = Self.ready()
        pr.mergeState.mergeQueuePosition = 2
        pr.checks[1].state = .running
        #expect(Self.status(pr).text == "● In the merge queue, position 2")
    }

    @Test func blockedByARequiredCheck() {
        var pr = Self.ready()
        pr.checks[1].state = .failed
        let status = Self.status(pr)
        #expect(status.state == .blocked)
        #expect(status.text == "✕ Blocked: e2e-chrome failed")
    }

    @Test func blockedByConflictsListsEveryBlocker() {
        var pr = Self.ready()
        pr.mergeState.mergeability = .conflicting
        pr.checks[0].state = .failed
        pr.reviewDecision = .changesRequested
        pr.reviewThreads = [Self.unresolvedThread("t1")]
        #expect(Self.status(pr).text == "✕ Blocked: merge conflicts, lint failed, changes requested, 1 thread unresolved")
    }

    @Test func threeFailedRequiredChecksAreCounted() {
        var pr = Self.ready()
        pr.checks.append(Check(name: "build", state: .failed, isRequired: true))
        pr.checks[0].state = .failed
        pr.checks[1].state = .failed
        #expect(Self.status(pr).text == "✕ Blocked: 3 required checks failed")
    }

    @Test func changesRequested() {
        var pr = Self.ready()
        pr.reviewDecision = .changesRequested
        pr.checks[1].state = .running
        let status = Self.status(pr)
        #expect(status.state == .changesRequested)
        #expect(status.text == "✕ Changes requested")
    }

    @Test func ciRunningTimedFromTheEarliestRunningCheck() {
        var pr = Self.ready()
        pr.checks[0].state = .running
        pr.checks[0].startedAt = Self.now.addingTimeInterval(-12 * 60 - 30)
        pr.checks[0].finishedAt = nil
        pr.checks[1].state = .running
        pr.checks[1].startedAt = Self.now.addingTimeInterval(-3 * 60)
        pr.checks[1].finishedAt = nil
        pr.reviewThreads = [Self.unresolvedThread("t1")]
        let status = Self.status(pr)
        #expect(status.state == .checksRunning)
        #expect(status.text == "● CI running 12 min")
        #expect(status.reasons.contains("lint running 12 min"))
    }

    @Test func ciJustStarted() {
        var pr = Self.ready()
        pr.checks[0].state = .running
        pr.checks[0].startedAt = Self.now.addingTimeInterval(-20)
        #expect(Self.status(pr).text == "● CI running under 1 min")
    }

    @Test func checksQueued() {
        var pr = Self.ready()
        pr.checks[1] = Check(name: "e2e-chrome", state: .queued, isRequired: true)
        #expect(Self.status(pr).text == "● Checks queued")
    }

    @Test func optionalCheckFailed() {
        var pr = Self.ready()
        pr.checks[2].state = .failed
        let status = Self.status(pr)
        #expect(status.state == .optionalChecksFailed)
        #expect(status.text == "◐ e2e-firefox failed, not required")
    }

    @Test func threadsUnresolved() {
        var pr = Self.ready()
        pr.reviewThreads = [Self.unresolvedThread("t1"), Self.unresolvedThread("t2")]
        pr.reviewRequests = [ReviewRequest(reviewer: .person(MockCast.maxChen), requestedAt: Self.now)]
        #expect(Self.status(pr).text == "◐ 2 threads unresolved")
    }

    @Test func resolvedThreadsDoNotCount() {
        var pr = Self.ready()
        var thread = Self.unresolvedThread("t1")
        thread.isResolved = true
        pr.reviewThreads = [thread]
        #expect(Self.status(pr).state == .readyToMerge)
    }

    @Test func waitingOnOneReviewer() {
        var pr = Self.ready()
        pr.reviewRequests = [ReviewRequest(reviewer: .person(MockCast.maxChen), requestedAt: Self.now)]
        pr.mergeState.isBehindBase = true
        let status = Self.status(pr)
        #expect(status.state == .waitingOnReviewers)
        #expect(status.text == "◐ Waiting on 1 reviewer")
    }

    @Test func waitingOnReviewersCountsATeamAsOne() {
        var pr = Self.ready()
        pr.reviewRequests = [
            ReviewRequest(reviewer: .person(MockCast.maxChen), requestedAt: Self.now),
            ReviewRequest(reviewer: .team(MockCast.webPlatformTeam), requestedAt: Self.now),
        ]
        #expect(Self.status(pr).text == "◐ Waiting on 2 reviewers")
    }

    @Test func needsAReviewWhenNoneIsRequested() {
        var pr = Self.ready()
        pr.reviews = []
        pr.reviewDecision = .reviewRequired
        #expect(Self.status(pr).text == "◐ Needs a review")
    }

    @Test func behindBase() {
        var pr = Self.ready()
        pr.mergeState.isBehindBase = true
        pr.baseBranch = "release/2026.11"
        #expect(Self.status(pr).text == "◐ Behind release/2026.11")
    }

    @Test func mergeabilityUnknown() {
        var pr = Self.ready()
        pr.mergeState.mergeability = .unknown
        #expect(Self.status(pr).text == "◐ Checking for conflicts")
    }

    @Test func reviewRequestedFromTheViewerDirectly() {
        var pr = Self.ready()
        pr.reviewRequests = [ReviewRequest(reviewer: .person(Self.viewer.person), requestedAt: Self.now)]
        let status = Self.status(pr)
        #expect(status.text == "◐ Waiting on 1 reviewer. Review requested from you.")
        #expect(status.isReviewRequestedFromViewer)
    }

    @Test func reviewRequestedFromTheViewersTeam() {
        var pr = Self.ready()
        pr.checks[1].state = .failed
        pr.reviewRequests = [ReviewRequest(reviewer: .team(MockCast.securityTeam), requestedAt: Self.now)]
        #expect(Self.status(pr).text == "✕ Blocked: e2e-chrome failed. Review requested from you.")
    }

    @Test func noRequestSentenceOnTheViewersOwnPullRequest() {
        var pr = Self.ready()
        pr.author = Self.viewer.person
        pr.reviewRequests = [ReviewRequest(reviewer: .team(MockCast.securityTeam), requestedAt: Self.now)]
        #expect(Self.status(pr).text == "◐ Waiting on 1 reviewer")
    }

    @Test func noChecksIsReady() {
        var pr = Self.ready()
        pr.checks = []
        #expect(Self.status(pr).state == .readyToMerge)
    }
}
