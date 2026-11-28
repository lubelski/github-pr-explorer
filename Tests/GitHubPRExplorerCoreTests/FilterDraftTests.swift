import Foundation
import Testing
@testable import GitHubPRExplorerCore

/// The filter being edited in the window's popovers, the values they offer, and the ids a
/// saved filter gets from its name.
@Suite struct FilterDraftTests {
    let world = MockWorld.standard
    var open: [PullRequest] { world.pullRequests.filter { $0.state == .open } }
    var context: FilterContext { FilterContext(viewer: world.viewer, now: world.now) }

    var twoSets: PullRequestFilter {
        PullRequestFilter(sets: [
            FilterConditionSet([FilterCondition(field: .status, values: ["blocked", "changesRequested"]),
                                FilterCondition(field: .author, .isNot, values: ["dependabot"])]),
            FilterConditionSet([FilterCondition(field: .reviewState, values: [FilterValues.waitingOnMe])]),
        ])
    }

    @Test func aDraftGivesBackTheFilterItWasMadeFrom() {
        #expect(FilterDraft(twoSets).filter == twoSets)
        #expect(FilterDraft().filter == .everything)
        #expect(FilterDraft().isEmpty)
        #expect(FilterDraft(SavedFilter.mine.filter).filter == SavedFilter.mine.filter)
    }

    @Test func unfinishedConditionsAndSetsAreLeftOut() {
        var draft = FilterDraft(twoSets)
        let first = draft.sets[0].id
        // A new line with no value does not narrow the first set.
        draft.addCondition(toSet: first)
        #expect(draft.filter == twoSets)
        // A new set with nothing finished does not widen the filter to everything.
        let id = draft.addSet()
        #expect(draft.filter == twoSets)
        draft.addValue("draft", to: id)
        #expect(draft.filter.sets.count == 3)
        #expect(draft.filter.sets[2].conditions == [FilterCondition(field: .status, values: ["draft"])])
    }

    @Test func addingAConditionPicksAFieldTheSetDoesNotUseYet() {
        var draft = FilterDraft(twoSets)
        let id = draft.addCondition(toSet: draft.sets[0].id)
        #expect(draft.condition(id)?.field == .organization)
        var empty = FilterDraft()
        let started = empty.addCondition(toSet: nil)
        #expect(empty.sets.count == 1)
        #expect(empty.condition(started)?.field == .status)
    }

    @Test func valuesAreAlternativesWithoutRepeats() {
        var draft = FilterDraft()
        let id = draft.addSet(field: .repository)
        draft.addValue("acme/api", to: id)
        draft.addValue("ACME/API", to: id)
        draft.addValue(" acme/web ", to: id)
        #expect(draft.condition(id)?.values == ["acme/api", "acme/web"])
        draft.toggleValue("acme/api", in: id)
        #expect(draft.condition(id)?.values == ["acme/web"])
        draft.setOperator(.isNot, of: id)
        #expect(draft.filter.sets[0].conditions[0].operator == .isNot)
    }

    @Test func draftTakesOneValueAndAFieldChangeDropsValues() {
        var draft = FilterDraft()
        let id = draft.addSet(field: .draft)
        draft.addValue("true", to: id)
        draft.addValue("false", to: id)
        #expect(draft.condition(id)?.values == ["false"])
        draft.setField(.status, of: id)
        #expect(draft.condition(id)?.values == [])
        #expect(draft.isEmpty)
    }

    @Test func removingTheLastConditionRemovesItsSet() {
        var draft = FilterDraft(twoSets)
        let only = draft.sets[1].conditions[0].id
        draft.removeCondition(only)
        #expect(draft.sets.count == 1)
        draft.removeSet(draft.sets[0].id)
        #expect(draft.isEmpty)
        var cleared = FilterDraft(twoSets)
        cleared.removeAll()
        #expect(cleared.filter == .everything)
    }

    // MARK: Values offered

    @Test func statusesAreOfferedInTheBadgesOrderWithCounts() {
        let choices = FilterValueChoices(field: .status, pullRequests: world.pullRequests, context: context, names: FilterValueNames())
        #expect(choices.choices.map(\.value) == StatusSentence.Badge.allCases.map(\.rawValue))
        let total = choices.choices.map(\.count).reduce(0, +)
        #expect(total == open.count)
        let blocked = choices.choices.first { $0.value == "blocked" }!
        #expect(blocked.count == PullRequestFilter([FilterCondition(field: .status, values: ["blocked"])]).pullRequests(in: open, context: context).count)
        #expect(blocked.title == "Blocked")
    }

    @Test func authorsOfferMeFirstThenTheMostUsed() {
        let names = FilterValueNames(pullRequests: world.pullRequests)
        let choices = FilterValueChoices(field: .author, pullRequests: world.pullRequests, context: context, names: names)
        #expect(choices.choices.first?.value == FilterValues.me)
        #expect(choices.choices.first?.title == "Me")
        #expect(choices.choices.first?.count == 12)
        // The viewer's own login is not offered twice.
        #expect(!choices.choices.contains { $0.value == world.viewer.person.login })
        let rest = choices.choices.dropFirst().map(\.count)
        #expect(rest == rest.sorted(by: >))
        // Typing finds a person by name or by login.
        let sam = choices.matching("sam")
        #expect(sam.first?.value == MockCast.samRivera.login)
        #expect(sam.first?.title == MockCast.samRivera.displayName)
    }

    @Test func aTypedNameIsAcceptedOnlyWhereTheLanguageAcceptsIt() {
        let repositories = FilterValueChoices(field: .repository, pullRequests: world.pullRequests, context: context, names: FilterValueNames())
        #expect(repositories.accepts(typed: "acme/new-service"))
        #expect(!repositories.accepts(typed: "not a repository"))
        let statuses = FilterValueChoices(field: .status, pullRequests: world.pullRequests, context: context, names: FilterValueNames())
        #expect(!statuses.accepts(typed: "blocked"))
    }

    @Test func valuesAreNamedInWords() {
        let names = FilterValueNames(pullRequests: world.pullRequests)
        #expect(names.title("changesRequested", field: .status) == StatusSentence.Badge.changesRequested.name)
        #expect(names.title(FilterValues.waitingOnMe, field: .reviewState) == "Waiting on me")
        #expect(names.title("false", field: .draft) == "No")
        #expect(names.title(MockCast.adaPark.login, field: .author) == MockCast.adaPark.displayName)
        #expect(names.title("someone-unknown", field: .author) == "someone-unknown")
    }

    // MARK: Ids and grouping

    @Test func anIdIsMadeFromTheName() {
        #expect(SavedFilter.id(forName: "Blocked in api", taken: []) == "blocked-in-api")
        #expect(SavedFilter.id(forName: "  Ça va? Déjà vu!  ", taken: []) == "ca-va-deja-vu")
        #expect(SavedFilter.id(forName: "Mine", taken: ["mine"]) == "mine-2")
        #expect(SavedFilter.id(forName: "Mine", taken: ["mine", "mine-2"]) == "mine-3")
        #expect(SavedFilter.id(forName: "Everything", taken: []) == "everything-2")
        #expect(SavedFilter.id(forName: "!!!", taken: []) == "filter")
        #expect(SavedFilter.isValidID(SavedFilter.id(forName: String(repeating: "word ", count: 30), taken: [])))
    }

    @Test func aSavedFiltersGroupingIsTheLists() {
        var saved = SavedFilter.mine
        #expect(saved.grouping == nil)
        saved.groupBy = ["organization", "repository"]
        #expect(saved.grouping == ListGrouping(.organization, then: .repository))
        saved.groupBy = ["unknownThing"]
        #expect(saved.grouping == nil)
        #expect(ListGrouping(.author, then: .status).savedFilterGroupBy == ["author", "status"])
    }
}
