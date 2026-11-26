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
