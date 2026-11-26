import Foundation
import GitHubPRExplorerCore
import Observation

/// What the main window shows: which pull request, which layout and tab, and the search.
///
/// It reads everything from the index it is given. Nothing here builds data or touches the
/// network.
@MainActor
@Observable
final class AppModel {
    let index: any PullRequestIndex
    /// The clock every age and running time is measured from. The mock world is seen from a
    /// fixed moment, so the app uses that moment and renders stay the same from run to run.
    let now: Date
    let library: LayoutLibrary

    var searchText = ""
    var selection: PullRequest.ID?
    var layoutID: String {
        didSet { if layoutID != oldValue { selectedTab = 0 } }
    }
    var selectedTab = 0
    var showsList = true

    /// Which of the fixed views the list shows. Remembered across launches as window state.
    var listView: FixedListView {
        didSet { if listView != oldValue { remember(listView.rawValue, for: WindowState.listView) } }
    }
    /// The list's width, which the person sets by dragging its edge. Remembered across launches
    /// as window state when a drag ends, through `rememberListWidth()`.
    var listWidth: CGFloat

    /// The version, build and commit shown at the right end of the title bar.
    let build: BuildInfo

    /// Where window state is remembered, or nil to remember nothing, as in renders.
    @ObservationIgnored private let windowState: UserDefaults?

    @ObservationIgnored private var statusByID: [PullRequest.ID: StatusSentence] = [:]

    init(index: any PullRequestIndex, now: Date, library: LayoutLibrary, selection: PullRequestReference? = nil,
         build: BuildInfo = .current, windowState: UserDefaults? = nil) {
        self.index = index
        self.now = now
        self.library = library
        self.build = build
        self.windowState = windowState
        self.layoutID = LayoutLibrary.fallbackID
        self.listView = windowState?.string(forKey: WindowState.listView).flatMap(FixedListView.init(rawValue:)) ?? .standard
        let width = windowState?.double(forKey: WindowState.listWidth) ?? 0
        self.listWidth = width > 0 ? Self.clampedListWidth(width) : Self.defaultListWidth
        self.selection = selection.flatMap { index.pullRequest($0)?.id } ?? index.allPullRequests.first { $0.state == .open }?.id
    }

    /// The pull requests in the chosen view that match the search, most recently updated first.
    var listedPullRequests: [PullRequest] {
        listView.pullRequests(in: index.search(searchText), viewer: index.viewer)
    }

    /// How many pull requests each view holds, within the search.
    var countsByView: [FixedListView: Int] {
        let found = index.search(searchText)
        let viewer = index.viewer
        return Dictionary(uniqueKeysWithValues: FixedListView.allCases.map { view in
            (view, found.count { view.includes($0, viewer: viewer) })
        })
    }

    // MARK: List width

    static let defaultListWidth: CGFloat = 300
    static let listWidthRange: ClosedRange<CGFloat> = 260...480

    static func clampedListWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, listWidthRange.lowerBound), listWidthRange.upperBound)
    }

    func rememberListWidth() {
        remember(Double(listWidth), for: WindowState.listWidth)
    }

    func resetListWidth() {
        listWidth = Self.defaultListWidth
        windowState?.removeObject(forKey: WindowState.listWidth)
    }

    /// Window state, not configuration: where the window was left, kept in `UserDefaults`.
    /// Settings that change what the app does belong in the configuration folder instead.
    private enum WindowState {
        static let listView = "MainWindow.listView"
        static let listWidth = "MainWindow.listWidth"
    }

    private func remember(_ value: Any, for key: String) {
        windowState?.set(value, forKey: key)
    }

    var selectedPullRequest: PullRequest? {
        selection.flatMap { index.pullRequest(id: $0) }
    }

    /// The layout in use. A missing or unreadable layout falls back to "Decision first".
    var layout: PageLayout { library.layout(id: layoutID) }

    var currentTabIndex: Int { min(max(0, selectedTab), max(0, layout.tabs.count - 1)) }

    func status(for pr: PullRequest) -> StatusSentence {
        if let known = statusByID[pr.id] { return known }
        let status = pr.statusSentence(for: index.viewer, now: now)
        statusByID[pr.id] = status
        return status
    }

    /// Moves the selection up or down the list, for the arrow keys while the search field has
    /// the keyboard.
    func moveSelection(by offset: Int) {
        let listed = listedPullRequests
        guard !listed.isEmpty else { return }
        guard let current = selection, let position = listed.firstIndex(where: { $0.id == current }) else {
            selection = (offset >= 0 ? listed.first : listed.last)?.id
            return
        }
        selection = listed[min(max(0, position + offset), listed.count - 1)].id
    }
}
