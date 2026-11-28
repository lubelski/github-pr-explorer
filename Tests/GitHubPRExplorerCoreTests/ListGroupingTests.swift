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

    @Test func shorthandsNameRepositoryAndAuthorSections() {
        let viewer = world.viewer.person
        let other = open.map(\.author).first { $0.login != viewer.login }!
        let shorthands = Shorthands([
            Shorthand(kind: .repository, target: MockCast.api.fullName, shorthand: "API"),
            Shorthand(kind: .person, target: viewer.login, shorthand: "Me"),
            Shorthand(kind: .person, target: other.login, shorthand: "Short"),
        ])
        let plain = sections(.repository)
        let repositories = ListGrouping.repository.sections(of: open, viewer: world.viewer, status: status, shorthands: shorthands)
        // The same sections in the same order: only the names change.
        #expect(repositories.map(\.id) == plain.map(\.id))
        let api = repositories.first { $0.id == "repository:\(MockCast.api.fullName)" }
        #expect(api?.title == "API")
        #expect(api?.name.fullName == MockCast.api.fullName)
        #expect(api?.name.isShortened == true)
        #expect(repositories.filter { $0.name.isShortened }.count == 1)

        let authors = ListGrouping.author.sections(of: open, viewer: world.viewer, status: status, shorthands: shorthands)
        #expect(authors.map(\.id) == sections(.author).map(\.id))
        #expect(authors.first?.title == "Me (you)")
        #expect(authors.first?.name.isShortened == true)
        #expect(authors.first { $0.id == "author:\(other.login)" }?.title == "Short")

        // With none set, a section's name is its full name, unshortened.
        #expect(plain.allSatisfy { !$0.name.isShortened && $0.name.fullName == $0.title })
        #expect(sections(.author).allSatisfy { !$0.name.isShortened && $0.name.fullName == $0.title })
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

    // MARK: Collapsing

    @Test func collapsedSectionsHideTheirRowsInScreenOrder() {
        let groups = sections(.repository)
        #expect(groups.count >= 3)
        let collapsed: Set<String> = [groups[1].id]
        let visible = ListGrouping.repository.visible(groups, collapsed: collapsed)
        let expected = ([groups[0]] + groups.dropFirst(2)).flatMap(\.pullRequests).map(\.id)
        #expect(visible.map(\.id) == expected)
        #expect(ListGrouping.repository.visible(groups, collapsed: []).map(\.id) == groups.flatMap(\.pullRequests).map(\.id))
    }

    @Test func theFlatListNeverFolds() {
        let flat = sections(.none)
        #expect(ListGrouping.none.visible(flat, collapsed: ["all"]).map(\.id) == open.map(\.id))
        #expect(!ListGrouping.none.canCollapseAll(flat, collapsed: []))
        #expect(!ListGrouping.none.canExpandAll(flat, collapsed: ["all"]))
    }

    @Test func idsOfSectionsNotShownAreHarmless() {
        let groups = sections(.status)
        let stale: Set<String> = ["repository:acme/gone", "author:nobody"]
        #expect(ListGrouping.status.visible(groups, collapsed: stale).count == open.count)
        #expect(!ListGrouping.status.canExpandAll(groups, collapsed: stale))
    }

    @Test func toggleOneSection() {
        var collapsed: Set<String> = []
        ListGrouping.toggle("repository:acme/api", in: &collapsed)
        #expect(collapsed == ["repository:acme/api"])
        ListGrouping.toggle("repository:acme/api", in: &collapsed)
        #expect(collapsed.isEmpty)
    }

    @Test func optionClickTogglesEverySectionFromTheClickedOne() {
        let groups = sections(.repository)
        let all = Set(groups.map(\.id))
        var collapsed: Set<String> = ["author:someone", groups[1].id]
        // The clicked section is expanded, so every section collapses.
        ListGrouping.toggleAll(from: groups[0].id, sections: groups, in: &collapsed)
        #expect(collapsed == all.union(["author:someone"]))
        // Now it is collapsed, so every section expands, and other groupings' ids stay.
        ListGrouping.toggleAll(from: groups[0].id, sections: groups, in: &collapsed)
        #expect(collapsed == ["author:someone"])
        // From a collapsed section while others are expanded: every section expands.
        collapsed = [groups[2].id]
        ListGrouping.toggleAll(from: groups[2].id, sections: groups, in: &collapsed)
        #expect(collapsed.isEmpty)
    }

    @Test func collapseAllAndExpandAllAreOnlyOfferedWhenTheyChangeSomething() {
        let groups = sections(.reviewState)
        var collapsed: Set<String> = []
        #expect(ListGrouping.reviewState.canCollapseAll(groups, collapsed: collapsed))
        #expect(!ListGrouping.reviewState.canExpandAll(groups, collapsed: collapsed))
        ListGrouping.setAll(collapsed: true, sections: groups, in: &collapsed)
        #expect(!ListGrouping.reviewState.canCollapseAll(groups, collapsed: collapsed))
        #expect(ListGrouping.reviewState.canExpandAll(groups, collapsed: collapsed))
        #expect(ListGrouping.reviewState.visible(groups, collapsed: collapsed).isEmpty)
        ListGrouping.setAll(collapsed: false, sections: groups, in: &collapsed)
        #expect(collapsed.isEmpty)
    }

    @Test func findsTheSectionHoldingAPullRequest() {
        let groups = sections(.author)
        let pr = groups[1].pullRequests[0]
        #expect(ListGrouping.sectionID(containing: pr.id, in: groups) == groups[1].id)
        #expect(ListGrouping.sectionID(containing: "no-such-id", in: groups) == nil)
    }
}
