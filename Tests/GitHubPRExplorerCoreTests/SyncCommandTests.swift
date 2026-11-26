import Foundation
import Testing
@testable import github_pr_explorer_ctl
@testable import GitHubPRExplorerCore

/// `sync`, and list and show reading the synced index. Always with `--index` and `--config`
/// pointing at temporary folders, and a fake GitHub.
@Suite struct SyncCommandTests {
    let config = TemporaryConfiguration()
    let indexFolder = FileManager.default.temporaryDirectory.appending(path: "github-pr-explorer-index-\(UUID().uuidString)", directoryHint: .isDirectory)
    let github = FakeGitHub()

    var folders: [String] { ["--config", config.folder.path, "--index", indexFolder.path] }

    func dependencies(token: Result<String, GitHubAccessError> = .success(FakeGitHub.token)) -> ControlCommand.SyncDependencies {
        ControlCommand.SyncDependencies(transport: github, tokenProvider: FixedTokenProvider(token), now: { FakeGitHub.now })
    }

    func runAsync(_ arguments: [String], sourceFromSettings: Bool = false,
                  token: Result<String, GitHubAccessError> = .success(FakeGitHub.token)) async -> ControlCommandResult {
        await ControlCommand.runAsync(arguments + folders, sourceFromSettings: sourceFromSettings, dependencies: dependencies(token: token))
    }

    @Test func syncRunReportsWhatItDid() async throws {
        defer { try? FileManager.default.removeItem(at: indexFolder) }
        let result = await runAsync(["sync", "run"])
        #expect(result.exitCode == 0, "\(result.errorOutput)")
        #expect(result.output.contains("Account        robin-quill"))
        #expect(result.output.contains("Pull requests  2 (2 with full detail)"))
        #expect(result.output.contains("REST (0 not modified)"))
        #expect(result.output.contains("Rate limit     GraphQL 4,900 of 5,000 left"))
        #expect(result.output.contains("The app shows the mock data until pullRequestSource is github"))
        #expect(!result.output.contains(FakeGitHub.token))
        #expect(FileManager.default.fileExists(atPath: indexFolder.appending(path: "github.json").path))
        #expect(!config.store.exists, "a sync never writes the configuration folder")

        let status = ControlCommand.run(["sync", "status"] + folders)
        #expect(status.exitCode == 0)
        #expect(status.output.contains("Account        robin-quill"))
        #expect(status.output.contains("Pull requests  2 (2 with full detail)"))
        #expect(status.output.contains("Last sync      2026-11-25T18:00:00Z"))

        let json = ControlCommand.run(["sync", "status", "--json"] + folders)
        let decoded = try GitHubPRExplorerJSON.decoder().decode(GitHubSyncStatus.self, from: Data(json.output.utf8))
        #expect(decoded.pullRequestCount == 2)
    }

    @Test func syncRunReadsWatchedRepositoriesFromSettings() async throws {
        defer { try? FileManager.default.removeItem(at: indexFolder) }
        try config.store.set(key: "watchedRepositories", value: "acme/docs", author: .commandLine)
        let result = await runAsync(["sync", "run"])
        #expect(result.output.contains("Pull requests  3"))
    }

    @Test func syncRunWithoutALoginFails() async throws {
        defer { try? FileManager.default.removeItem(at: indexFolder) }
        let result = await runAsync(["sync", "run"], token: .failure(.ghMissing))
        #expect(result.exitCode == 1)
        #expect(result.output.contains("problem\tgh not found"))
        #expect(github.sent.isEmpty)
        let check = await runAsync(["sync", "check"], token: .failure(.signedOut))
        #expect(check.output.contains("Signed out of gh"))
    }

    @Test func syncStatusBeforeAnySync() {
        let result = ControlCommand.run(["sync", "status"] + folders)
        #expect(result.exitCode == 0)
        #expect(result.output.hasPrefix("No sync has run yet."))
    }

    @Test func listAndShowReadTheSyncedIndex() async throws {
        defer { try? FileManager.default.removeItem(at: indexFolder) }
        let none = ControlCommand.run(["pull-requests", "list", "--source", "github"] + folders)
        #expect(none.exitCode == 1)
        #expect(none.errorOutput.contains("Run `github-pr-explorer-ctl sync run` first"))

        _ = await runAsync(["sync", "run"])
        let list = ControlCommand.run(["pull-requests", "list", "--source", "github"] + folders)
        #expect(list.exitCode == 0)
        let references = list.output.split(separator: "\n").map { $0.split(separator: "\t")[0] }
        #expect(references == ["acme/api#101", "acme/web#55"])
        let show = ControlCommand.run(["pull-request", "show", "acme/api#101", "--source", "github"] + folders)
        #expect(show.exitCode == 0)
        #expect(show.output.contains("Refresh sessions before they expire"))
        let filtered = ControlCommand.run(["pull-requests", "list", "--source", "github", "--repo", "acme/web"] + folders)
        #expect(filtered.output.hasPrefix("acme/web#55"))

        // Without --source, tests read the mock world. The real tool follows the setting.
        #expect(ControlCommand.run(["pull-requests", "list"] + folders).output.split(separator: "\n").count == 298)
        try config.store.set(key: "pullRequestSource", value: "github", author: .commandLine)
        let followed = ControlCommand.run(["pull-requests", "list"] + folders, sourceFromSettings: true)
        #expect(followed.output.split(separator: "\n").count == 2)
        let forced = ControlCommand.run(["pull-requests", "list", "--source", "mock"] + folders, sourceFromSettings: true)
        #expect(forced.output.split(separator: "\n").count == 298)
    }

    @Test func otherCommandsStillGoThroughRunAsync() async {
        let result = await ControlCommand.runAsync(["pull-request", "show", "acme/api#4826"], dependencies: dependencies())
        #expect(result.exitCode == 0)
        #expect(github.sent.isEmpty)
        let help = await ControlCommand.runAsync(["sync", "--help"], dependencies: dependencies())
        #expect(help.output.contains("sync run"))
    }
}

@Suite struct SourceSettingsTests {
    let config = TemporaryConfiguration()

    @Test func theSourceIsMockUntilSomeoneOptsIn() throws {
        #expect(ConfigurationSettings.defaults.pullRequestSource == .mock)
        #expect(ConfigurationSettings.defaults.syncIntervalSeconds == 300)
        #expect(ConfigurationSettings.defaults.watchedRepositories.isEmpty)
        let summary = try config.store.set(key: "pullRequestSource", value: "github", author: .commandLine)
        #expect(summary == "Pull requests come from GitHub")
        #expect(config.store.snapshot.settings.pullRequestSource == .github)
        #expect(throws: ConfigurationError.self) { try config.store.set(key: "pullRequestSource", value: "gitlab", author: .commandLine) }
    }

    @Test func theIntervalIsAMinuteToAnHour() throws {
        #expect(try config.store.set(key: "syncIntervalSeconds", value: "120", author: .commandLine) == "Sync every 2 min")
        #expect(config.store.snapshot.settings.syncIntervalSeconds == 120)
        #expect(throws: ConfigurationError.self) { try config.store.set(key: "syncIntervalSeconds", value: "30", author: .commandLine) }
        #expect(throws: ConfigurationError.self) { try config.store.set(key: "syncIntervalSeconds", value: "soon", author: .commandLine) }
    }

    @Test func watchedRepositoriesAreACommaSeparatedList() throws {
        #expect(try config.store.set(key: "watchedRepositories", value: "acme/api, acme/web,acme/API", author: .commandLine)
                == "Watch acme/api, acme/web in full")
        #expect(config.store.snapshot.settings.watchedRepositoryList == [Repository(owner: "acme", name: "api"), Repository(owner: "acme", name: "web")])
        #expect(throws: ConfigurationError.self) { try config.store.set(key: "watchedRepositories", value: "acme", author: .commandLine) }
        #expect(throws: ConfigurationError.self) { try config.store.set(key: "watchedRepositories", value: "acme/api/x", author: .commandLine) }
        try config.store.set(key: "watchedRepositories", value: "", author: .commandLine)
        #expect(config.store.snapshot.settings.watchedRepositories.isEmpty)
    }

    @Test func aHandWrittenFileWithABadRepositoryIsRefused() throws {
        try config.store.prepare(author: .app)
        try config.write(#"{"formatVersion": 1, "pullRequestSource": "github", "watchedRepositories": ["not a repo"]}"#, to: "settings.json")
        let snapshot = config.store.reload(committingAs: .editedOnDisk)
        #expect(snapshot.settings.pullRequestSource == .mock, "the last good settings stay in use")
        #expect(snapshot.problems.contains { $0.path == "watchedRepositories[0]" })
    }
}
