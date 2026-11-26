import Foundation

/// Who a review was asked of: one person, or a team.
public enum RequestedReviewer: Sendable, Hashable, Codable {
    case person(Person)
    case team(Team)

    /// `@login` or `@org/team`.
    public var handle: String {
        switch self {
        case .person(let person): person.handle
        case .team(let team): team.handle
        }
    }

    /// The name to show a reader: a person's display name, or a team's handle.
    public var displayName: String {
        switch self {
        case .person(let person): person.displayName
        case .team(let team): team.handle
        }
    }

    private enum CodingKeys: String, CodingKey { case kind, person, team }
    private enum Kind: String, Codable { case person, team }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .person: self = .person(try container.decode(Person.self, forKey: .person))
        case .team: self = .team(try container.decode(Team.self, forKey: .team))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .person(let person):
            try container.encode(Kind.person, forKey: .kind)
            try container.encode(person, forKey: .person)
        case .team(let team):
            try container.encode(Kind.team, forKey: .kind)
            try container.encode(team, forKey: .team)
        }
    }
}

/// A review that was asked for and has not been given yet.
public struct ReviewRequest: Codable, Sendable, Hashable {
    public var reviewer: RequestedReviewer
    public var requestedAt: Date
    /// GitHub asked because CODEOWNERS names this reviewer for a changed path.
    public var isCodeOwnerRequest: Bool

    public init(reviewer: RequestedReviewer, requestedAt: Date, isCodeOwnerRequest: Bool = false) {
        self.reviewer = reviewer
        self.requestedAt = requestedAt
        self.isCodeOwnerRequest = isCodeOwnerRequest
    }

    /// True when the request names the viewer, or a team the viewer is on.
    public func isRequested(from viewer: Viewer) -> Bool {
        switch reviewer {
        case .person(let person): viewer.isViewer(person)
        case .team(let team): viewer.isMember(of: team)
        }
    }
}

public enum ReviewState: String, Codable, Sendable, Hashable, CaseIterable {
    case approved
    case changesRequested
    case commented
}

/// A submitted review.
public struct Review: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var reviewer: Person
    public var state: ReviewState
    public var submittedAt: Date
    /// Markdown. Often empty for an approval.
    public var body: String

    public init(id: String, reviewer: Person, state: ReviewState, submittedAt: Date, body: String = "") {
        self.id = id
        self.reviewer = reviewer
        self.state = state
        self.submittedAt = submittedAt
        self.body = body
    }
}

/// GitHub's overall review decision for a pull request.
public enum ReviewDecision: String, Codable, Sendable, Hashable, CaseIterable {
    case approved
    case changesRequested
    case reviewRequired
}
