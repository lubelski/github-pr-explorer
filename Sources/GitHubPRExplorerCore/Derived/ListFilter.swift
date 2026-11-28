import Foundation

/// The list's advanced filters: which repositories, authors, statuses, drafts and review
/// states to keep. They narrow the chosen view, together with the search.
///
/// Each facet is "the field is one of these values", and a pull request must pass every facet
/// that is on. An empty facet is off. `clauses` gives the filter in exactly that shape, field
/// by field, so the filter language can take its place: each clause is one condition of the
/// form "field is one of values", and the filter is all of them together.
///
/// These are plain predicates, not the filter language and not saved views. There is one
/// filter language, and this type has no syntax of its own. When the language arrives, the
/// menu writes conditions in it and this type goes away, as `FixedListView` will.
public struct ListFilter: Codable, Sendable, Hashable {
    /// What to do with drafts.
    public enum Drafts: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
        /// Drafts are listed like any other pull request.
        case shown
        /// Drafts are left out.
        case hidden
        /// Only drafts are listed.
        case only

        public var id: String { rawValue }

        public var name: String {
            switch self {
            case .shown: "Show drafts"
            case .hidden: "Hide drafts"
            case .only: "Only drafts"
            }
        }
    }

    /// GitHub's review decision for a pull request, with a case for none.
    public enum ReviewState: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
        case approved
        case changesRequested
        case reviewRequired
        /// GitHub gives no decision, as when the repository requires no review.
        case noDecision

        public init(_ decision: ReviewDecision?) {
            self = switch decision {
            case .approved: .approved
            case .changesRequested: .changesRequested
            case .reviewRequired: .reviewRequired
            case nil: .noDecision
            }
        }

        public var id: String { rawValue }

        public var name: String {
            switch self {
            case .approved: "Approved"
            case .changesRequested: "Changes requested"
            case .reviewRequired: "Review required"
            case .noDecision: "No review decision"
            }
        }
    }

    /// The fields a filter can test. A clause names one.
    public enum Field: String, Codable, Sendable, Hashable, CaseIterable {
        case repository
        case author
        case status
        case draft
        case reviewState
    }

    /// One condition: the field is one of the values. The values are the plain forms the
    /// index holds: `owner/name`, a login, a badge's or review state's raw value, and for
    /// drafts `true` or `false`.
    public struct Clause: Sendable, Hashable {
        public var field: Field
        public var values: [String]

        public init(field: Field, values: [String]) {
            self.field = field
            self.values = values
        }
    }

    public var repositories: Set<Repository>
    /// Authors by login.
    public var authors: Set<String>
    public var statuses: Set<StatusSentence.Badge>
    public var drafts: Drafts
    public var reviewStates: Set<ReviewState>

    public init(repositories: Set<Repository> = [], authors: Set<String> = [], statuses: Set<StatusSentence.Badge> = [],
                drafts: Drafts = .shown, reviewStates: Set<ReviewState> = []) {
        self.repositories = repositories
        self.authors = authors
        self.statuses = statuses
        self.drafts = drafts
        self.reviewStates = reviewStates
    }

    /// No filter: every pull request passes.
    public static let none = ListFilter()

    public var isEmpty: Bool { clauses.isEmpty }

    /// How many facets are on.
    public var activeCount: Int { clauses.count }

    /// The filter as conditions that must all hold, in a fixed order. Empty when it is off.
    public var clauses: [Clause] {
        var clauses: [Clause] = []
        if !repositories.isEmpty { clauses.append(Clause(field: .repository, values: repositories.map(\.fullName).sorted())) }
        if !authors.isEmpty { clauses.append(Clause(field: .author, values: authors.sorted())) }
        if !statuses.isEmpty {
            clauses.append(Clause(field: .status, values: StatusSentence.Badge.allCases.filter(statuses.contains).map(\.rawValue)))
        }
        switch drafts {
        case .shown: break
        case .hidden: clauses.append(Clause(field: .draft, values: ["false"]))
        case .only: clauses.append(Clause(field: .draft, values: ["true"]))
        }
        if !reviewStates.isEmpty {
            clauses.append(Clause(field: .reviewState, values: ReviewState.allCases.filter(reviewStates.contains).map(\.rawValue)))
        }
        return clauses
    }

    /// Whether the pull request passes. `status` is its status sentence, which the caller
    /// usually has already, so it is not worked out twice.
    public func includes(_ pr: PullRequest, status: StatusSentence) -> Bool {
        if !repositories.isEmpty && !repositories.contains(pr.repository) { return false }
        if !authors.isEmpty && !authors.contains(pr.author.login) { return false }
        if !statuses.isEmpty && !statuses.contains(status.badge) { return false }
        switch drafts {
        case .shown: break
        case .hidden: if pr.isDraft { return false }
        case .only: if !pr.isDraft { return false }
        }
        if !reviewStates.isEmpty && !reviewStates.contains(ReviewState(pr.reviewDecision)) { return false }
        return true
    }

    /// The pull requests that pass, in the order given.
    public func pullRequests(in pullRequests: [PullRequest], status: (PullRequest) -> StatusSentence) -> [PullRequest] {
        guard !isEmpty else { return pullRequests }
        return pullRequests.filter { includes($0, status: status($0)) }
    }

    /// Adds the value to the set when it is missing and takes it out when it is there, as a
    /// checked menu item does.
    public static func toggle<Value: Hashable>(_ value: Value, in set: inout Set<Value>) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }
}

/// What the filter menu offers, built from the pull requests in the index. Values the filter
/// has chosen are always offered, even when nothing in the index has them any more, so they
/// can be turned off.
public struct ListFilterChoices: Sendable, Hashable {
    /// Sorted by full name.
    public var repositories: [Repository]
    /// The viewer first, then by display name.
    public var authors: [Person]
    /// In the status sentence's precedence order.
    public var statuses: [StatusSentence.Badge]
    public var reviewStates: [ListFilter.ReviewState]
    public var hasDrafts: Bool

    public init(pullRequests: [PullRequest], viewer: Viewer, status: (PullRequest) -> StatusSentence,
                keeping filter: ListFilter = .none) {
        let repositories = Set(pullRequests.map(\.repository)).union(filter.repositories)
        self.repositories = repositories.sorted()

        var authorsByLogin: [String: Person] = [:]
        for pr in pullRequests where authorsByLogin[pr.author.login] == nil {
            authorsByLogin[pr.author.login] = pr.author
        }
        for login in filter.authors where authorsByLogin[login] == nil {
            authorsByLogin[login] = Person(login: login, displayName: login)
        }
        authors = authorsByLogin.values.sorted(by: viewer.listsBefore)

        let badges = Set(pullRequests.map { status($0).badge }).union(filter.statuses)
        statuses = StatusSentence.Badge.allCases.filter(badges.contains)
        let reviews = Set(pullRequests.map { ListFilter.ReviewState($0.reviewDecision) }).union(filter.reviewStates)
        reviewStates = ListFilter.ReviewState.allCases.filter(reviews.contains)
        hasDrafts = pullRequests.contains(where: \.isDraft) || filter.drafts != .shown
    }
}

extension Viewer {
    /// The order the list puts people in, wherever it lists them: the viewer first, then by
    /// display name, then by login. The filter menu's authors and the list's author sections
    /// both use it.
    public func listsBefore(_ lhs: Person, _ rhs: Person) -> Bool {
        let lhsViewer = isViewer(lhs), rhsViewer = isViewer(rhs)
        if lhsViewer != rhsViewer { return lhsViewer }
        let order = lhs.displayName.localizedStandardCompare(rhs.displayName)
        if order != .orderedSame { return order == .orderedAscending }
        return lhs.login < rhs.login
    }
}
