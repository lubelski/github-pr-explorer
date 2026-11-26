import Foundation

public enum FileChangeKind: String, Codable, Sendable, Hashable, CaseIterable {
    case added
    case modified
    case removed
    case renamed
}

/// One file the pull request changes.
public struct ChangedFile: Codable, Sendable, Hashable {
    public var path: String
    /// The path before a rename. Nil unless `changeKind` is `.renamed`.
    public var previousPath: String?
    public var changeKind: FileChangeKind
    public var additions: Int
    public var deletions: Int
    public var isBinary: Bool
    /// The unified patch, hunks only, as GitHub's API returns it. Nil for a binary file
    /// or a rename with no content change.
    public var patch: String?

    public init(
        path: String,
        previousPath: String? = nil,
        changeKind: FileChangeKind,
        additions: Int,
        deletions: Int,
        isBinary: Bool = false,
        patch: String?
    ) {
        self.path = path
        self.previousPath = previousPath
        self.changeKind = changeKind
        self.additions = additions
        self.deletions = deletions
        self.isBinary = isBinary
        self.patch = patch
    }

    /// The patch, parsed. Nil when there is no patch text or it does not parse.
    public var parsedPatch: Patch? {
        guard let patch else { return nil }
        return try? PatchParser.parse(patch)
    }
}

/// A commit on the head branch.
public struct Commit: Codable, Sendable, Hashable, Identifiable {
    /// The full 40-character hash.
    public var id: String
    /// The full message. The first line is the subject.
    public var message: String
    public var author: Person
    public var authoredAt: Date

    public init(id: String, message: String, author: Person, authoredAt: Date) {
        self.id = id
        self.message = message
        self.author = author
        self.authoredAt = authoredAt
    }

    public var shortID: String { String(id.prefix(7)) }
    public var subject: String { String(message.split(separator: "\n", omittingEmptySubsequences: false).first ?? "") }
}
