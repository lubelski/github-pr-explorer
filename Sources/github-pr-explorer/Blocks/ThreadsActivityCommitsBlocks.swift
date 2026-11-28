import GitHubPRExplorerCore
import SwiftUI

/// Review conversations, unresolved first: where, who started it, and what they said. Threads
/// waiting on the viewer say "needs you".
struct ThreadsBlock: View {
    let pullRequest: PullRequest
    let size: BlockSize
    let context: BlockContext
    @Environment(\.pageActions) private var actions
    @Environment(\.shorthands) private var shorthands

    var body: some View {
        let threads = pullRequest.threadsUnresolvedFirst
        let needing = Set(pullRequest.threadsNeedingAttention(from: context.viewer).map(\.id))
        if threads.isEmpty {
            EmptyBlockText("No review threads.")
        } else if size == .small {
            let unresolved = pullRequest.unresolvedThreads.count
            Text("\(unresolved) unresolved · \(needing.count) \(needing.count == 1 ? "needs" : "need") you")
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(threads.enumerated()), id: \.element.id) { index, thread in
                    if index > 0 { Divider() }
                    row(thread, needsViewer: needing.contains(thread.id))
                }
            }
        }
    }

    private func row(_ thread: ReviewThread, needsViewer: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(verbatim: "\(thread.path):\(thread.line)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tint)
                    .lineLimit(1)
                    .truncationMode(.head)
                if needsViewer { Tag(text: "needs you", color: .accentColor) }
                if thread.isOutdated { Tag(text: "outdated") }
                if thread.isResolved { Tag(text: "resolved") }
                Spacer(minLength: 8)
                if let author = thread.startedBy {
                    ShortenedName(shorthands.name(for: author)).font(Style.secondary).foregroundStyle(.secondary)
                }
            }
            if let first = thread.comments.first {
                Text(inlineMarkdown(first.body))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if thread.comments.count > 1, let last = thread.lastComment {
                let replies = thread.comments.count - 1
                let lastName = shorthands.name(for: last.author)
                Text("\(replies) \(replies == 1 ? "reply" : "replies"), last by \(lastName.text)")
                    .optionalHelp(lastName.help)
                    .font(Style.secondary)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .opacity(thread.isResolved ? 0.65 : 1)
        .contentShape(.rect)
        .onTapGesture { if canOpen(thread) { actions.showThread?(thread.id) } }
        .help(canOpen(thread) ? "Open this thread beside its line in the diff" : "")
        .accessibilityAddTraits(canOpen(thread) ? .isButton : [])
    }

    /// A thread opens over its file's diff, so its file has to be in the pull request.
    private func canOpen(_ thread: ReviewThread) -> Bool {
        actions.showThread != nil && pullRequest.paneStack(showingThread: thread.id) != nil
    }
}

/// The timeline, people first and newest first. Bot events are hidden behind one row.
struct ActivityBlock: View {
    static let limit = 5

    let pullRequest: PullRequest
    let size: BlockSize
    let context: BlockContext
    @State private var showsBots = false
    @State private var showsAll = false
    @Environment(\.previewExpandsBlocks) private var previewExpands
    /// `hidesBotEventsInActivity` in `settings.json`.
    @Environment(\.hidesBotEventsInActivity) private var hidesBots
    @Environment(\.shorthands) private var shorthands

    var body: some View {
        if pullRequest.timeline.isEmpty {
            EmptyBlockText("Nothing has happened yet.")
        } else if size == .small {
            let feed = ActivityFeed(timeline: pullRequest.timeline, showsBots: false, limit: 1)
            VStack(alignment: .leading, spacing: 3) {
                if let event = feed.events.first {
                    HStack {
                        summary(event).lineLimit(1)
                        Spacer(minLength: 8)
                        age(event)
                    }
                }
                if feed.hiddenBotCount > 0 {
                    Text("\(botCount(feed.hiddenBotCount)) hidden").font(Style.secondary).foregroundStyle(.secondary)
                }
            }
        } else {
            large
                .onAppear {
                    showsBots = !hidesBots
                    if previewExpands { showsAll = true; showsBots = true }
                }
                .onChange(of: hidesBots) { _, hides in showsBots = !hides }
        }
    }

    private var large: some View {
        let feed = ActivityFeed(timeline: pullRequest.timeline, showsBots: showsBots, limit: showsAll ? nil : Self.limit)
        let hasBots = !pullRequest.botTimelineEvents.isEmpty
        return LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(feed.events) { event in
                HStack(alignment: .firstTextBaseline) {
                    summary(event)
                        .opacity(event.isFromBot ? 0.75 : 1)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    age(event)
                }
                .padding(.vertical, 4)
            }
            if feed.hiddenEarlierCount > 0 {
                footerRow {
                    Text("\(feed.hiddenEarlierCount) earlier \(feed.hiddenEarlierCount == 1 ? "event" : "events")").foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.secondary)
                    LinkButton(title: "Show") { showsAll = true }
                }
            }
            if hasBots {
                Divider().padding(.top, 6)
                footerRow {
                    if showsBots {
                        Text("Showing \(botCount(pullRequest.botTimelineEvents.count))").foregroundStyle(.secondary)
                        Text("·").foregroundStyle(.secondary)
                        LinkButton(title: "Hide") { showsBots = false }
                    } else {
                        Text("\(botCount(feed.hiddenBotCount)) hidden").foregroundStyle(.secondary)
                            .help("From " + feed.botLogins.map { shorthands.name(forLogin: $0).text }.joined(separator: ", "))
                        Text("·").foregroundStyle(.secondary)
                        LinkButton(title: "Show") { showsBots = true }
                    }
                }
            }
        }
    }

    private func footerRow(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: 4) { content() }
            .padding(.top, 6)
    }

    private func botCount(_ count: Int) -> String { count == 1 ? "1 bot event" : "\(count) bot events" }

    /// The actor's name in bold, with its shorthand, then the rest of the line. A shortened
    /// name shows the full name on hover.
    private func summary(_ event: TimelineEvent) -> some View {
        let line = shorthands.activityLine(event)
        let text = line.actor.map { Text("\(Text(verbatim: $0.text).fontWeight(.semibold))\(line.rest)") } ?? Text(event.summary)
        return text.optionalHelp(line.actor?.help)
    }

    private func age(_ event: TimelineEvent) -> some View {
        Text(RelativeAge.ago(event.occurredAt, now: context.now))
            .font(Style.secondary)
            .foregroundStyle(.secondary)
            .fixedSize()
    }
}

/// The commits on the branch, newest first.
struct CommitsBlock: View {
    static let limit = 5

    let pullRequest: PullRequest
    let size: BlockSize
    let context: BlockContext
    @State private var showsAll = false

    var body: some View {
        let commits = pullRequest.commitsNewestFirst
        if commits.isEmpty {
            EmptyBlockText("No commits.")
        } else if size == .small {
            Text("\(commits.count == 1 ? "1 commit" : "\(commits.count) commits") · last \(RelativeAge.ago(commits[0].authoredAt, now: context.now))")
        } else {
            let shown = showsAll ? commits : Array(commits.prefix(Self.limit))
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(shown) { commit in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(commit.shortID)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(commit.subject).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(RelativeAge.short(context.now.timeIntervalSince(commit.authoredAt)))
                            .font(Style.secondary)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                    .help(commit.message)
                }
                if shown.count < commits.count {
                    HStack(spacing: 4) {
                        Text("\(commits.count - shown.count) earlier commits").foregroundStyle(.secondary)
                        Text("·").foregroundStyle(.secondary)
                        LinkButton(title: "Show") { showsAll = true }
                    }
                    .padding(.top, 6)
                }
            }
        }
    }
}

/// Labels, milestone, linked issues, branches and assignees.
struct LabelsAndMetadataBlock: View {
    let pullRequest: PullRequest
    let size: BlockSize
    @Environment(\.shorthands) private var shorthands

    var body: some View {
        let pr = pullRequest
        if size == .small {
            if pr.labels.isEmpty {
                EmptyBlockText("No labels.")
            } else {
                labels
            }
        } else {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 7) {
                GridRow {
                    key("Labels")
                    if pr.labels.isEmpty { Text("None").foregroundStyle(.secondary) } else { labels }
                }
                GridRow {
                    key("Milestone")
                    Text(pr.milestone?.title ?? "None").foregroundStyle(pr.milestone == nil ? .secondary : .primary)
                }
                GridRow {
                    key("Linked issues")
                    if pr.linkedIssues.isEmpty {
                        Text("None").foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(pr.linkedIssues, id: \.self) { issue in
                                let repository = shorthands.name(for: issue.repository)
                                Text(verbatim: "\(repository.text)#\(issue.number) \(issue.title)").lineLimit(1)
                                    .optionalHelp(repository.isShortened ? "\(issue.repository.fullName)#\(issue.number) \(issue.title)" : nil)
                            }
                        }
                    }
                }
                GridRow {
                    key("Branches")
                    Text(verbatim: "\(pr.headBranch) → \(pr.baseBranch)").font(.system(size: 12, design: .monospaced))
                }
                GridRow {
                    key("Assignees")
                    let assignees = pr.assignees.map(shorthands.name(for:))
                    Text(verbatim: pr.assignees.isEmpty ? "None" : assignees.map(\.text).joined(separator: ", "))
                        .foregroundStyle(pr.assignees.isEmpty ? .secondary : .primary)
                        .optionalHelp(assignees.contains(where: \.isShortened) ? assignees.map(\.fullName).joined(separator: "\n") : nil)
                }
                GridRow {
                    key("Author")
                    ShortenedName(shorthands.name(for: pr.author))
                }
            }
        }
    }

    private var labels: some View {
        FlowLayout(spacing: 4) {
            ForEach(pullRequest.labels, id: \.name) { label in
                Text(label.name)
                    .font(.system(size: 11))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 1.5)
                    .overlay(Capsule().strokeBorder(Style.hairline))
            }
        }
    }

    private func key(_ text: String) -> some View {
        Text(text).font(Style.secondary).foregroundStyle(.secondary).gridColumnAlignment(.leading)
    }
}

/// Lays views left to right and wraps them onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrange(width: bounds.width, subviews: subviews)
        for (subview, origin) in zip(subviews, arrangement.origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (CGSize(width: widest, height: y + lineHeight), origins)
    }
}
