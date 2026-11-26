import Foundation

public enum PullRequestState: String, Codable, Sendable, Hashable, CaseIterable {
    case open
    case merged
    case closed
}

public struct Label: Codable, Sendable, Hashable {
    public var name: String
    /// Six hex digits, without the `#`, as GitHub stores it.
    public var color: String

    public init(name: String, color: String) {
        self.name = name
        self.color = color
    }
}

public struct Milestone: Codable, Sendable, Hashable {
    public var title: String
    public var dueOn: Date?

    public init(title: String, dueOn: Date? = nil) {
        self.title = title
        self.dueOn = dueOn
    }
}

/// An issue the pull request says it closes or refers to.
public struct LinkedIssue: Codable, Sendable, Hashable {
    public var repository: Repository
    public var number: Int
    public var title: String
    public var isClosed: Bool

    public init(repository: Repository, number: Int, title: String, isClosed: Bool) {
        self.repository = repository
        self.number = number
        self.title = title
        self.isClosed = isClosed
    }
}

/// `owner/name#number`, the short way to name a pull request.
public struct PullRequestReference: Codable, Sendable, Hashable, Comparable, CustomStringConvertible {
    public var repository: Repository
    public var number: Int

    public init(repository: Repository, number: Int) {
        self.repository = repository
        self.number = number
    }

    /// Reads `owner/name#number`. Returns nil for anything else.
    public init?(parsing text: String) {
        let parts = text.split(separator: "#", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let repository = Repository(fullName: String(parts[0])),
              let number = Int(parts[1]), number > 0
        else { return nil }
        self.init(repository: repository, number: number)
    }

    public var description: String { "\(repository.fullName)#\(number)" }

    public static func < (lhs: PullRequestReference, rhs: PullRequestReference) -> Bool {
        if lhs.repository != rhs.repository { return lhs.repository < rhs.repository }
        return lhs.number < rhs.number
    }
}

/// Everything the index knows about one pull request.
///
/// Each group of fields is one section, and `provenance` says where each section came from
/// and when. See `PullRequestSection` for which fields belong to which section.
public struct PullRequest: Codable, Sendable, Hashable, Identifiable {
    // Metadata
    /// Stable across renames and title changes. GitHub's node id in real data.
    public var id: String
    public var repository: Repository
    public var number: Int
    public var title: String
    /// Markdown, as the author wrote it. Can be empty.
    public var body: String
    public var author: Person
    public var state: PullRequestState
    public var isDraft: Bool
    public var baseBranch: String
    public var headBranch: String
    public var headCommitID: String
    public var createdAt: Date
    public var updatedAt: Date
    public var mergedAt: Date?
    public var closedAt: Date?
    public var additions: Int
    public var deletions: Int
    public var labels: [Label]
    public var milestone: Milestone?
    public var linkedIssues: [LinkedIssue]
    public var assignees: [Person]
    public var mergeState: MergeState

    // Reviews
    /// Reviews asked for and not yet given. GitHub drops a request once that reviewer reviews.
    public var reviewRequests: [ReviewRequest]
    public var reviews: [Review]
    /// GitHub's overall decision. Nil when the base branch requires no review.
    public var reviewDecision: ReviewDecision?
    public var codeOwners: [CodeOwnerMatch]

    // Checks
    public var checks: [Check]

    // Files
    public var files: [ChangedFile]
    public var commits: [Commit]

    // Threads
    public var reviewThreads: [ReviewThread]

    // Timeline
    /// Comments on the conversation tab, outside any review thread. Bots post most of them.
    public var comments: [IssueComment]
    public var timeline: [TimelineEvent]

    public var provenance: Provenance

    public init(
        id: String,
        repository: Repository,
        number: Int,
        title: String,
        body: String = "",
        author: Person,
        state: PullRequestState = .open,
        isDraft: Bool = false,
        baseBranch: String = "main",
        headBranch: String,
        headCommitID: String,
        createdAt: Date,
        updatedAt: Date,
        mergedAt: Date? = nil,
        closedAt: Date? = nil,
        additions: Int = 0,
        deletions: Int = 0,
        labels: [Label] = [],
        milestone: Milestone? = nil,
        linkedIssues: [LinkedIssue] = [],
        assignees: [Person] = [],
        mergeState: MergeState = MergeState(),
        reviewRequests: [ReviewRequest] = [],
        reviews: [Review] = [],
        reviewDecision: ReviewDecision? = nil,
        codeOwners: [CodeOwnerMatch] = [],
        checks: [Check] = [],
        files: [ChangedFile] = [],
        commits: [Commit] = [],
        reviewThreads: [ReviewThread] = [],
        comments: [IssueComment] = [],
        timeline: [TimelineEvent] = [],
        provenance: Provenance
    ) {
        self.id = id
        self.repository = repository
        self.number = number
        self.title = title
        self.body = body
        self.author = author
        self.state = state
        self.isDraft = isDraft
        self.baseBranch = baseBranch
        self.headBranch = headBranch
        self.headCommitID = headCommitID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.mergedAt = mergedAt
        self.closedAt = closedAt
        self.additions = additions
        self.deletions = deletions
        self.labels = labels
        self.milestone = milestone
        self.linkedIssues = linkedIssues
        self.assignees = assignees
        self.mergeState = mergeState
        self.reviewRequests = reviewRequests
        self.reviews = reviews
        self.reviewDecision = reviewDecision
        self.codeOwners = codeOwners
        self.checks = checks
        self.files = files
        self.commits = commits
        self.reviewThreads = reviewThreads
        self.comments = comments
        self.timeline = timeline
        self.provenance = provenance
    }

    public var reference: PullRequestReference {
        PullRequestReference(repository: repository, number: number)
    }

    public var changedLineCount: Int { additions + deletions }
}
