import GitHubPRExplorerCore
import SwiftUI

/// The main window: the pull request list on the left and the selected pull request's page.
///
/// The list sits in a plain row rather than a split view, so the window keeps the standard
/// title bar with no toolbar. It collapses with View > Hide Pull Request List, or its button.
struct MainWindowView: View {
    static let listWidth: CGFloat = 300

    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            if model.showsList {
                PullRequestList(model: model)
                    .frame(width: Self.listWidth)
                    .transition(.move(edge: .leading))
                Divider()
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
        .background(Style.pageBackground)
        .standardTitleBar()
    }
}

struct PullRequestList: View {
    @Bindable var model: AppModel
    @Environment(\.isRenderingPreview) private var rendering
    @FocusState private var searchFocused: Bool

    var body: some View {
        let listed = model.listedPullRequests
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text("Open").font(.system(size: 13, weight: .semibold))
                Text("· \(model.searchText.isEmpty ? model.openCount : listed.count)")
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    withAnimation(.snappy) { model.showsList = false }
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .buttonStyle(.borderless)
                .help("Hide the pull request list")
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            searchField
                .padding(.horizontal, 10)
                .padding(.bottom, 8)

            Divider()

            if listed.isEmpty {
                ContentUnavailableView.search(text: model.searchText)
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
        .background(Style.surface)
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
