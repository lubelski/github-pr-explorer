import Foundation

/// Where a pull request stands, as a symbol and one plain sentence, with every reason behind it.
///
/// State is always a symbol and words, never color alone.
///
/// Precedence, first match wins:
///
/// 1. **Merged** `✓`, then **Closed** `⊘`.
/// 2. **Draft** `○`. Nothing else matters until it is ready for review.
/// 3. **In the merge queue** `●`, with its position. It is out of the author's hands.
/// 4. **Blocked** `✕`, when something stops a merge outright: merge conflicts or a failed
///    required check. The sentence lists every blocker, adding changes requested and
///    unresolved threads when they also apply: "Blocked: e2e-chrome failed, 3 threads unresolved".
/// 5. **Changes requested** `✕`.
/// 6. **CI running** `●`, timed from the earliest running check: "CI running 12 min".
/// 7. **Checks queued** `●`, when checks wait and none runs.
/// 8. **A check that is not required failed** `◐`: "lint failed, not required". The check's
///    name is kept as written, so this sentence can start in lower case.
/// 9. **Threads unresolved** `◐`: "2 threads unresolved".
/// 10. **Waiting on reviewers** `◐`, counting pending requests, a team as one: "Waiting on 1 reviewer".
///     **Needs a review** `◐` when GitHub wants a review and none is requested.
/// 11. **Behind the base branch** `◐`: "Behind main".
/// 12. **Checking for conflicts** `◐`, while GitHub has not worked out mergeability.
/// 13. **Ready to merge** `✓`.
///
/// For any open pull request that is not a draft, when a review is requested from the viewer
/// or one of the viewer's teams, the sentence ends with "Review requested from you."
///
/// `reasons` lists every condition found, winning or not, in the order above.
public struct StatusSentence: Codable, Sendable, Hashable {
    public enum State: String, Codable, Sendable, Hashable, CaseIterable {
        case merged
        case closed
        case draft
        case inMergeQueue
        case blocked
        case changesRequested
        case checksRunning
        case checksQueued
        case optionalChecksFailed
        case threadsUnresolved
        case waitingOnReviewers
        case needsReview
        case behindBase
        case mergeabilityUnknown
        case readyToMerge
    }

    public enum Symbol: String, Codable, Sendable, Hashable, CaseIterable {
        case cross = "✕"
        case filledCircle = "●"
        case halfCircle = "◐"
        case emptyCircle = "○"
        case check = "✓"
        case slashedCircle = "⊘"
    }

    public var state: State
    public var symbol: Symbol
    /// The words, without the symbol. Such as "Blocked: e2e-chrome failed, 3 threads unresolved.
    /// Review requested from you."
    public var sentence: String
    public var reasons: [String]
    public var isReviewRequestedFromViewer: Bool
    /// What lies behind the state, for a line under the title where a badge already names the
    /// state: "e2e-chrome failed, 3 threads unresolved" beside "Blocked". It does not repeat the
    /// badge and leaves out "Review requested from you". See `init(pullRequest:viewer:now:)`.
    public var detail: String

    /// The symbol and the sentence, as a list row shows them.
    public var text: String { "\(symbol.rawValue) \(sentence)" }

    /// The short label for the state, such as "Blocked".
    public var badge: Badge { Badge(state) }

    /// `detail` defaults to the sentence.
    public init(state: State, symbol: Symbol, sentence: String, reasons: [String], isReviewRequestedFromViewer: Bool,
                detail: String? = nil) {
        self.state = state
        self.symbol = symbol
        self.sentence = sentence
        self.reasons = reasons
        self.isReviewRequestedFromViewer = isReviewRequestedFromViewer
        self.detail = detail ?? sentence
    }

    /// Works out the status. `now` times running checks, so the result never reads the clock.
    ///
    /// The detail is the headline, except where the headline would only repeat the badge:
    /// blocked lists its blockers alone, a draft lists what else was found ("Not ready for
    /// review" when nothing was), the merge queue gives the position, and ready to merge says
    /// how it got there ("Approved, 3 checks passed").
    public init(pullRequest pr: PullRequest, viewer: Viewer, now: Date) {
        switch pr.state {
        case .merged:
            self.init(state: .merged, symbol: .check, sentence: "Merged", reasons: [], isReviewRequestedFromViewer: false)
            return
        case .closed:
            self.init(state: .closed, symbol: .slashedCircle, sentence: "Closed without merging", reasons: [], isReviewRequestedFromViewer: false)
            return
        case .open:
            break
        }

        let facts = Facts(pr: pr, viewer: viewer, now: now)
        let state: State
        let symbol: Symbol
        let headline: String
        var detail: String?

        if pr.isDraft {
            (state, symbol, headline) = (.draft, .emptyCircle, "Draft")
            let others = facts.reasons.filter { $0 != "draft" && $0 != Facts.requestedFromViewerReason }
            detail = others.isEmpty ? "Not ready for review" : Self.firstWordCapitalized(others).joined(separator: ", ")
        } else if let position = pr.mergeState.mergeQueuePosition {
            (state, symbol, headline) = (.inMergeQueue, .filledCircle, "In the merge queue, position \(position)")
            detail = "Position \(position) in the merge queue"
        } else if facts.hasConflicts || !facts.failedRequired.isEmpty {
            var blockers: [String] = []
            if facts.hasConflicts { blockers.append(Facts.conflictsReason) }
            if !facts.failedRequired.isEmpty { blockers.append(facts.failedRequiredReason) }
            if facts.hasChangesRequested { blockers.append(Facts.changesRequestedReason) }
            if facts.unresolvedCount > 0 { blockers.append(facts.unresolvedReason) }
            (state, symbol, headline) = (.blocked, .cross, "Blocked: " + blockers.joined(separator: ", "))
            detail = Self.firstWordCapitalized(blockers).joined(separator: ", ")
        } else if facts.hasChangesRequested {
            (state, symbol, headline) = (.changesRequested, .cross, "Changes requested")
        } else if let minutes = facts.runningMinutes {
            (state, symbol, headline) = (.checksRunning, .filledCircle, "CI " + Facts.runningPhrase(minutes))
        } else if facts.queuedCount > 0 {
            (state, symbol, headline) = (.checksQueued, .filledCircle, "Checks queued")
        } else if !facts.failedOptional.isEmpty {
            (state, symbol, headline) = (.optionalChecksFailed, .halfCircle, facts.failedOptionalReason)
        } else if facts.unresolvedCount > 0 {
            (state, symbol, headline) = (.threadsUnresolved, .halfCircle, facts.unresolvedReason.capitalizedFirst)
        } else if facts.pendingReviewerCount > 0 {
            (state, symbol, headline) = (.waitingOnReviewers, .halfCircle, facts.waitingReason.capitalizedFirst)
        } else if pr.reviewDecision == .reviewRequired {
            (state, symbol, headline) = (.needsReview, .halfCircle, "Needs a review")
        } else if pr.mergeState.isBehindBase {
            (state, symbol, headline) = (.behindBase, .halfCircle, "Behind \(pr.baseBranch)")
        } else if pr.mergeState.mergeability == .unknown {
            (state, symbol, headline) = (.mergeabilityUnknown, .halfCircle, "Checking for conflicts")
        } else {
            (state, symbol, headline) = (.readyToMerge, .check, "Ready to merge")
            let review = pr.reviewDecision == .approved ? "Approved" : "No review required"
            let passed = pr.checks.count { $0.state == .passed }
            let checks = passed == 0 ? "no checks" : "\(passed) \(passed == 1 ? "check" : "checks") passed"
            detail = review + ", " + checks
        }

        let asksViewer = !pr.isDraft && facts.isRequestedFromViewer
        let sentence = asksViewer ? headline + ". " + Facts.requestedFromViewerSentence : headline
        self.init(state: state, symbol: symbol, sentence: sentence, reasons: facts.reasons,
                  isReviewRequestedFromViewer: asksViewer, detail: detail ?? headline)
    }

    /// Capitalizes the first phrase when it is one of the fixed ones, such as "merge conflicts".
    /// A check's name is kept as written, so "e2e-chrome failed" stays in lower case.
    private static func firstWordCapitalized(_ phrases: [String]) -> [String] {
        guard let first = phrases.first, Facts.fixedPhrases.contains(where: first.hasPrefix) else { return phrases }
        return [first.capitalizedFirst] + phrases.dropFirst()
    }

    /// The conditions the precedence reads, worked out once.
    private struct Facts {
        static let conflictsReason = "merge conflicts"
        static let changesRequestedReason = "changes requested"
        static let requestedFromViewerSentence = "Review requested from you."
        static let requestedFromViewerReason = "review requested from you"
        /// Phrases this type writes itself, which may start a detail with a capital letter.
        /// Anything else at the start is a check's name.
        static let fixedPhrases = [conflictsReason, changesRequestedReason, "in the merge queue", "waiting on",
                                   "needs a review", "behind ", "checking for conflicts", "draft"]

        let pr: PullRequest
        let now: Date
        let hasConflicts: Bool
        let failedRequired: [Check]
        let failedOptional: [Check]
        let running: [Check]
        let runningMinutes: Int?
        let queuedCount: Int
        let hasChangesRequested: Bool
        let unresolvedCount: Int
        let pendingReviewerCount: Int
        let isRequestedFromViewer: Bool

        init(pr: PullRequest, viewer: Viewer, now: Date) {
            self.pr = pr
            self.now = now
            hasConflicts = pr.mergeState.mergeability == .conflicting
            failedRequired = pr.checks.filter { $0.state == .failed && $0.isRequired }
            failedOptional = pr.checks.filter { $0.state == .failed && !$0.isRequired }
            running = pr.checks.filter { $0.state == .running }
            let earliestStart = running.compactMap(\.startedAt).min()
            if running.isEmpty {
                runningMinutes = nil
            } else if let earliestStart {
                runningMinutes = max(0, Int(now.timeIntervalSince(earliestStart) / 60))
            } else {
                runningMinutes = 0
            }
            queuedCount = pr.checks.count { $0.state == .queued }
            hasChangesRequested = pr.reviewDecision == .changesRequested
            unresolvedCount = pr.reviewThreads.count { !$0.isResolved }
            pendingReviewerCount = pr.reviewRequests.count
            isRequestedFromViewer = pr.isReviewRequested(from: viewer)
        }

        var failedRequiredReason: String { Self.failedPhrase(failedRequired, kind: "required checks") }
        var failedOptionalReason: String { Self.failedPhrase(failedOptional, kind: "checks") + ", not required" }
        var unresolvedReason: String { "\(unresolvedCount) \(unresolvedCount == 1 ? "thread" : "threads") unresolved" }
        var waitingReason: String { "waiting on \(pendingReviewerCount) \(pendingReviewerCount == 1 ? "reviewer" : "reviewers")" }

        var reasons: [String] {
            var reasons: [String] = []
            if pr.isDraft { reasons.append("draft") }
            if let position = pr.mergeState.mergeQueuePosition { reasons.append("in the merge queue, position \(position)") }
            if hasConflicts { reasons.append(Self.conflictsReason) }
            reasons.append(contentsOf: failedRequired.map { "\($0.name) failed" })
            if hasChangesRequested { reasons.append(Self.changesRequestedReason) }
            reasons.append(contentsOf: running.map { check in
                guard let startedAt = check.startedAt else { return "\(check.name) running" }
                return "\(check.name) " + Self.runningPhrase(max(0, Int(now.timeIntervalSince(startedAt) / 60)))
            })
            if queuedCount > 0 { reasons.append("\(queuedCount) \(queuedCount == 1 ? "check" : "checks") queued") }
            reasons.append(contentsOf: failedOptional.map { "\($0.name) failed, not required" })
            if unresolvedCount > 0 { reasons.append(unresolvedReason) }
            reasons.append(contentsOf: pr.reviewRequests.map { "waiting on \($0.reviewer.handle)" })
            if pendingReviewerCount == 0 && pr.reviewDecision == .reviewRequired { reasons.append("needs a review") }
            if pr.mergeState.isBehindBase { reasons.append("behind \(pr.baseBranch)") }
            if pr.mergeState.mergeability == .unknown { reasons.append("checking for conflicts") }
            if isRequestedFromViewer { reasons.append(Self.requestedFromViewerReason) }
            return reasons
        }

        static func failedPhrase(_ checks: [Check], kind: String) -> String {
            switch checks.count {
            case 1: "\(checks[0].name) failed"
            case 2: "\(checks[0].name) and \(checks[1].name) failed"
            default: "\(checks.count) \(kind) failed"
            }
        }

        static func runningPhrase(_ minutes: Int) -> String {
            minutes < 1 ? "running under 1 min" : "running \(minutes) min"
        }
    }
}

extension StatusSentence {
    /// The state in one short word or two, for a badge beside a list row and for the list's
    /// status filter. Several states share a badge where the difference is in the detail line:
    /// CI running and checks queued are both "Running", and waiting on reviewers and needing a
    /// review are both "Waiting". The cases are in the status sentence's precedence order.
    public enum Badge: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
        case draft
        case merging
        case blocked
        case changesRequested
        case running
        case failing
        case threads
        case waiting
        case behind
        case checking
        case ready
        case merged
        case closed

        /// How a badge is colored. The words carry the meaning, the color only helps.
        public enum Tone: String, Codable, Sendable, Hashable, CaseIterable {
            /// Can be merged: green.
            case positive
            /// Stopped until someone acts: red.
            case negative
            /// Something is under way: blue.
            case progress
            /// Not stopped, but something needs a look: orange.
            case attention
            /// Not in play: gray.
            case neutral
            /// Merged: purple, as GitHub shows it.
            case done
        }

        public var id: String { rawValue }

        public init(_ state: State) {
            self = switch state {
            case .merged: .merged
            case .closed: .closed
            case .draft: .draft
            case .inMergeQueue: .merging
            case .blocked: .blocked
            case .changesRequested: .changesRequested
            case .checksRunning, .checksQueued: .running
            case .optionalChecksFailed: .failing
            case .threadsUnresolved: .threads
            case .waitingOnReviewers, .needsReview: .waiting
            case .behindBase: .behind
            case .mergeabilityUnknown: .checking
            case .readyToMerge: .ready
            }
        }

        /// The badge's text, at most eight letters.
        public var label: String {
            switch self {
            case .draft: "Draft"
            case .merging: "Merging"
            case .blocked: "Blocked"
            case .changesRequested: "Changes"
            case .running: "Running"
            case .failing: "Failing"
            case .threads: "Threads"
            case .waiting: "Waiting"
            case .behind: "Behind"
            case .checking: "Checking"
            case .ready: "Ready"
            case .merged: "Merged"
            case .closed: "Closed"
            }
        }

        /// A longer name, for the status filter's menu and for tooltips.
        public var name: String {
            switch self {
            case .draft: "Draft"
            case .merging: "In the merge queue"
            case .blocked: "Blocked"
            case .changesRequested: "Changes requested"
            case .running: "CI running or queued"
            case .failing: "A check that is not required failed"
            case .threads: "Threads unresolved"
            case .waiting: "Waiting on a review"
            case .behind: "Behind the base branch"
            case .checking: "Checking for conflicts"
            case .ready: "Ready to merge"
            case .merged: "Merged"
            case .closed: "Closed"
            }
        }

        public var tone: Tone {
            switch self {
            case .ready: .positive
            case .blocked, .changesRequested: .negative
            case .running, .merging: .progress
            case .failing, .threads, .waiting, .behind, .checking: .attention
            case .draft, .closed: .neutral
            case .merged: .done
            }
        }

        /// The states that show this badge.
        public var states: [State] { State.allCases.filter { Badge($0) == self } }
    }
}

extension StringProtocol {
    var capitalizedFirst: String {
        guard let first else { return "" }
        return first.uppercased() + dropFirst()
    }
}

extension PullRequest {
    public func statusSentence(for viewer: Viewer, now: Date) -> StatusSentence {
        StatusSentence(pullRequest: self, viewer: viewer, now: now)
    }
}
