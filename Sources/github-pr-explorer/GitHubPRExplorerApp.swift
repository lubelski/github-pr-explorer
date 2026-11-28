import AppKit
import GitHubPRExplorerCore
import SwiftUI

/// The app's main window and its Settings window. Started from `main.swift`, which handles
/// `--render-previews` first, so a render never opens the real configuration folder.
///
/// It reads the built-in mock world through the index, with no network and no sign-in, until
/// `pullRequestSource` is `github`. Then `SyncModel` runs the sync and hands the window each
/// new index. What can be configured comes from the configuration folder, through
/// `ConfigurationModel`.
struct GitHubPRExplorerApp: App {
    @State private var model: AppModel
    @State private var configuration: ConfigurationModel
    @State private var updater: AppUpdater
    @State private var sync: SyncModel

    init() {
        let model = AppModel(
            index: MockWorld.standard.index,
            now: MockWorld.now,
            library: .builtIn(),
            selection: MockWorld.workedExample,
            windowState: .standard)
        let configuration = ConfigurationModel(store: ConfigurationStore(folder: ConfigurationStore.defaultFolder))
        let updater = AppUpdater()
        let sync = SyncModel(app: model)
        // Opening a pull request asks the sync to fetch it sooner. It is never a fetch.
        model.onSelect = { [weak sync] id in sync?.requestSooner(id) }
        model.onSyncNow = { [weak sync] in sync?.syncNow() }
        // Every change, from Settings, a hand edit or ctl, reaches the open window at once.
        configuration.onApply = { [weak model] snapshot, previous in
            model?.apply(snapshot, previous: previous)
            // Where pull requests come from, how often to sync, and what to watch.
            sync.apply(snapshot.settings)
            AppAppearance.apply(snapshot.settings.appearance)
            // settings.json is where this setting lives. Sparkle keeps its own copy, which is
            // set from the file on launch and on every change.
            updater.updatesAutomatically = snapshot.settings.updatesAutomatically
        }
        // The window writes saved filters through the same model as Settings.
        model.savedFilterStore = configuration
        configuration.start()
        _model = State(initialValue: model)
        _configuration = State(initialValue: configuration)
        _updater = State(initialValue: updater)
        _sync = State(initialValue: sync)
    }

    var body: some Scene {
        Window(AppName.display, id: "main") {
            MainWindowView(model: model, updater: updater)
                .environment(\.hidesBotEventsInActivity, model.hidesBotEventsInActivity)
                .frame(minWidth: 900, minHeight: 560)
                // NSApp does not exist yet when the app is made, so the appearance is applied
                // again once the window is up.
                .onAppear { AppAppearance.apply(configuration.snapshot.settings.appearance) }
        }
        .defaultSize(width: 1480, height: 900)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                if updater.isAvailable {
                    Button(AppUpdater.checkTitle) { updater.checkForUpdates() }
                        .disabled(!updater.canCheck)
                }
            }
            CommandGroup(after: .sidebar) {
                Button(model.showsList ? "Hide Pull Request List" : "Show Pull Request List") {
                    withAnimation(.snappy) { model.showsList.toggle() }
                }
                .keyboardShortcut("s", modifiers: [.control, .command])
            }
        }

        // The Settings scene puts Settings… in the app menu, with Command-comma.
        Settings {
            SettingsRootView(configuration: configuration,
                             context: SettingsContext(build: .current, world: .standard, updater: updater, sync: sync,
                                                      index: { [model] in model.index }, now: { [model] in model.now }))
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: SettingsRootView.size.width, height: SettingsRootView.size.height)
    }
}

/// Applies the appearance setting to every window of the app.
@MainActor
enum AppAppearance {
    static func apply(_ appearance: Appearance) {
        guard let app = NSApp else { return }
        let wanted: NSAppearance? = switch appearance {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
        if app.appearance?.name != wanted?.name { app.appearance = wanted }
    }
}
