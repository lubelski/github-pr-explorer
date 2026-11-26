import Foundation

// The shapes of GitHub's answers to the queries in `GitHubQueries`, as plain Decodable values.
// Fields GitHub can leave out or send as null are optional.

struct GraphQLRateLimit: Decodable, Sendable, Hashable {
    var cost: Int
    var remaining: Int?
    var limit: Int?
    var resetAt: Date?
}

struct Connection<Node: Decodable & Sendable>: Decodable, Sendable {
    var nodes: [Node?]?
    var pageInfo: PageInfo?
    var items: [Node] { (nodes ?? []).compactMap { $0 } }
}

struct PageInfo: Decodable, Sendable {
    var hasNextPage: Bool
    var endCursor: String?
}

struct GHActor: Decodable, Sendable, Hashable {
    var __typename: String?
    var login: String
    var name: String?
}

struct GHOwner: Decodable, Sendable { var login: String }
struct GHRepository: Decodable, Sendable {
    var name: String
    var owner: GHOwner
}

struct GHLabel: Decodable, Sendable { var name: String; var color: String }
struct GHUser: Decodable, Sendable { var login: String; var name: String? }

struct GHRequestedReviewer: Decodable, Sendable {
    var __typename: String
    var login: String?
    var name: String?
    var slug: String?
    var organization: GHOwner?
}

struct GHReviewRequest: Decodable, Sendable {
    var asCodeOwner: Bool
    var requestedReviewer: GHRequestedReviewer?
}

/// The light fields of one pull request, from the list pass.
struct GHListPullRequest: Decodable, Sendable {
    var id: String
    var number: Int
    var title: String
    var isDraft: Bool
    var state: String
    var createdAt: Date
    var updatedAt: Date
    var mergedAt: Date?
    var closedAt: Date?
    var baseRefName: String
    var headRefName: String
    var headRefOid: String
    var additions: Int
    var deletions: Int
    var repository: GHRepository
    var author: GHActor?
    var labels: Connection<GHLabel>?
    var assignees: Connection<GHUser>?
    var reviewRequests: Connection<GHReviewRequest>?
}

/// A search result node. Anything that is not a pull request comes back as an empty object.
struct GHSearchNode: Decodable, Sendable {
    var pullRequest: GHListPullRequest?
    init(from decoder: any Decoder) throws {
        let keys = try decoder.container(keyedBy: AnyKey.self)
        pullRequest = keys.allKeys.isEmpty ? nil : try GHListPullRequest(from: decoder)
    }
}

struct SearchPayload: Decodable, Sendable {
    var search: Connection<GHSearchNode>
}

struct RepositoryPullRequestsPayload: Decodable, Sendable {
    struct Repo: Decodable, Sendable { var pullRequests: Connection<GHListPullRequest> }
    var repository: Repo?
}

struct ViewerPayload: Decodable, Sendable {
    var viewer: GHUser
}

struct ViewerTeamsPayload: Decodable, Sendable {
    struct Slug: Decodable, Sendable { var slug: String }
    struct Organization: Decodable, Sendable {
        var login: String
        var teams: Connection<Slug>?
    }
    struct Viewer: Decodable, Sendable { var organizations: Connection<Organization> }
    var viewer: Viewer
}

// MARK: Detail

struct GHMilestone: Decodable, Sendable { var title: String; var dueOn: Date? }
struct GHLinkedIssue: Decodable, Sendable {
    var number: Int
    var title: String
    var closed: Bool
    var repository: GHRepository
}

struct GHReview: Decodable, Sendable {
    var id: String
    var state: String
    var submittedAt: Date?
    var createdAt: Date
    var body: String
    var author: GHActor?
}

struct GHCommitAuthor: Decodable, Sendable {
    var name: String?
    var user: GHUser?
}

struct GHCommit: Decodable, Sendable {
    var oid: String
    var message: String
    var authoredDate: Date
    var author: GHCommitAuthor?
}

struct GHCommitNode: Decodable, Sendable { var commit: GHCommit }

struct GHThreadComment: Decodable, Sendable {
    var id: String
    var body: String
    var createdAt: Date
    var diffHunk: String?
    var author: GHActor?
}

struct GHThread: Decodable, Sendable {
    var id: String
    var path: String
    var line: Int?
    var originalLine: Int?
    var diffSide: String?
    var isResolved: Bool
    var isOutdated: Bool
    var comments: Connection<GHThreadComment>
}

struct GHIssueComment: Decodable, Sendable {
    var id: String
    var body: String
    var createdAt: Date
    var author: GHActor?
}

struct GHTimelineItem: Decodable, Sendable {
    struct Label: Decodable, Sendable { var name: String }
    struct CommitInfo: Decodable, Sendable {
        var committedDate: Date
        var author: GHCommitAuthor?
    }
    var __typename: String
    var id: String?
    var createdAt: Date?
    var state: String?
    var author: GHActor?
    var actor: GHActor?
    var label: Label?
    var commit: CommitInfo?
    var requestedReviewer: GHRequestedReviewer?
}

struct GHDetail: Decodable, Sendable {
    var id: String
    var body: String
    var milestone: GHMilestone?
    var closingIssuesReferences: Connection<GHLinkedIssue>?
    var reviews: Connection<GHReview>?
    var commits: Connection<GHCommitNode>?
    var reviewThreads: Connection<GHThread>?
    var comments: Connection<GHIssueComment>?
    var timelineItems: Connection<GHTimelineItem>?
}

struct DetailPayload: Decodable, Sendable {
    var nodes: [GHDetail?]
}

// MARK: Computed

struct GHCheckContext: Decodable, Sendable {
    var __typename: String
    // CheckRun
    var name: String?
    var status: String?
    var conclusion: String?
    var startedAt: Date?
    var completedAt: Date?
    var title: String?
    // StatusContext
    var context: String?
    var state: String?
    var createdAt: Date?
    var description: String?
    var isRequired: Bool?
}

struct GHComputed: Decodable, Sendable {
    struct QueueEntry: Decodable, Sendable { var position: Int }
    struct Rollup: Decodable, Sendable { var contexts: Connection<GHCheckContext> }
    struct HeadCommit: Decodable, Sendable {
        var oid: String
        var statusCheckRollup: Rollup?
    }
    struct HeadNode: Decodable, Sendable { var commit: HeadCommit }

    var id: String
    var mergeable: String?
    var mergeStateStatus: String?
    var reviewDecision: String?
    var mergeQueueEntry: QueueEntry?
    var commits: Connection<HeadNode>?
}

/// `pr0`, `pr1` and so on, each a pull request's computed fields, beside `rateLimit`.
struct ComputedPayload: Decodable, Sendable {
    var nodes: [GHComputed]
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        nodes = try container.allKeys.filter { $0.stringValue.hasPrefix("pr") }.compactMap { key in
            try container.decodeIfPresent(GHComputed.self, forKey: key)
        }
    }
}

struct CodeOwnersPayload: Decodable, Sendable {
    struct Blob: Decodable, Sendable { var text: String? }
    struct Repo: Decodable, Sendable { var github: Blob?; var root: Blob?; var docs: Blob? }
    var repository: Repo?
}

/// Any key, for objects whose keys are not fixed.
struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { self.stringValue = String(intValue); self.intValue = intValue }
}

// MARK: REST

/// One entry of `GET /repos/{owner}/{repo}/pulls/{number}/files`.
struct RESTFile: Decodable, Sendable {
    var filename: String
    var previous_filename: String?
    var status: String
    var additions: Int
    var deletions: Int
    var changes: Int
    var patch: String?
}
