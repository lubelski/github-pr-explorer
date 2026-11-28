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
    /// Everything, then the saved filters from `saved-filters.json`, in tab order. The tabs
    /// above the list and the » menu are made from it. See `AppModel+SavedFilters.swift`.
    var savedFilters: [SavedFilter] = [.everything] + SavedFilterFile.defaults.savedFilters
    /// A filter applied from the Filter popover and not saved. It takes the place of the chosen
    /// tab's own filter, and that tab shows a dot. Like the search it is window state that is
    /// not remembered: it is dropped on Clear, on choosing another tab, and on quitting.
    var appliedFilter: PullRequestFilter?
    /// A saved filter that is not a tab, chosen from the » menu. It shows as a temporary last
    /// tab while it is chosen.
    var temporaryFilterID: String?
    /// The saved filter whose editing popover is open on its tab.
    var editingFilterID: String?
    /// Whether the Filter popover is open.
    var showsFilterPopover = false
    /// Writes saved filters to the configuration folder. Set by the app, and by renders to a
    /// temporary folder. Without one, the window cannot change saved filters.
    @ObservationIgnored var savedFilterStore: SavedFilterStore?
    /// The row selected in the list: a pull request, or a title row of the tree. Choosing
    /// another pull request closes the panes: they belong to the pull request they were opened
    /// on. Remembered across launches as window state.
    var listSelection: ListSelection? {
        didSet {
            guard listSelection != oldValue else { return }
            if selection != oldValue?.pullRequestID { panePath = PaneStackPath() }
            if let selection, selection != oldValue?.pullRequestID { onSelect?(selection) }
            revealSelection()
            remember(listSelection?.storedValue, for: WindowState.selection)
        }
    }

    /// The pull request shown, or nil when nothing or a title row is selected.
    var selection: PullRequest.ID? {
        get { listSelection?.pullRequestID }
        set { listSelection = newValue.map(ListSelection.pullRequest) }
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

    /// The saved filter the list shows, by id. Choosing one drops a filter applied on the tab
    /// before, and a saved filter with a grouping sets the list's grouping. Remembered across
    /// launches as window state.
    var selectedFilterID: String {
        didSet {
            guard selectedFilterID != oldValue else { return }
            remember(selectedFilterID, for: WindowState.selectedFilter)
            didChooseFilter(from: oldValue)
        }
    }
    /// How the list is drawn: one run of rows, or a tree of up to two levels. Remembered across
    /// launches as window state, like the view.
    var listGrouping: ListGrouping {
        didSet {
            guard listGrouping != oldValue else { return }
            remember(listGrouping.storedValue, for: WindowState.listGrouping)
            keepSelection(after: oldValue)
        }
    }
    /// The ids of the tree's closed title rows. Ids carry their grouping, such as
    /// `repository:acme/api`, so one set serves every grouping, and an id with no row now
    /// does nothing. Remembered across launches as window state.
    ///
    /// When a row closes over the selected row, the row that closed becomes the selection, as
    /// in Finder, so the selection is always a row on screen.
    var closedGroups: Set<String> {
        didSet {
            guard closedGroups != oldValue else { return }
            remember(closedGroups.sorted(), for: WindowState.closedGroups)
            if let listSelection, let shown = listTree.nearestVisible(listSelection, closed: closedGroups),
               shown != listSelection {
                self.listSelection = shown
            }
        }
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
        self.selectedFilterID = Self.rememberedFilterID(windowState)
        // A value saved by the one-level grouping, such as `repository`, reads as that level.
        self.listGrouping = windowState?.string(forKey: WindowState.listGrouping).map(ListGrouping.init(storedValue:)) ?? .standard
        self.closedGroups = Set(windowState?.stringArray(forKey: WindowState.closedGroups) ?? [])
        let width = windowState?.double(forKey: WindowState.listWidth) ?? 0
        self.listWidth = width > 0 ? Self.clampedListWidth(width) : Self.defaultListWidth
        self.rememberedSelection = windowState?.string(forKey: WindowState.selection).flatMap(ListSelection.init(storedValue:))
        let fallback = selection.flatMap { index.pullRequest($0)?.id } ?? index.allPullRequests.first { $0.state == .open }?.id
        self.listSelection = fallback.map(ListSelection.pullRequest)
        restoreRememberedSelection()
    }

    /// The selection remembered from the last launch, until the index holds its row. In GitHub
    /// mode the window opens on the mock world before the saved index arrives.
    @ObservationIgnored private var rememberedSelection: ListSelection?

    private func restoreRememberedSelection() {
        guard let remembered = rememberedSelection else { return }
        let found: Bool = switch remembered {
        case .pullRequest(let id): index.pullRequest(id: id) != nil
        case .group: listTree.contains(remembered)
        }
        guard found else { return }
        rememberedSelection = nil
        listSelection = remembered
    }

    /// The open pull requests that match the chosen tab's filter, or the filter applied on it,
    /// and the search, most recently updated first.
    var listedPullRequests: [PullRequest] {
        currentFilter.pullRequests(in: searchedOpen, context: filterContext)
    }

    /// The listed pull requests as the tree the list draws. With no grouping it has no title
    /// rows. A repository's or an author's title row is named by its shorthand when one is set.
    var listTree: ListTree {
        ListTree(grouping: listGrouping, pullRequests: listedPullRequests, viewer: index.viewer,
                 status: status(for:), shorthands: shorthands)
    }

    /// The title row selected, if a title row is.
    var selectedGroup: ListGroup? {
        listSelection?.groupID.flatMap { listTree.group(id: $0) }
    }

    /// Opens or closes one title row, or with `level` every row at its level, as Option-click
    /// on a triangle does.
    func toggleGroup(_ id: String, level: Bool = false) {
        if level {
            listTree.toggleLevel(from: id, in: &closedGroups)
        } else {
            ListTree.toggle(id, in: &closedGroups)
        }
    }

    /// Opens or closes a title row.
    func setGroup(_ id: String, open: Bool) {
        if open { closedGroups.remove(id) } else { closedGroups.insert(id) }
    }

    /// Collapse All or Expand All in the group by menu.
    func setAllGroups(closed: Bool) {
        listTree.setAll(closed: closed, in: &closedGroups)
    }

    /// Opens the title rows that hold the selection, so a selection made some other way than
    /// by clicking, such as by a search, the arrow keys in the search field or a sync, always
    /// shows. Closing a row over the selection moves the selection instead: see `closedGroups`.
    private func revealSelection() {
        guard !listGrouping.isNone, let listSelection else { return }
        let hiding = listTree.ancestorIDs(of: listSelection).filter(closedGroups.contains)
        guard !hiding.isEmpty else { return }
        closedGroups.subtract(hiding)
    }

    /// After the grouping changes: a selected pull request stays selected and shows, and a
    /// selected title row that is no longer in the tree gives way to the first pull request
    /// it held.
    private func keepSelection(after old: ListGrouping) {
        guard let listSelection else { return }
        switch listSelection {
        case .pullRequest:
            revealSelection()
        case .group(let id):
            guard !listTree.contains(listSelection) else { return }
            let before = ListTree(grouping: old, pullRequests: listedPullRequests, viewer: index.viewer, status: status(for:))
            let first = before.group(id: id)?.pullRequests.first ?? listTree.ordered.first
            self.listSelection = first.map { .pullRequest($0.id) }
        }
    }

    /// The open pull requests that match the search, before any filter.
    var searchedOpen: [PullRequest] {
        index.search(searchText, shorthands: shorthands).filter { $0.state == .open }
    }

    /// What a filter needs to match: who "me" is and each pull request's status, from the
    /// statuses this model has worked out already.
    var filterContext: FilterContext {
        // Every open pull request's status is worked out once and kept, so the closure reads
        // a plain dictionary and needs nothing from the main actor.
        for pr in index.allPullRequests where pr.state == .open && statusByID[pr.id] == nil {
            statusByID[pr.id] = pr.statusSentence(for: index.viewer, now: now)
        }
        let known = statusByID, viewer = index.viewer, now = now
        return FilterContext(viewer: viewer) { known[$0.id] ?? $0.statusSentence(for: viewer, now: now) }
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
        /// Where the three fixed views kept their choice before saved filters. Read once, so
        /// the list opens where it was left.
        static let listView = "MainWindow.listView"
        static let selectedFilter = "MainWindow.selectedFilter"
        static let listWidth = "MainWindow.listWidth"
        static let listGrouping = "MainWindow.listGrouping"
        /// The key the one-level grouping used for its collapsed sections. Their ids are the
        /// tree's ids for the same rows, so the set is kept under its old name.
        static let closedGroups = "MainWindow.collapsedSections"
        static let selection = "MainWindow.selection"
    }

    /// The saved filter chosen at the last launch. Before saved filters, the list kept one of
    /// three fixed views, which are now Everything and the two default saved filters. With
    /// nothing remembered, the list opens on Everything.
    private static func rememberedFilterID(_ windowState: UserDefaults?) -> String {
        if let id = windowState?.string(forKey: WindowState.selectedFilter) { return id }
        switch windowState?.string(forKey: WindowState.listView) {
        case "needsMyReview": return SavedFilter.needsMyReview.id
        case "mine": return SavedFilter.mine.id
        default: return SavedFilter.everythingID
        }
    }

    private func remember(_ value: Any?, for key: String) {
        if let value { windowState?.set(value, forKey: key) } else { windowState?.removeObject(forKey: key) }
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
        applySavedFilters(configuration.filters)
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
        let pathBefore = listSelection.map { listTree.ancestorIDs(of: $0) }
        replaceIndex(index, now: now)
        syncSummary = summary
        restoreRememberedSelection()
        let tree = listTree
        if let listSelection, tree.contains(listSelection) || listSelection.pullRequestID.flatMap(index.pullRequest(id:)) != nil {
            // The sync moved the selected pull request under another title row.
            if tree.ancestorIDs(of: listSelection) != pathBefore { revealSelection() }
        } else {
            // The first row on screen, which changing the selection then reveals if need be.
            let first = tree.visiblePullRequests(closed: closedGroups).first ?? listedPullRequests.first
            selection = first?.id ?? index.allPullRequests.first { $0.state == .open }?.id
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
    /// the keyboard. It follows the rows on screen, title rows included.
    func moveSelection(by offset: Int) {
        let rows = listTree.rows(closed: closedGroups).map(\.id)
        guard !rows.isEmpty else { return }
        guard let current = listSelection, let position = rows.firstIndex(of: current) else {
            listSelection = offset >= 0 ? rows.first : rows.last
            return
        }
        listSelection = rows[min(max(0, position + offset), rows.count - 1)]
    }

    /// Left arrow, as in Finder: closes an open title row, and otherwise selects the row that
    /// holds the selection.
    func moveSelectionOut() {
        guard let current = listSelection else { return }
        if let id = current.groupID, !closedGroups.contains(id) {
            closedGroups.insert(id)
        } else if let parent = listTree.parent(of: current) {
            listSelection = parent
        }
    }

    /// Right arrow: opens a closed title row, and on an open one selects its first row.
    func moveSelectionIn() {
        guard let id = listSelection?.groupID, let group = listTree.group(id: id) else { return }
        if closedGroups.contains(id) {
            closedGroups.remove(id)
        } else if let child = group.children.first {
            listSelection = .group(child.id)
        } else if let pr = group.pullRequests.first {
            listSelection = .pullRequest(pr.id)
        }
    }

    /// Double-click or Return on a title row opens or closes it.
    func toggleSelectedGroup() {
        guard let id = listSelection?.groupID else { return }
        ListTree.toggle(id, in: &closedGroups)
    }
}
