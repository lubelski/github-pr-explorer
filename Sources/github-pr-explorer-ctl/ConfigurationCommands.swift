import Foundation
import GitHubPRExplorerCore

/// `config` and `layouts`: read and change the configuration folder, the same files the app's
/// Settings window writes. Every change is recorded in the folder's history as made by "ctl".
extension ControlCommand {
    static let configHelp = """
        \(name) config <command> [--config <folder>]

        The configuration folder holds settings.json, saved-filters.json and layouts/*.json. The app watches it and
        applies a change as soon as it is saved. Every valid change is kept as a version.

        Commands:
          config path                      Print where the folder is.
          config validate                  Check every file. Exits 1 when any has a problem.
          config show [--json]             The settings, the layouts and any problems.
          config set <key> <value>         Change one setting. Keys: \(ConfigurationStore.settableKeys.joined(separator: ", ")).
          config history [--limit N] [--json]
                                           The versions, newest first: id, time (UTC), who, what.
          config diff <version>            What a version changed.
          config restore <version> [file]  Bring back the folder, or one file, as it was in a
                                           version. The restore is a new version: nothing is lost.

        Options:
          --config <folder>   Use this folder instead of the app's, which is
                              ~/Library/Application Support/github-pr-explorer/config.

        Examples:
          \(name) config set defaultLayout tabbed
          \(name) config set appearance dark
          \(name) config set pullRequestSource github
          \(name) config set watchedRepositories "acme/api, acme/web"
          \(name) config history --limit 5
          \(name) config restore 1a2b3c4 settings.json
        """

    static let layoutsHelp = """
        \(name) layouts <command> [--config <folder>]

        Commands:
          layouts list                          One line per layout: id, name, where it comes from,
                                                and "default" for the default.
          layouts show <id> [--json]            A layout's tabs, columns and blocks, or its JSON.
          layouts duplicate <id> <new-id> [--name <name>]
                                                Copy a layout to layouts/<new-id>.json to edit it.

        The built-in layouts are decision-first and tabbed. A file in layouts/ with a built-in
        layout's id replaces it.
        """

    /// Takes `--config <folder>` out of the arguments, wherever it is.
    static func configurationFolder(from arguments: inout [String]) -> Result<URL, ControlCommandResultError> {
        guard let index = arguments.firstIndex(of: "--config") else { return .success(ConfigurationStore.defaultFolder) }
        guard index + 1 < arguments.count else { return .failure(.init("--config needs a folder.\n")) }
        let path = (arguments[index + 1] as NSString).expandingTildeInPath
        arguments.removeSubrange(index...index + 1)
        return .success(URL(filePath: path, directoryHint: .isDirectory).standardizedFileURL)
    }

    struct ControlCommandResultError: Error {
        var message: String
        init(_ message: String) { self.message = message }
    }

    // MARK: config

    static func config(_ arguments: [String], folder: URL) -> ControlCommandResult {
        guard let command = arguments.first, command != "--help", command != "-h" else {
            return arguments.isEmpty ? .failure(configHelp + "\n", exitCode: 2) : .success(configHelp + "\n")
        }
        let rest = Array(arguments.dropFirst())
        if rest.contains("--help") || rest.contains("-h") { return .success(configHelp + "\n") }
        let store = ConfigurationStore(folder: folder)
        switch command {
        case "path":
            return .success(folder.path + "\n")
        case "validate":
            return validate(store)
        case "show":
            return showConfiguration(store, json: rest.contains("--json"))
        case "set":
            guard rest.count == 2 else {
                return .failure("config set needs a key and a value, such as `config set defaultLayout tabbed`.\n", exitCode: 2)
            }
            do throws(ConfigurationError) {
                let summary = try store.set(key: rest[0], value: rest[1], author: .commandLine)
                return .success(summary + ".\n" + historyWarning(store))
            } catch {
                return .failure(error.message + "\n")
            }
        case "history":
            return history(store, arguments: rest)
        case "diff":
            guard rest.count == 1 else { return .failure("config diff needs one version, such as `config diff 1a2b3c4`.\n", exitCode: 2) }
            guard store.exists else { return .failure(noFolder(store)) }
            do throws(ConfigurationError) {
                return .success(try store.diff(rest[0]))
            } catch {
                return .failure(error.message + "\n")
            }
        case "restore":
            guard (1...2).contains(rest.count) else {
                return .failure("config restore needs a version, and optionally one file, such as `config restore 1a2b3c4 settings.json`.\n", exitCode: 2)
            }
            guard store.exists else { return .failure(noFolder(store)) }
            do throws(ConfigurationError) {
                let version = try store.restore(rest[0], file: rest.count == 2 ? rest[1] : nil, author: .commandLine)
                let what = rest.count == 2 ? rest[1] : "The configuration"
                guard let version else {
                    return .success("\(what) now matches version \(rest[0]). It matched the latest version, so no new version was needed.\n" + problemLines(store.problems))
                }
                return .success("\(version.summary).\nRecorded as version \(version.shortID). The versions after it are kept.\n" + problemLines(store.problems))
            } catch {
                return .failure(error.message + "\n")
            }
        default:
            return .failure("Unknown command: config \(command).\n\n\(configHelp)\n", exitCode: 2)
        }
    }

    private static func noFolder(_ store: ConfigurationStore) -> String {
        "There is no configuration folder at \(store.folder.path) yet, so there is no history.\n"
    }

    private static func historyWarning(_ store: ConfigurationStore) -> String {
        store.historyProblem.map { "The change was made, but it was not kept as a version: \($0)\n" } ?? ""
    }

    static func problemLines(_ problems: [ConfigurationProblem]) -> String {
        problems.map { "problem\t\($0.description)\n" }.joined()
    }

    static func validate(_ store: ConfigurationStore) -> ControlCommandResult {
        guard store.exists else {
            return .success("No configuration folder at \(store.folder.path) yet. The defaults and the built-in layouts are in use.\n")
        }
        let snapshot = store.reload()
        let files = [ConfigurationSettings.fileName, SavedFilterFile.fileName] + (((try? FileManager.default.contentsOfDirectory(atPath: store.layoutsURL.path)) ?? [])
            .filter { $0.hasSuffix(".json") && !$0.hasPrefix(".") }.sorted().map { "\(ConfigurationStore.layoutsFolderName)/\($0)" })
        var lines: [String] = []
        for file in files {
            let problems = snapshot.problems.filter { $0.file == file }
            if !FileManager.default.fileExists(atPath: store.url(for: file).path) {
                lines.append("ok\t\(file) (missing, so the defaults are used)")
            } else if problems.isEmpty {
                lines.append("ok\t\(file)")
            } else {
                for problem in problems {
                    lines.append("\(problem.refusesFile ? "invalid" : "problem")\t\(problem.description)")
                }
            }
        }
        for problem in snapshot.problems where !files.contains(problem.file) {
            lines.append("problem\t\(problem.description)")
        }
        let text = lines.map { $0 + "\n" }.joined()
        if snapshot.problems.isEmpty { return .success(text) }
        let count = snapshot.problems.count
        return ControlCommandResult(exitCode: 1, output: text, errorOutput: "\(count) \(count == 1 ? "problem" : "problems") found.\n")
    }

    struct ConfigurationReport: Codable {
        struct Layout: Codable {
            var id: String
            var name: String
            /// "built in", or the file it was read from.
            var source: String
            var overridesBuiltIn: Bool
            var isDefault: Bool
        }
        var folder: String
        var folderExists: Bool
        var settings: ConfigurationSettings
        var layouts: [Layout]
        /// Everything first, then the saved filters in their order.
        var savedFilters: [SavedFilter]
        var problems: [ConfigurationProblem]
    }

    static func report(_ store: ConfigurationStore) -> ConfigurationReport {
        let snapshot = store.exists ? store.reload() : .builtIn
        let defaultID = snapshot.defaultLayout.id
        return ConfigurationReport(
            folder: store.folder.path, folderExists: store.exists, settings: snapshot.settings,
            layouts: snapshot.layouts.map { entry in
                var overrides = false
                if case .file(_, let flag) = entry.source { overrides = flag }
                return .init(id: entry.id, name: entry.layout.name, source: entry.source.file ?? "built in",
                             overridesBuiltIn: overrides, isDefault: entry.id == defaultID)
            },
            savedFilters: snapshot.filters,
            problems: snapshot.problems)
    }

    static func showConfiguration(_ store: ConfigurationStore, json: Bool) -> ControlCommandResult {
        let report = report(store)
        if json { return encodeJSON(report) }
        let settings = report.settings
        var text = "Folder      \(report.folder)\(report.folderExists ? "" : " (not created yet)")\n"
        text += "\nSettings (settings.json)\n"
        text += "  appearance                \(settings.appearance.rawValue)\n"
        text += "  defaultLayout             \(settings.defaultLayout)\n"
        text += "  hidesBotEventsInActivity  \(settings.hidesBotEventsInActivity)\n"
        text += "  updatesAutomatically      \(settings.updatesAutomatically)\n"
        text += "  pullRequestSource         \(settings.pullRequestSource.rawValue)\n"
        text += "  syncIntervalSeconds       \(settings.syncIntervalSeconds)\n"
        text += "  watchedRepositories       \(settings.watchedRepositories.isEmpty ? "(none)" : settings.watchedRepositories.joined(separator: ", "))\n"
        if Experiment.allCases.isEmpty {
            text += "  experiments               none right now\n"
        } else {
            for experiment in Experiment.allCases {
                text += "  experiments.\(experiment.key)  \(settings.isOn(experiment))\n"
            }
        }
        text += "\nSaved filters (\(SavedFilterFile.fileName)), in tab order\n"
        for saved in report.savedFilters {
            text += "  \(saved.id)\t\(saved.name)\t\(saved.isEverything ? "fixed" : saved.showsAsTab ? "tab" : "hidden")\t\(saved.summary)\n"
        }
        text += "\nLayouts\n"
        for layout in report.layouts {
            let source = layout.overridesBuiltIn ? "\(layout.source), replaces the built-in" : layout.source
            text += "  \(layout.id)\t\(layout.name)\t\(source)\(layout.isDefault ? "\tdefault" : "")\n"
        }
        if !report.problems.isEmpty {
            text += "\nProblems\n" + report.problems.map { "  \($0.description)\n" }.joined()
        }
        return .success(text)
    }

    static func history(_ store: ConfigurationStore, arguments: [String]) -> ControlCommandResult {
        var limit: Int?
        var json = false
        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--limit":
                guard let value = iterator.next(), let number = Int(value), number > 0 else {
                    return .failure("--limit needs a number above zero.\n", exitCode: 2)
                }
                limit = number
            case "--json": json = true
            default: return .failure("Unknown option: \(argument).\n\n\(configHelp)\n", exitCode: 2)
            }
        }
        guard store.exists else { return .success("No configuration folder at \(store.folder.path) yet, so there is no history.\n") }
        do throws(ConfigurationError) {
            let versions = try store.versions(limit: limit)
            if json { return encodeJSON(versions) }
            let lines = versions.map { version in
                "\(version.shortID)\t\(historyTime(version.date))\t\(version.author.isEmpty ? "unknown" : version.author)\t\(version.summary)\n"
            }
            return .success(lines.joined())
        } catch {
            return .failure(error.message + "\n")
        }
    }

    static func historyTime(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).dateTimeSeparator(.space)) + " UTC"
    }

    // MARK: layouts

    static func layouts(_ arguments: [String], folder: URL) -> ControlCommandResult {
        guard let command = arguments.first, command != "--help", command != "-h" else {
            return arguments.isEmpty ? .failure(layoutsHelp + "\n", exitCode: 2) : .success(layoutsHelp + "\n")
        }
        var rest = Array(arguments.dropFirst())
        if rest.contains("--help") || rest.contains("-h") { return .success(layoutsHelp + "\n") }
        let store = ConfigurationStore(folder: folder)
        switch command {
        case "list":
            let report = report(store)
            return .success(report.layouts.map { layout in
                let source = layout.overridesBuiltIn ? "\(layout.source) (replaces the built-in)" : layout.source
                return "\(layout.id)\t\(layout.name)\t\(source)\(layout.isDefault ? "\tdefault" : "")\n"
            }.joined())
        case "show":
            let json = rest.contains("--json")
            rest.removeAll { $0 == "--json" }
            guard rest.count == 1 else { return .failure("layouts show needs one layout id, such as `layouts show tabbed`.\n", exitCode: 2) }
            let snapshot = store.exists ? store.reload() : .builtIn
            guard let entry = snapshot.entry(id: rest[0]) else {
                return .failure("No layout has the id \"\(rest[0])\". Layouts: \(snapshot.layouts.map(\.id).joined(separator: ", ")).\n")
            }
            if json {
                guard let data = try? entry.layout.encoded() else { return .failure("Could not encode the layout.\n") }
                return .success(String(decoding: data, as: UTF8.self) + "\n")
            }
            return .success(layoutText(entry))
        case "duplicate":
            var name: String?
            if let index = rest.firstIndex(of: "--name") {
                guard index + 1 < rest.count else { return .failure("--name needs a name.\n", exitCode: 2) }
                name = rest[index + 1]
                rest.removeSubrange(index...index + 1)
            }
            guard rest.count == 2 else {
                return .failure("layouts duplicate needs a layout id and a new id, such as `layouts duplicate tabbed my-tabbed`.\n", exitCode: 2)
            }
            do throws(ConfigurationError) {
                let entry = try store.duplicateLayout(id: rest[0], as: rest[1], name: name, author: .commandLine)
                let file = entry.source.file ?? ConfigurationStore.layoutFile(id: rest[1])
                return .success("Wrote \(store.url(for: file).path)\nas \"\(entry.layout.name)\". Edit it, then run `\(Self.name) config validate`.\n" + historyWarning(store))
            } catch {
                return .failure(error.message + "\n")
            }
        default:
            return .failure("Unknown command: layouts \(command).\n\n\(layoutsHelp)\n", exitCode: 2)
        }
    }

    static func layoutText(_ entry: LayoutEntry) -> String {
        let layout = entry.layout
        var text = "\(layout.id)  \(layout.name)\n"
        switch entry.source {
        case .builtIn: text += "Built in. Duplicate it to edit.\n"
        case .file(let file, let overrides): text += "From \(file)\(overrides ? ", replacing the built-in layout" : "").\n"
        }
        for tab in layout.tabs {
            text += "\nTab \"\(tab.name)\"\n"
            if tab.columns.isEmpty { text += "  (no columns)\n" }
            for (index, column) in tab.columns.enumerated() {
                let blocks = column.blocks.map { "\($0.kind.rawValue) (\($0.size.rawValue))" }
                text += "  Column \(index + 1), width \(column.width.formatted()): \(blocks.isEmpty ? "no blocks" : blocks.joined(separator: ", "))\n"
            }
        }
        return text
    }

    static func encodeJSON(_ value: some Encodable) -> ControlCommandResult {
        do {
            let data = try GitHubPRExplorerJSON.encoder().encode(value)
            return .success(String(decoding: data, as: UTF8.self) + "\n")
        } catch {
            return .failure("Could not encode JSON: \(error)\n")
        }
    }
}
