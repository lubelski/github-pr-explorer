import Foundation

/// The situation a mock pull request is built to be in. Each one gives a different status sentence.
enum MockScenario: Hashable {
    case draft
    case checksQueued
    case checksRunning(minutes: Int)
    case requiredCheckFailed
    case optionalCheckFailed
    case changesRequested
    case readyToMerge
    case waitingOnReviewers
    case needsReview
    case unresolvedThreads(count: Int)
    case mergeConflicts
    case behindBase
    case mergeabilityUnknown
    case mergeQueue(position: Int)
    case merged
    case closed

    var isOpen: Bool { self != .merged && self != .closed }

    /// The states of the status precedence that rank above "waiting on reviewers", so a pending
    /// review request does not change what the sentence says.
    var outranksWaitingOnReviewers: Bool {
        switch self {
        case .checksQueued, .checksRunning, .requiredCheckFailed, .optionalCheckFailed, .changesRequested,
             .unresolvedThreads, .mergeConflicts, .draft:
            true
        default:
            false
        }
    }

    /// Scenarios whose sentence does not depend on unresolved threads.
    var allowsUnresolvedThreads: Bool {
        switch self {
        case .draft, .checksQueued, .checksRunning, .requiredCheckFailed, .changesRequested, .mergeConflicts,
             .unresolvedThreads, .closed:
            true
        default:
            false
        }
    }
}

struct MockFileSpec {
    var path: String
    var changeKind: FileChangeKind = .modified
    var additions: Int = 0
    var deletions: Int = 0
    var previousPath: String? = nil
    var isBinary = false
    /// Hand-written patch text. When nil, a patch is synthesized with exactly these counts.
    var patch: String? = nil
    var noNewlineAtEnd = false
}

struct MockReviewPlan {
    var approvedBy: [Person] = []
    var changesRequestedBy: [Person] = []
    var commentedBy: [Person] = []
    var pendingPeople: [Person] = []
    var pendingTeams: [Team] = []

    var reviewers: [Person] { approvedBy + changesRequestedBy + commentedBy }
}

enum MockThreadKind {
    case unresolved
    case resolved
    case outdated
    case outdatedResolved
    /// Unresolved and waiting on the viewer: the viewer wrote the pull request, or started the thread.
    case needsViewer
}

enum MockCheckboxComment {
    case unticked
    case ticked
}

/// What a mock pull request should be. The factory fills in everything left nil.
struct MockPullRequestSpec {
    var repository: Repository
    var number: Int
    var title: String
    var author: Person
    var scenario: MockScenario
    var body: String? = nil
    var createdAt: Date? = nil
    /// When a merged or closed pull request was merged or closed.
    var endedAt: Date? = nil
    var baseBranch = "main"
    var headBranch: String? = nil
    var area: MockArea? = nil
    var files: [MockFileSpec]? = nil
    var commitCount: Int? = nil
    var commitMessages: [String]? = nil
    var pushCount: Int? = nil
    var labels: [String]? = nil
    var reviewPlan: MockReviewPlan? = nil
    var checks: [MockCheckDefinition]? = nil
    var threads: [MockThreadKind]? = nil
    var ciBotCheckbox: MockCheckboxComment? = nil
    var allowsRandomCheckbox = true
    /// Posts a check result to the timeline for the first checks after every push.
    var reportsChecksOnEveryPush = false
    var linkedIssue: LinkedIssue? = nil
    var isBehindBase: Bool? = nil
}
