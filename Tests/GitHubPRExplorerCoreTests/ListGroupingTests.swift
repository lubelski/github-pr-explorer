import Foundation
import Testing
@testable import GitHubPRExplorerCore

@Suite struct ListGroupingTests {
    let world = MockWorld.standard
    var open: [PullRequest] { world.pullRequests.filter { $0.state == .open } }

    func status(_ pr: PullRequest) -> StatusSentence { pr.statusSentence(for: world.viewer, now: world.now) }

    func tree(_ grouping: ListGrouping, _ pullRequests: [PullRequest]? = nil) -> ListTree {
        ListTree(grouping: grouping, pullRequests: pullRequests ?? open, viewer: world.viewer, status: status)
    }

    /// Every grouping the menu offers: None, each property alone, and each with each second level.
    var everyGrouping: [ListGrouping] {
        [.none] + ListGrouping.Property.allCases.flatMap { first in
            [ListGrouping(first)] + first.secondLevelChoices.map { ListGrouping(first, then: $0) }
        }
    }

    let orgThenRepository = ListGrouping(.organization, then: .repository)

    // MARK: The choice

    @Test func levelsThatDoNotFitTogetherAreDropped() {
        #expect(ListGrouping([.repository, .organization]).levels == [.repository])
        #expect(ListGrouping([.author, .author]).levels == [.author])
        #expect(ListGrouping([.organization, .repository, .author]).levels == [.organization, .repository])
        #expect(ListGrouping([]).isNone)
        #expect(ListGrouping.standard == .none)
    }

    @Test func secondLevelChoicesFollowTheFirst() {
        #expect(ListGrouping.Property.repository.secondLevelChoices == [.author, .status, .reviewState])
        #expect(ListGrouping.Property.organization.secondLevelChoices == [.repository, .author, .status, .reviewState])
        for first in ListGrouping.Property.allCases {
            #expect(!first.secondLevelChoices.contains(first))
        }
    }

    @Test func namesAndStoredValuesAreFixed() {
        #expect(ListGrouping.Property.allCases.map(\.name) == ["Organization", "Repository", "Author", "Status", "Review State"])
        #expect(ListGrouping.Property.allCases.map(\.rawValue) == ["organization", "repository", "author", "status", "reviewState"])
        #expect(ListGrouping.none.name == "None")
        #expect(orgThenRepository.name == "Organization, then Repository")
        #expect(orgThenRepository.storedValue == "organization>repository")
        #expect(ListGrouping.none.storedValue == "none")
    }

    /// The one-level grouping remembered `none`, `repository`, `author`, `status` or
    /// `reviewState`. Each reads back as the same choice.
    @Test func valuesRememberedByTheOneLevelGroupingStillRead() {
        #expect(ListGrouping(storedValue: "none") == .none)
        #expect(ListGrouping(storedValue: "repository") == ListGrouping(.repository))
        #expect(ListGrouping(storedValue: "reviewState") == ListGrouping(.reviewState))
        #expect(ListGrouping(storedValue: "nonsense") == .none)
        #expect(ListGrouping(storedValue: "author>nonsense") == ListGrouping(.author))
        for grouping in everyGrouping {
            #expect(ListGrouping(storedValue: grouping.storedValue) == grouping)
        }
    }

    @Test func groupingCodesAsItsStoredValue() throws {
        let data = try JSONEncoder().encode([orgThenRepository])
        #expect(String(decoding: data, as: UTF8.self) == #"["organization>repository"]"#)
        #expect(try JSONDecoder().decode([ListGrouping].self, from: data) == [orgThenRepository])
    }

    @Test func selectionsAreRememberedAsText() {
        let selections: [ListSelection] = [.pullRequest("PR_1"), .group("organization:acme|repository:acme/api")]
        for selection in selections {
            #expect(ListSelection(storedValue: selection.storedValue) == selection)
        }
        #expect(ListSelection(storedValue: "something else") == nil)
    }

    // MARK: The tree

    @Test func noneIsTheFlatList() {
        let flat = tree(.none)
        #expect(flat.groups.isEmpty)
        #expect(flat.ordered.map(\.id) == open.map(\.id))
        let rows = flat.rows(closed: ["anything"])
        #expect(rows.map(\.id) == open.map { .pullRequest($0.id) })
        #expect(rows.allSatisfy { $0.depth == 0 && $0.namedByAncestors.isEmpty })
        #expect(!flat.canCloseAll(closed: []))
        #expect(!flat.canOpenAll(closed: ["anything"]))
    }

    @Test func nothingToGroupHasNoTitleRows() {
        for grouping in everyGrouping {
            #expect(tree(grouping, []).groups.isEmpty)
            #expect(tree(grouping, []).rows(closed: []).isEmpty)
        }
    }

    @Test func everyGroupingKeepsEveryRowOnce() {
        for grouping in everyGrouping {
            let built = tree(grouping)
            let ids = built.ordered.map(\.id)
            #expect(ids.count == open.count, "\(grouping)")
            #expect(Set(ids) == Set(open.map(\.id)), "\(grouping)")
            let all = built.allGroups
            #expect(Set(all.map(\.id)).count == all.count, "\(grouping)")
            #expect(all.allSatisfy { $0.count > 0 }, "\(grouping)")
            #expect(built.visiblePullRequests(closed: []).map(\.id) == ids, "\(grouping)")
        }
    }

    /// A title row counts every pull request inside it, at any depth.
    @Test func aTitleRowCountsEverythingInsideIt() {
        for grouping in everyGrouping where grouping.second != nil {
            for group in tree(grouping).groups {
                #expect(!group.children.isEmpty)
                #expect(group.count == group.children.reduce(0) { $0 + $1.count }, "\(group.id)")
                #expect(group.pullRequests.map(\.id) == group.children.flatMap(\.pullRequests).map(\.id))
            }
        }
    }

    @Test func rowsKeepTheirOrderInsideAGroup() {
        let position = Dictionary(uniqueKeysWithValues: open.enumerated().map { ($1.id, $0) })
        for grouping in everyGrouping {
            for group in tree(grouping).allGroups where group.children.isEmpty {
                let positions = group.pullRequests.compactMap { position[$0.id] }
                #expect(positions == positions.sorted())
            }
        }
    }

    /// The mock world has a second organization, and both have a `docs` repository.
    @Test func organizationThenRepository() {
        let built = tree(orgThenRepository)
        #expect(built.groups.map(\.title) == ["acme", "globex"])
        let acme = built.groups[0], globex = built.groups[1]
        #expect(acme.id == "organization:acme")
        #expect(acme.children.map(\.title) == ["api", "docs", "infra", "web"])
        #expect(globex.children.map(\.title) == ["billing", "docs"])
        #expect(acme.children.map(\.id).contains("organization:acme|repository:acme/docs"))
        #expect(globex.children.map(\.id).contains("organization:globex|repository:globex/docs"))
        #expect(acme.count == open.count { $0.repository.owner == "acme" })
        #expect(globex.count == open.count { $0.repository.owner == "globex" })
        #expect(globex.count > 0)
        for child in acme.children {
            #expect(child.depth == 1 && child.parentID == acme.id && child.property == .repository)
            #expect(child.pullRequests.allSatisfy { $0.repository.name == child.title && $0.repository.owner == "acme" })
        }
    }

    /// On its own, or first, a repository is named in full and keeps the id the one-level
    /// grouping gave it, so rows remembered as closed stay closed.
    @Test func aRepositoryOutsideItsOrganizationIsNamedInFull() {
        let built = tree(ListGrouping(.repository))
        #expect(built.groups.count > 1)
        #expect(built.groups.map(\.title) == built.groups.map(\.title).sorted())
        #expect(built.groups.contains { $0.id == "repository:\(MockCast.api.fullName)" && $0.title == "acme/api" })
        let byAuthor = tree(ListGrouping(.author, then: .repository))
        #expect(byAuthor.groups.flatMap(\.children).allSatisfy { $0.title.contains("/") })
    }

    @Test func groupsFollowTheFilterMenusOrder() {
        let choices = ListFilterChoices(pullRequests: open, viewer: world.viewer, status: status)
        #expect(tree(ListGrouping(.repository)).groups.map(\.title) == choices.repositories.map(\.fullName))
        #expect(tree(ListGrouping(.author)).groups.map(\.id) == choices.authors.map { "author:\($0.login)" })
        #expect(tree(ListGrouping(.status)).groups.map(\.title) == choices.statuses.map(\.name))
        #expect(tree(ListGrouping(.reviewState)).groups.map(\.title) == choices.reviewStates.map(\.name))
    }

    @Test func shorthandsNameRepositoryAndAuthorTitleRows() {
        let viewer = world.viewer.person
        let other = open.map(\.author).first { $0.login != viewer.login }!
        let shorthands = Shorthands([
            Shorthand(kind: .repository, target: MockCast.api.fullName, shorthand: "API"),
            Shorthand(kind: .person, target: viewer.login, shorthand: "Me"),
            Shorthand(kind: .person, target: other.login, shorthand: "Short"),
        ])
        func shortened(_ grouping: ListGrouping) -> ListTree {
            ListTree(grouping: grouping, pullRequests: open, viewer: world.viewer, status: status, shorthands: shorthands)
        }
        let plain = tree(ListGrouping(.repository)).groups
        let repositories = shortened(ListGrouping(.repository)).groups
        // The same title rows in the same order: only the names change.
        #expect(repositories.map(\.id) == plain.map(\.id))
        let api = repositories.first { $0.id == "repository:\(MockCast.api.fullName)" }
        #expect(api?.title == "API")
        #expect(api?.name.fullName == MockCast.api.fullName)
        #expect(api?.name.isShortened == true)
        #expect(repositories.filter { $0.name.isShortened }.count == 1)

        let authors = shortened(ListGrouping(.author)).groups
        #expect(authors.map(\.id) == tree(ListGrouping(.author)).groups.map(\.id))
        #expect(authors.first?.title == "Me (you)")
        #expect(authors.first?.name.isShortened == true)
        #expect(authors.first { $0.id == "author:\(other.login)" }?.title == "Short")

        // Under its organization, a repository with a shorthand is named by it alone, and one
        // without is named without its organization. The organization keeps its name.
        let nested = shortened(orgThenRepository)
        #expect(nested.allGroups.map(\.id) == tree(orgThenRepository).allGroups.map(\.id))
        #expect(nested.groups.allSatisfy { !$0.name.isShortened })
        let nestedAPI = nested.group(id: "organization:\(MockCast.api.owner)|repository:\(MockCast.api.fullName)")
        #expect(nestedAPI?.title == "API")
        #expect(nestedAPI?.name.fullName == MockCast.api.fullName)
        let nestedOthers = nested.allGroups.filter { $0.depth == 1 && $0.id != nestedAPI?.id }
        #expect(!nestedOthers.isEmpty)
        #expect(nestedOthers.allSatisfy { !$0.name.isShortened && !$0.title.contains("/") })

        // At the second level, an author's shorthand names their row too.
        let byRepositoryThenAuthor = shortened(ListGrouping(.repository, then: .author))
        #expect(byRepositoryThenAuthor.allGroups.contains { $0.depth == 1 && $0.title == "Me (you)" })

        // With none set, a title row's name is its full name, unshortened.
        for grouping in everyGrouping {
            #expect(tree(grouping).allGroups.allSatisfy { !$0.name.isShortened && $0.name.fullName == $0.title })
        }
    }

    @Test func theViewerIsTheFirstAuthor() {
        let groups = tree(ListGrouping(.author)).groups
        let viewer = world.viewer.person
        #expect(groups.first?.id == "author:\(viewer.login)")
        #expect(groups.first?.title == "\(viewer.displayName) (you)")
        #expect(groups.dropFirst().allSatisfy { !$0.title.hasSuffix("(you)") })
    }

    @Test func statusesFollowTheBadgeOrder() {
        let groups = tree(ListGrouping(.status)).groups
        #expect(groups.count > 1)
        let badges = groups.compactMap { $0.pullRequests.first.map { status($0).badge } }
        #expect(badges == StatusSentence.Badge.allCases.filter(Set(badges).contains))
        for (group, badge) in zip(groups, badges) {
            #expect(group.pullRequests.allSatisfy { status($0).badge == badge })
            #expect(group.title == badge.name)
        }
    }

    @Test func groupsLeftEmptyByAFilterAreNotShown() {
        let filtered = ListFilter(repositories: [MockCast.api]).pullRequests(in: open, status: status)
        let built = tree(orgThenRepository, filtered)
        #expect(built.groups.map(\.id) == ["organization:acme"])
        #expect(built.groups.first?.children.map(\.title) == ["api"])
        #expect(built.groups.first?.count == filtered.count)
    }

    // MARK: Rows

    @Test func rowsSayHowDeepTheySitAndWhatIsAlreadyNamed() {
        let rows = tree(orgThenRepository).rows(closed: [])
        guard case .group(let acme, true) = rows[0].content else { Issue.record("first row is not acme"); return }
        #expect(acme.title == "acme" && rows[0].depth == 0)
        guard case .group(let api, true) = rows[1].content else { Issue.record("second row is not api"); return }
        #expect(api.title == "api" && rows[1].depth == 1 && rows[1].namedByAncestors == [.organization])
        guard case .pullRequest(let pr) = rows[2].content else { Issue.record("third row is not a pull request"); return }
        #expect(pr.repository == MockCast.api)
        #expect(rows[2].depth == 2 && rows[2].namedByAncestors == [.organization, .repository])
    }

    @Test func aClosedRowHidesWhatItHoldsAndKeepsItsCount() {
        let built = tree(orgThenRepository)
        let api = "organization:acme|repository:acme/api"
        let rows = built.rows(closed: [api])
        let apiRow = rows.first { $0.id == .group(api) }
        guard case .group(let group, false)? = apiRow?.content else { Issue.record("api is not a closed row"); return }
        #expect(group.count == open.count { $0.repository == MockCast.api })
        #expect(!rows.contains { row in
            if case .pullRequest(let pr) = row.content { pr.repository == MockCast.api } else { false }
        })
        // Closing an organization hides its repositories' rows too.
        let closedOrg = built.rows(closed: ["organization:acme"])
        #expect(closedOrg.first?.id == .group("organization:acme"))
        #expect(closedOrg[1].id == .group("organization:globex"))
    }

    @Test func idsOfRowsNotInTheTreeAreHarmless() {
        let built = tree(ListGrouping(.status))
        let stale: Set<String> = ["repository:acme/gone", "author:nobody"]
        #expect(built.visiblePullRequests(closed: stale).count == open.count)
        #expect(!built.canOpenAll(closed: stale))
    }

    // MARK: Selection

    @Test func theNearestVisibleRowIsTheOutermostClosedOne() {
        let built = tree(orgThenRepository)
        let pr = built.groups[0].children[0].pullRequests[0]
        let api = built.groups[0].children[0].id
        #expect(built.ancestorIDs(of: .pullRequest(pr.id)) == ["organization:acme", api])
        #expect(built.parent(of: .pullRequest(pr.id)) == .group(api))
        #expect(built.parent(of: .group(api)) == .group("organization:acme"))
        #expect(built.parent(of: .group("organization:acme")) == nil)
        #expect(built.nearestVisible(.pullRequest(pr.id), closed: []) == .pullRequest(pr.id))
        #expect(built.nearestVisible(.pullRequest(pr.id), closed: [api]) == .group(api))
        #expect(built.nearestVisible(.pullRequest(pr.id), closed: [api, "organization:acme"]) == .group("organization:acme"))
        #expect(built.nearestVisible(.pullRequest("no-such-id"), closed: []) == nil)
        #expect(built.isVisible(.group(api), closed: [api]))
        #expect(!built.isVisible(.group(api), closed: ["organization:acme"]))
    }

    // MARK: Opening and closing

    @Test func toggleOneRow() {
        var closed: Set<String> = []
        ListTree.toggle("repository:acme/api", in: &closed)
        #expect(closed == ["repository:acme/api"])
        ListTree.toggle("repository:acme/api", in: &closed)
        #expect(closed.isEmpty)
    }

    /// Option-click on a triangle acts on every row at its level, and no other.
    @Test func optionClickTogglesEveryRowAtTheLevel() {
        let built = tree(orgThenRepository)
        let repositories = Set(built.allGroups.filter { $0.depth == 1 }.map(\.id))
        let first = built.groups[0].children[0].id
        var closed: Set<String> = ["author:someone"]
        built.toggleLevel(from: first, in: &closed)
        #expect(closed == repositories.union(["author:someone"]))
        built.toggleLevel(from: first, in: &closed)
        #expect(closed == ["author:someone"])
        built.toggleLevel(from: "organization:acme", in: &closed)
        #expect(closed == ["author:someone", "organization:acme", "organization:globex"])
    }

    @Test func collapseAllAndExpandAllAreOnlyOfferedWhenTheyChangeSomething() {
        let built = tree(orgThenRepository)
        var closed: Set<String> = []
        #expect(built.canCloseAll(closed: closed))
        #expect(!built.canOpenAll(closed: closed))
        built.setAll(closed: true, in: &closed)
        #expect(closed == Set(built.allGroups.map(\.id)))
        #expect(!built.canCloseAll(closed: closed))
        #expect(built.canOpenAll(closed: closed))
        #expect(built.rows(closed: closed).map(\.id) == built.groups.map { .group($0.id) })
        built.setAll(closed: false, in: &closed)
        #expect(closed.isEmpty)
    }
}
