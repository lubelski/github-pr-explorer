import Foundation
import Testing
@testable import GitHubPRExplorerCore

/// The short badge and the detail line a list row shows beside the status sentence.
@Suite struct StatusBadgeTests {
    typealias Fixture = StatusSentenceTests
    typealias Badge = StatusSentence.Badge

    @Test func everyStateHasABadge() {
        let expected: [StatusSentence.State: Badge] = [
            .merged: .merged, .closed: .closed, .draft: .draft, .inMergeQueue: .merging, .blocked: .blocked,
            .changesRequested: .changesRequested, .checksRunning: .running, .checksQueued: .running,
            .optionalChecksFailed: .failing, .threadsUnresolved: .threads, .waitingOnReviewers: .waiting,
            .needsReview: .waiting, .behindBase: .behind, .mergeabilityUnknown: .checking, .readyToMerge: .ready,
        ]
        #expect(Set(expected.keys) == Set(StatusSentence.State.allCases))
        for (state, badge) in expected {
            #expect(Badge(state) == badge, "\(state)")
            #expect(badge.states.contains(state))
        }
    }

    @Test func everyBadgeIsShownBySomeState() {
        for badge in Badge.allCases {
            #expect(!badge.states.isEmpty, "\(badge)")
        }
    }

    @Test func labelsAreShort() {
        for badge in Badge.allCases {
            #expect(badge.label.count <= 8, "\(badge.label)")
            #expect(!badge.name.isEmpty)
        }
        #expect(Set(Badge.allCases.map(\.label)).count == Badge.allCases.count)
    }

    @Test func badgeFollowsTheSentence() {
        var pr = Fixture.ready()
        #expect(Fixture.status(pr).badge == .ready)
        pr.checks[1].state = .failed
        #expect(Fixture.status(pr).badge == .blocked)
        pr.isDraft = true
        #expect(Fixture.status(pr).badge == .draft)
    }

    @Test func tones() {
        #expect(Badge.ready.tone == .positive)
        #expect(Badge.blocked.tone == .negative)
        #expect(Badge.changesRequested.tone == .negative)
        #expect(Badge.running.tone == .progress)
        #expect(Badge.waiting.tone == .attention)
        #expect(Badge.draft.tone == .neutral)
        #expect(Badge.merged.tone == .done)
    }

    // MARK: Detail

    @Test func blockedDetailListsTheBlockersWithoutTheWordBlocked() {
        var pr = Fixture.ready()
        pr.checks[1].state = .failed
        pr.reviewThreads = [Fixture.unresolvedThread("t1"), Fixture.unresolvedThread("t2"), Fixture.unresolvedThread("t3")]
        #expect(Fixture.status(pr).detail == "e2e-chrome failed, 3 threads unresolved")
    }

    @Test func blockedDetailCapitalizesAFixedPhraseButNotACheckName() {
        var pr = Fixture.ready()
        pr.mergeState.mergeability = .conflicting
        pr.checks[0].state = .failed
        #expect(Fixture.status(pr).detail == "Merge conflicts, lint failed")
    }

    @Test func detailLeavesOutTheRequestFromTheViewer() {
        var pr = Fixture.ready()
        pr.checks[1].state = .failed
        pr.reviewRequests = [ReviewRequest(reviewer: .team(MockCast.securityTeam), requestedAt: Fixture.now)]
        let status = Fixture.status(pr)
        #expect(status.sentence.hasSuffix("Review requested from you."))
        #expect(status.detail == "e2e-chrome failed")
    }

    @Test func readyDetailSaysHowItGotThere() {
        var pr = Fixture.ready()
        #expect(Fixture.status(pr).detail == "Approved, 3 checks passed")
        pr.reviewDecision = nil
        pr.checks = [pr.checks[0]]
        #expect(Fixture.status(pr).detail == "No review required, 1 check passed")
        pr.checks = []
        #expect(Fixture.status(pr).detail == "No review required, no checks")
    }

    @Test func draftDetailListsWhatElseWasFound() {
        var pr = Fixture.ready()
        pr.isDraft = true
        #expect(Fixture.status(pr).detail == "Not ready for review")
        pr.mergeState.mergeability = .conflicting
        pr.reviewThreads = [Fixture.unresolvedThread("t1")]
        pr.reviewRequests = [ReviewRequest(reviewer: .person(Fixture.viewer.person), requestedAt: Fixture.now)]
        #expect(Fixture.status(pr).detail == "Merge conflicts, 1 thread unresolved, waiting on @robin-quill")
    }

    @Test func mergeQueueDetailGivesThePosition() {
        var pr = Fixture.ready()
        pr.mergeState.mergeQueuePosition = 2
        #expect(Fixture.status(pr).detail == "Position 2 in the merge queue")
    }

    @Test func otherStatesUseTheHeadline() {
        var pr = Fixture.ready()
        pr.checks[2].state = .failed
        #expect(Fixture.status(pr).detail == "e2e-firefox failed, not required")
        pr = Fixture.ready()
        pr.reviewRequests = [ReviewRequest(reviewer: .person(MockCast.maxChen), requestedAt: Fixture.now)]
        #expect(Fixture.status(pr).detail == "Waiting on 1 reviewer")
        pr.state = .merged
        #expect(Fixture.status(pr).detail == "Merged")
    }

    @Test func everyOpenPullRequestInTheMockWorldHasADetail() {
        let world = MockWorld.standard
        for pr in world.pullRequests where pr.state == .open {
            let status = pr.statusSentence(for: world.viewer, now: world.now)
            #expect(!status.detail.isEmpty, "\(pr.reference)")
            #expect(!status.detail.contains("Review requested from you"), "\(pr.reference)")
        }
    }
}
