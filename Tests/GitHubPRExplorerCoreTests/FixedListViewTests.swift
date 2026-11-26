import Foundation
import Testing
@testable import GitHubPRExplorerCore

@Suite struct FixedListViewTests {
    let world = MockWorld.standard
    var viewer: Viewer { world.viewer }
    var open: [PullRequest] { world.pullRequests.filter { $0.state == .open } }

    func listed(_ view: FixedListView) -> [PullRequest] {
        view.pullRequests(in: world.pullRequests, viewer: viewer)
    }

    func isPersonalRequest(_ request: ReviewRequest) -> Bool {
        if case .person(let person) = request.reviewer { viewer.isViewer(person) } else { false }
    }

    @Test func countsInTheMockWorld() {
        #expect(listed(.needsMyReview).count == 48)
        #expect(listed(.mine).count == 12)
        #expect(listed(.everythingOpen).count == 218)
    }

    @Test func everyViewListsOnlyOpenPullRequests() {
        for view in FixedListView.allCases {
            #expect(listed(view).allSatisfy { $0.state == .open }, "\(view)")
        }
        // The world has closed and merged pull requests that would match otherwise.
        let closedMine = world.pullRequests.filter { $0.state != .open && viewer.isViewer($0.author) }
        let closedRequested = world.pullRequests.filter { $0.state != .open && $0.isReviewRequested(from: viewer) }
        #expect(!closedMine.isEmpty || !closedRequested.isEmpty)
    }

    @Test func needsMyReviewIsARequestFromTheViewerOrTheirTeam() {
        let listedIDs = Set(listed(.needsMyReview).map(\.id))
        for pr in open {
            let asked = pr.reviewRequests.contains { $0.isRequested(from: viewer) } && !viewer.isViewer(pr.author)
            #expect(listedIDs.contains(pr.id) == asked, "\(pr.reference)")
        }
    }

    @Test func needsMyReviewIncludesTeamOnlyRequests() {
        let teamOnly = listed(.needsMyReview).filter { pr in !pr.reviewRequests.contains(where: isPersonalRequest) }
        #expect(!teamOnly.isEmpty)
        #expect(teamOnly.allSatisfy { pr in
            pr.reviewRequests.contains { if case .team(let team) = $0.reviewer { viewer.isMember(of: team) } else { false } }
        })
    }

    @Test func needsMyReviewLeavesOutTeamsTheViewerIsNotOn() {
        let otherTeamOnly = open.filter { pr in
            !pr.reviewRequests.isEmpty && !pr.reviewRequests.contains { $0.isRequested(from: viewer) }
        }
        #expect(!otherTeamOnly.isEmpty)
        #expect(otherTeamOnly.allSatisfy { !FixedListView.needsMyReview.includes($0, viewer: viewer) })
    }

    @Test func mineIsWhatTheViewerWrote() {
        #expect(listed(.mine).allSatisfy { viewer.isViewer($0.author) })
        #expect(listed(.mine).count == open.count { viewer.isViewer($0.author) })
        // Never asks the viewer to review their own pull request.
        #expect(listed(.mine).allSatisfy { !FixedListView.needsMyReview.includes($0, viewer: viewer) })
    }

    @Test func everythingOpenIsEveryOpenPullRequestInOrder() {
        #expect(listed(.everythingOpen).map(\.id) == world.index.allPullRequests.filter { $0.state == .open }.map(\.id))
    }

    @Test func theWorkedExampleNeedsTheViewersReview() throws {
        let pr = try #require(world.index.pullRequest(MockWorld.workedExample))
        #expect(FixedListView.needsMyReview.includes(pr, viewer: viewer))
    }

    @Test func storedByStableNames() {
        #expect(FixedListView.allCases.map(\.rawValue) == ["needsMyReview", "mine", "everythingOpen"])
        #expect(FixedListView(rawValue: "needsMyReview") == .needsMyReview)
        #expect(FixedListView.standard == .needsMyReview)
    }
}
