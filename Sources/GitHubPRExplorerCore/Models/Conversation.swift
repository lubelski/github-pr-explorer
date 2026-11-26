import Foundation

/// Which side of a diff a review thread is on.
public enum DiffSide: String, Codable, Sendable, Hashable, CaseIterable {
    /// The old file. The thread's line is an old line number.
    case left
    /// The new file. The thread's line is a new line number.
    case right
}

public struct ReviewComment: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var author: Person
    /// Markdown.
    public var body: String
    public var createdAt: Date

    public init(id: String, author: Person, body: String, createdAt: Date) {
        self.id = id
        self.author = author
        self.body = body
        self.createdAt = createdAt
    }
}

/// A conversation on one line of the diff.
public struct ReviewThread: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var path: String
    public var line: Int
    public var side: DiffSide
    public var isResolved: Bool
    /// The line has changed since the thread started, so it no longer points at current code.
    public var isOutdated: Bool
    /// The code line the thread is on, without its diff marker.
    public var quotedLine: String
    /// Oldest first. The first comment started the thread.
    public var comments: [ReviewComment]

    public init(
        id: String,
        path: String,
        line: Int,
        side: DiffSide = .right,
        isResolved: Bool = false,
        isOutdated: Bool = false,
        quotedLine: String,
        comments: [ReviewComment]
    ) {
        self.id = id
        self.path = path
        self.line = line
        self.side = side
        self.isResolved = isResolved
        self.isOutdated = isOutdated
        self.quotedLine = quotedLine
        self.comments = comments
    }

    public var startedBy: Person? { comments.first?.author }
    public var lastComment: ReviewComment? { comments.last }
}

/// A comment on the pull request's conversation, outside any review thread.
public struct IssueComment: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var author: Person
    /// Markdown. A bot's comment can hold task-list checkboxes that start work when ticked.
    public var body: String
    public var createdAt: Date

    public init(id: String, author: Person, body: String, createdAt: Date) {
        self.id = id
        self.author = author
        self.body = body
        self.createdAt = createdAt
    }
}
