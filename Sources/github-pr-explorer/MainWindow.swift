import GitHubPRExplorerCore
import SwiftUI

/// The main window: the pull request list on the left and the selected pull request's page.
///
/// The list sits in a plain row rather than a split view, so the window keeps the standard
/// title bar with no toolbar. It collapses with View > Hide Pull Request List, or the sidebar
/// button just after the window buttons, which stays there while the list is hidden. Its width
/// follows a drag on its trailing edge. Status and the window's menu sit at the right end of
/// the title bar. There is no footer.
struct MainWindowView: View {
    @Bindable var model: AppModel
    /// The updater, for the indicator in the title bar when an update waits.
    var updater: AppUpdater

    /// The narrowest the page gets beside the list. The list gives way to it in a small
    /// window, without forgetting the width the person chose.
    static let minimumPageWidth: CGFloat = 600

    /// Below this window width the title bar's update indicator shows only its symbol, so the
    /// status at the right end does not run into the centered name.
    static let compactTitleBarWidth: CGFloat = 1200

    @State private var windowWidth: CGFloat = 0
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        GeometryReader { proxy in
            content(listWidth: shownListWidth(windowWidth: proxy.size.width))
        }
        .background(Style.pageBackground)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { windowWidth = $0 }
        .standardTitleBar {
            SidebarButton(model: model)
        } trailing: {
            TitleBarStatus(model: model, updater: updater, compact: windowWidth < Self.compactTitleBarWidth,
                           openSettings: { openSettings() })
        }
    }

    private func shownListWidth(windowWidth: CGFloat) -> CGFloat {
        max(AppModel.listWidthRange.lowerBound, min(model.listWidth, windowWidth - Self.minimumPageWidth))
    }

    private func content(listWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            if model.showsList {
                PullRequestList(model: model)
                    .frame(width: listWidth)
                    .transition(.move(edge: .leading))
                Divider()
                    .overlay { ListResizeHandle(model: model, shownWidth: listWidth) }
                    .zIndex(1)
            }
            Group {
                if let pr = model.selectedPullRequest {
                    PullRequestPage(model: model, pullRequest: pr)
                        .id(pr.id)
                } else if let group = model.selectedGroup {
                    ListGroupOverview(model: model, group: group)
                        .id(group.id)
                } else {
                    ContentUnavailableView("No Pull Request Selected", systemImage: "arrow.triangle.pull",
                                           description: Text("Choose one from the list."))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The button that shows and hides the list, in the title bar just after the window buttons.
struct SidebarButton: View {
    @Bindable var model: AppModel

    var body: some View {
        Button {
            withAnimation(.snappy) { model.showsList.toggle() }
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 13))
                .frame(width: 24, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(model.showsList ? "Hide the pull request list (Control-Command-S)" : "Show the pull request list (Control-Command-S)")
        .accessibilityLabel(model.showsList ? "Hide Pull Request List" : "Show Pull Request List")
    }
}

/// The list's trailing edge: drag to set the list's width, double-click to put it back.
/// It is wider than the line it sits on, so it is easy to grab.
struct ListResizeHandle: View {
    @Bindable var model: AppModel
    /// The width the list is drawn at, which is less than the chosen one in a small window.
    let shownWidth: CGFloat
    @State private var widthAtStart: CGFloat?

    var body: some View {
        Color.clear
            .frame(width: 8)
            .contentShape(Rectangle())
            .pointerStyle(.columnResize)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { drag in
                        let start = widthAtStart ?? shownWidth
                        widthAtStart = start
                        model.listWidth = AppModel.clampedListWidth(start + drag.translation.width)
                    }
                    .onEnded { _ in
                        widthAtStart = nil
                        model.rememberListWidth()
                    }
            )
            .simultaneousGesture(TapGesture(count: 2).onEnded { model.resetListWidth() })
            .help("Drag to resize the list. Double-click to reset it.")
            .accessibilityElement()
            .accessibilityLabel("List width")
            .accessibilityValue("\(Int(shownWidth)) points")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: model.listWidth = AppModel.clampedListWidth(shownWidth + 20)
                case .decrement: model.listWidth = AppModel.clampedListWidth(shownWidth - 20)
                @unknown default: break
                }
                model.rememberListWidth()
            }
    }
}

struct PullRequestList: View {
    @Bindable var model: AppModel
    @Environment(\.isRenderingPreview) private var rendering
    @FocusState private var searchFocused: Bool
    /// The Set Shorthand popover, when a row's right-click menu asked for it.
    @State private var shorthandEditor: ShorthandEditorRequest?

    var body: some View {
        let listed = model.listedPullRequests
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 8)

            HStack(spacing: 4) {
                SavedFilterTabBar(model: model)
                ListGroupingMenu(model: model)
                FilterButton(model: model)
            }
            .padding(.leading, 10)
            .padding(.trailing, 8)
            .padding(.bottom, 8)

            if model.hasUnsavedFilter {
                AppliedFilterLine(model: model)
                    .padding(.leading, 12)
                    .padding(.trailing, 8)
                    .padding(.bottom, 7)
            }

            Divider()

            if listed.isEmpty {
                if model.hasUnsavedFilter {
                    ContentUnavailableView {
                        Label("No Matches", systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text(model.searchText.isEmpty
                             ? "No open pull request matches the filter applied on \u{201C}\(model.selectedFilter.name)\u{201D}."
                             : "No open pull request matches the search and the filter applied on \u{201C}\(model.selectedFilter.name)\u{201D}.")
                    } actions: {
                        Button("Change Filter\u{2026}") { model.showsFilterPopover = true }
                        Button("Clear Filter") { model.clearAppliedFilter() }
                    }
                    .frame(maxHeight: .infinity)
                } else if model.searchText.isEmpty {
                    ContentUnavailableView {
                        Label(model.selectedFilter.isEverything ? "No Open Pull Requests" : "Nothing Here Right Now", systemImage: "tray")
                    } description: {
                        Text(model.selectedFilter.isEverything
                             ? "Every open pull request shows here."
                             : "Nothing matches \u{201C}\(model.selectedFilter.name)\u{201D} right now: \(model.selectedFilter.summary)")
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    ContentUnavailableView.search(text: model.searchText)
                        .frame(maxHeight: .infinity)
                }
            } else {
                ScrollViewReader { proxy in
                List(selection: rendering ? .constant(nil) : $model.listSelection) {
                    ForEach(model.listTree.rows(closed: model.closedGroups)) { row in
                        rowView(row)
                            .modifier(ShorthandPopoverAnchor(row: row.id, request: $shorthandEditor, shorthands: model.shorthands))
                            .tag(row.id)
                            .id(row.id)
                            .listRowBackground(rendering && model.listSelection == row.id
                                ? RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.18)).padding(.horizontal, 8)
                                : nil)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                // A right-click opens the row's menu (ListRowContextMenu). A double-click or
                // Return on a title row opens or closes it. A click selects.
                .contextMenu(forSelectionType: ListSelection.self, menu: { rows in
                    ListRowContextMenu(model: model, rows: rows) { shorthandEditor = $0 }
                }) { rows in
                    guard rows.count == 1, let id = rows.first?.groupID else { return }
                    withAnimation(.snappy(duration: 0.2)) { model.toggleGroup(id) }
                }
                // Left and right close and open title rows, and move out and in, as in Finder.
                .onKeyPress(.leftArrow) {
                    guard !model.listGrouping.isNone else { return .ignored }
                    withAnimation(.snappy(duration: 0.2)) { model.moveSelectionOut() }
                    return .handled
                }
                .onKeyPress(.rightArrow) {
                    guard !model.listGrouping.isNone else { return .ignored }
                    withAnimation(.snappy(duration: 0.2)) { model.moveSelectionIn() }
                    return .handled
                }
                // Bring the selection into view when the window opens.
                .onAppear { if let selection = model.listSelection { proxy.scrollTo(selection, anchor: .center) } }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Style.surface)
    }

    @ViewBuilder
    private func rowView(_ row: ListRow) -> some View {
        switch row.content {
        case .group(let group, let isOpen):
            ListGroupRow(model: model, group: group, isOpen: isOpen)
        case .pullRequest(let pr):
            PullRequestRow(pullRequest: pr, status: model.status(for: pr),
                           isViewer: model.index.viewer.isViewer(pr.author),
                           namedByAncestors: row.namedByAncestors,
                           shorthands: model.shorthands)
                .padding(.leading, CGFloat(row.depth) * ListTreeMetrics.indentStep)
                .background(alignment: .leading) { ListTreeGuides(depth: row.depth) }
        }
    }

    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search title, number, author, path", text: $model.searchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                // The arrow keys move through the list while typing a search.
                .onKeyPress(.downArrow) { model.moveSelection(by: 1); return .handled }
                .onKeyPress(.upArrow) { model.moveSelection(by: -1); return .handled }
            if !model.searchText.isEmpty {
                Button { model.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear the search")
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7).fill(.quaternary.opacity(0.7)))
    }
}

/// One pull request in the list, in three lines: the title across the full width, which may
/// wrap to a second line; then the repository, number and author, and the detail of the
/// status, with a badge for the state at the right of those two lines. The detail reads like
/// "e2e-chrome failed, 3 threads unresolved". A long repository name gives way in the middle,
/// and the author is left out before the number is ever hidden.
struct PullRequestRow: View {
    let pullRequest: PullRequest
    let status: StatusSentence
    /// The viewer wrote it, so the author shows as "you".
    var isViewer = false
    /// What the title rows above it already say. Inside a repository the row does not repeat
    /// the repository's name, and inside an organization it names the repository without it.
    var namedByAncestors: Set<ListGrouping.Property> = []
    /// Short names for the repository and the author. The hover keeps the full names.
    var shorthands: Shorthands = .none

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(pullRequest.title)
                .font(.system(size: 13))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 1)
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    repositoryLine
                    Text(status.detail)
                        .font(Style.secondary)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                StatusBadge(badge: status.badge)
            }
        }
        .padding(.vertical, 4)
        .help("\(pullRequest.title)\n\(pullRequest.repository.fullName) #\(pullRequest.number) by \(pullRequest.author.displayName)\n\(status.text)")
        .accessibilityElement(children: .combine)
    }

    /// "acme/api #4826 · Ada Park", or without the author when that does not fit. A shorthand
    /// takes the place of the repository's or the author's name, as in "API #4826 · Ada".
    /// Inside a repository it is "#4826 · Ada Park", inside an organization "api #4826 · Ada
    /// Park" (or the repository's shorthand, which stands alone), and inside an author
    /// "acme/api #4826".
    private var repositoryLine: some View {
        let repository: String? = if namedByAncestors.contains(.repository) {
            nil
        } else if let short = shorthands.shorthand(.repository, for: pullRequest.repository.fullName) {
            short
        } else if namedByAncestors.contains(.organization) {
            pullRequest.repository.name
        } else {
            // With the organization's shorthand, if it has one: "Acme/api".
            shorthands.name(for: pullRequest.repository).text
        }
        let number = repository == nil ? "#\(pullRequest.number)" : " #\(pullRequest.number)"
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                if let repository { Text(verbatim: repository) }
                Text(verbatim: number)
                // Inside an author's row the author goes without saying.
                if !namedByAncestors.contains(.author) {
                    Text(verbatim: " · ").foregroundStyle(.tertiary)
                    Text(isViewer ? "you" : shorthands.name(for: pullRequest.author).text)
                }
            }
            .fixedSize()
            HStack(spacing: 0) {
                if let repository {
                    Text(verbatim: repository)
                        .truncationMode(.middle)
                }
                Text(verbatim: number)
                    .fixedSize()
                    .layoutPriority(1)
            }
        }
        .font(Style.secondary)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}
