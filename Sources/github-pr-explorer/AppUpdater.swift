import Foundation
import GitHubPRExplorerCore
import Observation
import Sparkle

/// Keeps the app up to date with Sparkle. Every Sparkle reference in the app is in this file.
///
/// Only a release build updates itself. `scripts/release.sh` writes the feed address and the
/// public signing key into Info.plist. A build without them, such as one from
/// `scripts/bundle.sh` alone, has no updater, so a development copy is never replaced.
///
/// A release build checks about once a day and downloads a newer release without asking
/// (`SUEnableAutomaticChecks` and `SUAutomaticallyUpdate` in Info.plist). It does not relaunch
/// on its own while the window is open. Instead `pending` says an update is waiting, the title
/// bar shows a small indicator, and clicking it calls `installPendingUpdate()`. A downloaded
/// update also installs the next time the app quits, which is Sparkle's own behavior.
@MainActor
@Observable
final class AppUpdater {
    /// Whether this build can update itself.
    let isAvailable: Bool

    /// The title of every Check for Updates item.
    static let checkTitle = "Check for Updates…"

    /// The update waiting for the person, or nil when there is none. The title bar shows it.
    private(set) var pending: AppUpdates.Pending?

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private let delegate = Delegate()
    /// Sparkle's block that quits, installs and relaunches into a downloaded update.
    @ObservationIgnored private var immediateInstall: (() -> Void)?

    /// `info` is the bundle's Info.plist.
    init(info: [String: Any]? = Bundle.main.infoDictionary) {
        isAvailable = AppUpdates.hasFeed(info)
        delegate.owner = self
        guard isAvailable else { return }
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: delegate, userDriverDelegate: delegate)
    }

    /// A build with no feed, for previews and tests.
    static func unavailable() -> AppUpdater {
        AppUpdater(info: nil)
    }

    /// A build with no feed that shows an update as waiting, for renders of the title bar.
    static func preview(pending: AppUpdates.Pending) -> AppUpdater {
        let updater = AppUpdater(info: nil)
        updater.pending = pending
        return updater
    }

    /// False while a check is already running.
    var canCheck: Bool { controller?.updater.canCheckForUpdates ?? false }

    /// Whether Sparkle looks for, downloads, and installs updates without asking.
    var updatesAutomatically: Bool {
        get {
            guard let updater = controller?.updater else { return false }
            return updater.automaticallyChecksForUpdates && updater.automaticallyDownloadsUpdates
        }
        set {
            controller?.updater.automaticallyChecksForUpdates = newValue
            controller?.updater.automaticallyDownloadsUpdates = newValue
        }
    }

    /// Checks now and shows Sparkle's own windows with the result.
    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    /// What clicking the title bar indicator does. A downloaded update quits and relaunches
    /// into the new version. One that is only found shows Sparkle's window, which offers to
    /// download and install it.
    func installPendingUpdate() {
        if let install = immediateInstall {
            immediateInstall = nil
            pending = nil
            install()
        } else {
            checkForUpdates()
        }
    }

    // MARK: From Sparkle

    fileprivate func found(_ item: SUAppcastItem, stage: AppUpdates.Pending.Stage) {
        // Once downloaded, it stays "ready" even if Sparkle reports the same update again.
        if pending?.stage == .readyToInstall, stage == .available { return }
        pending = AppUpdates.Pending(stage: stage, version: item.displayVersionString)
    }

    fileprivate func readyToInstall(_ item: SUAppcastItem, install: @escaping () -> Void) {
        immediateInstall = install
        pending = AppUpdates.Pending(stage: .readyToInstall, version: item.displayVersionString)
    }

    fileprivate func sessionFinished() {
        // A downloaded update still waits for the click or the next quit.
        if immediateInstall == nil { pending = nil }
    }

    /// Sparkle's delegates. Sparkle calls them on the main thread.
    private final class Delegate: NSObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
        weak var owner: AppUpdater?

        /// A downloaded update that would install when the app quits. Hold it and let the title
        /// bar offer it, instead of relaunching while the person is reading a pull request.
        func updater(
            _ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
            immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
        ) -> Bool {
            MainActor.assumeIsolated { owner?.readyToInstall(item, install: immediateInstallHandler) }
            return true
        }

        // Gentle reminders: an update found by a scheduled check is not shown in a window of
        // Sparkle's. The title bar shows it instead, and a click shows Sparkle's window.
        var supportsGentleScheduledUpdateReminders: Bool { true }

        func standardUserDriverShouldHandleShowingScheduledUpdate(
            _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
        ) -> Bool {
            false
        }

        func standardUserDriverWillHandleShowingUpdate(
            _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
        ) {
            guard !handleShowingUpdate else { return }
            MainActor.assumeIsolated {
                owner?.found(update, stage: state.stage == .notDownloaded ? .available : .readyToInstall)
            }
        }

        func standardUserDriverWillFinishUpdateSession() {
            MainActor.assumeIsolated { owner?.sessionFinished() }
        }
    }
}
