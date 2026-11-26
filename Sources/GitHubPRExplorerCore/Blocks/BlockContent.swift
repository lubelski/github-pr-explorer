import Foundation

// What each block shows, worked out from a pull request without SwiftUI, so it can be tested.
// The views in the app only lay these out.

// MARK: Files

/// Changed files grouped by the folder they are in, in the order the pull request lists them.
public struct FileGroups: Sendable, Hashable {
    public struct Group: Sendable, Hashable, Identifiable {
        /// The folder with a trailing slash, such as `auth/`. Empty for files at the root.
        public var folder: String
        /// The code owners every listed file in this folder shares, when there are any.
        public var owners: [String]
        public var files: [ChangedFile]
        public var id: String { folder }
    }

    public var groups: [Group]
    /// Files left out by `limit`, and their counts, for a "4 more files" row.
    public var hiddenFileCount: Int
    public var hiddenAdditions: Int
    public var hiddenDeletions: Int

    /// Groups `files` by folder. Folders keep the order of their first file, and files keep
    /// their order within a folder. With a `limit`, only the first that many files are grouped
    /// and the rest are counted.
    public init(files: [ChangedFile], codeOwners: [CodeOwnerMatch], limit: Int? = nil) {
        let shown = limit.map { Array(files.prefix($0)) } ?? files
        let hidden = files.dropFirst(shown.count)
        var order: [String] = []
        var byFolder: [String: [ChangedFile]] = [:]
        for file in shown {
            let folder = Self.folder(of: file.path)
            if byFolder[folder] == nil { order.append(folder) }
            byFolder[folder, default: []].append(file)
        }
        var ownersByPath: [String: [String]] = [:]
        for match in codeOwners {
            for path in match.paths { ownersByPath[path] = match.owners }
        }
        groups = order.map { folder in
            let folderFiles = byFolder[folder] ?? []
            let owners = folderFiles.map { ownersByPath[$0.path] ?? [] }
            let shared = owners.allSatisfy { $0 == owners.first } ? (owners.first ?? []) : []
            return Group(folder: folder, owners: shared, files: folderFiles)
        }
        hiddenFileCount = hidden.count
        hiddenAdditions = hidden.reduce(0) { $0 + $1.additions }
        hiddenDeletions = hidden.reduce(0) { $0 + $1.deletions }
    }

    /// `auth/session.ts` is in `auth/`. `CHANGELOG.md` is at the root, `""`.
    public static func folder(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "" }
        return String(path[...slash])
    }

    /// `auth/session.ts` is `session.ts`.
    public static func fileName(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return path }
        return String(path[path.index(after: slash)...])
    }
}

extension ChangedFile {
    /// The share of changed lines that are additions, from 0 to 1, for a bar. Nil when nothing
    /// changed line by line, as for a binary file or a pure rename.
    public var additionShare: Double? {
        let total = additions + deletions
        return total == 0 ? nil : Double(additions) / Double(total)
    }
}

// MARK: Checks

/// Checks in the order a reader needs them: what needs attention one by one, then the rest
/// collapsed by state into rows such as "12 passed".
public struct CheckGroups: Sendable, Hashable {
    /// Failed, then running, then queued, then cancelled. Within a state, in the pull request's order.
    public var attention: [Check]
    /// Passed, then skipped. Each has at least one check.
    public var collapsed: [Collapsed]

    public struct Collapsed: Sendable, Hashable, Identifiable {
        public var state: CheckState
        public var checks: [Check]
        public var id: CheckState { state }
        /// "12 passed".
        public var title: String { "\(checks.count) \(state.rawValue)" }
    }

    public static let attentionOrder: [CheckState] = [.failed, .running, .queued, .cancelled]
    public static let collapsedOrder: [CheckState] = [.passed, .skipped]

    public init(checks: [Check]) {
        attention = Self.attentionOrder.flatMap { state in checks.filter { $0.state == state } }
        collapsed = Self.collapsedOrder.compactMap { state in
            let matching = checks.filter { $0.state == state }
            return matching.isEmpty ? nil : Collapsed(state: state, checks: matching)
        }
    }

    /// What a check's row says after its name: "2 tests failed", "running 4 min", "queued".
    public static func detail(for check: Check, now: Date) -> String {
        switch check.state {
        case .failed:
            return check.failureSummary ?? "failed"
        case .running:
            guard let started = check.startedAt else { return "running" }
            let minutes = max(0, Int(now.timeIntervalSince(started) / 60))
            return minutes < 1 ? "running under 1 min" : "running \(minutes) min"
        case .passed, .skipped, .cancelled, .queued:
            if check.state == .passed, let duration = check.duration { return "passed in \(RelativeAge.duration(duration))" }
            return check.state.rawValue
        }
    }
}

// MARK: Reviewers

/// One row of the Reviewers block: a person who reviewed, or a person or team still asked.
public struct ReviewerRow: Sendable, Hashable, Identifiable {
    public enum State: Sendable, Hashable {
        case approved
        case changesRequested
        case commented
        /// Asked and not yet given.
        case requested
    }

    /// `@login` or `@org/team`.
    public var id: String
    public var name: String
    public var state: State
    /// The request names the viewer or one of the viewer's teams.
    public var isViewer: Bool
    public var isCodeOwnerRequest: Bool

    /// Each person's latest review, oldest first, then each review still asked for. A person
    /// asked again after reviewing shows as asked, once.
    public static func rows(for pr: PullRequest, viewer: Viewer) -> [ReviewerRow] {
        var latest: [String: Review] = [:]
        for review in pr.reviews where review.reviewer.login != pr.author.login {
            if let existing = latest[review.reviewer.login], existing.submittedAt > review.submittedAt { continue }
            latest[review.reviewer.login] = review
        }
        let requested = Set(pr.reviewRequests.map(\.reviewer.handle))
        let reviewed = latest.values
            .filter { !requested.contains($0.reviewer.handle) }
            .sorted { $0.submittedAt == $1.submittedAt ? $0.reviewer.login < $1.reviewer.login : $0.submittedAt < $1.submittedAt }
            .map { review in
                ReviewerRow(id: review.reviewer.handle, name: review.reviewer.displayName, state: State(review.state),
                            isViewer: viewer.isViewer(review.reviewer), isCodeOwnerRequest: false)
            }
        let asked = pr.reviewRequests.map { request in
            ReviewerRow(id: request.reviewer.handle, name: request.reviewer.displayName, state: .requested,
                        isViewer: request.isRequested(from: viewer), isCodeOwnerRequest: request.isCodeOwnerRequest)
        }
        return reviewed + asked
    }

    /// "approved", "changes requested", "commented", "requested", with ", you" for the viewer's request.
    public var stateText: String {
        let words: String = switch state {
        case .approved: "approved"
        case .changesRequested: "changes requested"
        case .commented: "commented"
        case .requested: "requested"
        }
        return state == .requested && isViewer ? words + ", you" : words
    }
}

extension ReviewerRow.State {
    init(_ state: ReviewState) {
        switch state {
        case .approved: self = .approved
        case .changesRequested: self = .changesRequested
        case .commented: self = .commented
        }
    }
}

// MARK: Threads

extension PullRequest {
    /// Every thread, unresolved first: current unresolved, then outdated unresolved, then
    /// resolved. Within each, in the pull request's order.
    public var threadsUnresolvedFirst: [ReviewThread] {
        let current = reviewThreads.filter { !$0.isResolved && !$0.isOutdated }
        let outdated = reviewThreads.filter { !$0.isResolved && $0.isOutdated }
        let resolved = reviewThreads.filter(\.isResolved)
        return current + outdated + resolved
    }
}

// MARK: Activity

/// The timeline as the Activity block shows it: people and agents first, newest first, with
/// bot events hidden until asked for.
public struct ActivityFeed: Sendable, Hashable {
    /// Newest first.
    public var events: [TimelineEvent]
    /// Events left out by the limit, people's or bots' as shown.
    public var hiddenEarlierCount: Int
    /// Bot events not shown, zero when bots are shown.
    public var hiddenBotCount: Int
    /// Every bot that has events, by login, in order of first event.
    public var botLogins: [String]

    public init(timeline: [TimelineEvent], showsBots: Bool, limit: Int? = nil) {
        let chosen = showsBots ? timeline : timeline.filter { !$0.isFromBot }
        let newestFirst = chosen.enumerated()
            .sorted { $0.element.occurredAt == $1.element.occurredAt ? $0.offset > $1.offset : $0.element.occurredAt > $1.element.occurredAt }
            .map(\.element)
        events = limit.map { Array(newestFirst.prefix($0)) } ?? newestFirst
        hiddenEarlierCount = newestFirst.count - events.count
        let bots = timeline.filter(\.isFromBot)
        hiddenBotCount = showsBots ? 0 : bots.count
        var logins: [String] = []
        for event in bots where !logins.contains(event.actor.login) { logins.append(event.actor.login) }
        botLogins = logins
    }
}

// MARK: Commits

extension PullRequest {
    /// Newest first.
    public var commitsNewestFirst: [Commit] {
        commits.enumerated()
            .sorted { $0.element.authoredAt == $1.element.authoredAt ? $0.offset > $1.offset : $0.element.authoredAt > $1.element.authoredAt }
            .map(\.element)
    }
}

// MARK: Merge

extension PullRequest {
    /// Why Merge cannot be pressed, as the line under the button says it, or nil when GitHub
    /// would merge it now. Such as "Merge is unavailable until checks pass".
    public var mergeUnavailableReason: String? {
        switch state {
        case .merged: return "Already merged"
        case .closed: return "Closed without merging"
        case .open: break
        }
        if isDraft { return "Merge is unavailable while this is a draft" }
        if let position = mergeState.mergeQueuePosition { return "In the merge queue, position \(position)" }
        let reasons = mergeState.blockedReasons
        if mergeState.mergeability == .conflicting || reasons.contains(.mergeConflicts) {
            return "Merge is unavailable until the conflicts are resolved"
        }
        if reasons.contains(.requiredChecksFailing) || reasons.contains(.requiredChecksPending) {
            return "Merge is unavailable until checks pass"
        }
        if reasons.contains(.changesRequested) { return "Merge is unavailable while changes are requested" }
        if reasons.contains(.codeOwnerReviewRequired) { return "Merge is unavailable until a code owner approves" }
        if reasons.contains(.reviewRequired) { return "Merge is unavailable until it is approved" }
        if reasons.contains(.unresolvedConversations) { return "Merge is unavailable until threads are resolved" }
        if reasons.contains(.behindBase) { return "Merge is unavailable until it is up to date with \(baseBranch)" }
        if reasons.contains(.draft) { return "Merge is unavailable while this is a draft" }
        if mergeState.mergeability == .unknown { return "Merge waits while GitHub checks for conflicts" }
        return nil
    }
}

// MARK: Freshness

/// How old what the page shows is, from each section's provenance.
public struct Freshness: Sendable, Hashable {
    public struct Section: Sendable, Hashable {
        public var section: PullRequestSection
        public var source: DataSource
        public var age: TimeInterval
    }

    /// Oldest first.
    public var sections: [Section]

    public init(provenance: Provenance, now: Date) {
        sections = PullRequestSection.allCases
            .map { Section(section: $0, source: provenance[$0].source, age: max(0, now.timeIntervalSince(provenance[$0].fetchedAt))) }
            .sorted { $0.age == $1.age ? $0.section.rawValue < $1.section.rawValue : $0.age > $1.age }
    }

    /// The oldest section's age: everything on the page is at least this fresh.
    public var oldestAge: TimeInterval { sections.first?.age ?? 0 }

    /// "Synced 3 min ago", by the oldest section, so it never claims more than is true.
    public var summary: String { "Synced \(RelativeAge.ago(oldestAge))" }

    /// One line per section, oldest first, such as "files: 3 min ago, local clone".
    public var details: [String] {
        sections.map { "\($0.section.rawValue): \(RelativeAge.ago($0.age)), \($0.source.displayName)" }
    }
}

// MARK: Time

/// Short ages and durations, as the blocks show them.
public enum RelativeAge {
    /// "4 s ago", "12 min ago", "2 h ago", "3 d ago".
    public static func ago(_ seconds: TimeInterval) -> String {
        "\(short(seconds)) ago"
    }

    /// The age of `date` seen from `now`.
    public static func ago(_ date: Date, now: Date) -> String {
        ago(max(0, now.timeIntervalSince(date)))
    }

    /// "4 s", "12 min", "2 h", "3 d".
    public static func short(_ seconds: TimeInterval) -> String {
        let seconds = max(0, Int(seconds))
        if seconds < 60 { return "\(seconds) s" }
        if seconds < 3600 { return "\(seconds / 60) min" }
        if seconds < 86_400 { return "\(seconds / 3600) h" }
        return "\(seconds / 86_400) d"
    }

    /// "47 s", "6 min 12 s", "1 h 5 min".
    public static func duration(_ seconds: TimeInterval) -> String {
        let seconds = max(0, Int(seconds))
        if seconds < 60 { return "\(seconds) s" }
        if seconds < 3600 {
            let rest = seconds % 60
            return rest == 0 ? "\(seconds / 60) min" : "\(seconds / 60) min \(rest) s"
        }
        let rest = (seconds % 3600) / 60
        return rest == 0 ? "\(seconds / 3600) h" : "\(seconds / 3600) h \(rest) min"
    }
}
