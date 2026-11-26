import Foundation

public enum TimelineEventKind: String, Codable, Sendable, Hashable, CaseIterable {
    case opened
    case commented
    case reviewed
    case pushedCommits
    case forcePushed
    case labelAdded
    case labelRemoved
    case reviewRequested
    case reviewRequestRemoved
    case assigned
    case checkFinished
    case deployed
    case convertedToDraft
    case readyForReview
    case addedToMergeQueue
    case removedFromMergeQueue
    case renamedTitle
    case baseChanged
    case referenced
    case merged
    case closed
    case reopened
}

/// One thing that happened on the pull request.
public struct TimelineEvent: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var kind: TimelineEventKind
    public var actor: Person
    public var occurredAt: Date
    /// One plain line, such as "Sam Rivera pushed 2 commits".
    public var summary: String

    public init(id: String, kind: TimelineEventKind, actor: Person, occurredAt: Date, summary: String) {
        self.id = id
        self.kind = kind
        self.actor = actor
        self.occurredAt = occurredAt
        self.summary = summary
    }

    public var isFromBot: Bool { actor.isBot }
}

/// Where a section of a pull request came from.
public enum DataSource: String, Codable, Sendable, Hashable, CaseIterable {
    case graphQLAPI
    case restAPI
    case localClone
    case push
    case webPage
    /// Made up on this Mac, for tests and previews. Never from GitHub.
    case mock

    public var displayName: String {
        switch self {
        case .graphQLAPI: "GraphQL API"
        case .restAPI: "REST API"
        case .localClone: "local clone"
        case .push: "push"
        case .webPage: "web page"
        case .mock: "mock data"
        }
    }
}

/// The parts of a pull request that are fetched, and dated, separately.
public enum PullRequestSection: String, Codable, Sendable, Hashable, CaseIterable {
    /// Title, body, state, branches, labels, milestone, linked issues, assignees, merge state.
    case metadata
    case checks
    /// Review requests, reviews, the review decision, and code owners.
    case reviews
    /// Changed files with their patches, and commits.
    case files
    /// Review threads and their comments.
    case threads
    /// Timeline events and conversation comments.
    case timeline
}

public struct SectionProvenance: Codable, Sendable, Hashable {
    public var source: DataSource
    public var fetchedAt: Date

    public init(source: DataSource, fetchedAt: Date) {
        self.source = source
        self.fetchedAt = fetchedAt
    }

    /// A section the sync has not fetched yet, such as the files of a pull request seen only
    /// in the list pass. Its date is the distant past, so it never passes for fresh.
    public static let notFetched = SectionProvenance(source: .graphQLAPI, fetchedAt: .distantPast)

    public var isFetched: Bool { fetchedAt > .distantPast }
}

/// Where each section of a pull request came from and when it was fetched. `VISION.md`
/// requires every fact in the index to carry this.
public struct Provenance: Codable, Sendable, Hashable {
    public var metadata: SectionProvenance
    public var checks: SectionProvenance
    public var reviews: SectionProvenance
    public var files: SectionProvenance
    public var threads: SectionProvenance
    public var timeline: SectionProvenance

    public init(
        metadata: SectionProvenance,
        checks: SectionProvenance,
        reviews: SectionProvenance,
        files: SectionProvenance,
        threads: SectionProvenance,
        timeline: SectionProvenance
    ) {
        self.metadata = metadata
        self.checks = checks
        self.reviews = reviews
        self.files = files
        self.threads = threads
        self.timeline = timeline
    }

    /// Every section from one source at one time.
    public static func uniform(_ source: DataSource, fetchedAt: Date) -> Provenance {
        let stamp = SectionProvenance(source: source, fetchedAt: fetchedAt)
        return Provenance(metadata: stamp, checks: stamp, reviews: stamp, files: stamp, threads: stamp, timeline: stamp)
    }

    public subscript(section: PullRequestSection) -> SectionProvenance {
        switch section {
        case .metadata: metadata
        case .checks: checks
        case .reviews: reviews
        case .files: files
        case .threads: threads
        case .timeline: timeline
        }
    }
}
