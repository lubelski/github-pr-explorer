import Foundation

/// A GitHub repository, named by its owner and name, such as `acme/api`.
public struct Repository: Codable, Sendable, Hashable, Comparable, CustomStringConvertible {
    public var owner: String
    public var name: String

    public init(owner: String, name: String) {
        self.owner = owner
        self.name = name
    }

    /// Reads `owner/name`. Returns nil for anything else.
    public init?(fullName: String) {
        let parts = fullName.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        self.init(owner: String(parts[0]), name: String(parts[1]))
    }

    public var fullName: String { "\(owner)/\(name)" }

    /// True when `text` uses only the letters, digits, `-`, `_` and `.` GitHub allows in an
    /// owner and a repository name, with one `/` between them.
    public static func isPlainName(_ text: String) -> Bool {
        text.wholeMatch(of: /[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+/) != nil
    }
    public var description: String { fullName }

    public static func < (lhs: Repository, rhs: Repository) -> Bool {
        lhs.fullName < rhs.fullName
    }
}

/// A GitHub account: a person, a bot, or an agent that writes pull requests.
public struct Person: Codable, Sendable, Hashable {
    public var login: String
    public var displayName: String
    /// A bot account, such as one that posts deploy previews or coverage.
    public var isBot: Bool
    /// An agent that writes code and opens pull requests on its own.
    public var isAgent: Bool

    public init(login: String, displayName: String, isBot: Bool = false, isAgent: Bool = false) {
        self.login = login
        self.displayName = displayName
        self.isBot = isBot
        self.isAgent = isAgent
    }

    /// `@login`, the way GitHub mentions an account.
    public var handle: String { "@\(login)" }
}

/// A team in an organization, such as `@acme/security`.
public struct Team: Codable, Sendable, Hashable {
    public var organization: String
    public var slug: String
    public var members: [Person]

    public init(organization: String, slug: String, members: [Person]) {
        self.organization = organization
        self.slug = slug
        self.members = members
    }

    /// `@organization/slug`, the way GitHub and CODEOWNERS name a team.
    public var handle: String { "@\(organization)/\(slug)" }

    public func hasMember(login: String) -> Bool {
        members.contains { $0.login == login }
    }

    /// True when both name the same team, whatever members each copy lists.
    public func isSameTeam(as other: Team) -> Bool {
        organization == other.organization && slug == other.slug
    }
}

/// Who "you" are: the signed-in person and the teams they belong to.
public struct Viewer: Codable, Sendable, Hashable {
    public var person: Person
    public var teams: [Team]

    public init(person: Person, teams: [Team]) {
        self.person = person
        self.teams = teams
    }

    public func isMember(of team: Team) -> Bool {
        teams.contains { $0.isSameTeam(as: team) }
    }

    public func isViewer(_ other: Person) -> Bool {
        other.login == person.login
    }
}
