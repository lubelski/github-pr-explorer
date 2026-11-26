import Foundation

extension ReviewThread {
    /// True when this thread is waiting on the viewer.
    ///
    /// A thread needs the viewer when it is unresolved, not outdated, its last comment is by
    /// someone else, and the viewer has a stake in it: the viewer wrote the pull request,
    /// commented in the thread, or is mentioned in it by `@login`.
    public func needsAttention(from viewer: Viewer, pullRequestAuthor: Person) -> Bool {
        guard !isResolved, !isOutdated, let last = lastComment, !viewer.isViewer(last.author) else { return false }
        if viewer.isViewer(pullRequestAuthor) { return true }
        if comments.contains(where: { viewer.isViewer($0.author) }) { return true }
        let mention = viewer.person.handle
        return comments.contains { $0.body.contains(mention) }
    }
}

/// Who did something in a timeline, for telling people's events from automation.
public enum TimelineActorKind: String, Codable, Sendable, Hashable, CaseIterable {
    case person
    case agent
    case bot
}

extension TimelineEvent {
    public var actorKind: TimelineActorKind {
        if actor.isBot { return .bot }
        if actor.isAgent { return .agent }
        return .person
    }
}

extension PullRequest {
    /// Threads not yet resolved, outdated or not.
    public var unresolvedThreads: [ReviewThread] {
        reviewThreads.filter { !$0.isResolved }
    }

    /// Threads waiting on the viewer. See `ReviewThread.needsAttention(from:pullRequestAuthor:)`.
    public func threadsNeedingAttention(from viewer: Viewer) -> [ReviewThread] {
        reviewThreads.filter { $0.needsAttention(from: viewer, pullRequestAuthor: author) }
    }

    /// Timeline events by people and agents, leaving out bots.
    public var humanTimelineEvents: [TimelineEvent] {
        timeline.filter { !$0.isFromBot }
    }

    /// Timeline events by bots only.
    public var botTimelineEvents: [TimelineEvent] {
        timeline.filter(\.isFromBot)
    }

    /// True when a review is asked of the viewer, directly or through one of their teams.
    public func isReviewRequested(from viewer: Viewer) -> Bool {
        guard !viewer.isViewer(author) else { return false }
        return reviewRequests.contains { $0.isRequested(from: viewer) }
    }
}
