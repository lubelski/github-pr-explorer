import Foundation

/// The GraphQL queries the sync sends. They come in tiers, after the research in
/// `planning/research/github-data-sources.md`:
///
/// 1. **List**: light fields for every pull request in scope, on a timer. No computed fields.
/// 2. **Computed**: mergeability, merge state, review decision, merge queue position and the
///    check rollup, in small batches, because these are worked out by GitHub on request and
///    time out when many are asked for at once.
/// 3. **Detail**: description, reviews, commits, threads, comments and the timeline, when a
///    pull request is new, has changed, or is opened. Per-file patches come from REST, since
///    GraphQL has none.
enum GitHubQueries {
    static let rateLimitFields = "rateLimit { cost remaining limit resetAt }"

    static let actorFields = "__typename login ... on User { name }"

    static let viewer = """
        query { viewer { login name } \(rateLimitFields) }
        """

    static let viewerTeams = """
        query($login: String!) {
          viewer {
            organizations(first: 50) {
              nodes { login teams(first: 100, userLogins: [$login]) { nodes { slug } } }
            }
          }
          \(rateLimitFields)
        }
        """

    static let listFields = """
        fragment ListFields on PullRequest {
          id number title isDraft state createdAt updatedAt mergedAt closedAt
          baseRefName headRefName headRefOid additions deletions
          repository { name owner { login } }
          author { \(actorFields) }
          labels(first: 20) { nodes { name color } }
          assignees(first: 10) { nodes { login name } }
          reviewRequests(first: 30) {
            nodes {
              asCodeOwner
              requestedReviewer {
                __typename
                ... on User { login name }
                ... on Team { slug organization { login } }
                ... on Bot { login }
                ... on Mannequin { login }
              }
            }
          }
        }
        """

    /// Open pull requests found by a search, such as `is:pr is:open involves:@me`.
    static let search = """
        query($query: String!, $after: String) {
          search(query: $query, type: ISSUE, first: 50, after: $after) {
            pageInfo { hasNextPage endCursor }
            nodes { ... on PullRequest { ...ListFields } }
          }
          \(rateLimitFields)
        }
        \(listFields)
        """

    /// Every open pull request in one repository, most recently updated first.
    static let repositoryPullRequests = """
        query($owner: String!, $name: String!, $after: String) {
          repository(owner: $owner, name: $name) {
            pullRequests(states: OPEN, first: 50, after: $after, orderBy: {field: UPDATED_AT, direction: DESC}) {
              pageInfo { hasNextPage endCursor }
              nodes { ...ListFields }
            }
          }
          \(rateLimitFields)
        }
        \(listFields)
        """

    /// The searches that find pull requests involving the signed-in person. `involves` covers
    /// author, assignee, mentions and comments. Review requests, including a team's, and
    /// reviews given are separate qualifiers.
    static let involvementSearches = [
        "is:pr is:open archived:false involves:@me",
        "is:pr is:open archived:false review-requested:@me",
        "is:pr is:open archived:false reviewed-by:@me",
    ]

    /// Detail for a few pull requests by node id. No computed fields.
    static let detail = """
        query($ids: [ID!]!) {
          nodes(ids: $ids) {
            ... on PullRequest {
              id body
              milestone { title dueOn }
              closingIssuesReferences(first: 10) { nodes { number title closed repository { name owner { login } } } }
              reviews(last: 50) { nodes { id state submittedAt createdAt body author { \(actorFields) } } }
              commits(last: 100) {
                nodes { commit { oid message authoredDate author { name user { login name } } } }
              }
              reviewThreads(first: 50) {
                nodes {
                  id path line originalLine diffSide isResolved isOutdated
                  comments(first: 30) { nodes { id body createdAt diffHunk author { \(actorFields) } } }
                }
              }
              comments(last: 50) { nodes { id body createdAt author { \(actorFields) } } }
              timelineItems(last: 100, itemTypes: [\(timelineTypes.joined(separator: ", "))]) {
                nodes {
                  __typename
                  ... on IssueComment { id createdAt author { \(actorFields) } }
                  ... on PullRequestReview { id createdAt state author { \(actorFields) } }
                  ... on PullRequestCommit { id commit { committedDate author { name user { login name } } } }
                  ... on HeadRefForcePushedEvent { id createdAt actor { \(actorFields) } }
                  ... on LabeledEvent { id createdAt actor { \(actorFields) } label { name } }
                  ... on UnlabeledEvent { id createdAt actor { \(actorFields) } label { name } }
                  ... on ReviewRequestedEvent { id createdAt actor { \(actorFields) } requestedReviewer { __typename ... on User { login name } ... on Team { slug organization { login } } } }
                  ... on ReviewRequestRemovedEvent { id createdAt actor { \(actorFields) } }
                  ... on AssignedEvent { id createdAt actor { \(actorFields) } }
                  ... on ConvertToDraftEvent { id createdAt actor { \(actorFields) } }
                  ... on ReadyForReviewEvent { id createdAt actor { \(actorFields) } }
                  ... on AddedToMergeQueueEvent { id createdAt actor { \(actorFields) } }
                  ... on RemovedFromMergeQueueEvent { id createdAt actor { \(actorFields) } }
                  ... on RenamedTitleEvent { id createdAt actor { \(actorFields) } }
                  ... on BaseRefChangedEvent { id createdAt actor { \(actorFields) } }
                  ... on CrossReferencedEvent { id createdAt actor { \(actorFields) } }
                  ... on DeployedEvent { id createdAt actor { \(actorFields) } }
                  ... on MergedEvent { id createdAt actor { \(actorFields) } }
                  ... on ClosedEvent { id createdAt actor { \(actorFields) } }
                  ... on ReopenedEvent { id createdAt actor { \(actorFields) } }
                }
              }
            }
          }
          \(rateLimitFields)
        }
        """

    static let timelineTypes = [
        "ISSUE_COMMENT", "PULL_REQUEST_REVIEW", "PULL_REQUEST_COMMIT", "HEAD_REF_FORCE_PUSHED_EVENT",
        "LABELED_EVENT", "UNLABELED_EVENT", "REVIEW_REQUESTED_EVENT", "REVIEW_REQUEST_REMOVED_EVENT",
        "ASSIGNED_EVENT", "CONVERT_TO_DRAFT_EVENT", "READY_FOR_REVIEW_EVENT", "ADDED_TO_MERGE_QUEUE_EVENT",
        "REMOVED_FROM_MERGE_QUEUE_EVENT", "RENAMED_TITLE_EVENT", "BASE_REF_CHANGED_EVENT",
        "CROSS_REFERENCED_EVENT", "DEPLOYED_EVENT", "MERGED_EVENT", "CLOSED_EVENT", "REOPENED_EVENT",
    ]

    /// A node id as GitHub writes them: letters, digits, `_`, `-` and `=`. Anything else is
    /// never put into a query's text.
    static func isNodeID(_ text: String) -> Bool {
        !text.isEmpty && text.count < 200 && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "_-=".contains($0)) }
    }

    /// The computed fields for a few pull requests, one alias each. `isRequired` needs the
    /// pull request, so each alias names its own id.
    static func computed(ids: [String]) -> String {
        let parts = ids.enumerated().filter { isNodeID($0.element) }.map { position, id in
            """
              pr\(position): node(id: "\(id)") {
                ... on PullRequest {
                  id mergeable mergeStateStatus reviewDecision mergeQueueEntry { position }
                  commits(last: 1) {
                    nodes {
                      commit {
                        oid
                        statusCheckRollup {
                          contexts(first: 100) {
                            nodes {
                              __typename
                              ... on CheckRun { name status conclusion startedAt completedAt title isRequired(pullRequestId: "\(id)") }
                              ... on StatusContext { context state createdAt description isRequired(pullRequestId: "\(id)") }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            """
        }
        return "query {\n\(parts.joined(separator: "\n"))\n  \(rateLimitFields)\n}"
    }

    /// The CODEOWNERS file on a repository's default branch, wherever GitHub looks for it.
    static let codeOwners = """
        query($owner: String!, $name: String!) {
          repository(owner: $owner, name: $name) {
            github: object(expression: "HEAD:.github/CODEOWNERS") { ... on Blob { text } }
            root: object(expression: "HEAD:CODEOWNERS") { ... on Blob { text } }
            docs: object(expression: "HEAD:docs/CODEOWNERS") { ... on Blob { text } }
          }
          \(rateLimitFields)
        }
        """
}
