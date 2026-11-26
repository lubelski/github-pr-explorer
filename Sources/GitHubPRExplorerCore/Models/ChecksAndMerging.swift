import Foundation

public enum CheckState: String, Codable, Sendable, Hashable, CaseIterable {
    case queued
    case running
    case passed
    case failed
    case skipped
    case cancelled

    /// True once the check has stopped, whatever the outcome.
    public var isFinished: Bool {
        switch self {
        case .queued, .running: false
        case .passed, .failed, .skipped, .cancelled: true
        }
    }
}

/// One check run or status on the head commit.
public struct Check: Codable, Sendable, Hashable {
    public var name: String
    public var state: CheckState
    /// Branch protection requires this check to pass before merging.
    public var isRequired: Bool
    public var startedAt: Date?
    public var finishedAt: Date?
    /// A short line saying what went wrong, for a failed check. Such as "2 tests failed".
    public var failureSummary: String?

    public init(
        name: String,
        state: CheckState,
        isRequired: Bool,
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        failureSummary: String? = nil
    ) {
        self.name = name
        self.state = state
        self.isRequired = isRequired
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.failureSummary = failureSummary
    }

    /// How long it ran, for a finished check that started.
    public var duration: TimeInterval? {
        guard let startedAt, let finishedAt else { return nil }
        return finishedAt.timeIntervalSince(startedAt)
    }
}

public enum Mergeability: String, Codable, Sendable, Hashable, CaseIterable {
    case mergeable
    case conflicting
    /// GitHub has not worked it out yet, as just after a push.
    case unknown
}

/// Why GitHub will not merge the pull request yet, as branch protection reports it.
public enum BlockedReason: String, Codable, Sendable, Hashable, CaseIterable {
    case draft
    case mergeConflicts
    case requiredChecksFailing
    case requiredChecksPending
    case changesRequested
    case reviewRequired
    case codeOwnerReviewRequired
    case unresolvedConversations
    case behindBase
}

public struct MergeState: Codable, Sendable, Hashable {
    public var mergeability: Mergeability
    /// The base branch has commits the head branch lacks.
    public var isBehindBase: Bool
    public var blockedReasons: [BlockedReason]
    /// 1 is next to merge. Nil when the pull request is not in a merge queue.
    public var mergeQueuePosition: Int?

    public init(
        mergeability: Mergeability = .mergeable,
        isBehindBase: Bool = false,
        blockedReasons: [BlockedReason] = [],
        mergeQueuePosition: Int? = nil
    ) {
        self.mergeability = mergeability
        self.isBehindBase = isBehindBase
        self.blockedReasons = blockedReasons
        self.mergeQueuePosition = mergeQueuePosition
    }

    public var isInMergeQueue: Bool { mergeQueuePosition != nil }
}
