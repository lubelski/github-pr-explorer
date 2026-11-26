import Foundation
import GitHubPRExplorerCore

/// `sync`: run one sync from GitHub, check the gh login, and report how the sync stands. And
/// the index list and show read: the mock world, or the one the sync wrote.
extension ControlCommand {
    static let syncHelp = """
        \(name) sync <command> [--index <folder>] [--config <folder>] [--json]

        The sync reads open pull requests from GitHub through the gh login on this Mac: the
        ones that involve you, and every open one in the repositories in watchedRepositories.
        It is read-only. The index it writes is a cache next to the configuration folder, in
        ~/Library/Application Support/github-pr-explorer/index, and is safe to delete.

        Commands:
          sync run      Run one sync now, the same one the app runs on its timer, and print
                        what it did: pull requests, requests made, points spent, time taken,
                        and the rate limit left. Exits 1 when it could not finish.
          sync check    Check the gh login and print the account. One small request.
          sync status   How the last sync went, from the saved index. Uses no network.

        Options:
          --index <folder>    Use this index folder instead of the app's.
          --config <folder>   Read watchedRepositories from this configuration folder.
          --json              Print the status as JSON.

        `pull-requests list --source github` and `pull-request show --source github` read the
        synced index.
        """

    /// What list and show read: an index, the moment ages are measured from, and the
    /// repositories it covers.
    struct IndexChoice {
        var index: any PullRequestIndex
        var now: Date
        var repositories: [Repository]

        init(world: MockWorld) {
            index = world.index
            now = world.now
            repositories = world.repositories
        }

        init(snapshot: GitHubIndexSnapshot, now: Date) {
            let index = snapshot.index
            self.index = index
            self.now = now
            repositories = Array(Set(index.allPullRequests.map(\.repository))).sorted()
        }

        static func synced(_ folder: URL, now: Date = Date()) -> Result<IndexChoice, ControlCommandResultError> {
            let storage = JSONFileIndexStorage(folder: folder)
            do {
                guard let snapshot = try storage.load() else {
                    return .failure(.init("There is no synced index at \(storage.location.path) yet. Run `\(name) sync run` first.\n"))
                }
                return .success(IndexChoice(snapshot: snapshot, now: now))
            } catch {
                return .failure(.init("The synced index at \(storage.location.path) could not be read. It is a cache: delete it and run `\(name) sync run`.\n"))
            }
        }
    }

    /// Takes `--index <folder>` out of the arguments, wherever it is.
    static func indexFolder(from arguments: inout [String]) -> Result<URL, ControlCommandResultError> {
        guard let index = arguments.firstIndex(of: "--index") else { return .success(JSONFileIndexStorage.defaultFolder) }
        guard index + 1 < arguments.count else { return .failure(.init("--index needs a folder.\n")) }
        let path = (arguments[index + 1] as NSString).expandingTildeInPath
        arguments.removeSubrange(index...index + 1)
        return .success(URL(filePath: path, directoryHint: .isDirectory).standardizedFileURL)
    }

    /// The `pullRequestSource` setting, without creating the folder or recording anything.
    static func settingsSource(_ folder: URL) -> PullRequestSource {
        let store = ConfigurationStore(folder: folder)
        guard store.exists else { return .mock }
        return store.reload().settings.pullRequestSource
    }

    /// `sync status` and `sync --help`, which need no network. `sync run` and `sync check` go
    /// through `runAsync`.
    static func syncStatusOrHelp(_ arguments: [String], indexFolder: URL) -> ControlCommandResult {
        guard let command = arguments.first, command != "--help", command != "-h" else {
            return arguments.isEmpty ? .failure(syncHelp + "\n", exitCode: 2) : .success(syncHelp + "\n")
        }
        let json = arguments.contains("--json")
        switch command {
        case "status":
            let storage = JSONFileIndexStorage(folder: indexFolder)
            let snapshot: GitHubIndexSnapshot
            do {
                guard let saved = try storage.load() else {
                    return .success("No sync has run yet. The index would be at \(storage.location.path).\n")
                }
                snapshot = saved
            } catch {
                return .failure("The synced index at \(storage.location.path) could not be read. It is a cache: delete it and run `\(name) sync run`.\n")
            }
            if json { return encodeJSON(snapshot.status) }
            return .success(statusText(snapshot.status, location: storage.location, now: Date()))
        case "run", "check":
            return .failure("sync \(command) runs only from the command line tool itself.\n")
        default:
            return .failure("Unknown command: sync \(command).\n\n\(syncHelp)\n", exitCode: 2)
        }
    }

    /// What the real tool needs to reach GitHub. Tests give a fake transport and token.
    struct SyncDependencies: Sendable {
        var transport: any GitHubTransport = URLSessionGitHubTransport()
        var tokenProvider: any GitHubTokenProvider = GitHubCLITokenProvider()
        var now: @Sendable () -> Date = { Date() }
    }

    /// Runs a command, including `sync run` and `sync check`, which use the network.
    static func runAsync(_ arguments: [String], sourceFromSettings: Bool = false,
                         dependencies: SyncDependencies = SyncDependencies()) async -> ControlCommandResult {
        var rest = arguments
        guard let first = rest.firstIndex(where: { !$0.hasPrefix("--") && !isOptionValue(at: $0, in: arguments) }),
              rest[first] == "sync", first + 1 < rest.count, ["run", "check"].contains(rest[first + 1]),
              !rest.contains("--help"), !rest.contains("-h")
        else {
            return run(arguments, sourceFromSettings: sourceFromSettings)
        }
        let kind: GitHubSync.RunKind = rest[first + 1] == "run" ? .full : .loginCheck
        rest.removeSubrange(first...first + 1)
        let configFolder: URL
        switch configurationFolder(from: &rest) {
        case .success(let url): configFolder = url
        case .failure(let error): return .failure(error.message, exitCode: 2)
        }
        let indexFolder: URL
        switch self.indexFolder(from: &rest) {
        case .success(let url): indexFolder = url
        case .failure(let error): return .failure(error.message, exitCode: 2)
        }
        let json = rest.contains("--json")
        rest.removeAll { $0 == "--json" }
        if let unknown = rest.first {
            return .failure("Unknown option: \(unknown).\n\n\(syncHelp)\n", exitCode: 2)
        }

        let store = ConfigurationStore(folder: configFolder)
        let settings = store.exists ? store.reload().settings : .defaults
        let storage = JSONFileIndexStorage(folder: indexFolder)
        let sync = GitHubSync(transport: dependencies.transport, tokenProvider: dependencies.tokenProvider,
                              storage: storage, now: dependencies.now)
        let loadProblem = await sync.loadSaved()
        await sync.configure(watchedRepositories: settings.watchedRepositoryList, interval: TimeInterval(settings.syncIntervalSeconds))
        let status = await sync.run(kind)
        if json {
            var result = encodeJSON(status)
            if status.problem != nil { result.exitCode = 1 }
            return result
        }
        var text = loadProblem.map { "note\t\($0)\n" } ?? ""
        text += kind == .full ? runText(status, location: storage.location, now: dependencies.now())
                              : statusText(status, location: storage.location, now: dependencies.now())
        if kind == .full, settings.pullRequestSource == .mock {
            text += "\nThe app shows the mock data until pullRequestSource is github: `\(name) config set pullRequestSource github`.\n"
        }
        return status.problem == nil ? .success(text) : ControlCommandResult(exitCode: 1, output: text, errorOutput: "")
    }

    /// True when `text` follows an option that takes a value, such as the folder after `--config`.
    private static func isOptionValue(at text: String, in arguments: [String]) -> Bool {
        guard let position = arguments.firstIndex(of: text), position > 0 else { return false }
        return ["--config", "--index", "--source"].contains(arguments[position - 1])
    }

    static func runText(_ status: GitHubSyncStatus, location: URL, now: Date) -> String {
        let run = status.lastRun
        var text = ""
        text += "Account        \(status.accountLogin ?? "unknown")\n"
        text += "Pull requests  \(status.pullRequestCount) (\(status.detailedCount) with full detail)\n"
        text += "Requests       \(run.totalRequests): \(run.graphQLRequests) GraphQL, \(run.restRequests) REST (\(run.restNotModified) not modified)\n"
        text += "Points spent   GraphQL \(run.graphQLPoints), REST \(run.restPoints)\n"
        text += "Took           \(String(format: "%.1f", status.lastRunSeconds ?? 0)) s\n"
        text += rateLimitLines(status, now: now)
        text += "Saved to       \(location.path)\n"
        text += problemAndWarningLines(status, now: now)
        return text
    }

    static func statusText(_ status: GitHubSyncStatus, location: URL, now: Date) -> String {
        var text = ""
        text += "Account        \(status.accountLogin ?? "unknown")\(status.hasLogin == false ? " (no gh login)" : "")\n"
        text += "Pull requests  \(status.pullRequestCount) (\(status.detailedCount) with full detail)\n"
        text += "Last sync      \(status.lastSuccessAt.map { "\($0.formatted(.iso8601)) (\(RelativeAge.ago($0, now: now)))" } ?? "never")\n"
        if let attempt = status.lastAttemptAt, attempt != status.lastSuccessAt {
            text += "Last attempt   \(attempt.formatted(.iso8601)) (\(RelativeAge.ago(attempt, now: now)))\n"
        }
        let run = status.lastRun
        text += "Last run       \(run.totalRequests) requests, GraphQL \(run.graphQLPoints) points, REST \(run.restPoints), \(String(format: "%.1f", status.lastRunSeconds ?? 0)) s\n"
        text += rateLimitLines(status, now: now)
        text += "Index          \(location.path)\n"
        text += problemAndWarningLines(status, now: now)
        return text
    }

    private static func rateLimitLines(_ status: GitHubSyncStatus, now: Date) -> String {
        var text = ""
        for (key, label) in [("graphql", "GraphQL"), ("core", "REST")] {
            guard let reading = status.rateLimits[key] else { continue }
            text += "Rate limit     \(label) \(reading.summary), resets in \(RelativeAge.short(max(0, reading.resetAt.timeIntervalSince(now)))), read \(RelativeAge.ago(reading.readAt, now: now))\n"
        }
        return text
    }

    private static func problemAndWarningLines(_ status: GitHubSyncStatus, now: Date) -> String {
        var text = ""
        if let problem = status.problem {
            text += "problem\t\(problem.shortText(now: now)). \(problem.explanation)\n"
        }
        for warning in status.warnings { text += "warning\t\(warning)\n" }
        return text
    }
}
