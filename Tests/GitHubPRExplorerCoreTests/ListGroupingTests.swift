import Foundation
import Testing
@testable import GitHubPRExplorerCore

@Suite struct ListGroupingTests {
    let world = MockWorld.standard
    var open: [PullRequest] { FixedListView.everythingOpen.pullRequests(in: world.pullRequests, viewer: world.viewer) }

    func status(_ pr: PullRequest) -> StatusSentence { pr.statusSentence(for: world.viewer, now: world.now) }

    func sections(_ grouping: ListGrouping, _ pullRequests: [PullRequest]? = nil) -> [ListGrouping.Section] {
        grouping.sections(of: pullRequests ?? open, viewer: world.viewer, status: status)
    }

    @Test func noneIsTheFlatList() {
        let all = sections(.none)
        #expect(all.count == 1)
        #expect(all.first?.title == "")
        #expect(all.first?.pullRequests.map(\.id) == open.map(\.id))
        #expect(ListGrouping.none.ordered(open, viewer: world.viewer, status: status).map(\.id) == open.map(\.id))
        #expect(ListGrouping.standard == .none)
    }

    @Test func nothingToGroupHasNoSections() {
        for grouping in ListGrouping.allCases {
            #expect(sections(grouping, []).isEmpty)
        }
    }

    @Test func everyGroupingKeepsEveryRowOnce() {
        for grouping in ListGrouping.allCases {
            let groups = sections(grouping)
            let ids = groups.flatMap(\.pullRequests).map(\.id)
            #expect(ids.count == open.count)
            #expect(Set(ids) == Set(open.map(\.id)))
            #expect(groups.allSatisfy { $0.count > 0 })
            #expect(Set(groups.map(\.id)).count == groups.count)
            #expect(grouping.ordered(open, viewer: world.viewer, status: status).map(\.id) == ids)
        }
    }

    @Test func rowsKeepTheirOrderInsideASection() {
        let position = Dictionary(uniqueKeysWithValues: open.enumerated().map { ($1.id, $0) })
        for grouping in ListGrouping.allCases {
            for section in sections(grouping) {
                let positions = section.pullRequests.compactMap { position[$0.id] }
                #expect(positions == positions.sorted())
            }
        }
    }

    @Test func repositoriesAreSortedByFullName() {
        let groups = sections(.repository)
        #expect(groups.count > 1)
        #expect(groups.map(\.title) == groups.map(\.title).sorted())
        for section in groups {
            #expect(section.pullRequests.allSatisfy { $0.repository.fullName == section.title })
        }
        let api = groups.first { $0.id == "repository:\(MockCast.api.fullName)" }
        #expect(api?.count == open.count { $0.repository == MockCast.api })
    }

    @Test func sectionsFollowTheFilterMenusOrder() {
        let choices = ListFilterChoices(pullRequests: open, viewer: world.viewer, status: status)
        #expect(sections(.repository).map(\.title) == choices.repositories.map(\.fullName))
        #expect(sections(.author).map(\.id) == choices.authors.map { "author:\($0.login)" })
        #expect(sections(.status).map(\.title) == choices.statuses.map(\.name))
        #expect(sections(.reviewState).map(\.title) == choices.reviewStates.map(\.name))
    }

    @Test func theViewerIsTheFirstAuthor() {
        let groups = sections(.author)
        let viewer = world.viewer.person
        #expect(open.contains { $0.author.login == viewer.login })
        #expect(groups.first?.id == "author:\(viewer.login)")
        #expect(groups.first?.title == "\(viewer.displayName) (you)")
        let others = groups.dropFirst().compactMap { $0.pullRequests.first?.author.displayName }
        #expect(others == others.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        #expect(groups.dropFirst().allSatisfy { !$0.title.hasSuffix("(you)") })
    }

    @Test func statusesFollowTheBadgeOrder() {
        let groups = sections(.status)
        #expect(groups.count > 1)
        let badges = groups.compactMap { $0.pullRequests.first.map { status($0).badge } }
        #expect(badges == StatusSentence.Badge.allCases.filter(Set(badges).contains))
        for (section, badge) in zip(groups, badges) {
            #expect(section.pullRequests.allSatisfy { status($0).badge == badge })
            #expect(section.title == badge.name)
        }
    }

    @Test func reviewStatesFollowTheirOrder() {
        let groups = sections(.reviewState)
        #expect(groups.count > 1)
        let states = groups.compactMap { $0.pullRequests.first.map { ListFilter.ReviewState($0.reviewDecision) } }
        #expect(states == ListFilter.ReviewState.allCases.filter(Set(states).contains))
        for (section, state) in zip(groups, states) {
            #expect(section.pullRequests.allSatisfy { ListFilter.ReviewState($0.reviewDecision) == state })
        }
    }

    @Test func groupsLeftEmptyByAFilterAreNotShown() {
        let filtered = ListFilter(repositories: [MockCast.api]).pullRequests(in: open, status: status)
        let groups = sections(.repository, filtered)
        #expect(groups.map(\.id) == ["repository:\(MockCast.api.fullName)"])
        #expect(groups.first?.count == filtered.count)
    }

    @Test func groupingNamesAndRawValuesAreFixed() {
        #expect(ListGrouping.allCases.map(\.name) == ["None", "Repository", "Author", "Status", "Review state"])
        #expect(ListGrouping.allCases.map(\.rawValue) == ["none", "repository", "author", "status", "reviewState"])
    }
}
