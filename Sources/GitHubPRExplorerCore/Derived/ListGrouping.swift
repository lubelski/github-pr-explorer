import Foundation

/// How the pull request list is drawn: as one run of rows, or in sections by repository,
/// author, status or review state.
///
/// Grouping only arranges the rows the list already holds. It keeps no pull request out and
/// adds none, so it is not a filter and has no syntax. Sections are ordered the way the filter
/// menu orders the same values (`ListFilterChoices`), and rows keep their order inside a
/// section.
public enum ListGrouping: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    /// One run of rows, with no sections.
    case none
    case repository
    case author
    case status
    case reviewState

    public var id: String { rawValue }

    /// The grouping the list starts with when nothing was chosen before.
    public static let standard: ListGrouping = .none

    public var name: String {
        switch self {
        case .none: "None"
        case .repository: "Repository"
        case .author: "Author"
        case .status: "Status"
        case .reviewState: "Review state"
        }
    }

    /// One section of the list: a group's name and its rows.
    public struct Section: Sendable, Hashable, Identifiable {
        /// Unique within one grouping, such as `repository:acme/api`.
        public var id: String
        public var title: String
        public var pullRequests: [PullRequest]

        public init(id: String, title: String, pullRequests: [PullRequest]) {
            self.id = id
            self.title = title
            self.pullRequests = pullRequests
        }

        public var count: Int { pullRequests.count }
    }

    /// The pull requests in sections, in the order given inside each. With `none` it is one
    /// section with an empty title holding every pull request, or nothing when there are none.
    /// A group with no pull requests is never a section. `status` is each pull request's
    /// status sentence, which the caller usually has already.
    public func sections(of pullRequests: [PullRequest], viewer: Viewer,
                         status: (PullRequest) -> StatusSentence) -> [Section] {
        guard !pullRequests.isEmpty else { return [] }
        switch self {
        case .none:
            return [Section(id: "all", title: "", pullRequests: pullRequests)]
        case .repository:
            return grouped(pullRequests, key: \.repository, order: { $0.sorted() }) {
                Section(id: "repository:\($0.fullName)", title: $0.fullName, pullRequests: $1)
            }
        case .author:
            var people: [String: Person] = [:]
            for pr in pullRequests where people[pr.author.login] == nil { people[pr.author.login] = pr.author }
            return grouped(pullRequests, key: \.author.login,
                           order: { logins in logins.compactMap { people[$0] }.sorted(by: viewer.listsBefore).map(\.login) }) { login, rows in
                let person = people[login] ?? Person(login: login, displayName: login)
                let title = viewer.isViewer(person) ? "\(person.displayName) (you)" : person.displayName
                return Section(id: "author:\(login)", title: title, pullRequests: rows)
            }
        case .status:
            return grouped(pullRequests, key: { status($0).badge },
                           order: { badges in StatusSentence.Badge.allCases.filter(badges.contains) }) {
                Section(id: "status:\($0.rawValue)", title: $0.name, pullRequests: $1)
            }
        case .reviewState:
            return grouped(pullRequests, key: { ListFilter.ReviewState($0.reviewDecision) },
                           order: { states in ListFilter.ReviewState.allCases.filter(states.contains) }) {
                Section(id: "review:\($0.rawValue)", title: $0.name, pullRequests: $1)
            }
        }
    }

    /// The pull requests in the order the list draws them, section after section.
    public func ordered(_ pullRequests: [PullRequest], viewer: Viewer,
                        status: (PullRequest) -> StatusSentence) -> [PullRequest] {
        guard self != .none else { return pullRequests }
        return sections(of: pullRequests, viewer: viewer, status: status).flatMap(\.pullRequests)
    }

    private func grouped<Key: Hashable>(_ pullRequests: [PullRequest], key: (PullRequest) -> Key,
                                        order: (Set<Key>) -> [Key],
                                        section: (Key, [PullRequest]) -> Section) -> [Section] {
        var rows: [Key: [PullRequest]] = [:]
        for pr in pullRequests { rows[key(pr), default: []].append(pr) }
        return order(Set(rows.keys)).compactMap { key in rows[key].map { section(key, $0) } }
    }
}
