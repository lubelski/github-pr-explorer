import GitHubPRExplorerCore
import SwiftUI

/// The main window: the pull request list on the left and the selected pull request's page.
///
/// The list sits in a plain row rather than a split view, so the window keeps the standard
/// title bar with no toolbar. It collapses with View > Hide Pull Request List, or its button.
/// Its width follows a drag on its trailing edge. Status and the layout menu sit at the right
/// end of the title bar. There is no footer.
struct MainWindowView: View {
    @Bindable var model: AppModel

    /// The narrowest the page gets beside the list. The list gives way to it in a small
    /// window, without forgetting the width the person chose.
    static let minimumPageWidth: CGFloat = 600

    var body: some View {
        GeometryReader { proxy in
            content(listWidth: shownListWidth(windowWidth: proxy.size.width))
        }
        .background(Style.pageBackground)
        .standardTitleBar { TitleBarStatus(model: model) }
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
            HStack(spacing: 6) {
                searchField
                Button {
                    withAnimation(.snappy) { model.showsList = false }
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .buttonStyle(.borderless)
                .help("Hide the pull request list")
            }
            .padding(.leading, 10)
            .padding(.trailing, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            ListViewPicker(model: model)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)

            Divider()

            if listed.isEmpty {
                if model.searchText.isEmpty {
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
                    ForEach(listed) { pr in
                        PullRequestRow(pullRequest: pr, status: model.status(for: pr))
                            .tag(pr.id)
                            .id(pr.id)
                            .listRowBackground(rendering && model.selection == pr.id
                                ? RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.18)).padding(.horizontal, 8)
                                : nil)
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

struct PullRequestRow: View {
    let pullRequest: PullRequest
    let status: StatusSentence

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            StatusMark(systemName: status.symbol.systemName, color: status.symbol.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(pullRequest.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Text(verbatim: "\(pullRequest.repository.fullName) #\(pullRequest.number) · \(status.sentence)")
                    .font(Style.secondary)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
        .help("\(pullRequest.title)\n\(status.text)")
    }
}
