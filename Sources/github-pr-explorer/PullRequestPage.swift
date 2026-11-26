import GitHubPRExplorerCore
import SwiftUI

/// One pull request: a fixed header, then a stack of panes down to the window's bottom edge.
/// The page's blocks, tab strip included, are the stack's base. A file's diff slides in over
/// them, and a review thread over the diff. The header is never covered. Freshness and the
/// layout menu are in the title bar, in `TitleBarStatus`.
struct PullRequestPage: View {
    @Bindable var model: AppModel
    let pullRequest: PullRequest

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(model: model, pullRequest: pullRequest)
            PaneStackView(
                path: model.panePath,
                stripWidths: { available in
                    DiffPaneLayout.widths(available: available, mode: model.diffMode, depth: model.panePath.depth).strips
                },
                backLabel: { level in level.depth == 0 ? "Back to the pull request" : "Back to the files" },
                change: { body in change { body(&model.panePath) } }
            ) { level, available in
                pane(level, available: available)
            }
        }
        .background(Style.pageBackground)
        .environment(\.pageActions, PageActions(
            openFilePath: model.panePath.openFilePath,
            openFile: { path in change { model.openFile(path) } },
            showThread: { id in change { model.showThread(id, in: pullRequest) } }))
    }

    @ViewBuilder private func pane(_ level: PaneLevel, available: CGFloat) -> some View {
        switch level.item.flatMap(PullRequestPane.init(entry:)) {
        case nil:
            PageBlocks(model: model, pullRequest: pullRequest)
        case .files(let path):
            DiffPane(model: model, pullRequest: pullRequest, path: path,
                     treeIsRail: DiffPaneLayout.widths(available: available, mode: model.diffMode, depth: 1).treeIsRail,
                     change: change)
        case .thread(let id):
            if let thread = pullRequest.reviewThreads.first(where: { $0.id == id }) {
                ThreadPane(model: model, pullRequest: pullRequest, thread: thread, now: model.now)
                    .frame(width: DiffPaneLayout.threadPaneWidth, alignment: .topLeading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    /// Changes panes with the stack's motion.
    private func change(_ body: @escaping () -> Void) {
        withAnimation(PaneMotion.animation(reduceMotion: reduceMotion), body)
    }
}

/// The page's blocks: the tab strip when there is more than one tab, and the selected tab's
/// blocks. It is the base of the pane stack, so a diff covers all of it.
struct PageBlocks: View {
    @Bindable var model: AppModel
    let pullRequest: PullRequest

    var body: some View {
        let layout = model.layout
        let tabIndex = model.currentTabIndex
        VStack(spacing: 0) {
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Style.pageBackground)
    }
}

/// What blocks on the page can open in the panes over it.
struct PageActions {
    /// The file whose diff is open, which the Files block marks.
    var openFilePath: String?
    var openFile: ((String) -> Void)?
    var showThread: ((String) -> Void)?
}

extension EnvironmentValues {
    @Entry var pageActions = PageActions()
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
