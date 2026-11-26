import Foundation
import GitHubPRExplorerCore

/// The readable form of `pull-request show`: every section of one pull request.
enum PullRequestReport {
    static func text(for pr: PullRequest, viewer: Viewer, now: Date) -> String {
        var out: [String] = []
        let status = pr.statusSentence(for: viewer, now: now)
        func section(_ title: String) { out.append(""); out.append(title) }
        func row(_ label: String, _ value: String) { out.append("  \(label.padding(toLength: 11, withPad: " ", startingAt: 0)) \(value)") }

        out.append("\(pr.reference)  \(pr.title)")
        out.append(status.text)
        if !status.reasons.isEmpty { out.append("Reasons: " + status.reasons.joined(separator: "; ")) }

        section("Summary")
        row("Author", person(pr.author))
        row("State", pr.state.rawValue + (pr.isDraft ? ", draft" : ""))
        row("Branches", "\(pr.headBranch) → \(pr.baseBranch)")
        row("Head", String(pr.headCommitID.prefix(7)))
        row("Created", iso(pr.createdAt))
        row("Updated", iso(pr.updatedAt))
        if let mergedAt = pr.mergedAt { row("Merged", iso(mergedAt)) }
        if let closedAt = pr.closedAt, pr.mergedAt == nil { row("Closed", iso(closedAt)) }
        row("Changes", "+\(pr.additions) −\(pr.deletions) in \(pr.files.count) \(plural(pr.files.count, "file")), \(pr.commits.count) \(plural(pr.commits.count, "commit"))")
        row("Labels", pr.labels.isEmpty ? "none" : pr.labels.map(\.name).joined(separator: ", "))
        row("Milestone", pr.milestone.map { $0.title + ($0.dueOn.map { ", due \(day($0))" } ?? "") } ?? "none")
        row("Linked", pr.linkedIssues.isEmpty ? "none" : pr.linkedIssues.map {
            "\($0.repository.fullName)#\($0.number) \($0.title)\($0.isClosed ? " (closed)" : "")"
        }.joined(separator: "; "))
        row("Assignees", pr.assignees.isEmpty ? "none" : pr.assignees.map(\.displayName).joined(separator: ", "))

        section("Description")
        if pr.body.isEmpty {
            out.append("  (empty)")
        } else {
            out.append(contentsOf: pr.body.split(separator: "\n", omittingEmptySubsequences: false).map { $0.isEmpty ? "" : "  \($0)" })
        }

        section("Checks: \(pr.checkSummary.text)")
        let order = Dictionary(uniqueKeysWithValues: CheckSummary.displayOrder.enumerated().map { ($1, $0) })
        let sortedChecks = pr.checks.enumerated().sorted { (order[$0.element.state] ?? 0, $0.offset) < (order[$1.element.state] ?? 0, $1.offset) }
        for (_, check) in sortedChecks {
            var line = "  \(checkSymbol(check.state)) \(check.name)\(check.isRequired ? " (required)" : "") \(check.state.rawValue)"
            if let duration = check.duration { line += " in \(durationText(duration))" }
            if check.state == .running, let started = check.startedAt { line += " for \(durationText(now.timeIntervalSince(started)))" }
            if let failure = check.failureSummary { line += ": \(failure)" }
            out.append(line)
        }

        section("Reviews: \(pr.reviewDecision.map(decisionText) ?? "no review required")")
        for review in pr.reviews {
            out.append("  \(review.reviewer.displayName) \(reviewText(review.state)) at \(iso(review.submittedAt))" + (review.body.isEmpty ? "" : ": \(review.body)"))
        }
        for request in pr.reviewRequests {
            let you = request.isRequested(from: viewer) ? " (you)" : ""
            out.append("  \(request.reviewer.handle)\(you) requested, pending\(request.isCodeOwnerRequest ? ", as code owner" : "")")
        }
        if pr.reviews.isEmpty && pr.reviewRequests.isEmpty { out.append("  No reviews and no reviewers.") }

        section("Merge state")
        let merge = pr.mergeState
        row("Mergeable", merge.mergeability.rawValue)
        row("Base", merge.isBehindBase ? "behind \(pr.baseBranch)" : "up to date with \(pr.baseBranch)")
        if let position = merge.mergeQueuePosition { row("Queue", "position \(position)") }
        row("Blocked by", merge.blockedReasons.isEmpty ? "nothing" : merge.blockedReasons.map(\.rawValue).joined(separator: ", "))

        section("Code owners")
        if pr.codeOwners.isEmpty { out.append("  No code owners for these files.") }
        for match in pr.codeOwners {
            out.append("  \(match.pattern) → \(match.owners.joined(separator: ", ")): \(match.paths.joined(separator: ", "))")
        }

        section("Files (\(pr.files.count))")
        for file in pr.files {
            var line = "  \(fileKindLetter(file.changeKind)) \(file.path)"
            if let previous = file.previousPath { line += " (from \(previous))" }
            line += file.isBinary ? " binary" : " +\(file.additions) −\(file.deletions)"
            out.append(line)
        }

        section("Commits (\(pr.commits.count))")
        for commit in pr.commits {
            out.append("  \(commit.shortID) \(commit.subject) (\(commit.author.displayName), \(iso(commit.authoredAt)))")
        }

        let needingYou = pr.threadsNeedingAttention(from: viewer)
        section("Threads (\(pr.reviewThreads.count), \(pr.unresolvedThreads.count) unresolved, \(needingYou.count) \(needingYou.count == 1 ? "needs" : "need") you)")
        for thread in pr.reviewThreads {
            var flags: [String] = [thread.isResolved ? "resolved" : "unresolved"]
            if thread.isOutdated { flags.append("outdated") }
            if needingYou.contains(where: { $0.id == thread.id }) { flags.append("needs you") }
            out.append("  \(thread.path):\(thread.line)\(thread.side == .left ? " (old)" : "") [\(flags.joined(separator: ", "))]")
            out.append("    > \(thread.quotedLine.trimmingCharacters(in: .whitespaces))")
            for comment in thread.comments {
                out.append("    \(comment.author.displayName): \(comment.body)")
            }
        }

        section("Comments (\(pr.comments.count))")
        for comment in pr.comments {
            let firstLine = comment.body.split(separator: "\n").first.map(String.init) ?? ""
            out.append("  \(comment.author.login)\(comment.author.isBot ? " (bot)" : "") at \(iso(comment.createdAt)): \(firstLine)")
        }

        let human = pr.humanTimelineEvents.count, bots = pr.botTimelineEvents.count
        section("Timeline (\(pr.timeline.count) events: \(human) from people, \(bots) from bots)")
        for event in pr.timeline {
            out.append("  \(iso(event.occurredAt)) \(event.isFromBot ? "[bot] " : "")\(event.summary)")
        }

        section("Sources")
        for name in PullRequestSection.allCases {
            let stamp = pr.provenance[name]
            row(name.rawValue, "\(stamp.source.displayName), fetched \(age(now.timeIntervalSince(stamp.fetchedAt))) ago")
        }
        return out.joined(separator: "\n") + "\n"
    }

    // MARK: Formatting

    static func iso(_ date: Date) -> String { date.formatted(.iso8601) }

    static func day(_ date: Date) -> String { String(iso(date).prefix(10)) }

    static func person(_ person: Person) -> String {
        var text = "\(person.displayName) (\(person.login))"
        if person.isBot { text += ", bot" }
        if person.isAgent { text += ", agent" }
        return text
    }

    static func plural(_ count: Int, _ word: String) -> String { count == 1 ? word : word + "s" }

    static func durationText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let minutes = total / 60, rest = total % 60
        if minutes == 0 { return "\(rest)s" }
        return rest == 0 ? "\(minutes)m" : "\(minutes)m \(rest)s"
    }

    static func age(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        if total < 60 { return "\(total) s" }
        if total < 3600 { return "\(total / 60) min" }
        return "\(total / 3600) h"
    }

    static func checkSymbol(_ state: CheckState) -> String {
        switch state {
        case .failed: "✕"
        case .running: "●"
        case .queued: "○"
        case .passed: "✓"
        case .skipped: "–"
        case .cancelled: "⊘"
        }
    }

    static func decisionText(_ decision: ReviewDecision) -> String {
        switch decision {
        case .approved: "approved"
        case .changesRequested: "changes requested"
        case .reviewRequired: "review required"
        }
    }

    static func reviewText(_ state: ReviewState) -> String {
        switch state {
        case .approved: "approved"
        case .changesRequested: "requested changes"
        case .commented: "commented"
        }
    }

    static func fileKindLetter(_ kind: FileChangeKind) -> String {
        switch kind {
        case .added: "A"
        case .modified: "M"
        case .removed: "D"
        case .renamed: "R"
        }
    }
}
