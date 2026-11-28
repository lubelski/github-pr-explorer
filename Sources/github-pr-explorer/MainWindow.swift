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

    var body: some View {
        let listed = model.listedPullRequests
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 8)

            HStack(spacing: 4) {
                ListViewPicker(model: model)
                ListGroupingMenu(model: model)
                ListFilterMenu(model: model)
            }
            .padding(.leading, 10)
            .padding(.trailing, 8)
            .padding(.bottom, 8)

            if !model.listFilter.isEmpty {
                ActiveFiltersLine(model: model)
                    .padding(.leading, 12)
                    .padding(.trailing, 8)
                    .padding(.bottom, 7)
            }

            Divider()

            if listed.isEmpty {
                if !model.listFilter.isEmpty {
                    ContentUnavailableView {
                        Label("No Matches", systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text(model.searchText.isEmpty
                             ? "Nothing in \u{201C}\(model.listView.name)\u{201D} matches the filters."
                             : "Nothing in \u{201C}\(model.listView.name)\u{201D} matches the search and the filters.")
                    } actions: {
                        Button("Clear Filters") { model.listFilter = .none }
                    }
                    .frame(maxHeight: .infinity)
                } else if model.searchText.isEmpty {
                    ContentUnavailableView(emptyTitle, systemImage: "tray",
                                           description: Text("Nothing in \u{201C}\(model.listView.name)\u{201D} right now."))
                        .frame(maxHeight: .infinity)
                } else {
                    ContentUnavailableView.search(text: model.searchText)
                        .frame(maxHeight: .infinity)
                }
            } else {
                ScrollViewReader { proxy in
                List(selection: rendering ? .constant(nil) : $model.selection) {
                    if model.listGrouping == .none {
                        rows(listed)
                    } else {
                        ForEach(model.listSections) { section in
                            Section(isExpanded: expanded(section.id)) {
                                rows(section.pullRequests)
                            } header: {
                                ListSectionHeader(model: model, section: section)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                // Bring the selected pull request into view when the window opens.
                .onAppear { if let selection = model.selection { proxy.scrollTo(selection, anchor: .center) } }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Style.surface)
    }

    /// Whether a section is expanded, for the system's own disclosure control.
    private func expanded(_ id: String) -> Binding<Bool> {
        Binding {
            !model.collapsedSections.contains(id)
        } set: { isExpanded in
            if isExpanded { model.collapsedSections.remove(id) } else { model.collapsedSections.insert(id) }
        }
    }

    private func rows(_ pullRequests: [PullRequest]) -> some View {
        ForEach(pullRequests) { pr in
            PullRequestRow(pullRequest: pr, status: model.status(for: pr),
                           isViewer: model.index.viewer.isViewer(pr.author),
                           shorthands: model.shorthands)
                .tag(pr.id)
                .id(pr.id)
                .listRowBackground(rendering && model.selection == pr.id
                    ? RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.18)).padding(.horizontal, 8)
                    : nil)
        }
    }

    private var emptyTitle: String {
        switch model.listView {
        case .needsMyReview: "No Reviews Waiting"
        case .mine: "No Open Pull Requests of Yours"
        case .everythingOpen: "No Open Pull Requests"
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

/// The fixed views above the list, each with its count within the search. The chosen one is
/// filled with the accent color. When the list is too narrow for the full names, the short
/// ones are used.
struct ListViewPicker: View {
    @Bindable var model: AppModel

    var body: some View {
        let counts = model.countsByView
        ViewThatFits(in: .horizontal) {
            row(counts: counts, short: false)
            row(counts: counts, short: true)
        }
    }

    private func row(counts: [FixedListView: Int], short: Bool) -> some View {
        HStack(spacing: 4) {
            ForEach(FixedListView.allCases) { view in
                let selected = model.listView == view
                Button {
                    model.listView = view
                } label: {
                    HStack(spacing: 4) {
                        Text(short ? view.shortName : view.name)
                            .fontWeight(selected ? .semibold : .regular)
                        Text("\(counts[view] ?? 0)")
                            .monospacedDigit()
                            .foregroundStyle(selected ? Color.accentColor : .secondary)
                    }
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background {
                        Capsule().fill(selected ? Color.accentColor.opacity(0.16) : Color.clear)
                    }
                    .overlay {
                        Capsule().strokeBorder(selected ? Color.accentColor.opacity(0.45) : Color.clear)
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selected ? .primary : .secondary)
                .help(help(for: view))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 12))
    }

    private func help(for view: FixedListView) -> String {
        switch view {
        case .needsMyReview: "Open pull requests where a review is asked of you or one of your teams"
        case .mine: "Open pull requests you wrote"
        case .everythingOpen: "Every open pull request"
        }
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
    private var repositoryLine: some View {
        let repository = shorthands.name(for: pullRequest.repository).text
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                Text(verbatim: repository)
                Text(verbatim: " #\(pullRequest.number)")
                Text(verbatim: " · ").foregroundStyle(.tertiary)
                Text(isViewer ? "you" : shorthands.name(for: pullRequest.author).text)
            }
            .fixedSize()
            HStack(spacing: 0) {
                Text(verbatim: repository)
                    .truncationMode(.middle)
                Text(verbatim: " #\(pullRequest.number)")
                    .fixedSize()
                    .layoutPriority(1)
            }
        }
        .font(Style.secondary)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}
