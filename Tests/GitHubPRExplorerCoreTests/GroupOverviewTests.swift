import Foundation
import Testing
@testable import GitHubPRExplorerCore

/// The overview of a selected title row (Figma row 10): its counts, its sections, and whose
/// move each card is.
@Suite struct GroupOverviewTests {
    let world = MockWorld.standard
    var open: [PullRequest] { FixedListView.everythingOpen.pullRequests(in: world.pullRequests, viewer: world.viewer) }
    var mine: [PullRequest] { FixedListView.mine.pullRequests(in: world.pullRequests, viewer: world.viewer) }

    func status(_ pr: PullRequest) -> StatusSentence { pr.statusSentence(for: world.viewer, now: world.now) }

    func tree(_ grouping: ListGrouping, _ pullRequests: [PullRequest]) -> ListTree {
        ListTree(grouping: grouping, pullRequests: pullRequests, viewer: world.viewer, status: status)
    }

    func overview(_ id: String, in tree: ListTree) throws -> GroupOverview {
        let group = try #require(tree.group(id: id))
        return GroupOverview(group: group, in: tree, viewer: world.viewer, status: status)
    }

    let orgThenRepository = ListGrouping(.organization, then: .repository)

    /// Every title row of every grouping: the counts add up to the row's count, and the cards
    /// are the row's pull requests, each once, in the list's order within a section.
    @Test func everyOverviewHoldsExactlyItsRowsPullRequests() {
        let groupings = ListGrouping.Property.allCases.flatMap { first in
            [ListGrouping(first)] + first.secondLevelChoices.map { ListGrouping(first, then: $0) }
        }
        for grouping in groupings {
            let built = tree(grouping, open)
            for group in built.allGroups {
                let overview = GroupOverview(group: group, in: built, viewer: world.viewer, status: status)
                #expect(overview.statusCounts.reduce(0) { $0 + $1.count } == group.count, "\(group.id)")
                let ids = overview.sections.flatMap(\.cards).map(\.id)
                #expect(Set(ids) == Set(group.pullRequests.map(\.id)), "\(group.id)")
                #expect(ids.count == group.count, "\(group.id)")
                #expect(overview.sections.allSatisfy { !$0.cards.isEmpty }, "\(group.id)")
                for section in overview.sections {
                    #expect(section.statusCounts.reduce(0) { $0 + $1.count } == section.cards.count)
                }
            }
        }
    }

    /// An organization grouped then by repository has a section per repository, named as the
    /// list's rows name them, each pointing at its row.
    @Test func sectionsAreTheRowsOneLevelDown() throws {
        let built = tree(orgThenRepository, mine)
        let acme = try overview("organization:acme", in: built)
        let rows = try #require(built.group(id: "organization:acme")).children
        #expect(acme.sections.map(\.id) == rows.map(\.id))
        #expect(acme.sections.map(\.groupID) == rows.map(\.id))
        #expect(acme.sections.map { $0.name?.text } == rows.map(\.title))
        #expect(acme.sectionProperty == .repository)
        #expect(acme.sections.allSatisfy { $0.namedProperties == [.organization, .repository] })
        #expect(acme.ancestorProperties.isEmpty)
    }

    /// At the last level the cards are in sections by status, in the badges' order. Those are
    /// not rows of the list, so a heading selects nothing.
    @Test func theLastLevelIsInSectionsByStatus() throws {
        let built = tree(orgThenRepository, open)
        let api = try overview("organization:acme|repository:acme/api", in: built)
        #expect(api.ancestorProperties == [.organization])
        #expect(api.sectionProperty == nil)
        #expect(api.sections.count > 1)
        let badges = api.sections.compactMap { section in StatusSentence.Badge.allCases.first { "status:\($0.rawValue)" == section.id } }
        #expect(badges.count == api.sections.count)
        #expect(badges == StatusSentence.Badge.allCases.filter(badges.contains))
        #expect(api.sections.allSatisfy { $0.groupID == nil && $0.namedProperties.contains(.status) })
        for section in api.sections {
            #expect(Set(section.cards.map(\.status.badge)).count == 1)
            #expect(section.name?.text == section.cards.first?.status.badge.name)
        }
    }

    /// A status row, or a row inside one, is not split by status again.
    @Test func aStatusIsNotSplitByStatus() throws {
        let byStatus = tree(ListGrouping(.status), open)
        let blocked = try overview("status:blocked", in: byStatus)
        #expect(blocked.sections.count == 1)
        #expect(blocked.sections[0].name == nil)
        #expect(blocked.statusCounts.map(\.badge) == [.blocked])

        let statusThenRepository = tree(ListGrouping(.status, then: .repository), open)
        let inner = try #require(statusThenRepository.group(id: "status:blocked")?.children.first)
        let overview = GroupOverview(group: inner, in: statusThenRepository, viewer: world.viewer, status: status)
        #expect(overview.sections.map(\.id) == ["all"])
        #expect(overview.ancestorProperties == [.status])
    }

    /// The overview reads the tree the list draws, so the search and the filters narrow it the
    /// same way.
    @Test func theOverviewFollowsWhatTheListHolds() throws {
        let filter = ListFilter(statuses: [.blocked])
        let narrowed = filter.pullRequests(in: open, status: status)
        let full = try overview("organization:acme", in: tree(orgThenRepository, open))
        let few = try overview("organization:acme", in: tree(orgThenRepository, narrowed))
        #expect(few.group.count < full.group.count)
        #expect(few.statusCounts.map(\.badge) == [.blocked])
        #expect(few.sections.flatMap(\.cards).allSatisfy { $0.status.badge == .blocked })
    }

    /// A group of one pull request, as acme/docs is in "Mine".
    @Test func aGroupOfOne() throws {
        let built = tree(orgThenRepository, mine)
        let one = try #require(built.allGroups.first { $0.count == 1 })
        let overview = GroupOverview(group: one, in: built, viewer: world.viewer, status: status)
        #expect(overview.sections.count == 1)
        #expect(overview.sections[0].cards.count == 1)
        #expect(overview.statusCounts.map(\.count) == [1])
    }

    /// Whose move it is follows the status sentence.
    @Test func nextMoveFollowsTheStatus() {
        for pr in open {
            let sentence = status(pr)
            let move = GroupOverview.nextMove(pr, status: sentence)
            switch sentence.badge {
            case .waiting:
                #expect(move == .reviewers(pr.reviewRequests.map(\.reviewer)), "\(pr.reference)")
            case .running:
                #expect(move == .checks)
            case .merging:
                #expect(move == .mergeQueue)
            case .checking:
                #expect(move == .github)
            case .draft, .blocked, .changesRequested, .failing, .threads, .behind, .ready:
                #expect(move == .author(pr.author), "\(pr.reference)")
            case .merged, .closed:
                Issue.record("an open pull request is never merged or closed")
            }
        }
    }

    /// A card needs the viewer when a review is asked of them or their team, or it is theirs
    /// and waits on them, other than as a draft.
    @Test func whatNeedsTheViewer() throws {
        let built = tree(ListGrouping(.organization), open)
        let acme = try overview("organization:acme", in: built)
        let cards = acme.sections.flatMap(\.cards)
        for card in cards {
            let theirMove = card.nextMove == .author(card.pullRequest.author)
                && world.viewer.isViewer(card.pullRequest.author) && !card.pullRequest.isDraft
            #expect(card.needsViewer == (card.status.isReviewRequestedFromViewer || theirMove), "\(card.pullRequest.reference)")
        }
        #expect(acme.needsViewerCount == cards.count { $0.needsViewer })
        #expect(acme.needsViewerCount > 0)
        #expect(acme.needsViewerCount < cards.count)
        // The worked example asks a review of the viewer's team.
        let example = try #require(cards.first { $0.pullRequest.reference == MockWorld.workedExample })
        #expect(example.needsViewer)
    }

    /// The mock world gives the overview a group of about 200, for scrolling.
    @Test func theMockWorldHasALargeGroup() throws {
        let acme = try overview("organization:acme", in: tree(ListGrouping(.organization), open))
        #expect(acme.group.count >= 200)
    }

    // MARK: The layout

    @Test func theStandardLayoutIsTheSummaryThenThePullRequests() {
        #expect(OverviewLayout.standard.blocks.map(\.kind) == [.summary, .pullRequests])
        #expect(OverviewLayout.standard.blocks.allSatisfy { $0.size == .large })
        #expect(OverviewBlockKind.allCases.map(\.rawValue) == ["summary", "pullRequests"])
    }

    @Test func theLayoutRoundTripsAsJSON() throws {
        let data = try GitHubPRExplorerJSON.encoder().encode(OverviewLayout.standard)
        let decoded = try GitHubPRExplorerJSON.decoder().decode(OverviewLayout.self, from: data)
        #expect(decoded == OverviewLayout.standard)
        let unknown = Data(#"{"formatVersion": 1, "id": "x", "name": "X", "blocks": [{"kind": "chart", "size": "large"}]}"#.utf8)
        #expect(throws: DecodingError.self) { try GitHubPRExplorerJSON.decoder().decode(OverviewLayout.self, from: unknown) }
    }
}
