import GitHubPRExplorerCore
import SwiftUI

/// The overview's pull requests, as cards in a grid under a heading for each section: the
/// title rows one level down, or the statuses at the last level. The grids are lazy, so a
/// group of 200 builds only the cards on screen.
///
/// A click on a card selects its pull request in the list, which opens the rows above it, and
/// shows its page. A click on a section's heading selects that title row.
struct OverviewPullRequestsBlock: View {
    let overview: GroupOverview
    let size: BlockSize
    let context: OverviewContext

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 26) {
            ForEach(overview.sections) { section in
                VStack(alignment: .leading, spacing: 10) {
                    if let name = section.name {
                        SectionHeading(section: section, name: name, showsCounts: overview.sectionProperty.map { $0 != .status } ?? false,
                                       select: context.select)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: size == .large ? 270 : 220), spacing: 12, alignment: .top)],
                              alignment: .leading, spacing: 12) {
                        ForEach(section.cards) { card in
                            PullRequestCard(card: card, named: section.namedProperties, size: size, context: context)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A section's name and count, and for a title row one level down, its counts by status. A
/// click selects that row in the list.
private struct SectionHeading: View {
    let section: GroupOverview.Section
    let name: DisplayName
    let showsCounts: Bool
    let select: (ListSelection) -> Void

    var body: some View {
        if let id = section.groupID {
            Button { select(.group(id)) } label: { content }
                .buttonStyle(.plain)
                .help(name.isShortened ? "\(name.fullName): show its overview" : "Show its overview")
        } else {
            content
        }
    }

    private var content: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(verbatim: name.text)
                .font(.system(size: 15, weight: .semibold))
                .accessibilityLabel(name.accessibilityLabel)
            Text("\(section.cards.count)")
                .font(.system(size: 13))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            if showsCounts {
                HStack(spacing: 5) {
                    ForEach(section.statusCounts) { CountBadge(count: $0.count, label: $0.badge.label, color: $0.badge.tone.color) }
                }
                .padding(.leading, 6)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// One pull request as a card: the title and its badge, the number, author and age, the
/// status's detail, and at the foot whose move it is and how big the change is. A card that
/// asks the viewer's review is outlined in the accent color, since someone waits on them. The
/// viewer's own move shows as "Waits on you" in the accent color, without the outline, so a
/// page of the viewer's own pull requests is not all outlined. Small: the title, badge and number only.
struct PullRequestCard: View {
    let card: GroupOverview.Card
    /// What the section's heading and the rows above already say, so the card does not repeat it.
    let named: Set<ListGrouping.Property>
    let size: BlockSize
    let context: OverviewContext

    @State private var hovering = false

    private var pr: PullRequest { card.pullRequest }

    var body: some View {
        Button { context.select(.pullRequest(pr.id)) } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 8) {
                    Text(pr.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    StatusBadge(badge: card.status.badge)
                }
                .padding(.bottom, 4)
                referenceLine
                if size == .large {
                    Text(card.status.detail)
                        .font(Style.secondary)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    footer
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: Style.cornerRadius)
                .fill(hovering ? Color.primary.opacity(0.03) : Color.clear)
                .background(RoundedRectangle(cornerRadius: Style.cornerRadius).fill(Style.surface)))
            .overlay(RoundedRectangle(cornerRadius: Style.cornerRadius)
                .strokeBorder(card.asksViewersReview ? Color.accentColor.opacity(0.7) : Style.hairline,
                              lineWidth: card.asksViewersReview ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: Style.cornerRadius))
        }
        .buttonStyle(.plain)
        .opacity(pr.isDraft ? 0.75 : 1)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the pull request")
    }

    /// "#4715 · you · 2 h ago", with the repository in front when no heading names it, and
    /// without the author when the row above is the author. Shorthands take the place of the
    /// repository's and the author's names, with the full name on hover.
    private var referenceLine: some View {
        let shorthands = context.shorthands
        let repository: DisplayName? = if named.contains(.repository) {
            nil
        } else if shorthands.shorthand(.repository, for: pr.repository.fullName) != nil {
            shorthands.name(for: pr.repository)
        } else if named.contains(.organization) {
            DisplayName(text: pr.repository.name, fullName: pr.repository.fullName, isShortened: false)
        } else {
            DisplayName(pr.repository.fullName)
        }
        let author: DisplayName? = if named.contains(.author) {
            nil
        } else if context.viewer.isViewer(pr.author) {
            DisplayName("you")
        } else {
            shorthands.name(for: pr.author)
        }
        return HStack(spacing: 0) {
            if let repository {
                ShortenedName(repository).truncationMode(.middle)
                Text(verbatim: " ")
            }
            Text(verbatim: "#\(pr.number)").fixedSize()
            if let author {
                Text(verbatim: " · ").foregroundStyle(.tertiary)
                ShortenedName(author)
            }
            Text(verbatim: " · ").foregroundStyle(.tertiary)
            Text(verbatim: RelativeAge.ago(pr.updatedAt, now: context.now)).fixedSize()
        }
        .font(Style.secondary)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    /// Whose move it is, and the size of the change.
    private var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            NextMoveLabel(move: card.nextMove, viewer: context.viewer, shorthands: context.shorthands,
                          authorIsNamed: named.contains(.author))
            if card.asksViewersReview && !NextMoveLabel.includesViewer(card.nextMove, viewer: context.viewer) {
                Tag(text: "your review", color: .accentColor)
                    .help("A review is asked of you or one of your teams")
            }
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                Text(verbatim: "+\(pr.additions)").foregroundStyle(Style.added)
                Text(verbatim: "−\(pr.deletions)").foregroundStyle(Style.removed)
            }
            .font(.system(size: 11).monospacedDigit())
            .fixedSize()
            .help("\(pr.additions) lines added and \(pr.deletions) removed in \(pr.files.count) file\(pr.files.count == 1 ? "" : "s")")
        }
        .font(Style.secondary)
    }

    private var help: String {
        let checks = pr.checkSummary.total > 0 ? "\nChecks: \(pr.checkSummary.text)" : ""
        return "\(pr.title)\n\(pr.repository.fullName) #\(pr.number) by \(pr.author.displayName)\n\(card.status.text)"
            + "\nUpdated \(RelativeAge.ago(pr.updatedAt, now: context.now)), opened \(RelativeAge.ago(pr.createdAt, now: context.now))"
            + checks
    }
}

/// "Waits on Ada Park", "Waits on you", "Waits on Sam Rivera, @acme/security +1", "Waits on
/// CI". The viewer, or a team the viewer is on, is drawn in the accent color.
struct NextMoveLabel: View {
    let move: GroupOverview.NextMove
    let viewer: Viewer
    let shorthands: Shorthands
    /// The heading or the row above is the author, so "Waits on the author" says who.
    var authorIsNamed = false

    static let shownReviewers = 2

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            words
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(.secondary)
        .help(help)
    }

    private var symbol: String {
        switch move {
        case .author, .reviewers: "arrow.turn.down.right"
        case .checks: "circle.dotted"
        case .mergeQueue: "arrow.triangle.merge"
        case .github: "hourglass"
        case .nobody: "checkmark"
        }
    }

    private var words: Text {
        switch move {
        case .author(let person):
            if authorIsNamed && !viewer.isViewer(person) { return Text("Waits on the author") }
            return Text("Waits on \(name(person))")
        case .reviewers(let reviewers):
            guard !reviewers.isEmpty else { return Text("Waits on a reviewer") }
            let shown = reviewers.prefix(Self.shownReviewers).map(name)
            var joined = shown.dropFirst().reduce(shown[0]) { Text("\($0), \($1)") }
            if reviewers.count > Self.shownReviewers {
                joined = Text("\(joined) +\(reviewers.count - Self.shownReviewers)")
            }
            return Text("Waits on \(joined)")
        case .checks: return Text("Waits on CI")
        case .mergeQueue: return Text("In the merge queue")
        case .github: return Text("Waits on GitHub")
        case .nobody: return Text("Done")
        }
    }

    private func name(_ person: Person) -> Text {
        viewer.isViewer(person)
            ? Text("you").fontWeight(.semibold).foregroundStyle(Color.accentColor)
            : Text(verbatim: shorthands.name(for: person).text)
    }

    private func name(_ reviewer: RequestedReviewer) -> Text {
        switch reviewer {
        case .person(let person):
            return name(person)
        case .team(let team):
            let text = Text(verbatim: team.handle)
            return viewer.isMember(of: team) ? text.fontWeight(.semibold).foregroundStyle(Color.accentColor) : text
        }
    }

    /// Every name in full, since the line shows at most two and may use shorthands.
    private var help: String {
        switch move {
        case .author(let person): "Waits on the author, \(person.displayName) (\(person.handle))"
        case .reviewers(let reviewers):
            reviewers.isEmpty ? "Waits on a review, and nobody is asked yet"
                : "Waits on a review from " + reviewers.map { reviewer in
                    switch reviewer {
                    case .person(let person): "\(person.displayName) (\(person.handle))"
                    case .team(let team): team.handle
                    }
                }.joined(separator: ", ")
        case .checks: "Waits on checks that run or wait to run"
        case .mergeQueue: "In the merge queue"
        case .github: "Waits on GitHub to check for conflicts"
        case .nobody: "Merged or closed"
        }
    }

    /// Whether the line already names the viewer or one of the viewer's teams.
    static func includesViewer(_ move: GroupOverview.NextMove, viewer: Viewer) -> Bool {
        switch move {
        case .author(let person): viewer.isViewer(person)
        case .reviewers(let reviewers):
            reviewers.contains { reviewer in
                switch reviewer {
                case .person(let person): viewer.isViewer(person)
                case .team(let team): viewer.isMember(of: team)
                }
            }
        default: false
        }
    }
}
