import Foundation
import Testing
@testable import GitHubPRExplorerCore

/// The one filter language: sets joined by OR, conditions joined by AND, alternatives inside a
/// condition, is and is not. Checked against the mock world.
@Suite struct FilterLanguageTests {
    let world = MockWorld.standard
    var open: [PullRequest] { world.pullRequests.filter { $0.state == .open } }
    var context: FilterContext { FilterContext(viewer: world.viewer, now: world.now) }

    func status(_ pr: PullRequest) -> StatusSentence { pr.statusSentence(for: world.viewer, now: world.now) }

    func kept(_ filter: PullRequestFilter) -> [PullRequest] { filter.pullRequests(in: open, context: context) }

    func condition(_ field: FilterField, _ op: FilterOperator = .is, _ values: String...) -> FilterCondition {
        FilterCondition(field: field, op, values: values)
    }

    // MARK: One language with the menu and the fixed views

    @Test func theMenusFilterKeepsWhatTheLanguageKeeps() {
        let filters: [ListFilter] = [
            .none,
            ListFilter(repositories: [MockCast.api]),
            ListFilter(repositories: [MockCast.api, MockCast.web], statuses: [.blocked, .changesRequested]),
            ListFilter(authors: [MockCast.adaPark.login, MockCast.samRivera.login], drafts: .hidden),
            ListFilter(drafts: .only),
            ListFilter(statuses: [.running], reviewStates: [.reviewRequired, .noDecision]),
            ListFilter(repositories: [MockCast.web], authors: [MockCast.maxChen.login], statuses: [.waiting], drafts: .hidden, reviewStates: [.approved]),
        ]
        for filter in filters {
            let byMenu = filter.pullRequests(in: open, status: status).map(\.id)
            let byLanguage = kept(filter.filter).map(\.id)
            #expect(byMenu == byLanguage, "\(filter.clauses)")
        }
    }

    @Test func theDefaultSavedFiltersAreTodaysViews() {
        let all = world.pullRequests
        let viewer = world.viewer
        #expect(SavedFilter.needsMyReview.evaluate(all, context: context).matches.map(\.id)
                == FixedListView.needsMyReview.pullRequests(in: all, viewer: viewer).map(\.id))
        #expect(SavedFilter.mine.evaluate(all, context: context).matches.map(\.id)
                == FixedListView.mine.pullRequests(in: all, viewer: viewer).map(\.id))
        #expect(SavedFilter.everything.evaluate(all, context: context).matches.map(\.id)
                == FixedListView.everythingOpen.pullRequests(in: all, viewer: viewer).map(\.id))
        #expect(SavedFilter.needsMyReview.evaluate(all, context: context).count == 48)
        #expect(SavedFilter.mine.evaluate(all, context: context).count == 12)
        #expect(SavedFilter.everything.evaluate(all, context: context).count == 218)
        #expect(SavedFilterFile.defaults.savedFilters.map(\.id) == ["needs-my-review", "mine"])
    }

    // MARK: Matching

    @Test func setsAreOrAndConditionsAreAnd() {
        let blockedInAPI = [condition(.status, .is, "blocked"), condition(.repository, .is, "acme/api")]
        let drafts = [condition(.draft, .is, "true")]
        let both = kept(PullRequestFilter(sets: [FilterConditionSet(blockedInAPI), FilterConditionSet(drafts)]))
        let first = kept(PullRequestFilter(blockedInAPI))
        let second = kept(PullRequestFilter(drafts))
        #expect(!first.isEmpty && !second.isEmpty)
        #expect(first.allSatisfy { status($0).badge == .blocked && $0.repository == MockCast.api })
        #expect(Set(both.map(\.id)) == Set(first.map(\.id)).union(second.map(\.id)))
    }

    @Test func valuesOnOneConditionAreAlternatives() {
        let api = kept(PullRequestFilter([condition(.repository, .is, "acme/api")])).count
        let web = kept(PullRequestFilter([condition(.repository, .is, "acme/web")])).count
        #expect(kept(PullRequestFilter([condition(.repository, .is, "acme/api", "acme/web")])).count == api + web)
    }

    @Test func isNotKeepsWhatHasNoneOfTheValues() {
        let notAPIOrWeb = kept(PullRequestFilter([condition(.repository, .isNot, "acme/api", "acme/web")]))
        #expect(!notAPIOrWeb.isEmpty)
        #expect(notAPIOrWeb.allSatisfy { $0.repository != MockCast.api && $0.repository != MockCast.web })
        let `is` = kept(PullRequestFilter([condition(.repository, .is, "acme/api", "acme/web")])).count
        #expect(notAPIOrWeb.count + `is` == open.count)
    }

    @Test func namesIgnoreCaseAndOrganizationIsTheOwner() {
        #expect(kept(PullRequestFilter([condition(.repository, .is, "ACME/Api")])).count
                == open.count { $0.repository == MockCast.api })
        #expect(kept(PullRequestFilter([condition(.organization, .is, "acme")])).count == open.count)
        #expect(kept(PullRequestFilter([condition(.organization, .isNot, "Acme")])).isEmpty)
        #expect(kept(PullRequestFilter([condition(.author, .is, "ADA-PARK")])).allSatisfy { $0.author.login == "ada-park" })
    }

    @Test func meAndWaitingOnMeFollowTheViewer() {
        let mine = kept(PullRequestFilter([condition(.author, .is, FilterValues.me)]))
        #expect(mine.count == 12)
        #expect(mine.allSatisfy { world.viewer.isViewer($0.author) })
        let byLogin = kept(PullRequestFilter([condition(.author, .is, world.viewer.person.login)]))
        #expect(byLogin.map(\.id) == mine.map(\.id))
        let waiting = kept(PullRequestFilter([condition(.reviewState, .is, FilterValues.waitingOnMe)]))
        #expect(waiting.allSatisfy { $0.isReviewRequested(from: world.viewer) })
        // Waiting on me sits beside the review decision: a pull request has both.
        let waitingAndRequired = kept(PullRequestFilter([condition(.reviewState, .is, FilterValues.waitingOnMe),
                                                         condition(.reviewState, .is, "reviewRequired")]))
        #expect(!waitingAndRequired.isEmpty)
    }

    @Test func noSetsOrAnEmptySetMatchEverything() {
        #expect(kept(.everything).count == open.count)
        #expect(kept(PullRequestFilter(sets: [FilterConditionSet()])).count == open.count)
        #expect(PullRequestFilter.everything.matchesEverything)
    }

    // MARK: Evaluation

    @Test func evaluationCountsByStatus() {
        let filter = PullRequestFilter([condition(.repository, .is, "acme/api")])
        let evaluation = filter.evaluate(open, context: context)
        #expect(evaluation.total == 218)
        #expect(evaluation.count == open.count { $0.repository == MockCast.api })
        #expect(evaluation.byStatus.map(\.count).reduce(0, +) == evaluation.count)
        #expect(evaluation.byStatus.map(\.status) == StatusSentence.Badge.allCases.filter { badge in evaluation.byStatus.contains { $0.status == badge } })
        #expect(evaluation.byStatus.allSatisfy { $0.count > 0 })
        #expect(evaluation.countText == "\(evaluation.count) of 218 match")
        #expect(evaluation.text.hasPrefix("\(evaluation.count) of 218 match, "))
        #expect(evaluation.breakdownText.contains(" · "))
    }

    @Test func countWords() {
        let evaluation = FilterEvaluation(matches: [], total: 218, byStatus: [
            .init(status: .blocked, count: 3), .init(status: .changesRequested, count: 1), .init(status: .waiting, count: 2), .init(status: .ready, count: 2),
        ])
        #expect(evaluation.breakdownText == "3 blocked · 1 changes requested · 2 waiting · 2 ready")
        #expect(FilterEvaluation(matches: [], total: 5, byStatus: []).text == "0 of 5 match")
    }

    // MARK: Summary

    @Test func summaryInPlainWords() {
        let filter = PullRequestFilter(sets: [
            FilterConditionSet([condition(.status, .is, "blocked", "changesRequested"),
                                condition(.repository, .is, "acme/api", "acme/web"),
                                condition(.author, .isNot, "dependabot")]),
            FilterConditionSet([condition(.reviewState, .is, FilterValues.waitingOnMe), condition(.draft, .is, "false")]),
        ])
        #expect(filter.summary == "Blocked or changes requested, in acme/api or acme/web, not by dependabot. Or waiting on me and not a draft.")
        #expect(PullRequestFilter.everything.summary == "Every open pull request.")
        #expect(SavedFilter.mine.summary == "By me.")
        #expect(SavedFilter.needsMyReview.summary == "Waiting on me.")
        #expect(PullRequestFilter([condition(.draft, .isNot, "false")]).summary == "A draft.")
        #expect(PullRequestFilter([condition(.organization, .is, "acme"), condition(.reviewState, .isNot, "approved", "noDecision")]).summary
                == "In acme and not approved or no review decision.")
        #expect(PullRequestFilter([condition(.status, .is, "ready", "behind", "running")]).summary
                == "Ready to merge, behind the base branch or CI running or queued.")
    }

    // MARK: Reading

    @Test func decodesWithOperatorDefaultingToIs() throws {
        let text = #"{"sets": [{"conditions": [{"field": "status", "values": ["blocked"]}, {"field": "author", "operator": "isNot", "values": ["ci-bot"]}]}]}"#
        let filter = try PullRequestFilter.decode(Data(text.utf8))
        #expect(filter == PullRequestFilter([condition(.status, .is, "blocked"), condition(.author, .isNot, "ci-bot")]))
        let again = try PullRequestFilter.decode(try filter.encoded())
        #expect(again == filter)
    }

    @Test(arguments: [
        (#"{"sets": [{"conditions": [{"field": "label", "values": ["x"]}]}]}"#, "sets[0].conditions[0].field"),
        (#"{"sets": [{"conditions": [{"field": "status", "values": ["purple"]}]}]}"#, "sets[0].conditions[0].values[0]"),
        (#"{"sets": [{"conditions": [{"field": "status", "values": []}]}]}"#, "sets[0].conditions[0].values"),
        (#"{"sets": [{"conditions": [{"field": "status", "operator": "isn't", "values": ["blocked"]}]}]}"#, "sets[0].conditions[0].operator"),
        (#"{"sets": [{"conditions": [{"field": "status", "value": ["blocked"]}]}]}"#, "sets[0].conditions[0].value"),
        (#"{"sets": [], "colour": "red"}"#, "colour"),
        (#"{"sets": [{"conditions": [{"field": "repository", "values": ["acme"]}]}]}"#, "sets[0].conditions[0].values[0]"),
        (#"{"sets": [{"conditions": [{"field": "draft", "values": ["no"]}]}]}"#, "sets[0].conditions[0].values[0]"),
        (#"{"sets": [{"conditions": [{"field": "author", "values": ["two words"]}]}]}"#, "sets[0].conditions[0].values[0]"),
    ])
    func badFiltersNameWhere(text: String, path: String) {
        #expect {
            try PullRequestFilter.decode(Data(text.utf8))
        } throws: { error in
            (error as? LayoutFileError)?.path == path
        }
    }
}
