import GitHubPRExplorerCore
import SwiftUI

/// One pull request: a fixed header, a tab strip when the layout has more than one tab, the
/// selected tab's blocks in columns, and a footer with freshness and the layout menu.
struct PullRequestPage: View {
    @Bindable var model: AppModel
    let pullRequest: PullRequest

    var body: some View {
        let layout = model.layout
        let tabIndex = model.currentTabIndex
        VStack(spacing: 0) {
            PageHeader(model: model, pullRequest: pullRequest)
            if layout.tabs.count > 1 {
                TabStrip(layout: layout, pullRequest: pullRequest, selection: $model.selectedTab)
            }
            Divider()
            if layout.tabs.indices.contains(tabIndex) {
                BlockGrid(tab: layout.tabs[tabIndex], pullRequest: pullRequest,
                          context: BlockContext(viewer: model.index.viewer, now: model.now))
                    // Each tab keeps its own scroll position and block state.
                    .id("\(layout.id)/\(tabIndex)")
            }
            Divider()
            PageFooter(model: model, pullRequest: pullRequest)
        }
        .background(Style.pageBackground)
    }
}

struct PageHeader: View {
    let model: AppModel
    let pullRequest: PullRequest
    private let notConnected = "Not connected to GitHub yet"

    var body: some View {
        let pr = pullRequest
        let status = model.status(for: pr)
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if !model.showsList {
                        Button { model.showsList = true } label: { Image(systemName: "sidebar.left") }
                            .buttonStyle(.borderless)
                            .help("Show the pull request list")
                    }
                    Text(verbatim: "\(pr.repository.fullName) #\(pr.number)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Text(pr.title)
                    .font(.system(size: 19, weight: .semibold))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .help(pr.title)
                StatusLine(status: status)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 8) {
                    Button("Approve") {}
                        .buttonStyle(.borderedProminent)
                    Button("Request changes") {}
                    Button("Comment") {}
                    Button("Merge") {}
                        .help(pr.mergeUnavailableReason ?? notConnected)
                }
                .controlSize(.large)
                .disabled(true)
                .help(notConnected)
                Text(pr.mergeUnavailableReason.map { "\($0) · \(notConnected)" } ?? notConnected)
                    .font(Style.secondary)
                    .foregroundStyle(.secondary)
            }
            .fixedSize()
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 14)
        .background(Style.surface)
    }
}

/// The status symbol and sentence. The headline, up to a colon, is bold in the status's color.
struct StatusLine: View {
    let status: StatusSentence

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            StatusMark(systemName: status.symbol.systemName, color: status.symbol.color, size: 12)
            sentence
                .font(.system(size: 14))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var sentence: Text {
        let words = status.sentence
        if let colon = words.firstIndex(of: ":") {
            let head = String(words[...colon])
            let rest = String(words[words.index(after: colon)...])
            return Text("\(Text(head).fontWeight(.semibold).foregroundStyle(status.symbol.color))\(rest)")
        }
        return Text(words)
    }
}

/// The layout's tabs, each with the count of its first block when that block has one.
struct TabStrip: View {
    let layout: PageLayout
    let pullRequest: PullRequest
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 20) {
            ForEach(Array(layout.tabs.enumerated()), id: \.offset) { index, tab in
                let selected = index == min(selection, layout.tabs.count - 1)
                Button { selection = index } label: {
                    VStack(spacing: 6) {
                        HStack(spacing: 4) {
                            Text(tab.name).fontWeight(selected ? .semibold : .regular)
                            if let count = tab.placements.first.flatMap({ $0.kind.count(for: pullRequest) }) {
                                Text("\(count)").foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(selected ? .primary : .secondary)
                        Rectangle()
                            .fill(selected ? Color.accentColor : .clear)
                            .frame(height: 2)
                    }
                    .fixedSize()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer()
        }
        .font(.system(size: 13))
        .padding(.horizontal, 20)
        .padding(.top, 2)
        .background(Style.surface)
    }
}

/// The tab's columns side by side, each as wide as its share, the whole grid scrolling.
struct BlockGrid: View {
    static let singleColumnMaxWidth: CGFloat = 1000

    let tab: LayoutTab
    let pullRequest: PullRequest
    let context: BlockContext

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical) {
                if tab.placements.isEmpty {
                    Text("This tab has no blocks yet.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(40)
                } else {
                    let spacing = Style.blockSpacing
                    // One column reads best at a measure, not the window's whole width.
                    let width = tab.columns.count == 1 ? min(proxy.size.width, Self.singleColumnMaxWidth) : proxy.size.width
                    let available = max(0, width - spacing * CGFloat(tab.columns.count + 1))
                    let total = tab.columns.reduce(0) { $0 + $1.width }
                    HStack(alignment: .top, spacing: spacing) {
                        ForEach(Array(tab.columns.enumerated()), id: \.offset) { _, column in
                            LazyVStack(spacing: spacing) {
                                ForEach(Array(column.blocks.enumerated()), id: \.offset) { _, placement in
                                    BlockView(placement: placement, pullRequest: pullRequest, context: context)
                                }
                            }
                            .frame(width: total > 0 ? available * column.width / total : 0)
                        }
                    }
                    .padding(spacing)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

struct PageFooter: View {
    @Bindable var model: AppModel
    let pullRequest: PullRequest

    var body: some View {
        let freshness = Freshness(provenance: pullRequest.provenance, now: model.now)
        HStack(spacing: 12) {
            Text(freshness.summary)
                .help(freshness.details.joined(separator: "\n"))
            if !model.library.problems.isEmpty {
                let count = model.library.problems.count
                Label(count == 1 ? "A layout file could not be read" : "\(count) layout files could not be read",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .help(model.library.problems.map(\.description).joined(separator: "\n"))
            }
            Spacer()
            Menu {
                Picker("Layout", selection: $model.layoutID) {
                    ForEach(model.library.layouts) { layout in
                        Text(layout.name).tag(layout.id)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Text("Layout: \(model.layout.name)")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .fixedSize()
        }
        .font(Style.secondary)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .background(Style.surface)
    }
}
