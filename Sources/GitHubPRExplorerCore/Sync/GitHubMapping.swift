import Foundation

/// Turns GitHub's answers into the index's models. Pure functions: no network, no clock.
enum GitHubMapping {
    // MARK: People

    static let ghost = Person(login: "ghost", displayName: "Deleted account")

    static func person(_ actor: GHActor?) -> Person {
        guard let actor else { return ghost }
        let isBot = actor.__typename == "Bot" || actor.login.hasSuffix("[bot]")
        return Person(login: actor.login, displayName: displayName(actor.name, login: actor.login), isBot: isBot)
    }

    static func person(_ user: GHUser) -> Person {
        Person(login: user.login, displayName: displayName(user.name, login: user.login), isBot: user.login.hasSuffix("[bot]"))
    }

    static func person(_ author: GHCommitAuthor?) -> Person {
        if let user = author?.user { return person(user) }
        let name = author?.name?.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? ghost : Person(login: name, displayName: name)
    }

    static func displayName(_ name: String?, login: String) -> String {
        let trimmed = name?.trimmingCharacters(in: .whitespaces) ?? ""
        return trimmed.isEmpty ? login : trimmed
    }

    static func reviewer(_ reviewer: GHRequestedReviewer?) -> RequestedReviewer? {
        guard let reviewer else { return nil }
        if reviewer.__typename == "Team", let slug = reviewer.slug, let organization = reviewer.organization?.login {
            return .team(Team(organization: organization, slug: slug, members: []))
        }
        guard let login = reviewer.login else { return nil }
        return .person(Person(login: login, displayName: displayName(reviewer.name, login: login),
                              isBot: reviewer.__typename == "Bot"))
    }

    // MARK: The list pass

    static func state(_ text: String) -> PullRequestState {
        switch text {
        case "MERGED": .merged
        case "CLOSED": .closed
        default: .open
        }
    }

    /// A pull request from the list pass. Sections the list does not carry are kept from the
    /// copy already in the index, or marked as not fetched yet.
    static func pullRequest(_ node: GHListPullRequest, existing: PullRequest?, fetchedAt: Date) -> PullRequest {
        let repository = Repository(owner: node.repository.owner.login, name: node.repository.name)
        let author = person(node.author)
        var pr = existing ?? PullRequest(
            id: node.id, repository: repository, number: node.number, title: node.title, author: author,
            headBranch: node.headRefName, headCommitID: node.headRefOid, createdAt: node.createdAt, updatedAt: node.updatedAt,
            mergeState: MergeState(mergeability: .unknown),
            provenance: Provenance(metadata: .notFetched, checks: .notFetched, reviews: .notFetched,
                                   files: .notFetched, threads: .notFetched, timeline: .notFetched))
        pr.id = node.id
        pr.repository = repository
        pr.number = node.number
        pr.title = node.title
        pr.author = author
        pr.state = state(node.state)
        pr.isDraft = node.isDraft
        pr.baseBranch = node.baseRefName
        pr.headBranch = node.headRefName
        if pr.headCommitID != node.headRefOid {
            // A push: GitHub works out mergeability again, so it is unknown until asked.
            pr.mergeState.mergeability = .unknown
        }
        pr.headCommitID = node.headRefOid
        pr.createdAt = node.createdAt
        pr.updatedAt = node.updatedAt
        pr.mergedAt = node.mergedAt
        pr.closedAt = node.closedAt
        pr.additions = node.additions
        pr.deletions = node.deletions
        pr.labels = node.labels?.items.map { Label(name: $0.name, color: $0.color) } ?? []
        pr.assignees = node.assignees?.items.map(person) ?? []
        let known = Dictionary(pr.reviewRequests.map { ($0.reviewer.handle, $0.requestedAt) }, uniquingKeysWith: { first, _ in first })
        pr.reviewRequests = node.reviewRequests?.items.compactMap { request in
            guard let reviewer = reviewer(request.requestedReviewer) else { return nil }
            // GitHub gives no time on a request. The timeline's event gives it once detail is
            // fetched. Until then it is the time the pull request was opened.
            return ReviewRequest(reviewer: reviewer, requestedAt: known[reviewer.handle] ?? node.createdAt,
                                 isCodeOwnerRequest: request.asCodeOwner)
        } ?? []
        pr.provenance.metadata = SectionProvenance(source: .graphQLAPI, fetchedAt: fetchedAt)
        return pr
    }

    // MARK: Detail

    static func reviewState(_ text: String) -> ReviewState? {
        switch text {
        case "APPROVED": .approved
        case "CHANGES_REQUESTED": .changesRequested
        case "COMMENTED": .commented
        // A dismissed review no longer counts, and a pending one is the viewer's unsent draft.
        default: nil
        }
    }

    static func apply(_ detail: GHDetail, to pr: inout PullRequest, fetchedAt: Date) {
        let stamp = SectionProvenance(source: .graphQLAPI, fetchedAt: fetchedAt)
        pr.body = detail.body
        pr.milestone = detail.milestone.map { Milestone(title: $0.title, dueOn: $0.dueOn) }
        pr.linkedIssues = detail.closingIssuesReferences?.items.map {
            LinkedIssue(repository: Repository(owner: $0.repository.owner.login, name: $0.repository.name),
                        number: $0.number, title: $0.title, isClosed: $0.closed)
        } ?? []
        pr.reviews = detail.reviews?.items.compactMap { review in
            guard let state = reviewState(review.state) else { return nil }
            return Review(id: review.id, reviewer: person(review.author), state: state,
                          submittedAt: review.submittedAt ?? review.createdAt, body: review.body)
        } ?? []
        // Newest last, as GitHub lists them, and the model keeps them.
        pr.commits = detail.commits?.items.map {
            Commit(id: $0.commit.oid, message: $0.commit.message, author: person($0.commit.author), authoredAt: $0.commit.authoredDate)
        } ?? []
        pr.reviewThreads = detail.reviewThreads?.items.map(thread) ?? []
        pr.comments = detail.comments?.items.map {
            IssueComment(id: $0.id, author: person($0.author), body: $0.body, createdAt: $0.createdAt)
        } ?? []
        let events = timeline(detail.timelineItems?.items ?? [], pr: pr)
        pr.timeline = events
        // The time each pending request was made, from its timeline event.
        var requestedAt: [String: Date] = [:]
        for item in detail.timelineItems?.items ?? [] where item.__typename == "ReviewRequestedEvent" {
            if let reviewer = reviewer(item.requestedReviewer), let date = item.createdAt { requestedAt[reviewer.handle] = date }
        }
        for position in pr.reviewRequests.indices {
            if let date = requestedAt[pr.reviewRequests[position].reviewer.handle] { pr.reviewRequests[position].requestedAt = date }
        }
        pr.provenance.reviews = stamp
        pr.provenance.threads = stamp
        pr.provenance.timeline = stamp
    }

    static func thread(_ node: GHThread) -> ReviewThread {
        let comments = node.comments.items.map {
            ReviewComment(id: $0.id, author: person($0.author), body: $0.body, createdAt: $0.createdAt)
        }
        let side: DiffSide = node.diffSide == "LEFT" ? .left : .right
        return ReviewThread(id: node.id, path: node.path, line: node.line ?? node.originalLine ?? 0, side: side,
                            isResolved: node.isResolved, isOutdated: node.isOutdated,
                            quotedLine: quotedLine(node.comments.items.first?.diffHunk),
                            comments: comments)
    }

    /// The line a thread is on: the last line of the first comment's diff hunk, without its marker.
    static func quotedLine(_ hunk: String?) -> String {
        guard let last = hunk?.split(separator: "\n", omittingEmptySubsequences: true).last(where: { !$0.hasPrefix("@@") }) else { return "" }
        let text = String(last)
        if let first = text.first, "+- ".contains(first) { return String(text.dropFirst()) }
        return text
    }

    static func timeline(_ items: [GHTimelineItem], pr: PullRequest) -> [TimelineEvent] {
        var events: [TimelineEvent] = [
            TimelineEvent(id: "\(pr.id)-opened", kind: .opened, actor: pr.author, occurredAt: pr.createdAt,
                          summary: "\(pr.author.displayName) opened the pull request"),
        ]
        var position = 0
        while position < items.count {
            let item = items[position]
            if item.__typename == "PullRequestCommit" {
                // A run of commits by one person is one push, as the mock world and GitHub show it.
                let actor = person(item.commit?.author)
                var count = 0
                var last = item
                while position < items.count, items[position].__typename == "PullRequestCommit",
                      person(items[position].commit?.author) == actor {
                    last = items[position]
                    count += 1
                    position += 1
                }
                let date = last.commit?.committedDate ?? pr.createdAt
                events.append(TimelineEvent(id: last.id ?? "\(pr.id)-push-\(events.count)", kind: .pushedCommits, actor: actor, occurredAt: date,
                                            summary: "\(actor.displayName) pushed \(count == 1 ? "1 commit" : "\(count) commits")"))
                continue
            }
            position += 1
            guard let date = item.createdAt else { continue }
            let actor = person(item.author ?? item.actor)
            let name = actor.displayName
            let kind: TimelineEventKind
            let summary: String
            switch item.__typename {
            case "IssueComment": (kind, summary) = (.commented, "\(name) commented")
            case "PullRequestReview":
                switch item.state {
                case "APPROVED": (kind, summary) = (.reviewed, "\(name) approved")
                case "CHANGES_REQUESTED": (kind, summary) = (.reviewed, "\(name) requested changes")
                case "PENDING": continue
                default: (kind, summary) = (.reviewed, "\(name) reviewed")
                }
            case "HeadRefForcePushedEvent": (kind, summary) = (.forcePushed, "\(name) force-pushed")
            case "LabeledEvent": (kind, summary) = (.labelAdded, "\(name) added the label \(item.label?.name ?? "")")
            case "UnlabeledEvent": (kind, summary) = (.labelRemoved, "\(name) removed the label \(item.label?.name ?? "")")
            case "ReviewRequestedEvent":
                let who = reviewer(item.requestedReviewer)?.displayName ?? "a reviewer"
                (kind, summary) = (.reviewRequested, "\(name) asked \(who) for a review")
            case "ReviewRequestRemovedEvent": (kind, summary) = (.reviewRequestRemoved, "\(name) removed a review request")
            case "AssignedEvent": (kind, summary) = (.assigned, "\(name) assigned someone")
            case "ConvertToDraftEvent": (kind, summary) = (.convertedToDraft, "\(name) marked it as a draft")
            case "ReadyForReviewEvent": (kind, summary) = (.readyForReview, "\(name) marked it ready for review")
            case "AddedToMergeQueueEvent": (kind, summary) = (.addedToMergeQueue, "\(name) added it to the merge queue")
            case "RemovedFromMergeQueueEvent": (kind, summary) = (.removedFromMergeQueue, "\(name) removed it from the merge queue")
            case "RenamedTitleEvent": (kind, summary) = (.renamedTitle, "\(name) changed the title")
            case "BaseRefChangedEvent": (kind, summary) = (.baseChanged, "\(name) changed the base branch")
            case "CrossReferencedEvent": (kind, summary) = (.referenced, "\(name) referenced this")
            case "DeployedEvent": (kind, summary) = (.deployed, "\(name) deployed")
            case "MergedEvent": (kind, summary) = (.merged, "\(name) merged it")
            case "ClosedEvent": (kind, summary) = (.closed, "\(name) closed it")
            case "ReopenedEvent": (kind, summary) = (.reopened, "\(name) reopened it")
            default: continue
            }
            events.append(TimelineEvent(id: item.id ?? "\(pr.id)-event-\(events.count)", kind: kind, actor: actor, occurredAt: date, summary: summary))
        }
        return events.sorted { $0.occurredAt == $1.occurredAt ? $0.id < $1.id : $0.occurredAt < $1.occurredAt }
    }

    // MARK: Computed fields

    static func checkState(_ context: GHCheckContext) -> CheckState {
        if context.__typename == "StatusContext" {
            switch context.state {
            case "SUCCESS": return .passed
            case "FAILURE", "ERROR": return .failed
            default: return .running
            }
        }
        switch context.status {
        case "COMPLETED":
            switch context.conclusion {
            case "SUCCESS": return .passed
            case "SKIPPED", "NEUTRAL": return .skipped
            case "CANCELLED", "STALE": return .cancelled
            default: return .failed
            }
        case "IN_PROGRESS": return .running
        default: return .queued
        }
    }

    static func check(_ context: GHCheckContext) -> Check? {
        let state = checkState(context)
        if context.__typename == "StatusContext" {
            guard let name = context.context else { return nil }
            return Check(name: name, state: state, isRequired: context.isRequired ?? false, startedAt: context.createdAt,
                         finishedAt: state.isFinished ? context.createdAt : nil,
                         failureSummary: state == .failed ? context.description : nil)
        }
        guard let name = context.name else { return nil }
        return Check(name: name, state: state, isRequired: context.isRequired ?? false, startedAt: context.startedAt,
                     finishedAt: context.completedAt, failureSummary: state == .failed ? context.title : nil)
    }

    static func apply(_ computed: GHComputed, to pr: inout PullRequest, fetchedAt: Date) {
        let head = computed.commits?.items.first?.commit
        pr.checks = head?.statusCheckRollup?.contexts.items.compactMap(check) ?? []
        pr.reviewDecision = switch computed.reviewDecision {
        case "APPROVED": .approved
        case "CHANGES_REQUESTED": .changesRequested
        case "REVIEW_REQUIRED": .reviewRequired
        default: nil
        }
        var merge = MergeState()
        merge.mergeability = switch computed.mergeable {
        case "MERGEABLE": .mergeable
        case "CONFLICTING": .conflicting
        default: .unknown
        }
        merge.isBehindBase = computed.mergeStateStatus == "BEHIND"
        // The model's 1 is next to merge. GitHub's position is taken to count from 0. That is
        // believed, not checked against a real merge queue.
        merge.mergeQueuePosition = computed.mergeQueueEntry.map { $0.position + 1 }
        merge.blockedReasons = blockedReasons(pr: pr, mergeability: merge.mergeability, mergeStateStatus: computed.mergeStateStatus)
        pr.mergeState = merge
        pr.provenance.checks = SectionProvenance(source: .graphQLAPI, fetchedAt: fetchedAt)
    }

    /// GitHub says only that a pull request is blocked, not why, so the reasons are worked
    /// out from what the index holds.
    static func blockedReasons(pr: PullRequest, mergeability: Mergeability, mergeStateStatus: String?) -> [BlockedReason] {
        var reasons: [BlockedReason] = []
        if pr.isDraft { reasons.append(.draft) }
        if mergeability == .conflicting { reasons.append(.mergeConflicts) }
        if pr.checks.contains(where: { $0.isRequired && ($0.state == .failed || $0.state == .cancelled) }) { reasons.append(.requiredChecksFailing) }
        if pr.checks.contains(where: { $0.isRequired && !$0.state.isFinished }) { reasons.append(.requiredChecksPending) }
        if pr.reviewDecision == .changesRequested { reasons.append(.changesRequested) }
        if pr.reviewDecision == .reviewRequired {
            reasons.append(pr.reviewRequests.contains(where: \.isCodeOwnerRequest) ? .codeOwnerReviewRequired : .reviewRequired)
        }
        if mergeStateStatus == "BLOCKED", reasons.isEmpty,
           pr.reviewThreads.contains(where: { !$0.isResolved }) { reasons.append(.unresolvedConversations) }
        if mergeStateStatus == "BEHIND" { reasons.append(.behindBase) }
        return reasons
    }

    // MARK: Files

    static func file(_ entry: RESTFile) -> ChangedFile {
        let kind: FileChangeKind = switch entry.status {
        case "added": .added
        case "removed": .removed
        case "renamed": .renamed
        default: .modified
        }
        // GitHub leaves the patch out for a binary file, and for a very large diff. A file with
        // no patch and no counted lines is taken as binary, unless it is a pure rename.
        let isBinary = entry.patch == nil && entry.changes == 0 && kind != .renamed
        return ChangedFile(path: entry.filename, previousPath: kind == .renamed ? entry.previous_filename : nil, changeKind: kind,
                           additions: entry.additions, deletions: entry.deletions, isBinary: isBinary, patch: entry.patch)
    }

    // MARK: CODEOWNERS

    /// Reads a CODEOWNERS file: a pattern and its owners per line, `#` starting a comment.
    static func codeOwnerRules(_ text: String) -> [CodeOwnerRule] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let content = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
            let words = content.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let pattern = words.first else { return nil }
            return CodeOwnerRule(pattern: pattern, owners: Array(words.dropFirst()))
        }
    }
}
