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
    /// The pull request shown. Choosing another closes its panes: they belong to the pull
    /// request they were opened on.
    var selection: PullRequest.ID? {
        didSet { if selection != oldValue { panePath = PaneStackPath() } }
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

    @ObservationIgnored private var statusByID: [PullRequest.ID: StatusSentence] = [:]

    init(index: any PullRequestIndex, now: Date, library: LayoutLibrary, selection: PullRequestReference? = nil) {
        self.index = index
        self.now = now
        self.library = library
        self.layoutID = LayoutLibrary.fallbackID
        self.selection = selection.flatMap { index.pullRequest($0)?.id } ?? index.allPullRequests.first { $0.state == .open }?.id
    }

    /// Open pull requests matching the search, most recently updated first.
    var listedPullRequests: [PullRequest] {
        index.search(searchText).filter { $0.state == .open }
    }

    var openCount: Int { index.allPullRequests.count { $0.state == .open } }

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
