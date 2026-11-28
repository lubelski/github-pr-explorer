import Foundation
import Testing
@testable import GitHubPRExplorerCore

/// Everything and the default saved filters, "Needs my review" and "Mine". They took the place
/// of the list's three fixed views, and keep exactly what those views kept.
@Suite struct DefaultSavedFilterTests {
    let world = MockWorld.standard
    var viewer: Viewer { world.viewer }
    var open: [PullRequest] { world.pullRequests.filter { $0.state == .open } }
    var context: FilterContext { FilterContext(viewer: viewer, now: world.now) }

    enum View: CaseIterable { case needsMyReview, mine, everythingOpen }

    func saved(_ view: View) -> SavedFilter {
        switch view {
        case .needsMyReview: .needsMyReview
        case .mine: .mine
        case .everythingOpen: .everything
        }
    }

    func listed(_ view: View) -> [PullRequest] {
        saved(view).evaluate(world.pullRequests, context: context).matches
    }

    func needsMyReview(_ pr: PullRequest) -> Bool {
        saved(.needsMyReview).evaluate([pr], context: context).count == 1
    }

    func isPersonalRequest(_ request: ReviewRequest) -> Bool {
        if case .person(let person) = request.reviewer { viewer.isViewer(person) } else { false }
    }

    @Test func countsInTheMockWorld() {
        #expect(listed(.needsMyReview).count == 53)
        #expect(listed(.mine).count == 12)
        #expect(listed(.everythingOpen).count == 218)
    }

    @Test func everyViewListsOnlyOpenPullRequests() {
        for view in View.allCases {
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
        #expect(otherTeamOnly.allSatisfy { !needsMyReview($0) })
    }

    @Test func mineIsWhatTheViewerWrote() {
        #expect(listed(.mine).allSatisfy { viewer.isViewer($0.author) })
        #expect(listed(.mine).count == open.count { viewer.isViewer($0.author) })
        // Never asks the viewer to review their own pull request.
        #expect(listed(.mine).allSatisfy { !needsMyReview($0) })
    }

    @Test func everythingOpenIsEveryOpenPullRequestInOrder() {
        #expect(listed(.everythingOpen).map(\.id) == world.index.allPullRequests.filter { $0.state == .open }.map(\.id))
    }

    @Test func theWorkedExampleNeedsTheViewersReview() throws {
        let pr = try #require(world.index.pullRequest(MockWorld.workedExample))
        #expect(needsMyReview(pr))
    }

    @Test func storedByStableIDs() {
        #expect(SavedFilterFile.defaults.savedFilters.map(\.id) == ["needs-my-review", "mine"])
        #expect(SavedFilter.everything.id == "everything")
    }
}
