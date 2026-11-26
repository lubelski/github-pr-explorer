import AppKit
import GitHubPRExplorerCore
import Observation

/// The configuration folder as the app sees it: the store, what it last read, its history, and
/// the problems seen since launch. Settings reads and changes everything through here, and the
/// main window is told of every change through `onApply`.
///
/// Nothing configurable is kept anywhere else. A change from the Settings window is written to
/// the folder by the store. A change made on disk, by an agent, an editor or `ctl`, is seen by
/// the folder watcher and read again.
@MainActor
@Observable
final class ConfigurationModel {
    struct LoggedProblem: Identifiable, Hashable {
        let id = UUID()
        let date: Date
        let text: String
    }

    @ObservationIgnored let store: ConfigurationStore
    private(set) var snapshot: ConfigurationSnapshot
    private(set) var versions: [ConfigurationVersion] = []
    private(set) var historyProblem: String?
    /// Every problem seen since launch, newest last: files that failed, history that failed,
    /// and changes that could not be made.
    private(set) var problemLog: [LoggedProblem] = []
    /// The version History shows. Nil shows the newest.
    var selectedVersionID: String?
    /// Whether the folder is being watched for changes made on disk.
    var isWatching: Bool { watcher?.isWatching ?? false }

    /// Called after every change is applied, with the new snapshot and the one before it.
    @ObservationIgnored var onApply: ((ConfigurationSnapshot, ConfigurationSnapshot?) -> Void)?
    @ObservationIgnored private var watcher: FolderWatcher?
    @ObservationIgnored private var applied: ConfigurationSnapshot?
    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private var diffs: [String: String] = [:]

    /// - Parameter clock: The time problems are logged at. Renders pass a fixed one.
    init(store: ConfigurationStore, clock: @escaping () -> Date = Date.init) {
        self.store = store
        self.clock = clock
        self.snapshot = store.snapshot
    }

    var folder: URL { store.folder }

    /// The folder as Settings shows it, with `~` for the home folder. A render sets it to the
    /// app's own location, so an image never shows the temporary folder it was drawn from.
    var displayPath: String {
        get {
            if let shownPath { return shownPath }
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let path = store.folder.path
            return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
        }
        set { shownPath = newValue }
    }
    @ObservationIgnored private var shownPath: String?

    /// Creates the folder on first run, reads it, records anything changed while the app was
    /// closed, and starts watching it.
    func start(watching: Bool = true) {
        do throws(ConfigurationError) {
            try store.prepare(author: .app)
        } catch {
            log(error.message)
        }
        refresh()
        if watching {
            watcher = FolderWatcher(folder: store.folder) { [weak self] in self?.reloadFromDisk() }
        }
    }

    /// Reads the folder again and records what changed on disk. The watcher calls it, and so
    /// does the Settings window when it comes forward, in case an edit was missed.
    func reloadFromDisk() {
        store.reload(committingAs: .editedOnDisk)
        watcher?.rearm()
        refresh()
    }

    private func refresh() {
        let previous = applied
        snapshot = store.snapshot
        do throws(ConfigurationError) {
            versions = try store.versions(limit: 500)
        } catch {
            versions = []
            if store.historyProblem == nil { historyProblem = error.message }
        }
        if let problem = store.historyProblem ?? store.history.availability()?.message {
            if problem != historyProblem { log("History: \(problem)") }
            historyProblem = problem
        } else {
            historyProblem = nil
        }
        let known = Set(previous?.problems ?? [])
        for problem in snapshot.problems where !known.contains(problem) {
            log(problem.description)
        }
        if let selectedVersionID, !versions.contains(where: { $0.id == selectedVersionID }) {
            self.selectedVersionID = nil
        }
        applied = snapshot
        if previous != snapshot { onApply?(snapshot, previous) }
    }

    func log(_ text: String) {
        if problemLog.last?.text == text { return }
        problemLog.append(LoggedProblem(date: clock(), text: text))
    }

    // MARK: Changing, all through the store

    private func change(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            log((error as? ConfigurationError)?.message ?? error.localizedDescription)
            NSSound.beep()
        }
        refresh()
    }

    func setAppearance(_ appearance: Appearance) {
        guard appearance != snapshot.settings.appearance else { return }
        change { try store.set(key: "appearance", value: appearance.rawValue, author: .settingsWindow) }
    }

    func setDefaultLayout(_ id: String) {
        guard id != snapshot.settings.defaultLayout else { return }
        change { try store.set(key: "defaultLayout", value: id, author: .settingsWindow) }
    }

    func setHidesBotEvents(_ hides: Bool) {
        guard hides != snapshot.settings.hidesBotEventsInActivity else { return }
        change { try store.set(key: "hidesBotEventsInActivity", value: String(hides), author: .settingsWindow) }
    }

    func setUpdatesAutomatically(_ on: Bool) {
        guard on != snapshot.settings.updatesAutomatically else { return }
        change { try store.set(key: "updatesAutomatically", value: String(on), author: .settingsWindow) }
    }

    func setExperiment(_ experiment: Experiment, on: Bool) {
        change { try store.set(key: "experiments.\(experiment.key)", value: String(on), author: .settingsWindow) }
    }

    func duplicate(_ id: String) {
        change { try store.duplicateLayout(id: id, author: .settingsWindow) }
    }

    func delete(file: String) {
        change { try store.deleteLayout(file: file, author: .settingsWindow) }
    }

    func restore(_ version: ConfigurationVersion, file: String? = nil) {
        change {
            try store.restore(version.id, file: file, author: .settingsWindow)
            selectedVersionID = nil
        }
    }

    /// What a version changed. Kept once read: a version never changes.
    func diff(_ version: ConfigurationVersion) -> String {
        if let known = diffs[version.id] { return known }
        do throws(ConfigurationError) {
            let text = try store.diff(version.id)
            diffs[version.id] = text
            return text
        } catch {
            return error.message
        }
    }

    // MARK: Finder and the clipboard

    func showInFinder(_ file: String? = nil) {
        let url = file.map(store.url(for:)) ?? store.folder
        if FileManager.default.fileExists(atPath: url.path), file != nil {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(store.folder)
        }
    }

    func copyFolderPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(store.folder.path, forType: .string)
    }
}
