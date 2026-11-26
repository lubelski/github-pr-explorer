import Foundation
import Testing
@testable import GitHubPRExplorerCore

/// A configuration folder in the temporary directory, removed afterwards. No test reads or
/// writes the real folder under ~/Library.
final class TemporaryConfiguration {
    let folder: URL
    let store: ConfigurationStore
    private var clock = Date(timeIntervalSince1970: 1_764_000_000)

    init(gitPath: String = ConfigurationHistory.defaultGitPath) {
        folder = FileManager.default.temporaryDirectory
            .appending(path: "github-pr-explorer-config-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        // Each version a minute after the one before, so history reads in a fixed order.
        var dates = clock
        store = ConfigurationStore(folder: folder, gitPath: gitPath, commitDate: {
            dates = dates.addingTimeInterval(60)
            return dates
        })
        #expect(!folder.path.contains("/Library/Application Support"))
    }

    deinit { try? FileManager.default.removeItem(at: folder) }

    func write(_ text: String, to file: String) throws {
        let url = folder.appending(path: file)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func read(_ file: String) throws -> String {
        try String(contentsOf: folder.appending(path: file), encoding: .utf8)
    }

    func exists(_ file: String) -> Bool { FileManager.default.fileExists(atPath: folder.appending(path: file).path) }

    func versions() throws -> [ConfigurationVersion] { try store.versions() }
}

let myLayout = """
    {"formatVersion": 1, "id": "mine", "name": "Mine", "tabs": [{"name": "All", "columns": [{"width": 1, "blocks": [{"kind": "checks", "size": "small"}]}]}]}
    """

@Suite struct ConfigurationStoreTests {
    @Test func firstRunCreatesTheFolder() throws {
        let config = TemporaryConfiguration()
        #expect(!config.store.exists)
        let snapshot = try config.store.prepare(author: .app)
        #expect(config.exists("settings.json"))
        #expect(config.exists("README.md"))
        #expect(config.exists(".git"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: config.store.layoutsURL.path).isEmpty,
                "copies of the built-in layouts are not written")
        #expect(try ConfigurationSettings.decode(Data(config.read("settings.json").utf8)) == .defaults)
        #expect(snapshot.problems.isEmpty, "\(snapshot.problems)")
        #expect(snapshot.layouts.map(\.id) == ["decision-first", "tabbed"])
        #expect(snapshot.layouts.allSatisfy { $0.source == .builtIn })
        #expect(try config.read("README.md").contains("github-pr-explorer-ctl config validate"))

        let versions = try config.versions()
        #expect(versions.count == 1)
        #expect(versions[0].summary == "Created the configuration folder")
        #expect(versions[0].author == "app")
        #expect(Set(versions[0].files) == [".gitignore", "README.md", "settings.json"])

        // A second start changes nothing and records nothing.
        try config.store.prepare(author: .app)
        #expect(try config.versions().count == 1)
    }

    @Test func aValidEditOnDiskIsPickedUpAndCommitted() throws {
        let config = TemporaryConfiguration()
        try config.store.prepare(author: .app)
        try config.write(#"{"formatVersion": 1, "defaultLayout": "tabbed", "appearance": "dark"}"#, to: "settings.json")
        let snapshot = config.store.reload(committingAs: .editedOnDisk)
        #expect(snapshot.settings.defaultLayout == "tabbed")
        #expect(snapshot.settings.appearance == .dark)
        #expect(snapshot.settings.hidesBotEventsInActivity, "a key left out takes its default")
        #expect(snapshot.defaultLayout.id == "tabbed")
        let latest = try #require(try config.versions().first)
        #expect(latest.summary == "Changed settings.json")
        #expect(latest.author == "edited on disk")
        #expect(latest.files == ["settings.json"])
        #expect(try config.versions().count == 2)
    }

    @Test func anInvalidEditIsRefusedAndTheLastGoodKept() throws {
        let config = TemporaryConfiguration()
        try config.store.prepare(author: .app)
        try config.store.set(key: "defaultLayout", value: "tabbed", author: .commandLine)
        #expect(try config.versions().count == 2)

        // Half-written JSON.
        try config.write(#"{"formatVersion": 1, "defaultLayout": "#, to: "settings.json")
        var snapshot = config.store.reload(committingAs: .editedOnDisk)
        #expect(snapshot.settings.defaultLayout == "tabbed")
        let problem = try #require(snapshot.problems.first { $0.file == "settings.json" })
        #expect(problem.refusesFile && problem.lastGoodInUse)
        #expect(problem.problem.contains("not valid JSON"))
        #expect(problem.description.contains("The last version that worked is still in use."))
        #expect(try config.versions().count == 2, "a refused file is not committed")

        // A misspelled key is refused too, with where it is.
        try config.write(#"{"formatVersion": 1, "defaultLayuot": "decision-first"}"#, to: "settings.json")
        snapshot = config.store.reload(committingAs: .editedOnDisk)
        let misspelled = try #require(snapshot.problems.first { $0.file == "settings.json" })
        #expect(misspelled.path == "defaultLayuot")
        #expect(misspelled.problem.contains("unknown key"))
        #expect(snapshot.settings.defaultLayout == "tabbed")

        // A layout file that is wrong from the start is left out and reported, while a valid
        // change beside it is still committed.
        try config.write(myLayout.replacingOccurrences(of: "\"checks\"", with: "\"summary\""), to: "layouts/mine.json")
        try config.write(#"{"formatVersion": 1, "appearance": "dark"}"#, to: "settings.json")
        snapshot = config.store.reload(committingAs: .editedOnDisk)
        #expect(!snapshot.layouts.contains { $0.id == "mine" })
        let layoutProblem = try #require(snapshot.problems.first { $0.file == "layouts/mine.json" })
        #expect(layoutProblem.path == "tabs[0].columns[0].blocks[0].kind")
        #expect(!layoutProblem.lastGoodInUse)
        #expect(snapshot.library.problems.count == 1, "the window's footer sees layout problems")
        let latest = try #require(try config.versions().first)
        #expect(latest.files == ["settings.json"])

        // A store started later, as ctl or the app after a relaunch, falls back on the last
        // recorded version of a file that is wrong now.
        try config.write(#"{"formatVersion": 1, "appearance": "purple"}"#, to: "settings.json")
        let fresh = ConfigurationStore(folder: config.folder)
        let freshSnapshot = fresh.reload()
        #expect(freshSnapshot.settings.appearance == .dark)
        #expect(freshSnapshot.problems.first { $0.file == "settings.json" }?.lastGoodInUse == true)
    }

    @Test func aLayoutKeepsItsLastGoodVersion() throws {
        let config = TemporaryConfiguration()
        try config.store.prepare(author: .app)
        try config.write(myLayout, to: "layouts/mine.json")
        var snapshot = config.store.reload(committingAs: .editedOnDisk)
        #expect(snapshot.entry(id: "mine")?.source == .file("layouts/mine.json", overridesBuiltIn: false))
        try config.write(myLayout.replacingOccurrences(of: "\"width\": 1", with: "\"width\": 0"), to: "layouts/mine.json")
        snapshot = config.store.reload(committingAs: .editedOnDisk)
        #expect(snapshot.entry(id: "mine")?.layout.tabs[0].columns[0].width == 1)
        #expect(snapshot.problems.first?.lastGoodInUse == true)
    }

    @Test func restoreBringsBackAnEarlierVersionAsANewOne() throws {
        let config = TemporaryConfiguration()
        try config.store.prepare(author: .app)
        try config.store.set(key: "defaultLayout", value: "tabbed", author: .settingsWindow)
        try config.store.set(key: "appearance", value: "dark", author: .settingsWindow)
        try config.write(myLayout, to: "layouts/mine.json")
        config.store.reload(committingAs: .editedOnDisk)
        let versions = try config.versions()
        #expect(versions.map(\.summary) == ["Added layouts/mine.json", "Set appearance to Dark",
                                            "Set the default layout to Tabbed", "Created the configuration folder"])
        let tabbedVersion = versions[2]

        let restored = try #require(try config.store.restore(tabbedVersion.shortID, author: .settingsWindow))
        #expect(restored.summary.hasPrefix("Restored the configuration to version \(tabbedVersion.shortID)"))
        #expect(restored.author == "Settings window")
        #expect(config.store.snapshot.settings.appearance == .system)
        #expect(config.store.snapshot.settings.defaultLayout == "tabbed")
        #expect(!config.exists("layouts/mine.json"), "a file added after that version is not in it")
        let after = try config.versions()
        #expect(after.count == 5)
        #expect(after.dropFirst().map(\.id) == versions.map(\.id), "nothing is lost")

        // One file: bring the layout back from the version that added it.
        let one = try #require(try config.store.restore(versions[0].id, file: "layouts/mine.json", author: .commandLine))
        #expect(one.files == ["layouts/mine.json"])
        #expect(config.store.snapshot.entry(id: "mine") != nil)
        #expect(config.store.snapshot.settings.appearance == .system, "other files are left alone")

        // A version that does not exist.
        #expect(throws: ConfigurationError.self) { try config.store.restore("0000000", author: .commandLine) }
    }

    @Test func diffShowsWhatAVersionChanged() throws {
        let config = TemporaryConfiguration()
        try config.store.prepare(author: .app)
        try config.store.set(key: "appearance", value: "light", author: .commandLine)
        let latest = try #require(try config.versions().first)
        let diff = try config.store.diff(latest.shortID)
        #expect(diff.contains("-  \"appearance\" : \"system\","))
        #expect(diff.contains("+  \"appearance\" : \"light\","))
    }

    @Test func aLayoutFileOverridesTheBuiltInWithItsID() throws {
        let config = TemporaryConfiguration()
        try config.store.prepare(author: .app)
        let ours = myLayout.replacingOccurrences(of: "\"id\": \"mine\", \"name\": \"Mine\"", with: "\"id\": \"tabbed\", \"name\": \"Our tabbed\"")
        try config.write(ours, to: "layouts/tabbed.json")
        let snapshot = config.store.reload(committingAs: .editedOnDisk)
        #expect(snapshot.layouts.map(\.id) == ["decision-first", "tabbed"], "it takes the built-in's place")
        #expect(snapshot.layouts[1].source == .file("layouts/tabbed.json", overridesBuiltIn: true))
        #expect(snapshot.library.layout(id: "tabbed").name == "Our tabbed")
        #expect(snapshot.problems.isEmpty)

        // A file must be named after its id.
        try config.write(myLayout, to: "layouts/other-name.json")
        let misnamed = config.store.reload(committingAs: .editedOnDisk)
        #expect(misnamed.problems.first?.file == "layouts/other-name.json")
        #expect(misnamed.problems.first?.problem.contains("layouts/mine.json") == true)
        #expect(misnamed.entry(id: "mine") == nil)
    }

    @Test func twoRapidEditsBothEndUpInHistory() throws {
        let config = TemporaryConfiguration()
        try config.store.prepare(author: .app)
        // Two changes through the store, one straight after the other: two versions.
        try config.store.set(key: "appearance", value: "dark", author: .settingsWindow)
        try config.store.set(key: "hidesBotEventsInActivity", value: "false", author: .settingsWindow)
        var versions = try config.versions()
        #expect(versions.count == 3)
        #expect(versions[0].summary == "Bot events start shown in Activity")
        #expect(versions[1].summary == "Set appearance to Dark")

        // Two files changed on disk before the app looks: both are in the next version.
        try config.write(myLayout, to: "layouts/mine.json")
        try config.write(#"{"formatVersion": 1, "defaultLayout": "mine"}"#, to: "settings.json")
        config.store.reload(committingAs: .editedOnDisk)
        versions = try config.versions()
        #expect(versions.count == 4)
        #expect(Set(versions[0].files) == ["layouts/mine.json", "settings.json"])
        #expect(versions[0].summary == "Changed settings.json, added layouts/mine.json")
        #expect(config.store.snapshot.defaultLayout.id == "mine")
    }

    @MainActor @Test func theWatcherSeesAnEditAndTheStoreCommitsIt() async throws {
        let config = TemporaryConfiguration()
        try config.store.prepare(author: .app)
        var reloads = 0
        let watcher = FolderWatcher(folder: config.folder, delay: .milliseconds(50)) {
            reloads += 1
            config.store.reload(committingAs: .editedOnDisk)
        }
        #expect(watcher.isWatching)

        // Written in place, as a shell's `>` does.
        let handle = try FileHandle(forWritingTo: config.store.settingsURL)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data(#"{"formatVersion": 1, "appearance": "light"}"#.utf8))
        try handle.close()
        try await waitUntil { config.store.snapshot.settings.appearance == .light }

        // Two files written one after the other, atomically, as an editor saves: both end up
        // in history.
        try Data(myLayout.utf8).write(to: config.folder.appending(path: "layouts/mine.json"), options: .atomic)
        try Data(#"{"formatVersion": 1, "appearance": "light", "defaultLayout": "mine"}"#.utf8)
            .write(to: config.store.settingsURL, options: .atomic)
        try await waitUntil { config.store.snapshot.defaultLayout.id == "mine" }
        let files = Set(try config.versions().prefix(2).flatMap(\.files))
        #expect(files.isSuperset(of: ["layouts/mine.json", "settings.json"]))
        #expect(try config.store.history.pendingChanges().isEmpty)
        #expect(reloads >= 2)
        _ = watcher
    }

    @Test func historyFailingNeverBlocksASave() throws {
        let config = TemporaryConfiguration(gitPath: "/nonexistent/git")
        try config.store.prepare(author: .app)
        #expect(config.store.historyProblem?.contains("git was not found") == true)
        try config.store.set(key: "defaultLayout", value: "tabbed", author: .settingsWindow)
        #expect(config.store.snapshot.settings.defaultLayout == "tabbed")
        #expect(try config.read("settings.json").contains("\"tabbed\""))
        #expect(try config.versions().isEmpty)
    }

    @Test func historyUsesItsOwnIdentity() throws {
        let config = TemporaryConfiguration()
        try config.store.prepare(author: .app)
        let author = try config.store.history.git(["log", "-1", "--format=%an <%ae>|%cn <%ce>"])
        #expect(author.trimmingCharacters(in: .newlines)
                == "github-pr-explorer <github-pr-explorer@localhost>|github-pr-explorer <github-pr-explorer@localhost>")
        let local = try config.read(".git/config")
        #expect(!local.contains("[user]"), "the identity is passed per command, not written to any config")
    }

    @Test func duplicateAndDeleteALayout() throws {
        let config = TemporaryConfiguration()
        try config.store.prepare(author: .app)
        let copy = try config.store.duplicateLayout(id: "tabbed", author: .settingsWindow)
        #expect(copy.id == "tabbed-copy")
        #expect(copy.layout.name == "Tabbed copy")
        #expect(copy.source == .file("layouts/tabbed-copy.json", overridesBuiltIn: false))
        #expect(copy.layout.tabs == LayoutLibrary.builtIn().layout(id: "tabbed").tabs)
        #expect(try config.store.duplicateLayout(id: "tabbed", author: .settingsWindow).id == "tabbed-copy-2")
        #expect(throws: ConfigurationError.self) { try config.store.duplicateLayout(id: "tabbed", as: "tabbed-copy", author: .commandLine) }
        #expect(throws: ConfigurationError.self) { try config.store.duplicateLayout(id: "tabbed", as: "Not An ID", author: .commandLine) }
        #expect(throws: ConfigurationError.self) { try config.store.duplicateLayout(id: "nope", author: .commandLine) }

        try config.store.deleteLayout(file: "layouts/tabbed-copy.json", author: .settingsWindow)
        #expect(config.store.snapshot.entry(id: "tabbed-copy") == nil)
        let latest = try #require(try config.versions().first)
        #expect(latest.summary == "Deleted the layout Tabbed copy, layouts/tabbed-copy.json")
        #expect(throws: ConfigurationError.self) { try config.store.deleteLayout(file: "settings.json", author: .settingsWindow) }
    }

    @Test func settingsAreNotChangedWhileTheFileIsWrong() throws {
        let config = TemporaryConfiguration()
        try config.store.prepare(author: .app)
        try config.write("{ oops", to: "settings.json")
        #expect(throws: ConfigurationError.self) { try config.store.set(key: "appearance", value: "dark", author: .settingsWindow) }
        #expect(try config.read("settings.json") == "{ oops", "a hand edit being fixed is never overwritten")
    }

    @Test func badSettingValuesAreRefused() throws {
        let config = TemporaryConfiguration()
        try config.store.prepare(author: .app)
        #expect(throws: ConfigurationError.self) { try config.store.set(key: "appearance", value: "purple", author: .commandLine) }
        #expect(throws: ConfigurationError.self) { try config.store.set(key: "defaultLayout", value: "nope", author: .commandLine) }
        #expect(throws: ConfigurationError.self) { try config.store.set(key: "hidesBotEventsInActivity", value: "maybe", author: .commandLine) }
        #expect(throws: ConfigurationError.self) { try config.store.set(key: "experiments.none", value: "true", author: .commandLine) }
        #expect(throws: ConfigurationError.self) { try config.store.set(key: "colour", value: "red", author: .commandLine) }
        #expect(try config.versions().count == 1)
    }

    @Test func aDefaultLayoutNoLayoutHasIsReportedButApplied() throws {
        let config = TemporaryConfiguration()
        try config.store.prepare(author: .app)
        try config.write(#"{"formatVersion": 1, "defaultLayout": "gone", "appearance": "dark"}"#, to: "settings.json")
        let snapshot = config.store.reload(committingAs: .editedOnDisk)
        #expect(snapshot.settings.appearance == .dark)
        #expect(snapshot.defaultLayout.id == "decision-first")
        let problem = try #require(snapshot.problems.first)
        #expect(!problem.refusesFile && problem.path == "defaultLayout")
        #expect(try config.versions().first?.files == ["settings.json"], "the file was applied, so it is recorded")
    }

    @Test func unknownExperimentsAreRefused() throws {
        #expect(throws: LayoutFileError.self) {
            try ConfigurationSettings.decode(Data(#"{"formatVersion": 1, "experiments": {"warpDrive": true}}"#.utf8))
        }
        #expect(try ConfigurationSettings.decode(Data(#"{"formatVersion": 1, "experiments": {}}"#.utf8)) == .defaults)
        #expect(throws: LayoutFileError.self) { try ConfigurationSettings.decode(Data(#"{"appearance": "dark"}"#.utf8)) }
        #expect(throws: LayoutFileError.self) { try ConfigurationSettings.decode(Data(#"{"formatVersion": 2}"#.utf8)) }
    }
}

/// Waits up to five seconds for a condition the main actor's run loop brings about.
@MainActor
func waitUntil(_ condition: @MainActor () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async throws {
    let deadline = Date().addingTimeInterval(5)
    while !condition() {
        if Date() > deadline {
            Issue.record("timed out", sourceLocation: sourceLocation)
            return
        }
        try await Task.sleep(for: .milliseconds(20))
    }
}
