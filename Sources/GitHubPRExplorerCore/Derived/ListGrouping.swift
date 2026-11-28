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
        /// The group's name as the header draws it, with a shorthand in place of a
        /// repository's or a person's full name when one is set.
        public var name: DisplayName
        public var pullRequests: [PullRequest]

        public init(id: String, name: DisplayName, pullRequests: [PullRequest]) {
            self.id = id
            self.name = name
            self.pullRequests = pullRequests
        }

        public init(id: String, title: String, pullRequests: [PullRequest]) {
            self.init(id: id, name: DisplayName(title), pullRequests: pullRequests)
        }

        /// What the header draws.
        public var title: String { name.text }

        public var count: Int { pullRequests.count }
    }

    /// The pull requests in sections, in the order given inside each. With `none` it is one
    /// section with an empty title holding every pull request, or nothing when there are none.
    /// A group with no pull requests is never a section. `status` is each pull request's
    /// status sentence, which the caller usually has already. A repository's or an author's
    /// section is named by its shorthand when `shorthands` sets one, and is still ordered by
    /// the full name.
    public func sections(of pullRequests: [PullRequest], viewer: Viewer,
                         status: (PullRequest) -> StatusSentence,
                         shorthands: Shorthands = .none) -> [Section] {
        guard !pullRequests.isEmpty else { return [] }
        switch self {
        case .none:
            return [Section(id: "all", title: "", pullRequests: pullRequests)]
        case .repository:
            return grouped(pullRequests, key: \.repository, order: { $0.sorted() }) {
                Section(id: "repository:\($0.fullName)", name: shorthands.name(for: $0), pullRequests: $1)
            }
        case .author:
            var people: [String: Person] = [:]
            for pr in pullRequests where people[pr.author.login] == nil { people[pr.author.login] = pr.author }
            return grouped(pullRequests, key: \.author.login,
                           order: { logins in logins.compactMap { people[$0] }.sorted(by: viewer.listsBefore).map(\.login) }) { login, rows in
                let person = people[login] ?? Person(login: login, displayName: login)
                var name = shorthands.name(for: person)
                if viewer.isViewer(person) {
                    name.text += " (you)"
                    if !name.isShortened { name.fullName = name.text }
                }
                return Section(id: "author:\(login)", name: name, pullRequests: rows)
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

    // MARK: Collapsed sections

    /// The rows the list shows when the sections whose ids are in `collapsed` are folded
    /// away, in the order on screen. With `none` nothing folds: the flat list has no sections.
    public func visible(_ sections: [Section], collapsed: Set<String>) -> [PullRequest] {
        guard self != .none else { return sections.flatMap(\.pullRequests) }
        return sections.filter { !collapsed.contains($0.id) }.flatMap(\.pullRequests)
    }

    /// Collapses the section when it is expanded and expands it when it is collapsed.
    public static func toggle(_ id: String, in collapsed: inout Set<String>) {
        if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
    }

    /// Option-click on a header, as in Finder: when the clicked section was expanded every
    /// section collapses, otherwise every section expands. Ids of sections not shown now are
    /// left as they are.
    public static func toggleAll(from id: String, sections: [Section], in collapsed: inout Set<String>) {
        setAll(collapsed: !collapsed.contains(id), sections: sections, in: &collapsed)
    }

    /// Collapses or expands every section shown.
    public static func setAll(collapsed collapse: Bool, sections: [Section], in collapsed: inout Set<String>) {
        let ids = Set(sections.map(\.id))
        if collapse { collapsed.formUnion(ids) } else { collapsed.subtract(ids) }
    }

    /// Whether Collapse All would change anything: some section shown is expanded.
    public func canCollapseAll(_ sections: [Section], collapsed: Set<String>) -> Bool {
        self != .none && sections.contains { !collapsed.contains($0.id) }
    }

    /// Whether Expand All would change anything: some section shown is collapsed.
    public func canExpandAll(_ sections: [Section], collapsed: Set<String>) -> Bool {
        self != .none && sections.contains { collapsed.contains($0.id) }
    }

    /// The id of the section that holds the pull request, or nil when no section does.
    public static func sectionID(containing id: PullRequest.ID, in sections: [Section]) -> String? {
        sections.first { section in section.pullRequests.contains { $0.id == id } }?.id
    }

    private func grouped<Key: Hashable>(_ pullRequests: [PullRequest], key: (PullRequest) -> Key,
                                        order: (Set<Key>) -> [Key],
                                        section: (Key, [PullRequest]) -> Section) -> [Section] {
        var rows: [Key: [PullRequest]] = [:]
        for pr in pullRequests { rows[key(pr), default: []].append(pr) }
        return order(Set(rows.keys)).compactMap { key in rows[key].map { section(key, $0) } }
    }
}
