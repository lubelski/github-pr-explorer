import Foundation
import Testing
@testable import GitHubPRExplorerCore

@Suite struct ListFilterTests {
    let world = MockWorld.standard
    var open: [PullRequest] { world.pullRequests.filter { $0.state == .open } }

    func status(_ pr: PullRequest) -> StatusSentence { pr.statusSentence(for: world.viewer, now: world.now) }

    func filtered(_ filter: ListFilter, _ pullRequests: [PullRequest]? = nil) -> [PullRequest] {
        filter.pullRequests(in: pullRequests ?? open, status: status)
    }

    @Test func noFilterKeepsEverything() {
        #expect(ListFilter.none.isEmpty)
        #expect(ListFilter.none.activeCount == 0)
        #expect(ListFilter.none.clauses.isEmpty)
        #expect(filtered(.none).count == open.count)
    }

    @Test func repositoryKeepsOnlyThatRepository() {
        let filter = ListFilter(repositories: [MockCast.api])
        let kept = filtered(filter)
        #expect(!kept.isEmpty)
        #expect(kept.allSatisfy { $0.repository == MockCast.api })
        #expect(kept.count == open.count { $0.repository == MockCast.api })
    }

    @Test func valuesInOneFacetAreEitherOr() {
        let api = filtered(ListFilter(repositories: [MockCast.api])).count
        let web = filtered(ListFilter(repositories: [MockCast.web])).count
        #expect(filtered(ListFilter(repositories: [MockCast.api, MockCast.web])).count == api + web)
    }

    @Test func facetsAllHaveToPass() {
        let filter = ListFilter(repositories: [MockCast.api], statuses: [.blocked])
        let kept = filtered(filter)
        #expect(!kept.isEmpty)
        #expect(kept.allSatisfy { $0.repository == MockCast.api && status($0).badge == .blocked })
        #expect(kept.count == open.count { $0.repository == MockCast.api && status($0).badge == .blocked })
        #expect(filter.activeCount == 2)
    }

    @Test func authorIsByLogin() {
        let author = MockCast.adaPark
        let kept = filtered(ListFilter(authors: [author.login]))
        #expect(!kept.isEmpty)
        #expect(kept.allSatisfy { $0.author.login == author.login })
    }

    @Test func statusUsesTheBadge() {
        let kept = filtered(ListFilter(statuses: [.running]))
        #expect(!kept.isEmpty)
        let states = Set(kept.map { status($0).state })
        #expect(states.isSubset(of: [.checksRunning, .checksQueued]))
    }

    @Test func drafts() {
        let drafts = open.count(where: \.isDraft)
        #expect(drafts > 0)
        #expect(filtered(ListFilter(drafts: .only)).count == drafts)
        #expect(filtered(ListFilter(drafts: .hidden)).count == open.count - drafts)
        #expect(filtered(ListFilter(drafts: .shown)).count == open.count)
        #expect(ListFilter(drafts: .shown).isEmpty)
    }

    @Test func reviewState() {
        for state in ListFilter.ReviewState.allCases {
            let kept = filtered(ListFilter(reviewStates: [state]))
            #expect(kept.allSatisfy { ListFilter.ReviewState($0.reviewDecision) == state })
        }
        let total = ListFilter.ReviewState.allCases.map { filtered(ListFilter(reviewStates: [$0])).count }.reduce(0, +)
        #expect(total == open.count)
    }

    @Test func reviewStateNamesNoDecision() {
        #expect(ListFilter.ReviewState(nil) == .noDecision)
        #expect(ListFilter.ReviewState(.approved) == .approved)
    }

    @Test func clausesSayEachConditionInAFixedOrder() {
        let filter = ListFilter(repositories: [MockCast.web, MockCast.api], authors: ["sam-rivera", "ada-park"],
                                statuses: [.ready, .blocked], drafts: .hidden, reviewStates: [.reviewRequired, .approved])
        #expect(filter.clauses == [
            .init(field: .repository, values: ["acme/api", "acme/web"]),
            .init(field: .author, values: ["ada-park", "sam-rivera"]),
            .init(field: .status, values: ["blocked", "ready"]),
            .init(field: .draft, values: ["false"]),
            .init(field: .reviewState, values: ["approved", "reviewRequired"]),
        ])
        #expect(ListFilter(drafts: .only).clauses == [.init(field: .draft, values: ["true"])])
    }

    @Test func toggleAddsAndRemoves() {
        var set: Set<String> = []
        ListFilter.toggle("a", in: &set)
        #expect(set == ["a"])
        ListFilter.toggle("a", in: &set)
        #expect(set.isEmpty)
    }

    @Test func roundTripsThroughJSON() throws {
        let filter = ListFilter(repositories: [MockCast.api], authors: ["ada-park"], statuses: [.waiting], drafts: .only,
                                reviewStates: [.noDecision])
        let data = try JSONEncoder().encode(filter)
        #expect(try JSONDecoder().decode(ListFilter.self, from: data) == filter)
    }

    // MARK: Choices

    @Test func choicesComeFromTheIndex() {
        let choices = ListFilterChoices(pullRequests: open, viewer: world.viewer, status: status)
        #expect(choices.repositories == Set(open.map(\.repository)).sorted())
        #expect(Set(choices.authors.map(\.login)) == Set(open.map(\.author.login)))
        #expect(Set(choices.statuses) == Set(open.map { status($0).badge }))
        #expect(choices.statuses == StatusSentence.Badge.allCases.filter(choices.statuses.contains))
        #expect(choices.hasDrafts)
        #expect(!choices.statuses.contains(.merged))
    }

    @Test func theViewerIsTheFirstAuthor() {
        let choices = ListFilterChoices(pullRequests: open, viewer: world.viewer, status: status)
        #expect(choices.authors.first?.login == world.viewer.person.login)
        let rest = choices.authors.dropFirst().map(\.displayName)
        #expect(rest == rest.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
    }

    @Test func chosenValuesStayOfferedWhenTheIndexLosesThem() {
        let gone = Repository(owner: "acme", name: "retired")
        let filter = ListFilter(repositories: [gone], authors: ["someone-gone"], statuses: [.merged], drafts: .only)
        let choices = ListFilterChoices(pullRequests: [], viewer: world.viewer, status: status, keeping: filter)
        #expect(choices.repositories == [gone])
        #expect(choices.authors.map(\.login) == ["someone-gone"])
        #expect(choices.statuses == [.merged])
        #expect(choices.hasDrafts)
    }

    @Test func combinesWithAViewAndASearch() {
        let searched = world.index.search("auth")
        let inView = searched.filter { $0.state == .open }
        let kept = filtered(ListFilter(repositories: [MockCast.api]), inView)
        #expect(kept.allSatisfy { $0.repository == MockCast.api && $0.state == .open })
        #expect(kept.count <= inView.count)
    }
}
