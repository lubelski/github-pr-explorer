import AppKit
import GitHubPRExplorerCore
import SwiftUI

/// The Settings window's render states, for `--render-previews`. Each fills a temporary
/// configuration folder of its own, made for the render and removed afterwards. A render never
/// reads or writes the real folder under ~/Library, nor the preferences.
///
/// Versions are dated a fixed time before the mock world's `now`, and History measures from
/// that moment, so the images read the same on every run.
@MainActor
enum SettingsPreviews {
    nonisolated static let size = CGSize(width: 900, height: 620)

    struct State {
        let name: String
        var size = CGSize(width: 900, height: 620)
        let view: () -> AnyView
    }

    /// Folders made by this run, removed once every image is drawn.
    private(set) static var folders: [URL] = []

    static func removeFolders() {
        for folder in folders { try? FileManager.default.removeItem(at: folder) }
        folders = []
    }

    /// A store in a new temporary folder, with each version a few minutes after the last.
    static func store(gitPath: String = ConfigurationHistory.defaultGitPath) -> ConfigurationStore {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "github-pr-explorer-render-\(UUID().uuidString)", directoryHint: .isDirectory)
        folders.append(folder)
        var date = MockWorld.now.addingTimeInterval(-26 * 3600)
        let steps: [TimeInterval] = [0, 3 * 3600, 7 * 3600, 40 * 60, 9 * 60, 4 * 3600, 2 * 3600, 25 * 60]
        var step = 0
        return ConfigurationStore(folder: folder, gitPath: gitPath, commitDate: {
            date = date.addingTimeInterval(steps[min(step, steps.count - 1)])
            step += 1
            return date
        })
    }

    static func write(_ text: String, _ file: String, in store: ConfigurationStore) {
        let url = store.url(for: file)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(text.utf8).write(to: url, options: .atomic)
    }

    static let triageLayout = """
        {
          "formatVersion" : 1,
          "id" : "triage",
          "name" : "Triage",
          "tabs" : [
            {
              "columns" : [
                { "blocks" : [ { "kind" : "checks", "size" : "small" }, { "kind" : "reviewers", "size" : "small" } ], "width" : 1 },
                { "blocks" : [ { "kind" : "description", "size" : "large" }, { "kind" : "threads", "size" : "small" } ], "width" : 2 },
                { "blocks" : [ { "kind" : "activity", "size" : "small" }, { "kind" : "labelsAndMetadata", "size" : "small" } ], "width" : 1 }
              ],
              "name" : "Triage"
            }
          ]
        }

        """

    /// A configuration a team has been using for a day: two layouts of its own, a few changes
    /// from Settings, one by hand and one from ctl.
    static func usedStore() -> ConfigurationStore {
        let store = store()
        _ = try? store.prepare(author: .app)
        _ = try? store.duplicateLayout(id: "tabbed", as: "review", name: "Review", author: .settingsWindow)
        write(triageLayout, "layouts/triage.json", in: store)
        store.reload(committingAs: .editedOnDisk)
        _ = try? store.set(key: "defaultLayout", value: "review", author: .commandLine)
        _ = try? store.set(key: "appearance", value: "dark", author: .settingsWindow)
        _ = try? store.set(key: "hidesBotEventsInActivity", value: "false", author: .settingsWindow)
        return store
    }

    /// Placeholder shorthands for the mock world's repositories and people.
    static let sampleShorthands: [(ShorthandKind, String, String)] = [
        (.repository, "acme/api", "API"), (.repository, "acme/web", "Web"), (.repository, "acme/infra", "Infra"),
        (.person, "sam-rivera", "Sam"), (.person, "ada-park", "Ada"), (.person, "jo-lindqvist", "Jo"),
        (.person, "max-chen", "Max"), (.person, "deploy-preview-bot", "Previews"),
    ]

    /// A store with the sample shorthands, and with `extra` after them.
    static func shorthandStore(_ extra: [(ShorthandKind, String, String)] = []) -> ConfigurationStore {
        let store = store()
        for (kind, target, shorthand) in sampleShorthands + extra {
            _ = try? store.setShorthand(kind, for: target, to: shorthand, author: .settingsWindow)
        }
        return store
    }

    static func model(_ store: ConfigurationStore, configure: (ConfigurationModel) -> Void = { _ in }) -> ConfigurationModel {
        let model = ConfigurationModel(store: store, clock: { MockWorld.now.addingTimeInterval(-12 * 60) })
        model.start(watching: false)
        model.displayPath = "~/Library/Application Support/github-pr-explorer/config"
        configure(model)
        return model
    }

    /// A sync for renders: a fixed status, never a sync, never the network.
    static func previewSync(_ status: GitHubSyncStatus? = nil, ghPath: String? = "/opt/homebrew/bin/gh",
                            source: PullRequestSource = .mock) -> SyncModel {
        SyncModel(previewStatus: status, ghPath: ghPath, source: source, now: MockWorld.now)
    }

    static func window(_ model: ConfigurationModel, _ section: SettingsSection, sync: SyncModel = previewSync()) -> AnyView {
        let context = SettingsContext(build: .preview, world: .standard, updater: .unavailable(), sync: sync)
        return AnyView(SettingsRootView(configuration: model, context: context, renderedSection: section)
            .environment(\.historyNow, MockWorld.now))
    }

    static func states() -> [State] {
        [
            State(name: "settings-general") {
                let store = store()
                _ = try? store.prepare(author: .app)
                return window(model(store), .general)
            },
            State(name: "settings-general-broken-settings") {
                let store = usedStore()
                write(#"{"formatVersion": 1, "appearance": "dark", "defaultLayuot": "triage"}"#, "settings.json", in: store)
                return window(model(store), .general)
            },
            State(name: "settings-layouts-built-in-only") {
                let store = store()
                _ = try? store.prepare(author: .app)
                return window(model(store), .layouts)
            },
            State(name: "settings-layouts") {
                window(model(usedStore()), .layouts)
            },
            State(name: "settings-layouts-broken-file") {
                let store = usedStore()
                let model = model(store)
                // One file wrong from the start, and one that worked and then went wrong.
                write(#"{"formatVersion": 1, "id": "standup", "name": "Standup", "tabs": [{"name": "Main", "columns": [{"width": 1, "blocks": [{"kind": "summary", "size": "large"}]}]}]}"#,
                      "layouts/standup.json", in: store)
                write(triageLayout.replacingOccurrences(of: "\"width\" : 2", with: "\"width\" : 0"), "layouts/triage.json", in: store)
                model.reloadFromDisk()
                return window(model, .layouts)
            },
            State(name: "settings-history") {
                let store = usedStore()
                let versions = (try? store.versions()) ?? []
                // Bring back the layouts as they were before the default changed, as a version.
                if versions.count > 3 { _ = try? store.restore(versions[3].id, file: "settings.json", author: .settingsWindow) }
                return window(model(store) { model in
                    model.selectedVersionID = model.versions.first { $0.summary.hasPrefix("Changed") || $0.summary.hasPrefix("Added") }?.id
                }, .history)
            },
            State(name: "settings-history-latest") {
                window(model(usedStore()), .history)
            },
            State(name: "settings-history-unavailable") {
                let store = store(gitPath: "/nonexistent/git")
                return window(model(store), .history)
            },
            // The GitHub section (MAC-59), with a made-up sync status and placeholder names.
            State(name: "settings-github-mock") {
                let store = store()
                _ = try? store.prepare(author: .app)
                var status = GitHubSyncStatus()
                status.hasLogin = true
                status.accountLogin = "robin-quill"
                return window(model(store), .github, sync: previewSync(status))
            },
            State(name: "settings-github-on", size: CGSize(width: 900, height: 900)) {
                let store = store()
                _ = try? store.set(key: "pullRequestSource", value: "github", author: .settingsWindow)
                _ = try? store.set(key: "watchedRepositories", value: "acme/api,acme/web", author: .settingsWindow)
                return window(model(store), .github, sync: previewSync(Self.syncedStatus, source: .github))
            },
            State(name: "settings-github-gh-missing", size: CGSize(width: 900, height: 900)) {
                let store = store()
                _ = try? store.set(key: "pullRequestSource", value: "github", author: .settingsWindow)
                var status = GitHubSyncStatus()
                status.hasLogin = false
                status.problem = .ghMissing
                return window(model(store), .github, sync: previewSync(status, ghPath: nil, source: .github))
            },
            State(name: "settings-github-rate-limited", size: CGSize(width: 900, height: 900)) {
                let store = store()
                _ = try? store.set(key: "pullRequestSource", value: "github", author: .settingsWindow)
                var status = Self.syncedStatus
                status.problem = .rateLimited(until: MockWorld.now.addingTimeInterval(38 * 60))
                return window(model(store), .github, sync: previewSync(status, source: .github))
            },
            // Shorthands (MAC-73): none, several, and two things that share one.
            State(name: "settings-shorthands-empty") {
                let store = store()
                _ = try? store.prepare(author: .app)
                return window(model(store), .shorthands)
            },
            State(name: "settings-shorthands", size: CGSize(width: 900, height: 900)) {
                window(model(shorthandStore()), .shorthands)
            },
            State(name: "settings-shorthands-clash", size: CGSize(width: 900, height: 900)) {
                window(model(shorthandStore([(.repository, "acme/docs", "Web")])), .shorthands)
            },
            State(name: "settings-experiments") {
                let store = store()
                _ = try? store.prepare(author: .app)
                return window(model(store), .experiments)
            },
            // Taller than the window, to show the whole section.
            State(name: "settings-debugging", size: CGSize(width: 900, height: 1240)) {
                window(model(usedStore()), .debugging)
            },
            State(name: "settings-debugging-problems", size: CGSize(width: 900, height: 1460)) {
                let store = usedStore()
                let model = model(store)
                write(#"{"formatVersion": 1, "id": "standup", "name": "Standup", "tabs": []}"#, "layouts/standup.json", in: store)
                model.reloadFromDisk()
                return window(model, .debugging)
            },
        ]
    }

    /// A sync that has run a while, with placeholder counts.
    static var syncedStatus: GitHubSyncStatus {
        var status = GitHubSyncStatus()
        status.hasLogin = true
        status.accountLogin = "robin-quill"
        status.lastSuccessAt = MockWorld.now.addingTimeInterval(-4 * 60)
        status.pullRequestCount = 42
        status.detailedCount = 40
        status.rateLimits["graphql"] = RateLimitReading(resource: "graphql", limit: 5000, remaining: 4870,
                                                        resetAt: MockWorld.now.addingTimeInterval(40 * 60), readAt: MockWorld.now)
        status.rateLimits["core"] = RateLimitReading(resource: "core", limit: 5000, remaining: 4931,
                                                     resetAt: MockWorld.now.addingTimeInterval(22 * 60), readAt: MockWorld.now)
        return status
    }

    /// The main window after `settings.json` was changed: the default layout and the bot
    /// events setting reach the open window through `AppModel.apply`, as they do in the app.
    static func mainWindowStates(model: @escaping (ConfigurationSnapshot) -> AppModel) -> [State] {
        // The same window with no shorthands and with the sample ones, each listing every open
        // pull request, so the two can be compared row by row.
        func shorthandWindow(_ store: ConfigurationStore, configure: (AppModel) -> Void = { _ in }) -> AnyView {
            store.reload()
            let snapshot = store.snapshot
            let app = model(snapshot)
            app.apply(snapshot, previous: nil)
            app.listView = .everythingOpen
            configure(app)
            return AnyView(MainWindowView(model: app, updater: .unavailable())
                .environment(\.hidesBotEventsInActivity, app.hidesBotEventsInActivity))
        }
        return [
            State(name: "shorthands-none", size: CGSize(width: 1560, height: 940)) {
                let store = store()
                _ = try? store.prepare(author: .app)
                return shorthandWindow(store)
            },
            State(name: "shorthands-set", size: CGSize(width: 1560, height: 940)) {
                shorthandWindow(shorthandStore())
            },
            // The search finds a pull request by its repository's shorthand.
            State(name: "shorthands-search", size: CGSize(width: 1560, height: 940)) {
                shorthandWindow(shorthandStore()) { $0.searchText = "Web Ada" }
            },
            // The page's other tabs, where threads, owners and metadata draw names.
            State(name: "shorthands-page-tabbed-threads", size: CGSize(width: 1560, height: 940)) {
                shorthandWindow(shorthandStore()) { app in
                    app.layoutID = "tabbed"
                    app.selectedTab = 3
                }
            },
            // The diff with a thread open: the line's marker and the thread's comments.
            State(name: "shorthands-diff-thread", size: CGSize(width: 1560, height: 940)) {
                shorthandWindow(shorthandStore()) { app in
                    guard let pr = app.selectedPullRequest,
                          let thread = pr.reviewThreads.first(where: { $0.path == "auth/middleware.ts" }),
                          let path = pr.paneStack(showingThread: thread.id) else { return }
                    app.panePath = path
                    app.buildDocumentNow(for: pr, path: thread.path)
                }
            },
            State(name: "shorthands-page-tabbed-overview", size: CGSize(width: 1560, height: 940)) {
                shorthandWindow(shorthandStore()) { app in
                    app.layoutID = "tabbed"
                    app.selectedTab = 0
                }
            },

            State(name: "page-4826-configured-default", size: CGSize(width: 1560, height: 940)) {
                let store = usedStore()
                store.reload()
                let snapshot = store.snapshot
                let app = model(snapshot)
                app.apply(snapshot, previous: nil)
                return AnyView(MainWindowView(model: app, updater: .unavailable())
                    .environment(\.hidesBotEventsInActivity, app.hidesBotEventsInActivity))
            },
        ]
    }
}
