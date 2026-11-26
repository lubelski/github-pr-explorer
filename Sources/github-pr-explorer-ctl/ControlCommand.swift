import Foundation
import GitHubPRExplorerCore

/// What a command printed and how it ended. Tests call `ControlCommand.run` and read this
/// instead of starting a process.
struct ControlCommandResult: Equatable {
    var exitCode: Int32
    var output: String
    var errorOutput: String

    static func success(_ output: String) -> ControlCommandResult {
        ControlCommandResult(exitCode: 0, output: output, errorOutput: "")
    }

    static func failure(_ message: String, exitCode: Int32 = 1) -> ControlCommandResult {
        ControlCommandResult(exitCode: exitCode, output: "", errorOutput: message)
    }
}

/// `github-pr-explorer-ctl`: inspect the index from the command line, run a sync, and read and
/// change the configuration folder. The index is the mock world or the synced GitHub index.
enum ControlCommand {
    static let name = "github-pr-explorer-ctl"

    static let help = """
        \(name): inspect github-pr-explorer's pull request index, run a sync, and read and
        change its configuration, from the command line. The index is the built-in mock world,
        or the pull requests synced from GitHub. Only `sync run` and `sync check` use the network.

        Commands:
          pull-requests list     One line per pull request: reference, status, title.
          pull-request show      Every section of one pull request.
          sync                   GitHub: run one sync, check the gh login, or report status.
          mock-data export       Write the mock world to JSON files.
          config                 The configuration folder: path, validate, show, set, history,
                                 diff, restore.
          layouts                Page layouts: list, show, duplicate.

        Options:
          --config <folder>      Use this configuration folder instead of the app's.
          --index <folder>       Use this synced index folder instead of the app's, which is
                                 ~/Library/Application Support/github-pr-explorer/index.
          --source mock|github   For list and show: which index to read. Default: the
                                 pullRequestSource setting.

        Run `\(name) <command> --help` for a command's options.
        """

    static let listHelp = """
        \(name) pull-requests list [--repo <owner/name>] [--state open|merged|closed|all] [--search <text>]
                                   [--source mock|github]

        Prints one line per pull request, most recently updated first:
        the reference, the status symbol and sentence, and the title, separated by tabs.

        Options:
          --repo <owner/name>   Only this repository, such as acme/api.
          --state <state>       open, merged, closed, or all. Default: all.
          --search <text>       Only pull requests matching every word, in the title, number,
                                author, repository or a changed file's path.
          --source mock|github  The mock world, or the index synced from GitHub. Default: the
                                pullRequestSource setting.
        """

    static let showHelp = """
        \(name) pull-request show <owner/name#number> [--json] [--source mock|github]

        Prints every section of one pull request: summary, description, checks, reviews,
        merge state, code owners, files, commits, threads, comments, timeline and sources.

        Options:
          --json                Print the whole pull request as JSON instead.
          --source mock|github  The mock world, or the index synced from GitHub. Default: the
                                pullRequestSource setting.

        Example:
          \(name) pull-request show acme/api#4826
        """

    static let exportHelp = """
        \(name) mock-data export <directory>

        Writes the mock world as JSON: world.json with the viewer, people, teams, repositories
        and code owners, and one file per pull request under pull-requests/, such as
        pull-requests/acme-api-4826.json. Keys are sorted and dates are ISO 8601, so two
        exports are byte for byte the same. The directory is created if it does not exist.
        """

    /// Runs a command. With `sourceFromSettings`, list and show read the index the
    /// `pullRequestSource` setting names when `--source` is not given, as the real tool does.
    /// Tests leave it off, so they read the mock world and never the real folders.
    static func run(_ arguments: [String], world: MockWorld = .standard, sourceFromSettings: Bool = false) -> ControlCommandResult {
        var arguments = arguments
        let folder: URL
        switch configurationFolder(from: &arguments) {
        case .success(let url): folder = url
        case .failure(let error): return .failure(error.message, exitCode: 2)
        }
        let indexFolder: URL
        switch Self.indexFolder(from: &arguments) {
        case .success(let url): indexFolder = url
        case .failure(let error): return .failure(error.message, exitCode: 2)
        }
        var source: PullRequestSource?
        if let flag = arguments.firstIndex(of: "--source") {
            guard flag + 1 < arguments.count, let parsed = PullRequestSource(rawValue: arguments[flag + 1]) else {
                return .failure("--source needs mock or github.\n", exitCode: 2)
            }
            source = parsed
            arguments.removeSubrange(flag...flag + 1)
        }
        func pullRequests() -> Result<IndexChoice, ControlCommandResultError> {
            let chosen = source ?? (sourceFromSettings ? settingsSource(folder) : .mock)
            return chosen == .mock ? .success(IndexChoice(world: world)) : IndexChoice.synced(indexFolder)
        }
        guard let first = arguments.first else { return .failure(help + "\n", exitCode: 2) }
        if first == "--help" || first == "-h" || first == "help" { return .success(help + "\n") }
        let rest = Array(arguments.dropFirst())
        switch first {
        case "pull-requests":
            guard rest.first == "list" else {
                if rest.first == "--help" || rest.first == "-h" { return .success(listHelp + "\n") }
                return .failure("Unknown command: pull-requests \(rest.first ?? "").\n\n\(listHelp)\n", exitCode: 2)
            }
            switch pullRequests() {
            case .success(let choice): return list(Array(rest.dropFirst()), choice: choice)
            case .failure(let error): return .failure(error.message)
            }
        case "pull-request":
            guard rest.first == "show" else {
                if rest.first == "--help" || rest.first == "-h" { return .success(showHelp + "\n") }
                return .failure("Unknown command: pull-request \(rest.first ?? "").\n\n\(showHelp)\n", exitCode: 2)
            }
            switch pullRequests() {
            case .success(let choice): return show(Array(rest.dropFirst()), choice: choice)
            case .failure(let error): return .failure(error.message)
            }
        case "mock-data":
            guard rest.first == "export" else {
                if rest.first == "--help" || rest.first == "-h" { return .success(exportHelp + "\n") }
                return .failure("Unknown command: mock-data \(rest.first ?? "").\n\n\(exportHelp)\n", exitCode: 2)
            }
            return export(Array(rest.dropFirst()), world: world)
        case "config":
            return config(rest, folder: folder)
        case "layouts":
            return layouts(rest, folder: folder)
        case "sync":
            return syncStatusOrHelp(rest, indexFolder: indexFolder)
        default:
            return .failure("Unknown command: \(first).\n\n\(help)\n", exitCode: 2)
        }
    }

    // MARK: pull-requests list

    static func list(_ arguments: [String], choice: IndexChoice) -> ControlCommandResult {
        if arguments.contains("--help") || arguments.contains("-h") { return .success(listHelp + "\n") }
        var repository: Repository?
        var state: PullRequestState?
        var search = ""
        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--repo":
                guard let value = iterator.next(), let parsed = Repository(fullName: value) else {
                    return .failure("--repo needs a repository such as acme/api.\n", exitCode: 2)
                }
                repository = parsed
            case "--state":
                guard let value = iterator.next() else { return .failure("--state needs open, merged, closed or all.\n", exitCode: 2) }
                if value == "all" { state = nil }
                else if let parsed = PullRequestState(rawValue: value) { state = parsed }
                else { return .failure("Unknown state: \(value). Use open, merged, closed or all.\n", exitCode: 2) }
            case "--search":
                guard let value = iterator.next() else { return .failure("--search needs some text.\n", exitCode: 2) }
                search = value
            default:
                return .failure("Unknown option: \(argument).\n\n\(listHelp)\n", exitCode: 2)
            }
        }
        if let repository, !choice.repositories.contains(repository) {
            return .failure("No repository \(repository.fullName) in the index.\n")
        }
        let index = choice.index
        let lines = index.search(search)
            .filter { repository == nil || $0.repository == repository }
            .filter { state == nil || $0.state == state }
            .map { listLine($0, viewer: index.viewer, now: choice.now) }
        return .success(lines.map { $0 + "\n" }.joined())
    }

    static func listLine(_ pr: PullRequest, viewer: Viewer, now: Date) -> String {
        "\(pr.reference)\t\(pr.statusSentence(for: viewer, now: now).text)\t\(pr.title)"
    }

    // MARK: pull-request show

    static func show(_ arguments: [String], choice: IndexChoice) -> ControlCommandResult {
        if arguments.contains("--help") || arguments.contains("-h") { return .success(showHelp + "\n") }
        let asJSON = arguments.contains("--json")
        let positional = arguments.filter { $0 != "--json" }
        guard positional.count == 1 else {
            return .failure("pull-request show needs one pull request, such as acme/api#4826.\n\n\(showHelp)\n", exitCode: 2)
        }
        for argument in positional where argument.hasPrefix("--") {
            return .failure("Unknown option: \(argument).\n\n\(showHelp)\n", exitCode: 2)
        }
        guard let reference = PullRequestReference(parsing: positional[0]) else {
            return .failure("Not a pull request reference: \(positional[0]). Write it as owner/name#number, such as acme/api#4826.\n", exitCode: 2)
        }
        let index = choice.index
        guard let pr = index.pullRequest(reference) else {
            return .failure("No pull request \(reference) in the index.\n")
        }
        if asJSON {
            do {
                let data = try GitHubPRExplorerJSON.encoder().encode(pr)
                return .success(String(decoding: data, as: UTF8.self) + "\n")
            } catch {
                return .failure("Could not encode \(reference): \(error)\n")
            }
        }
        return .success(PullRequestReport.text(for: pr, viewer: index.viewer, now: choice.now))
    }

    // MARK: mock-data export

    struct WorldFile: Codable {
        var now: Date
        var viewer: Viewer
        var people: [Person]
        var teams: [Team]
        var repositories: [Repository]
        var codeOwners: [MockWorld.RepositoryCodeOwners]
        /// The files under `pull-requests/`, in the index's order.
        var pullRequestFiles: [String]
    }

    static func fileName(for reference: PullRequestReference) -> String {
        "\(reference.repository.owner)-\(reference.repository.name)-\(reference.number).json"
    }

    static func export(_ arguments: [String], world: MockWorld) -> ControlCommandResult {
        if arguments.contains("--help") || arguments.contains("-h") { return .success(exportHelp + "\n") }
        guard arguments.count == 1, !arguments[0].hasPrefix("--") else {
            return .failure("mock-data export needs one directory.\n\n\(exportHelp)\n", exitCode: 2)
        }
        let directory = URL(fileURLWithPath: arguments[0], isDirectory: true)
        let pullRequestDirectory = directory.appendingPathComponent("pull-requests", isDirectory: true)
        let encoder = GitHubPRExplorerJSON.encoder()
        do {
            try FileManager.default.createDirectory(at: pullRequestDirectory, withIntermediateDirectories: true)
            var names: [String] = []
            for pr in world.pullRequests {
                let name = fileName(for: pr.reference)
                names.append("pull-requests/\(name)")
                try encoder.encode(pr).write(to: pullRequestDirectory.appendingPathComponent(name), options: .atomic)
            }
            let worldFile = WorldFile(now: world.now, viewer: world.viewer, people: world.people, teams: world.teams,
                                      repositories: world.repositories, codeOwners: world.codeOwners, pullRequestFiles: names)
            try encoder.encode(worldFile).write(to: directory.appendingPathComponent("world.json"), options: .atomic)
            return .success("Wrote world.json and \(names.count) pull request files to \(directory.path).\n")
        } catch {
            return .failure("Could not export to \(directory.path): \(error.localizedDescription)\n")
        }
    }
}
