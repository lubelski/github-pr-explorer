import Foundation
import GitHubPRExplorerCore
import Observation

/// What the main window shows: which pull request, which layout and tab, and the search.
///
/// It reads everything from the index it is given. Nothing here builds data or touches the
/// network. In GitHub mode `SyncModel` hands it a new index whenever the sync changes one.
@MainActor
@Observable
final class AppModel {
    private(set) var index: any PullRequestIndex
    /// The clock every age and running time is measured from. The mock world is seen from a
    /// fixed moment, so the app uses that moment and renders stay the same from run to run.
    /// In GitHub mode it is the real time, moved on by `SyncModel`.
    private(set) var now: Date
    /// The sync's status for the title bar. Nil in mock mode, where the title bar is as it was.
    var syncSummary: SyncStatusSummary?
    /// Told when the selection changes, so the sync can fetch that pull request sooner. It is
    /// a request to the sync, never a fetch.
    @ObservationIgnored var onSelect: ((PullRequest.ID) -> Void)?
    /// Told when the person picks Sync Now. Set only by the app, so renders never sync.
    @ObservationIgnored var onSyncNow: (() -> Void)?
    /// The layouts the layout menu offers: the built-in ones and the configuration folder's.
    var library: LayoutLibrary
    /// Whether Activity starts with bot events folded away, from `settings.json`.
    var hidesBotEventsInActivity = true
    /// The short names drawn for repositories and people, from `shorthands.json`. None by
    /// default, and then every label is as it was.
    var shorthands = Shorthands.none

    var searchText = ""
    /// The list's advanced filters. They narrow the chosen view together with the search.
    /// Like the search, they are not remembered across launches: a filter worth keeping is a
    /// saved view, which the filter language will bring.
    var listFilter = ListFilter.none
    /// The pull request shown. Choosing another closes its panes: they belong to the pull
    /// request they were opened on.
    var selection: PullRequest.ID? {
        didSet {
            if selection != oldValue { panePath = PaneStackPath() }
            if let selection, selection != oldValue { onSelect?(selection) }
            if selection != oldValue { revealSelection() }
        }
    }
    /// The panes open over the page: a file's diff, then a thread. See `PullRequestPane`.
    var panePath = PaneStackPath()
    var diffMode: DiffMode = .inline
    /// Diff documents built so far, by pull request and path. A document is built off the main
    /// thread the first time its file opens, then kept for as long as the window is open.
    private(set) var diffDocuments: [String: DiffDocument] = [:]
    var layoutID: String {
        didSet { if layoutID != oldValue { selectedTab = 0 } }
    }
    var selectedTab = 0
    var showsList = true

    /// Which of the fixed views the list shows. Remembered across launches as window state.
    var listView: FixedListView {
        didSet { if listView != oldValue { remember(listView.rawValue, for: WindowState.listView) } }
    }
    /// How the list is drawn: one run of rows, or in sections. Remembered across launches as
    /// window state, like the view.
    var listGrouping: ListGrouping {
        didSet { if listGrouping != oldValue { remember(listGrouping.rawValue, for: WindowState.listGrouping) } }
    }
    /// The ids of the list's collapsed sections. Ids carry their grouping, such as
    /// `repository:acme/api`, so one set serves every grouping, and an id with no section now
    /// does nothing. Remembered across launches as window state.
    var collapsedSections: Set<String> {
        didSet { if collapsedSections != oldValue { remember(collapsedSections.sorted(), for: WindowState.collapsedSections) } }
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
        self.listGrouping = windowState?.string(forKey: WindowState.listGrouping).flatMap(ListGrouping.init(rawValue:)) ?? .standard
        self.collapsedSections = Set(windowState?.stringArray(forKey: WindowState.collapsedSections) ?? [])
        let width = windowState?.double(forKey: WindowState.listWidth) ?? 0
        self.listWidth = width > 0 ? Self.clampedListWidth(width) : Self.defaultListWidth
        self.selection = selection.flatMap { index.pullRequest($0)?.id } ?? index.allPullRequests.first { $0.state == .open }?.id
    }

    /// The pull requests in the chosen view that match the search and the filters, most
    /// recently updated first.
    var listedPullRequests: [PullRequest] {
        listView.pullRequests(in: searchedAndFiltered, viewer: index.viewer)
    }

    /// The listed pull requests in the sections the list draws. With no grouping, one section
    /// holds them all.
    var listSections: [ListGrouping.Section] {
        listGrouping.sections(of: listedPullRequests, viewer: index.viewer, status: status(for:), shorthands: shorthands)
    }

    /// Collapses or expands one section, or with `all` every section from it, as Option-click does.
    func toggleSection(_ id: String, all: Bool = false) {
        if all {
            ListGrouping.toggleAll(from: id, sections: listSections, in: &collapsedSections)
        } else {
            ListGrouping.toggle(id, in: &collapsedSections)
        }
    }

    /// Collapse All or Expand All in the group by menu.
    func setAllSections(collapsed: Bool) {
        ListGrouping.setAll(collapsed: collapsed, sections: listSections, in: &collapsedSections)
    }

    /// Expands the section that holds the selected pull request, so the selection is never a row
    /// that is folded away. Called when the selection changes and when a new index moves the
    /// selected pull request into another section, never when the person collapses a section.
    private func revealSelection() {
        guard listGrouping != .none, let selection,
              let id = ListGrouping.sectionID(containing: selection, in: listSections),
              collapsedSections.contains(id) else { return }
        collapsedSections.remove(id)
    }

    /// How many pull requests each view holds, within the search and the filters, so a view's
    /// count is always the number of rows choosing it would show.
    var countsByView: [FixedListView: Int] {
        let found = searchedAndFiltered
        let viewer = index.viewer
        return Dictionary(uniqueKeysWithValues: FixedListView.allCases.map { view in
            (view, found.count { view.includes($0, viewer: viewer) })
        })
    }

    private var searchedAndFiltered: [PullRequest] {
        listFilter.pullRequests(in: index.search(searchText, shorthands: shorthands), status: status(for:))
    }

    /// What the filter menu offers: the repositories, authors, statuses and review states of
    /// the open pull requests in the index, and whatever the filters already hold.
    var filterChoices: ListFilterChoices {
        ListFilterChoices(pullRequests: index.allPullRequests.filter { $0.state == .open }, viewer: index.viewer,
                          status: status(for:), keeping: listFilter)
    }

    /// Whether Sync Now means anything: only when pull requests come from GitHub.
    var canSyncNow: Bool { syncSummary != nil }

    func syncNow() { onSyncNow?() }

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
        static let listGrouping = "MainWindow.listGrouping"
        static let collapsedSections = "MainWindow.collapsedSections"
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

    /// Takes in a change to the configuration. When the default layout changes, by Settings,
    /// by a hand edit of `settings.json` or by `ctl config set`, the open window switches to it.
    /// The layout menu changes the open window only, and the next change to the default wins.
    func apply(_ configuration: ConfigurationSnapshot, previous: ConfigurationSnapshot?) {
        library = configuration.library
        hidesBotEventsInActivity = configuration.settings.hidesBotEventsInActivity
        shorthands = configuration.shorthands
        let defaultID = configuration.defaultLayout.id
        if previous == nil || previous?.defaultLayout.id != defaultID {
            layoutID = defaultID
        }
    }

    // MARK: Where the index comes from

    /// Shows the mock world, as the app did before there was a sync.
    func showMock() {
        replaceIndex(MockWorld.standard.index, now: MockWorld.now)
        syncSummary = nil
        selection = MockWorld.standard.index.pullRequest(MockWorld.workedExample)?.id ?? selection
    }

    /// Shows an index from the sync. The open page stays open when its pull request is still
    /// there, and its panes stay open when its files did not change.
    func showGitHub(index: any PullRequestIndex, now: Date, summary: SyncStatusSummary?) {
        let sectionBefore = selection.flatMap { ListGrouping.sectionID(containing: $0, in: listSections) }
        replaceIndex(index, now: now)
        syncSummary = summary
        if selection.flatMap(index.pullRequest(id:)) == nil {
            // The first row on screen, which changing the selection then reveals if need be.
            let first = listGrouping.visible(listSections, collapsed: collapsedSections).first ?? listedPullRequests.first
            selection = first?.id ?? index.allPullRequests.first { $0.state == .open }?.id
        } else if selection.flatMap({ ListGrouping.sectionID(containing: $0, in: listSections) }) != sectionBefore {
            // The sync moved the selected pull request into another section.
            revealSelection()
        }
    }

    /// Moves the clock on, so ages read right while nothing new is synced.
    func setNow(_ now: Date, summary: SyncStatusSummary?) {
        self.now = now
        statusByID = [:]
        syncSummary = summary
    }

    private func replaceIndex(_ new: any PullRequestIndex, now: Date) {
        let old = index
        index = new
        self.now = now
        statusByID = [:]
        // A diff document is kept only while its file's patch is unchanged.
        diffDocuments = diffDocuments.filter { key, _ in
            guard let id = key.split(separator: "|", maxSplits: 1).first.map(String.init) else { return false }
            return old.pullRequest(id: id)?.files == new.pullRequest(id: id)?.files
        }
    }

    func status(for pr: PullRequest) -> StatusSentence {
        if let known = statusByID[pr.id] { return known }
        let status = pr.statusSentence(for: index.viewer, now: now)
        statusByID[pr.id] = status
        return status
    }

    // MARK: Panes and diffs

    private func documentKey(_ pr: PullRequest, _ path: String) -> String { "\(pr.id)|\(path)" }

    /// The file's diff document if it has been built.
    func cachedDocument(for pr: PullRequest, path: String) -> DiffDocument? {
        diffDocuments[documentKey(pr, path)]
    }

    /// Builds the file's diff document now, on this thread, for renders that cannot wait.
    @discardableResult
    func buildDocumentNow(for pr: PullRequest, path: String) -> DiffDocument? {
        if let known = cachedDocument(for: pr, path: path) { return known }
        guard let file = pr.files.first(where: { $0.path == path }) else { return nil }
        let document = DiffDocument(file: file, threads: pr.reviewThreads)
        diffDocuments[documentKey(pr, path)] = document
        return document
    }

    /// Builds the file's diff document off the main thread, if it is not built yet.
    func loadDocument(for pr: PullRequest, path: String) async {
        let key = documentKey(pr, path)
        guard diffDocuments[key] == nil, let file = pr.files.first(where: { $0.path == path }) else { return }
        let threads = pr.reviewThreads
        let document = await Task.detached(priority: .userInitiated) {
            DiffDocument(file: file, threads: threads)
        }.value
        diffDocuments[key] = document
    }

    /// Opens a file's diff over the page, or swaps the file when the diff is already open.
    func openFile(_ path: String) {
        panePath.open(PullRequestPane.files(path: path).entry, from: 0)
    }

    /// Opens a thread over the diff it is on.
    func openThread(_ id: String) {
        panePath.open(PullRequestPane.thread(id: id).entry, from: 1)
    }

    /// Opens a thread from the page: its file's diff, with the thread on top.
    func showThread(_ id: String, in pr: PullRequest) {
        if let path = pr.paneStack(showingThread: id) { panePath = path }
    }

    /// Moves the selection up or down the list, for the arrow keys while the search field has
    /// the keyboard. It follows the order on screen, across sections.
    func moveSelection(by offset: Int) {
        let listed = listGrouping.visible(listSections, collapsed: collapsedSections)
        guard !listed.isEmpty else { return }
        guard let current = selection, let position = listed.firstIndex(where: { $0.id == current }) else {
            selection = (offset >= 0 ? listed.first : listed.last)?.id
            return
        }
        selection = listed[min(max(0, position + offset), listed.count - 1)].id
    }
}
