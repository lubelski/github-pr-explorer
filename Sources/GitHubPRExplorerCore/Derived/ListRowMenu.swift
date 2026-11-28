import Foundation

/// Links to a thing's page on github.com, for Open on GitHub and Copy Link. Built from what the
/// index holds, never fetched.
public enum GitHubWebLinks {
    public static let base = URL(string: "https://github.com")!

    public static func organization(_ name: String) -> URL { base.appending(path: name) }

    public static func repository(_ repository: Repository) -> URL {
        base.appending(path: repository.owner).appending(path: repository.name)
    }

    public static func pullRequest(_ pr: PullRequest) -> URL {
        repository(pr.repository).appending(path: "pull").appending(path: String(pr.number))
    }

    /// A person's profile. An app's bot account, `name[bot]`, has its page under `apps/`.
    public static func person(_ person: Person) -> URL {
        if person.login.hasSuffix("[bot]") {
            return base.appending(path: "apps").appending(path: String(person.login.dropLast("[bot]".count)))
        }
        return base.appending(path: person.login)
    }
}

/// One thing a shorthand can be set for, as the list's right-click menu and the Set Shorthand
/// popover name it.
public struct ShorthandTarget: Sendable, Hashable, Identifiable {
    public var kind: ShorthandKind
    /// `owner/name`, a login, or an organization's name: what the file's `for` holds.
    public var identity: String
    /// How the popover's heading names it: "acme/api", "Ada Park (@ada-park)", "acme".
    public var title: String
    /// The shorthand offered when there is none yet, such as "API" for `acme/api`.
    public var suggestion: String

    public var id: String { Shorthand.key(kind, identity) }

    public init(kind: ShorthandKind, identity: String, title: String, suggestion: String) {
        self.kind = kind
        self.identity = identity
        self.title = title
        self.suggestion = suggestion
    }

    public static func repository(_ repository: Repository) -> ShorthandTarget {
        ShorthandTarget(kind: .repository, identity: repository.fullName, title: repository.fullName,
                        suggestion: suggestedShorthand(for: repository.name))
    }

    public static func organization(_ name: String) -> ShorthandTarget {
        ShorthandTarget(kind: .organization, identity: name, title: name, suggestion: suggestedShorthand(for: name))
    }

    public static func person(_ person: Person) -> ShorthandTarget {
        let title = person.displayName == person.login ? person.handle : "\(person.displayName) (\(person.handle))"
        let first = person.displayName == person.login
            ? suggestedShorthand(for: person.login.replacingOccurrences(of: "[bot]", with: ""))
            : String(person.displayName.split(separator: " ").first ?? Substring(person.displayName))
        return ShorthandTarget(kind: .person, identity: person.login, title: title, suggestion: first)
    }

    /// A first guess at a short name: a name of three letters or fewer in capitals ("API"),
    /// otherwise each hyphenated word capitalized ("Web Admin"). Only offered, never set.
    static func suggestedShorthand(for name: String) -> String {
        let words = name.split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == "." }).map(String.init)
        guard !words.isEmpty else { return name }
        if words.count == 1, name.count <= 3 { return name.uppercased() }
        return words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}

/// The Set Shorthand popover, without SwiftUI: what Save does with what was typed, and the
/// warning when another thing already has that shorthand.
public struct ShorthandEdit: Sendable, Hashable {
    public enum Outcome: Sendable, Hashable {
        /// Write this shorthand.
        case set(String)
        /// Take the shorthand away.
        case remove
        /// Nothing to write: unchanged, or empty with nothing to remove.
        case nothing
    }

    public var target: ShorthandTarget
    /// The shorthand it has now, if any.
    public var current: String?

    public init(target: ShorthandTarget, shorthands: Shorthands) {
        self.target = target
        self.current = shorthands.shorthand(target.kind, for: target.identity)
    }

    /// What the field starts with: the shorthand it has, or the suggestion.
    public var initialText: String { current ?? target.suggestion }

    /// Save with this text. An empty field removes the shorthand, as Remove does.
    public func outcome(of text: String) -> Outcome {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return current == nil ? .nothing : .remove }
        return trimmed == current ? .nothing : .set(trimmed)
    }

    /// "“Web” is also the shorthand for acme/docs, so the label does not tell them apart." when
    /// something else has the typed shorthand. Allowed, as in Settings, so only a warning.
    public func clashWarning(for text: String, in shorthands: Shorthands) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let others = shorthands.entries.filter {
            $0.id != target.id && $0.shorthand.trimmingCharacters(in: .whitespaces).lowercased() == trimmed.lowercased()
        }
        guard !others.isEmpty else { return nil }
        return "\u{201C}\(trimmed)\u{201D} is also the shorthand for \(ShorthandClash.list(others.map(\.target))), so the label does not tell them apart."
    }
}

/// What a row of the pull request list is about, for its right-click menu.
public enum ListRowSubject: Sendable, Hashable {
    case organization(String)
    case repository(Repository)
    case author(Person)
    /// A status or review state title row: nothing to name or open, only to open and close.
    case grouping(ListGrouping.Property)
    case pullRequest(PullRequest)
}

/// The right-click menu of one row of the pull request list: the operations on the thing the
/// row is about, in sections. It is plain data, so which items each kind of row offers is
/// tested without a window. The app draws it and carries out each action.
///
/// Only what the app can do from the index is offered. Nothing here reaches GitHub: Open on
/// GitHub hands a link to the browser.
public struct ListRowMenu: Sendable, Hashable {
    public enum Action: Sendable, Hashable {
        /// Opens the Set Shorthand popover on the row.
        case setShorthand(ShorthandTarget)
        case openInBrowser(URL)
        case copy(String)
        /// Opens or closes these title rows.
        case setOpen([String], open: Bool)
    }

    public struct Item: Sendable, Hashable, Identifiable {
        public var title: String
        public var action: Action
        public var isEnabled: Bool

        public init(_ title: String, _ action: Action, isEnabled: Bool = true) {
            self.title = title
            self.action = action
            self.isEnabled = isEnabled
        }

        public var id: String { title }
    }

    public var subject: ListRowSubject
    /// Sections, drawn with a divider between them. None is empty.
    public var sections: [[Item]]

    public var items: [Item] { sections.flatMap(\.self) }
    public var titles: [String] { items.map(\.title) }

    /// The menu for one row of `tree`, with the title rows in `closed` closed. Nil when the row
    /// is not in the tree.
    public init?(for row: ListSelection, in tree: ListTree, closed: Set<String>, shorthands: Shorthands) {
        switch row {
        case .pullRequest(let id):
            guard let pr = tree.ordered.first(where: { $0.id == id }) else { return nil }
            self.init(pullRequest: pr, shorthands: shorthands)
        case .group(let id):
            guard let group = tree.group(id: id) else { return nil }
            self.init(group: group, in: tree, closed: closed, shorthands: shorthands)
        }
    }

    init(pullRequest pr: PullRequest, shorthands: Shorthands) {
        subject = .pullRequest(pr)
        let link = GitHubWebLinks.pullRequest(pr)
        sections = [
            [Item("Open on GitHub", .openInBrowser(link)),
             Item("Copy Link", .copy(link.absoluteString)),
             Item("Copy Reference", .copy("\(pr.repository.fullName)#\(pr.number)"))],
            [Self.setShorthand(.repository(pr.repository), shorthands, naming: "Repository"),
             Self.setShorthand(.person(pr.author), shorthands, naming: "Author"),
             Self.setShorthand(.organization(pr.repository.owner), shorthands, naming: "Organization")],
        ]
    }

    init(group: ListGroup, in tree: ListTree, closed: Set<String>, shorthands: Shorthands) {
        var sections: [[Item]] = []
        let first = group.pullRequests.first
        switch group.property {
        case .organization:
            let name = first?.repository.owner ?? group.name.fullName
            subject = .organization(name)
            sections.append([Self.setShorthand(.organization(name), shorthands)])
            sections.append([Item("Open on GitHub", .openInBrowser(GitHubWebLinks.organization(name))),
                             Item("Copy Name", .copy(name))])
        case .repository:
            guard let repository = first?.repository else { subject = .grouping(.repository); break }
            subject = .repository(repository)
            sections.append([Self.setShorthand(.repository(repository), shorthands)])
            sections.append([Item("Open on GitHub", .openInBrowser(GitHubWebLinks.repository(repository))),
                             Item("Copy Name", .copy(repository.fullName))])
        case .author:
            guard let person = first?.author else { subject = .grouping(.author); break }
            subject = .author(person)
            sections.append([Self.setShorthand(.person(person), shorthands)])
            sections.append([Item("Open on GitHub", .openInBrowser(GitHubWebLinks.person(person))),
                             Item("Copy Username", .copy(person.login))])
        case .status, .reviewState:
            subject = .grouping(group.property)
        }
        sections.append(Self.openAndClose(group, in: tree, closed: closed))
        self.sections = sections
    }

    /// "Set Shorthand…", or "Change Shorthand…" when it has one. On a pull request the item
    /// names what the shorthand is for: "Set Shorthand for Repository…".
    static func setShorthand(_ target: ShorthandTarget, _ shorthands: Shorthands, naming: String? = nil) -> Item {
        let verb = shorthands.shorthand(target.kind, for: target.identity) == nil ? "Set" : "Change"
        let title = naming.map { "\(verb) Shorthand for \($0)\u{2026}" } ?? "\(verb) Shorthand\u{2026}"
        return Item(title, .setShorthand(target))
    }

    /// A title row with title rows inside offers to open or close it and everything inside, and
    /// each is offered only when it would change something. A title row of the last level
    /// offers Expand or Collapse, whichever applies.
    static func openAndClose(_ group: ListGroup, in tree: ListTree, closed: Set<String>) -> [Item] {
        guard !group.children.isEmpty else {
            let isOpen = !closed.contains(group.id)
            return [Item(isOpen ? "Collapse" : "Expand", .setOpen([group.id], open: !isOpen))]
        }
        let ids = tree.groupIDs(within: group.id)
        return [
            Item("Expand Everything Inside", .setOpen(ids, open: true), isEnabled: ids.contains(where: closed.contains)),
            Item("Collapse Everything Inside", .setOpen(ids, open: false), isEnabled: ids.contains { !closed.contains($0) }),
        ]
    }
}

extension ListTree {
    /// The title row and every title row inside it, at any depth, outermost first.
    public func groupIDs(within id: String) -> [String] {
        guard let group = group(id: id) else { return [] }
        func walk(_ group: ListGroup) -> [String] { [group.id] + group.children.flatMap(walk) }
        return walk(group)
    }
}
