import Foundation

/// What a shorthand stands for. A shorthand matches its thing exactly, by the thing's identity:
/// a repository by `owner/name`, a person by login. There are no patterns.
///
/// Each shorthand in `shorthands.json` names its kind, so another kind, such as a proper noun,
/// is a new case here and a new value in the file, and the file keeps its shape.
public enum ShorthandKind: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    /// A repository, matched by `owner/name`, such as `acme/web`.
    case repository
    /// A person, bot or agent, matched by login, such as `ada-park`.
    case person

    public var id: String { rawValue }

    public init(from decoder: any Decoder) throws {
        self = try decodeNamedValue(decoder, as: ShorthandKind.self)
    }

    /// The heading for this kind's shorthands, as Settings shows them.
    public var pluralTitle: String {
        switch self {
        case .repository: "Repositories"
        case .person: "People"
        }
    }

    /// What `for` holds, in words, for problems and help.
    public var identityDescription: String {
        switch self {
        case .repository: "a repository written as owner/name, such as acme/api"
        case .person: "a GitHub login, such as ada-park"
        }
    }

    /// The placeholder for a new shorthand's identity in Settings.
    public var identityPlaceholder: String {
        switch self {
        case .repository: "owner/name"
        case .person: "login"
        }
    }

    /// True when `text` is written the way this kind's identity is.
    public func isValidIdentity(_ text: String) -> Bool {
        switch self {
        case .repository: Repository.isPlainName(text)
        case .person: text.wholeMatch(of: /[A-Za-z0-9][A-Za-z0-9-]*(\[bot\])?/) != nil
        }
    }

    /// An identity as typed, made plain: spaces trimmed, and a leading `@` taken off a login.
    public func normalizedIdentity(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if self == .person, trimmed.hasPrefix("@") { return String(trimmed.dropFirst()) }
        return trimmed
    }
}

/// One shorthand: a short text the app draws in place of a thing's full name.
///
/// It is display only. It changes the labels the app draws, never text people wrote, links,
/// copied values, or anything sent to GitHub.
public struct Shorthand: Codable, Sendable, Hashable, Identifiable {
    public var kind: ShorthandKind
    /// The thing's identity: `owner/name` for a repository, the login for a person. Written
    /// `for` in the file.
    public var target: String
    /// What the app draws instead of the full name.
    public var shorthand: String

    public init(kind: ShorthandKind, target: String, shorthand: String) {
        self.kind = kind
        self.target = target
        self.shorthand = shorthand
    }

    /// The kind and the identity. GitHub treats repository names and logins without regard to
    /// case, so this does too.
    public var id: String { Self.key(kind, target) }

    /// The id a shorthand for this kind and identity has.
    public static func key(_ kind: ShorthandKind, _ target: String) -> String { "\(kind.rawValue):\(target.lowercased())" }

    enum CodingKeys: String, CodingKey {
        case kind
        case target = "for"
        case shorthand
    }
}

/// Two or more things that share one shorthand. It is allowed, and Settings shows a warning
/// beside each of them, so the person knows the label no longer tells them apart.
public struct ShorthandClash: Sendable, Hashable {
    /// The shared text, as the first of them writes it.
    public var shorthand: String
    /// Every shorthand with that text, in the file's order.
    public var entries: [Shorthand]

    /// "Also used for acme/docs." for one entry, naming the others.
    public func warning(for entry: Shorthand) -> String {
        let others = entries.filter { $0.id != entry.id }.map(\.target)
        return "\u{201C}\(shorthand)\u{201D} is also the shorthand for \(Self.list(others)), so the label does not tell them apart."
    }

    /// "“Web” is the shorthand for acme/web and acme/docs, so the label does not tell them apart."
    public var summary: String {
        "\u{201C}\(shorthand)\u{201D} is the shorthand for \(Self.list(entries.map(\.target))), so the label does not tell them apart."
    }

    static func list(_ names: [String]) -> String {
        switch names.count {
        case 0: ""
        case 1: names[0]
        case 2: "\(names[0]) and \(names[1])"
        default: names.dropLast().joined(separator: ", ") + ", and " + names.last!
        }
    }
}

/// A name as a label draws it: the text, and the full name it stands for.
public struct DisplayName: Sendable, Hashable {
    /// What the label draws.
    public var text: String
    /// The full name. The same as `text` when nothing was shortened.
    public var fullName: String
    /// True when a shorthand took the full name's place.
    public var isShortened: Bool

    public init(text: String, fullName: String, isShortened: Bool) {
        self.text = text
        self.fullName = fullName
        self.isShortened = isShortened
    }

    /// A name with no shorthand.
    public init(_ text: String) {
        self.init(text: text, fullName: text, isShortened: false)
    }

    /// What hovering over the label shows: the full name when shortened, otherwise nothing.
    public var help: String? { isShortened ? fullName : nil }

    /// What VoiceOver reads: the shorthand and the full name when shortened.
    public var accessibilityLabel: String { isShortened ? "\(text), short for \(fullName)" : text }
}

/// The shorthands the configuration folder sets, ready to look up. Every label the app draws
/// for a repository or a person comes through here, so no view formats a name on its own.
///
/// With no shorthands every label is exactly what it was before shorthands existed.
public struct Shorthands: Sendable, Hashable {
    /// In the file's order.
    public private(set) var entries: [Shorthand]
    private var byKey: [String: String]

    public init(_ entries: [Shorthand] = []) {
        self.entries = entries
        var byKey: [String: String] = [:]
        for entry in entries where byKey[entry.id] == nil { byKey[entry.id] = entry.shorthand }
        self.byKey = byKey
    }

    public static let none = Shorthands()

    public var isEmpty: Bool { entries.isEmpty }

    /// The shorthand for one thing, if it has one.
    public func shorthand(_ kind: ShorthandKind, for target: String) -> String? {
        byKey[Shorthand.key(kind, target)]
    }

    public func entries(of kind: ShorthandKind) -> [Shorthand] { entries.filter { $0.kind == kind } }

    // MARK: Labels

    /// `Web` for a repository with a shorthand, `acme/web` otherwise.
    public func name(for repository: Repository) -> DisplayName {
        guard let short = shorthand(.repository, for: repository.fullName) else { return DisplayName(repository.fullName) }
        return DisplayName(text: short, fullName: repository.fullName, isShortened: true)
    }

    /// `Web #95` for a repository with a shorthand, `acme/web #95` otherwise. The shorthand
    /// stands alone, without the owner.
    public func reference(_ repository: Repository, number: Int) -> DisplayName {
        let repositoryName = name(for: repository)
        let full = "\(repository.fullName) #\(number)"
        return DisplayName(text: "\(repositoryName.text) #\(number)", fullName: full, isShortened: repositoryName.isShortened)
    }

    /// The pull request's own reference, as the list and the page header draw it.
    public func reference(of pr: PullRequest) -> DisplayName { reference(pr.repository, number: pr.number) }

    /// A person's shorthand, or their display name as before. Shortened, the full name is the
    /// display name and the login.
    public func name(for person: Person) -> DisplayName {
        guard let short = shorthand(.person, for: person.login) else { return DisplayName(person.displayName) }
        return DisplayName(text: short, fullName: Self.fullName(of: person), isShortened: true)
    }

    /// A login as it is, or its shorthand, for places that show a login rather than a name.
    public func name(forLogin login: String) -> DisplayName {
        guard let short = shorthand(.person, for: login) else { return DisplayName(login) }
        return DisplayName(text: short, fullName: login, isShortened: true)
    }

    /// A requested reviewer: a person as `name(for:)` draws them, a team by its handle.
    public func name(for reviewer: RequestedReviewer) -> DisplayName {
        switch reviewer {
        case .person(let person): name(for: person)
        case .team(let team): DisplayName(team.handle)
        }
    }

    /// An owner as CODEOWNERS writes it: `@login` takes the person's shorthand, and a team,
    /// written `@org/team`, stays as it is.
    public func name(forHandle handle: String) -> DisplayName {
        guard handle.hasPrefix("@"), !handle.contains("/"),
              let short = shorthand(.person, for: String(handle.dropFirst())) else { return DisplayName(handle) }
        return DisplayName(text: short, fullName: handle, isShortened: true)
    }

    /// An Activity line split into the actor's name, drawn bold, and the rest. A summary that
    /// starts with the actor's display name or login takes the actor's shorthand there. The
    /// rest of the summary is left as it is.
    public func activityLine(_ event: TimelineEvent) -> (actor: DisplayName?, rest: String) {
        let names = [event.actor.displayName, event.actor.login]
        guard let written = names.first(where: { event.summary.hasPrefix($0 + " ") }) else { return (nil, event.summary) }
        let rest = String(event.summary.dropFirst(written.count))
        guard let short = shorthand(.person, for: event.actor.login) else { return (DisplayName(written), rest) }
        return (DisplayName(text: short, fullName: Self.fullName(of: event.actor), isShortened: true), rest)
    }

    /// "Ada Park, @ada-park", or "@ci-bot" when the display name is the login.
    static func fullName(of person: Person) -> String {
        person.displayName == person.login ? person.handle : "\(person.displayName), \(person.handle)"
    }

    // MARK: Search

    /// The shorthands of a pull request's repository and author, so the word search finds a
    /// pull request by either. It searches the same fields it did before, by their full names.
    public func searchTerms(for pr: PullRequest) -> [String] {
        [shorthand(.repository, for: pr.repository.fullName), shorthand(.person, for: pr.author.login)].compactMap(\.self)
    }

    // MARK: Clashes

    /// Groups of things that share a shorthand, ignoring case and spaces at either end.
    public var clashes: [ShorthandClash] {
        var groups: [String: [Shorthand]] = [:]
        var order: [String] = []
        for entry in entries {
            let key = entry.shorthand.trimmingCharacters(in: .whitespaces).lowercased()
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(entry)
        }
        return order.compactMap { key in
            guard let group = groups[key], group.count > 1 else { return nil }
            return ShorthandClash(shorthand: group[0].shorthand, entries: group)
        }
    }

    /// The clash an entry is part of, if any.
    public func clash(for entry: Shorthand) -> ShorthandClash? {
        clashes.first { $0.entries.contains { $0.id == entry.id } }
    }
}

/// `shorthands.json` in the configuration folder.
///
/// It holds `formatVersion` and a list of shorthands, each with its `kind`, the identity it is
/// `for`, and the `shorthand` drawn in its place. A missing file means no shorthands. The
/// schema is `schemas/shorthands.schema.json` in the repository, and a test keeps the two in
/// step.
public struct ShorthandsFile: Codable, Sendable, Hashable {
    public static let currentFormatVersion = 1
    public static let fileName = "shorthands.json"
    /// The keys the file and each shorthand may hold, for the unknown-key check.
    public static let keys = ["formatVersion", "shorthands"]
    public static let entryKeys = ["kind", "for", "shorthand"]

    public var formatVersion: Int
    public var shorthands: [Shorthand]

    public init(formatVersion: Int = currentFormatVersion, shorthands: [Shorthand] = []) {
        self.formatVersion = formatVersion
        self.shorthands = shorthands
    }

    public var lookup: Shorthands { Shorthands(shorthands) }

    /// Sorted keys and pretty printed, the same bytes on every run.
    public func encoded() throws -> Data {
        var data = try GitHubPRExplorerJSON.encoder().encode(self)
        data.append(0x0A)
        return data
    }

    /// Reads a shorthands file. Problems name where in the file and what is wrong.
    public static func decode(_ data: Data, fileName: String = fileName) throws(LayoutFileError) -> ShorthandsFile {
        try JSONKeyCheck.check(data, fileName: fileName, allowed: JSONKeyCheck.shorthandsShape)
        let file: ShorthandsFile
        do {
            file = try GitHubPRExplorerJSON.decoder().decode(ShorthandsFile.self, from: data)
        } catch let error as DecodingError {
            throw LayoutFileError.describe(error, fileName: fileName)
        } catch {
            throw LayoutFileError(fileName: fileName, problem: error.localizedDescription)
        }
        guard file.formatVersion == currentFormatVersion else {
            throw LayoutFileError(fileName: fileName, path: "formatVersion",
                                  problem: "format version \(file.formatVersion) is not one this app reads. It reads version \(currentFormatVersion).")
        }
        var seen: [String: Int] = [:]
        for (position, entry) in file.shorthands.enumerated() {
            if !entry.kind.isValidIdentity(entry.target) {
                throw LayoutFileError(fileName: fileName, path: "shorthands[\(position)].for",
                                      problem: "\"\(entry.target)\" is not \(entry.kind.identityDescription)")
            }
            if entry.shorthand.trimmingCharacters(in: .whitespaces).isEmpty {
                throw LayoutFileError(fileName: fileName, path: "shorthands[\(position)].shorthand",
                                      problem: "the shorthand for \(entry.target) is empty")
            }
            if let earlier = seen[entry.id] {
                throw LayoutFileError(fileName: fileName, path: "shorthands[\(position)].for",
                                      problem: "\(entry.target) already has a shorthand, at shorthands[\(earlier)]. Keep one of them")
            }
            seen[entry.id] = position
        }
        return file
    }
}

extension PullRequestIndex {
    /// The word search without shorthands, as it was before them.
    public func search(_ text: String) -> [PullRequest] { search(text, shorthands: .none) }
}

/// The repositories and people the index knows, offered when a shorthand is added. Read from
/// the index, never the network.
public struct ShorthandCandidates: Sendable, Hashable {
    /// `owner/name`, sorted.
    public var repositories: [String]
    /// Authors, reviewers, commenters and assignees, people before bots, by name.
    public var people: [Person]

    public init(repositories: [String] = [], people: [Person] = []) {
        self.repositories = repositories
        self.people = people
    }

    public init(index: any PullRequestIndex) {
        var repositories = Set<String>()
        var people: [String: Person] = [:]
        func add(_ person: Person) { if people[person.login.lowercased()] == nil { people[person.login.lowercased()] = person } }
        for pr in index.allPullRequests {
            repositories.insert(pr.repository.fullName)
            add(pr.author)
            pr.assignees.forEach(add)
            pr.reviews.forEach { add($0.reviewer) }
            for request in pr.reviewRequests { if case .person(let person) = request.reviewer { add(person) } }
            for thread in pr.reviewThreads { thread.comments.forEach { add($0.author) } }
        }
        self.repositories = repositories.sorted { $0.lowercased() < $1.lowercased() }
        self.people = people.values.sorted {
            ($0.isBot ? 1 : 0, $0.displayName.lowercased(), $0.login) < ($1.isBot ? 1 : 0, $1.displayName.lowercased(), $1.login)
        }
    }

    /// The identities of one kind that have no shorthand yet, with a name to show for each.
    public func unset(_ kind: ShorthandKind, in shorthands: Shorthands) -> [(identity: String, title: String)] {
        switch kind {
        case .repository:
            repositories.filter { shorthands.shorthand(.repository, for: $0) == nil }.map { ($0, $0) }
        case .person:
            people.filter { shorthands.shorthand(.person, for: $0.login) == nil }
                .map { ($0.login, $0.displayName == $0.login ? $0.login : "\($0.displayName) (\($0.login))") }
        }
    }
}
