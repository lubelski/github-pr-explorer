import Foundation

/// A row the list can select: a pull request, or a title row of the tree.
public enum ListSelection: Hashable, Sendable, Codable, CustomStringConvertible {
    case pullRequest(PullRequest.ID)
    /// A title row, by `ListGroup.id`.
    case group(String)

    public var pullRequestID: PullRequest.ID? {
        if case .pullRequest(let id) = self { id } else { nil }
    }

    public var groupID: String? {
        if case .group(let id) = self { id } else { nil }
    }

    /// How the selection is remembered: `pull-request:<id>` or `group:<id>`.
    public var storedValue: String {
        switch self {
        case .pullRequest(let id): "pull-request:\(id)"
        case .group(let id): "group:\(id)"
        }
    }

    public init?(storedValue: String) {
        if storedValue.hasPrefix("pull-request:") {
            self = .pullRequest(String(storedValue.dropFirst("pull-request:".count)))
        } else if storedValue.hasPrefix("group:") {
            self = .group(String(storedValue.dropFirst("group:".count)))
        } else {
            return nil
        }
    }

    public var description: String { storedValue }
}

/// A title row of the tree: an organization, a repository, an author, a status or a review
/// state, with what it holds.
public struct ListGroup: Sendable, Identifiable {
    /// Unique in the tree, and the same from one grouping to the next for the same group at
    /// the same place, such as `repository:acme/api` at the top, or
    /// `organization:acme|repository:acme/api` under its organization. A one-level grouping
    /// gives the ids the sectioned list gave, so rows remembered as closed stay closed.
    public var id: String
    public var property: ListGrouping.Property
    /// The name on the row. Under its organization a repository is named without it: "api".
    public var title: String
    /// 0 for the outermost level.
    public var depth: Int
    public var parentID: String?
    /// The title rows inside, at the next level. Empty at the last level.
    public var children: [ListGroup]
    /// Every pull request inside, at any depth, in the order the list draws them.
    public var pullRequests: [PullRequest]

    /// How many pull requests are inside, at any depth.
    public var count: Int { pullRequests.count }
}

/// One row as the list draws it: a title row or a pull request, with how deep it sits.
public struct ListRow: Sendable, Identifiable {
    public enum Content: Sendable {
        case group(ListGroup, isOpen: Bool)
        case pullRequest(PullRequest)
    }

    public var content: Content
    /// How many title rows hold this row. The guide lines of each of them run past it.
    public var depth: Int
    /// What the title rows above it already say, so a pull request row need not repeat it:
    /// inside a repository a row reads "#4715 · you".
    public var namedByAncestors: Set<ListGrouping.Property>

    public var id: ListSelection {
        switch content {
        case .group(let group, _): .group(group.id)
        case .pullRequest(let pr): .pullRequest(pr.id)
        }
    }
}

/// The pull request list as a tree of title rows, built from a grouping. With no grouping it
/// has no title rows and the list is flat.
///
/// Which title rows are closed is a set of group ids kept by the caller. An id with no title
/// row in this tree does nothing, so one set serves every grouping.
public struct ListTree: Sendable {
    public let grouping: ListGrouping
    /// The outermost title rows. Empty with no grouping.
    public let groups: [ListGroup]
    /// Every pull request, in the order the list draws them with every row open.
    public let ordered: [PullRequest]

    private let groupsByID: [String: ListGroup]
    /// For each pull request, the ids of the title rows that hold it, outermost first.
    private let pathByPullRequest: [PullRequest.ID: [String]]

    /// `status` is each pull request's status sentence, which the caller usually has already.
    /// Groups follow the filter menu's order for the same values, and rows keep their order
    /// inside a group. A group with no pull requests is never made.
    public init(grouping: ListGrouping, pullRequests: [PullRequest], viewer: Viewer,
                status: (PullRequest) -> StatusSentence) {
        self.grouping = grouping
        let groups = Self.build(pullRequests, levels: grouping.levels[...], depth: 0, parent: nil,
                                named: [], viewer: viewer, status: status)
        self.groups = groups
        var byID: [String: ListGroup] = [:]
        var paths: [PullRequest.ID: [String]] = [:]
        var ordered: [PullRequest] = []
        func walk(_ group: ListGroup, path: [String]) {
            byID[group.id] = group
            let path = path + [group.id]
            if group.children.isEmpty {
                for pr in group.pullRequests { paths[pr.id] = path }
                ordered += group.pullRequests
            } else {
                for child in group.children { walk(child, path: path) }
            }
        }
        for group in groups { walk(group, path: []) }
        self.groupsByID = byID
        self.pathByPullRequest = paths
        self.ordered = grouping.isNone ? pullRequests : ordered
    }

    /// Every title row, outermost first and in screen order.
    public var allGroups: [ListGroup] {
        func flatten(_ groups: [ListGroup]) -> [ListGroup] { groups.flatMap { [$0] + flatten($0.children) } }
        return flatten(groups)
    }

    public func group(id: String) -> ListGroup? { groupsByID[id] }

    /// Whether the row is in this tree.
    public func contains(_ selection: ListSelection) -> Bool {
        switch selection {
        case .group(let id): groupsByID[id] != nil
        case .pullRequest(let id): grouping.isNone ? ordered.contains { $0.id == id } : pathByPullRequest[id] != nil
        }
    }

    /// The ids of the title rows that hold the row, outermost first.
    public func ancestorIDs(of selection: ListSelection) -> [String] {
        switch selection {
        case .pullRequest(let id):
            return pathByPullRequest[id] ?? []
        case .group(let id):
            var ids: [String] = []
            var parent = groupsByID[id]?.parentID
            while let current = parent {
                ids.insert(current, at: 0)
                parent = groupsByID[current]?.parentID
            }
            return ids
        }
    }

    /// The title row that directly holds the row, if any.
    public func parent(of selection: ListSelection) -> ListSelection? {
        ancestorIDs(of: selection).last.map(ListSelection.group)
    }

    // MARK: Rows

    /// The rows on screen when the title rows in `closed` are closed, in order.
    public func rows(closed: Set<String>) -> [ListRow] {
        guard !grouping.isNone else {
            return ordered.map { ListRow(content: .pullRequest($0), depth: 0, namedByAncestors: []) }
        }
        var rows: [ListRow] = []
        func add(_ group: ListGroup, named: Set<ListGrouping.Property>) {
            let isOpen = !closed.contains(group.id)
            rows.append(ListRow(content: .group(group, isOpen: isOpen), depth: group.depth, namedByAncestors: named))
            guard isOpen else { return }
            let named = named.union([group.property])
            if group.children.isEmpty {
                for pr in group.pullRequests {
                    rows.append(ListRow(content: .pullRequest(pr), depth: group.depth + 1, namedByAncestors: named))
                }
            } else {
                for child in group.children { add(child, named: named) }
            }
        }
        for group in groups { add(group, named: []) }
        return rows
    }

    /// The pull requests on screen, in order, when the title rows in `closed` are closed.
    public func visiblePullRequests(closed: Set<String>) -> [PullRequest] {
        rows(closed: closed).compactMap { row in
            if case .pullRequest(let pr) = row.content { pr } else { nil }
        }
    }

    /// Whether the row shows, that is whether every title row holding it is open.
    public func isVisible(_ selection: ListSelection, closed: Set<String>) -> Bool {
        contains(selection) && ancestorIDs(of: selection).allSatisfy { !closed.contains($0) }
    }

    /// The row itself when it shows, otherwise the outermost closed title row holding it,
    /// which is the row on screen that hides it. Nil when the row is not in the tree.
    public func nearestVisible(_ selection: ListSelection, closed: Set<String>) -> ListSelection? {
        guard contains(selection) else { return nil }
        if let hiding = ancestorIDs(of: selection).first(where: closed.contains) { return .group(hiding) }
        return selection
    }

    // MARK: Opening and closing

    /// Closes the title row when it is open and opens it when it is closed.
    public static func toggle(_ id: String, in closed: inout Set<String>) {
        if closed.contains(id) { closed.remove(id) } else { closed.insert(id) }
    }

    /// Option-click on a triangle, as in Finder: every title row at the clicked one's level
    /// closes when the clicked one was open, otherwise they all open. Ids of rows not in this
    /// tree are left as they are.
    public func toggleLevel(from id: String, in closed: inout Set<String>) {
        guard let depth = groupsByID[id]?.depth else { return }
        let level = Set(allGroups.filter { $0.depth == depth }.map(\.id))
        if closed.contains(id) { closed.subtract(level) } else { closed.formUnion(level) }
    }

    /// Collapse All and Expand All: closes or opens every title row in the tree.
    public func setAll(closed close: Bool, in closed: inout Set<String>) {
        let ids = Set(groupsByID.keys)
        if close { closed.formUnion(ids) } else { closed.subtract(ids) }
    }

    /// Whether Collapse All would change anything: some title row is open.
    public func canCloseAll(closed: Set<String>) -> Bool {
        groupsByID.keys.contains { !closed.contains($0) }
    }

    /// Whether Expand All would change anything: some title row is closed.
    public func canOpenAll(closed: Set<String>) -> Bool {
        groupsByID.keys.contains { closed.contains($0) }
    }

    // MARK: Building

    private static func build(_ pullRequests: [PullRequest], levels: ArraySlice<ListGrouping.Property>, depth: Int,
                              parent: String?, named: Set<ListGrouping.Property>, viewer: Viewer,
                              status: (PullRequest) -> StatusSentence) -> [ListGroup] {
        guard let property = levels.first, !pullRequests.isEmpty else { return [] }
        return buckets(pullRequests, by: property, named: named, viewer: viewer, status: status).map { bucket in
            let id = parent.map { "\($0)|\(bucket.key)" } ?? bucket.key
            let children = build(bucket.rows, levels: levels.dropFirst(), depth: depth + 1, parent: id,
                                 named: named.union([property]), viewer: viewer, status: status)
            return ListGroup(id: id, property: property, title: bucket.title, depth: depth, parentID: parent,
                             children: children,
                             pullRequests: children.isEmpty ? bucket.rows : children.flatMap(\.pullRequests))
        }
    }

    private struct Bucket {
        var key: String
        var title: String
        var rows: [PullRequest]
    }

    /// The pull requests split by one property, in the filter menu's order for its values.
    private static func buckets(_ pullRequests: [PullRequest], by property: ListGrouping.Property,
                                named: Set<ListGrouping.Property>, viewer: Viewer,
                                status: (PullRequest) -> StatusSentence) -> [Bucket] {
        switch property {
        case .organization:
            return grouped(pullRequests, key: \.repository.owner,
                           order: { $0.sorted { $0.localizedStandardCompare($1) == .orderedAscending } }) {
                Bucket(key: "organization:\($0)", title: $0, rows: $1)
            }
        case .repository:
            let short = named.contains(.organization)
            return grouped(pullRequests, key: \.repository, order: { $0.sorted() }) {
                Bucket(key: "repository:\($0.fullName)", title: short ? $0.name : $0.fullName, rows: $1)
            }
        case .author:
            var people: [String: Person] = [:]
            for pr in pullRequests where people[pr.author.login] == nil { people[pr.author.login] = pr.author }
            return grouped(pullRequests, key: \.author.login,
                           order: { logins in logins.compactMap { people[$0] }.sorted(by: viewer.listsBefore).map(\.login) }) { login, rows in
                let person = people[login] ?? Person(login: login, displayName: login)
                let title = viewer.isViewer(person) ? "\(person.displayName) (you)" : person.displayName
                return Bucket(key: "author:\(login)", title: title, rows: rows)
            }
        case .status:
            return grouped(pullRequests, key: { status($0).badge },
                           order: { badges in StatusSentence.Badge.allCases.filter(badges.contains) }) {
                Bucket(key: "status:\($0.rawValue)", title: $0.name, rows: $1)
            }
        case .reviewState:
            return grouped(pullRequests, key: { ListFilter.ReviewState($0.reviewDecision) },
                           order: { states in ListFilter.ReviewState.allCases.filter(states.contains) }) {
                Bucket(key: "review:\($0.rawValue)", title: $0.name, rows: $1)
            }
        }
    }

    private static func grouped<Key: Hashable>(_ pullRequests: [PullRequest], key: (PullRequest) -> Key,
                                               order: (Set<Key>) -> [Key],
                                               bucket: (Key, [PullRequest]) -> Bucket) -> [Bucket] {
        var rows: [Key: [PullRequest]] = [:]
        for pr in pullRequests { rows[key(pr), default: []].append(pr) }
        return order(Set(rows.keys)).compactMap { key in rows[key].map { bucket(key, $0) } }
    }
}
