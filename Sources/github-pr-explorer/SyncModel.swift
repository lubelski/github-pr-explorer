import Foundation
import GitHubPRExplorerCore
import Observation

/// Where the window's pull requests come from, and the sync when that is GitHub.
///
/// In mock mode the window reads the mock world, as it always has, and nothing here runs. In
/// GitHub mode it shows the saved snapshot at once, starts `GitHubSync` on its timer, and
/// hands each new index to the window. Views never reach GitHub: they read the index, and
/// selecting a pull request only asks the sync to fetch it sooner.
@MainActor
@Observable
final class SyncModel {
    private(set) var source: PullRequestSource = .mock
    /// The sync's status as last reported. Nil until GitHub mode has started once.
    private(set) var status: GitHubSyncStatus?
    /// Where `gh` was found, if it was. Only a file check, no network.
    private(set) var ghPath: String?
    /// Where the snapshot is kept.
    let indexLocation: URL
    /// Ages are measured from this. In GitHub mode it moves every 30 seconds.
    private(set) var now: Date = Date()

    @ObservationIgnored private weak var app: AppModel?
    @ObservationIgnored private let sync: GitHubSync?
    @ObservationIgnored private let storage: (any GitHubIndexStorage)?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var clockTask: Task<Void, Never>?
    @ObservationIgnored private var lastSequence = 0
    @ObservationIgnored private var watched: [Repository] = []
    @ObservationIgnored private var interval: TimeInterval = 300

    /// The real sync: the gh login, URLSession, and the index folder in Application Support.
    init(app: AppModel) {
        let storage = JSONFileIndexStorage()
        self.app = app
        self.storage = storage
        self.indexLocation = storage.location
        self.ghPath = GitHubCLILocator.find()?.path
        self.sync = GitHubSync(tokenProvider: GitHubCLITokenProvider(), storage: storage)
        // Updates come from the sync's actor and hop to the main actor through this.
        let box = UpdateBox()
        self.boxedSync = box
        box.model = self
    }

    /// For renders: a fixed status, never a sync, never the network.
    init(previewStatus: GitHubSyncStatus?, ghPath: String?, source: PullRequestSource, now: Date) {
        self.sync = nil
        self.storage = nil
        // Shown with ~ for the home folder, so a render never shows whose Mac drew it.
        self.indexLocation = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/github-pr-explorer/index/github.json")
        self.status = previewStatus
        self.ghPath = ghPath
        self.source = source
        self.now = now
    }

    @ObservationIgnored private var boxedSync: UpdateBox?

    /// Carries updates from the sync's actor to the main actor, dropping any that arrive late.
    private final class UpdateBox: @unchecked Sendable {
        weak var model: SyncModel?
    }

    var summary: SyncStatusSummary? {
        guard source == .github else { return nil }
        return SyncStatusSummary(status: status ?? GitHubSyncStatus(), now: now)
    }

    // MARK: Following the settings

    /// Takes in the settings. Switching the source swaps the window's index. The interval and
    /// the watched repositories go to the sync as they change.
    func apply(_ settings: ConfigurationSettings) {
        watched = settings.watchedRepositoryList
        interval = TimeInterval(settings.syncIntervalSeconds)
        if let sync {
            let watched = watched, interval = interval
            Task { await sync.configure(watchedRepositories: watched, interval: interval) }
        }
        guard settings.pullRequestSource != source else { return }
        source = settings.pullRequestSource
        switch source {
        case .mock: stopGitHub()
        case .github: startGitHub()
        }
    }

    private func startGitHub() {
        guard let sync, let app else { return }
        now = Date()
        // The last snapshot shows at once, before the first fetch returns.
        let saved = try? storage?.load()
        if let saved {
            status = saved.status
            status?.phase = .idle
        }
        app.showGitHub(index: saved?.index ?? GitHubIndexSnapshot(savedAt: now).index, now: now, summary: summary)
        let box = boxedSync
        let watched = watched, interval = interval
        loop = Task {
            await sync.setUpdateHandler { update in
                Task { @MainActor in box?.model?.receive(update) }
            }
            await sync.loadSaved()
            await sync.configure(watchedRepositories: watched, interval: interval)
            await sync.runUntilCancelled()
        }
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                self?.tick()
            }
        }
    }

    private func stopGitHub() {
        loop?.cancel()
        loop = nil
        clockTask?.cancel()
        clockTask = nil
        app?.showMock()
    }

    private func tick() {
        guard source == .github else { return }
        now = Date()
        app?.setNow(now, summary: summary)
    }

    private func receive(_ update: GitHubSync.Update) {
        guard source == .github, update.sequence > lastSequence else { return }
        lastSequence = update.sequence
        status = update.status
        now = Date()
        app?.showGitHub(index: update.index, now: now, summary: summary)
    }

    // MARK: Requests from views

    /// Asks the sync to fetch a pull request sooner, as when it is opened. Not a fetch.
    func requestSooner(_ id: PullRequest.ID) {
        guard source == .github, let sync else { return }
        Task { await sync.requestSooner(id) }
    }

    /// Sync Now in the title bar's menu: in GitHub mode, the next tick runs the list pass. It
    /// keeps to the sync's rules, so a rate limit or a paused budget still waits. In mock mode
    /// it does nothing.
    func syncNow() {
        guard source == .github, let sync else { return }
        Task { await sync.runSoon() }
    }

    /// Check Again in Settings: in GitHub mode, the next tick runs the list pass. In mock mode,
    /// one login check, so Settings can say whose login it is before the switch is turned on.
    func checkAgain() {
        ghPath = GitHubCLILocator.find()?.path
        guard let sync else { return }
        if source == .github {
            Task { await sync.runSoon() }
            return
        }
        let box = boxedSync
        Task {
            await sync.setUpdateHandler { update in
                Task { @MainActor in box?.model?.receiveLoginCheck(update) }
            }
            await sync.loadSaved()
            await sync.run(.loginCheck)
        }
    }

    private func receiveLoginCheck(_ update: GitHubSync.Update) {
        guard update.sequence > lastSequence else { return }
        lastSequence = update.sequence
        status = update.status
    }
}
