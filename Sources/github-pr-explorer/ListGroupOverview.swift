import GitHubPRExplorerCore
import SwiftUI

/// What the right side shows while a title row of the list is selected: an overview of the
/// pull requests the row holds, after Figma row 10.
///
/// Nothing on it has a fixed place: it is the blocks of an `OverviewLayout`, top to bottom,
/// today the built-in one, a summary and then the pull requests as cards. It reads the tree
/// the list draws, so it holds exactly the rows under the selected row, within the chosen
/// tab, a filter applied on it, and the search.
struct ListGroupOverview: View {
    @Bindable var model: AppModel
    let group: ListGroup
    var layout: OverviewLayout = .standard

    static let maximumWidth: CGFloat = 1400

    var body: some View {
        let overview = GroupOverview(group: group, in: model.listTree, viewer: model.index.viewer,
                                     status: model.status(for:))
        let context = OverviewContext(
            viewer: model.index.viewer, now: model.now, shorthands: model.shorthands,
            unnarrowedCount: model.unnarrowedCount(ofGroup: group.id),
            narrowedBy: model.narrowedBy,
            select: { model.listSelection = $0 })
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 28) {
                ForEach(Array(layout.blocks.enumerated()), id: \.offset) { _, placement in
                    OverviewBlockView(placement: placement, overview: overview, context: context)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 32)
            .frame(maxWidth: Self.maximumWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Style.pageBackground)
        .environment(\.shorthands, model.shorthands)
    }
}

/// What every overview block needs besides the overview.
struct OverviewContext {
    let viewer: Viewer
    /// The clock ages are measured from.
    let now: Date
    let shorthands: Shorthands
    /// How many the row would hold in the chosen tab's own saved filter, without the search
    /// and a filter applied on the tab, or nil when neither narrows the list.
    let unnarrowedCount: Int?
    /// What narrows it: "the search", "the applied filter", or both.
    let narrowedBy: String
    /// Selects a row of the list: a pull request, which opens its page, or a title row.
    let select: (ListSelection) -> Void
}

/// One block of the overview, as its layout places it.
struct OverviewBlockView: View {
    let placement: OverviewBlockPlacement
    let overview: GroupOverview
    let context: OverviewContext

    var body: some View {
        switch placement.kind {
        case .summary: OverviewSummaryBlock(overview: overview, size: placement.size, context: context)
        case .pullRequests: OverviewPullRequestsBlock(overview: overview, size: placement.size, context: context)
        }
    }
}

// MARK: Summary

/// The group's name, what kind of row it is and how many it holds, then a tile for how many
/// ask the viewer's review, one for how many of the viewer's own wait on them, and one for
/// each status. Small: the name and one line of counts.
struct OverviewSummaryBlock: View {
    let overview: GroupOverview
    let size: BlockSize
    let context: OverviewContext

    private var group: ListGroup { overview.group }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: size == .large ? 19 : 15))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                ShortenedName(name)
                    .font(.system(size: size == .large ? 26 : 19, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Text(summary)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            // An applied filter takes the place of the tab's own, so it can hold more than the
            // tab does. The line shows only when the row holds fewer, so it is never wrong.
            if let total = context.unnarrowedCount, group.count < total {
                Label {
                    Text("Narrowed by \(context.narrowedBy): \(group.count) of \(total) shown")
                } icon: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                .font(.system(size: 12))
                .foregroundStyle(Color.accentColor)
            }
            if size == .large {
                FlowLayout(spacing: 8) {
                    if overview.reviewsAskedOfViewerCount > 0 {
                        CountTile(count: overview.reviewsAskedOfViewerCount, label: "Your review", color: .accentColor,
                                  emphasized: true, help: "A review is asked of you or one of your teams")
                    }
                    if overview.viewersMoveCount > 0 {
                        CountTile(count: overview.viewersMoveCount, label: "Your move", color: .accentColor,
                                  help: "Yours, and waiting on you: to fix, answer, update or merge")
                    }
                    ForEach(overview.statusCounts) { entry in
                        CountTile(count: entry.count, label: entry.badge.label, color: entry.badge.tone.color,
                                  help: entry.badge.name)
                    }
                }
                .padding(.top, 10)
            } else {
                countsLine
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    /// "3 Your review · 2 Blocked · 1 Ready", for the small size.
    private var countsLine: some View {
        HStack(spacing: 10) {
            if overview.reviewsAskedOfViewerCount > 0 {
                CountBadge(count: overview.reviewsAskedOfViewerCount, label: "Your review", color: .accentColor)
            }
            if overview.viewersMoveCount > 0 {
                CountBadge(count: overview.viewersMoveCount, label: "Your move", color: .accentColor)
            }
            ForEach(overview.statusCounts) { CountBadge(count: $0.count, label: $0.badge.label, color: $0.badge.tone.color) }
        }
    }

    /// The group's name in full, or its shorthand with the full name on hover. Under its
    /// organization a repository's row says only "api", but here it says "acme/api".
    private var name: DisplayName {
        if group.property == .repository, let repository = group.pullRequests.first?.repository {
            return context.shorthands.name(for: repository)
        }
        return group.name
    }

    /// "Organization · 8 open pull requests in 3 repositories", or "Status · 4 open pull requests".
    private var summary: String {
        let count = "\(group.count) open pull request\(group.count == 1 ? "" : "s")"
        guard let level = overview.sectionProperty else { return "\(group.property.name) · \(count)" }
        let children = group.children.count
        return "\(group.property.name) · \(count) in \(children) \(level.countedName(children))"
    }

    private var symbol: String {
        switch group.property {
        case .organization: "building.2"
        case .repository: "folder"
        case .author: "person"
        case .status: "circle.dashed"
        case .reviewState: "checkmark.bubble"
        }
    }
}

extension ListGrouping.Property {
    /// "repository" or "repositories", for a count.
    func countedName(_ count: Int) -> String {
        let one = switch self {
        case .organization: "organization"
        case .repository: "repository"
        case .author: "author"
        case .status: "status"
        case .reviewState: "review state"
        }
        guard count != 1 else { return one }
        return switch self {
        case .repository: "repositories"
        case .status: "statuses"
        default: one + "s"
        }
    }
}

/// A count over a label, such as 3 over "Blocked" in red, as a small tile.
struct CountTile: View {
    let count: Int
    let label: String
    let color: Color
    var emphasized = false
    let help: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(count)")
                .font(.system(size: 20, weight: .semibold))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(color)
        }
        .frame(minWidth: 84, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: Style.cornerRadius)
            .fill(emphasized ? color.opacity(0.10) : Style.surface))
        .overlay(RoundedRectangle(cornerRadius: Style.cornerRadius)
            .strokeBorder(emphasized ? color.opacity(0.55) : Style.hairline, lineWidth: 1))
        .help(help)
        .accessibilityElement(children: .combine)
    }
}

/// A count and a label in a capsule of the label's color, such as "3 Blocked".
struct CountBadge: View {
    let count: Int
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Text("\(count)").monospacedDigit()
            Text(label)
        }
        .font(.system(size: 10.5, weight: .semibold))
        .foregroundStyle(color)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(color.opacity(0.13)))
        .accessibilityElement(children: .combine)
    }
}
