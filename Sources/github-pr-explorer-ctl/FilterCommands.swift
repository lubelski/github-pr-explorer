import Foundation
import GitHubPRExplorerCore

/// `filters`: list, read, evaluate, add, change, move and remove saved filters, the same
/// `saved-filters.json` the app's Settings writes. MCP's saved filter tools call the same
/// functions, so the two always agree.
extension ControlCommand {
    static let filtersHelp = """
        \(name) filters <command> [--config <folder>] [--source mock|github]

        Saved filters are tabs above the pull request list. "Everything" is always first and
        cannot be changed. The rest are in saved-filters.json in the configuration folder, in
        their order. A filter applies to the open pull requests in the index.

        Commands:
          filters list [--json]               One line per filter: id, tab or hidden, how many
                                              open pull requests match, name, and the filter in
                                              plain words.
          filters show <id> [--json]          One filter: its name, conditions, grouping and count.
          filters evaluate <id> [--json] [--limit N]
          filters evaluate --filter <json> [--json] [--limit N]
                                              The count, the count by status, and the matching
                                              pull requests. With --filter, try a filter before
                                              saving it.
          filters add <id> --name <name> --filter <json> [--group-by <a[,b]>] [--hidden]
                      [--position N]          Add a saved filter, last or at a position. 1 is
                                              first after Everything.
          filters change <id> [--name <name>] [--new-id <id>] [--filter <json>]
                      [--group-by <a[,b]>] [--tab true|false]
                                              Change a saved filter. --group-by "" turns
                                              grouping off.
          filters move <id> <position>        Move a saved filter. 1 is first after Everything.
          filters remove <id>                 Remove a saved filter. History keeps it.

        A filter is JSON in the one filter language: sets joined by OR, each holding conditions
        joined by AND. A condition is a field, "is" or "isNot", and values that are
        alternatives. Fields: \(FilterField.allCases.map(\.rawValue).joined(separator: ", ")).
        The schema is schemas/saved-filters.schema.json in the app's repository.

        Examples:
          \(name) filters list
          \(name) filters evaluate --filter '{"sets": [{"conditions": [{"field": "status", "values": ["blocked"]}, {"field": "repository", "values": ["acme/api"]}]}]}'
          \(name) filters add blocked-in-api --name "Blocked in api" --filter '{"sets": [{"conditions": [{"field": "status", "values": ["blocked"]}, {"field": "repository", "values": ["acme/api"]}]}]}'
          \(name) filters change blocked-in-api --group-by author --tab false
          \(name) filters move blocked-in-api 1
        """

    // MARK: Reports, shared with MCP

    /// One filter as `filters list --json`, `show --json` and MCP give it.
    struct SavedFilterReport: Codable, Equatable {
        struct Counts: Codable, Equatable {
            var matching: Int
            var total: Int
            var byStatus: [String: Int]
            /// "7 of 218 match, 3 blocked · 2 waiting · 2 ready"
            var text: String
        }
        var id: String
        var name: String
        /// 0 for Everything, then 1, 2, ... for the saved filters.
        var position: Int
        /// True for Everything, which cannot be changed.
        var builtIn: Bool
        var showsAsTab: Bool
        var groupBy: [String]
        var summary: String
        var filter: PullRequestFilter
        /// Missing when the index could not be read.
        var counts: Counts?
    }

    /// What `filters evaluate --json` and MCP's `filter_evaluate` give.
    struct FilterEvaluationReport: Codable, Equatable {
        struct Match: Codable, Equatable {
            var reference: String
            var status: String
            var title: String
        }
        var summary: String
        var counts: SavedFilterReport.Counts
        var matches: [Match]
        /// True when `limit` left some matches out.
        var truncated: Bool
    }

    static func counts(_ evaluation: FilterEvaluation) -> SavedFilterReport.Counts {
        .init(matching: evaluation.count, total: evaluation.total,
              byStatus: Dictionary(uniqueKeysWithValues: evaluation.byStatus.map { ($0.status.rawValue, $0.count) }),
              text: evaluation.text)
    }

    static func context(_ choice: IndexChoice) -> FilterContext {
        FilterContext(viewer: choice.index.viewer, now: choice.now)
    }

    static func savedFilterReports(_ snapshot: ConfigurationSnapshot, choice: IndexChoice?) -> [SavedFilterReport] {
        let context = choice.map(context)
        return snapshot.filters.enumerated().map { position, saved in
            var counts: SavedFilterReport.Counts?
            if let choice, let context {
                counts = Self.counts(saved.evaluate(choice.index.allPullRequests, context: context))
            }
            return SavedFilterReport(id: saved.id, name: saved.name, position: position, builtIn: saved.isEverything,
                                     showsAsTab: saved.showsAsTab, groupBy: saved.groupBy, summary: saved.summary,
                                     filter: saved.filter, counts: counts)
        }
    }

    static func evaluationReport(_ filter: PullRequestFilter, choice: IndexChoice, limit: Int?) -> FilterEvaluationReport {
        let context = context(choice)
        let evaluation = SavedFilter(id: "evaluated", name: "", filter: filter).evaluate(choice.index.allPullRequests, context: context)
        let shown = limit.map { Array(evaluation.matches.prefix($0)) } ?? evaluation.matches
        return FilterEvaluationReport(
            summary: filter.summary, counts: counts(evaluation),
            matches: shown.map { .init(reference: $0.reference.description, status: context.status($0).badge.rawValue, title: $0.title) },
            truncated: shown.count < evaluation.count)
    }

    /// The configuration as it stands, without creating the folder.
    static func currentSnapshot(_ store: ConfigurationStore) -> ConfigurationSnapshot {
        store.exists ? store.reload() : .builtIn
    }

    /// Reads a filter given as JSON text, with a problem that says where.
    static func parseFilter(_ text: String) -> Result<PullRequestFilter, ControlCommandResultError> {
        do throws(LayoutFileError) {
            return .success(try PullRequestFilter.decode(Data(text.utf8), fileName: "the filter"))
        } catch {
            return .failure(.init(error.description))
        }
    }

    /// `a,b` as grouping levels. Empty text is no grouping.
    static func parseGrouping(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    // MARK: filters

    static func filters(_ arguments: [String], folder: URL, index: () -> Result<IndexChoice, ControlCommandResultError>) -> ControlCommandResult {
        guard let command = arguments.first, command != "--help", command != "-h" else {
            return arguments.isEmpty ? .failure(filtersHelp + "\n", exitCode: 2) : .success(filtersHelp + "\n")
        }
        let rest = Array(arguments.dropFirst())
        if rest.contains("--help") || rest.contains("-h") { return .success(filtersHelp + "\n") }
        let options: FilterOptions
        switch FilterOptions.parse(rest, flags: ["--json", "--hidden"]) {
        case .success(let parsed): options = parsed
        case .failure(let error): return .failure(error.message + "\n", exitCode: 2)
        }
        let store = ConfigurationStore(folder: folder)
        let usage = "Run `\(name) filters --help` for the commands.\n"

        switch command {
        case "list":
            guard options.positional.isEmpty, options.unknown(allowed: ["--json"]) == nil else { return .failure(usage, exitCode: 2) }
            let choice = try? index().get()
            let reports = savedFilterReports(currentSnapshot(store), choice: choice)
            if options.flags.contains("--json") { return encodeJSON(reports) }
            let lines = reports.map { report in
                let place = report.builtIn ? "fixed" : report.showsAsTab ? "tab" : "hidden"
                let count = report.counts.map { String($0.matching) } ?? "-"
                return "\(report.id)\t\(place)\t\(count)\t\(report.name)\t\(report.summary)\n"
            }
            return .success(lines.joined() + problemLines(store.exists ? store.problems.filter { $0.file == SavedFilterFile.fileName } : []))

        case "show":
            guard options.positional.count == 1, options.unknown(allowed: ["--json"]) == nil else {
                return .failure("filters show needs one id, such as `filters show mine`.\n", exitCode: 2)
            }
            let snapshot = currentSnapshot(store)
            guard let report = savedFilterReports(snapshot, choice: try? index().get()).first(where: { $0.id == options.positional[0] }) else {
                return .failure(noFilter(options.positional[0], snapshot))
            }
            if options.flags.contains("--json") { return encodeJSON(report) }
            return .success(filterText(report))

        case "evaluate":
            guard options.unknown(allowed: ["--json", "--filter", "--limit"]) == nil else { return .failure(usage, exitCode: 2) }
            var limit: Int?
            if let text = options.values["--limit"] {
                guard let number = Int(text), number >= 0 else { return .failure("--limit needs a number.\n", exitCode: 2) }
                limit = number
            }
            let filter: PullRequestFilter
            if let text = options.values["--filter"] {
                guard options.positional.isEmpty else { return .failure("Give a saved filter's id or --filter, not both.\n", exitCode: 2) }
                switch parseFilter(text) {
                case .success(let parsed): filter = parsed
                case .failure(let error): return .failure(error.message + "\n")
                }
            } else {
                guard options.positional.count == 1 else {
                    return .failure("filters evaluate needs a saved filter's id or --filter <json>.\n", exitCode: 2)
                }
                let snapshot = currentSnapshot(store)
                guard let saved = snapshot.filter(id: options.positional[0]) else { return .failure(noFilter(options.positional[0], snapshot)) }
                filter = saved.filter
            }
            let choice: IndexChoice
            switch index() {
            case .success(let found): choice = found
            case .failure(let error): return .failure(error.message)
            }
            let report = evaluationReport(filter, choice: choice, limit: limit)
            if options.flags.contains("--json") { return encodeJSON(report) }
            var text = "\(report.summary)\n\(report.counts.text)\n"
            text += report.matches.map { "\($0.reference)\t\($0.status)\t\($0.title)\n" }.joined()
            if report.truncated { text += "… and \(report.counts.matching - report.matches.count) more\n" }
            return .success(text)

        case "add":
            guard options.positional.count == 1, options.unknown(allowed: ["--name", "--filter", "--group-by", "--hidden", "--position"]) == nil else {
                return .failure("filters add needs an id, --name and --filter. \(usage)", exitCode: 2)
            }
            guard let name = options.values["--name"] else { return .failure("filters add needs --name <name>.\n", exitCode: 2) }
            guard let filterText = options.values["--filter"] else { return .failure("filters add needs --filter <json>.\n", exitCode: 2) }
            let filter: PullRequestFilter
            switch parseFilter(filterText) {
            case .success(let parsed): filter = parsed
            case .failure(let error): return .failure(error.message + "\n")
            }
            var position: Int?
            if let text = options.values["--position"] {
                guard let number = Int(text) else { return .failure("--position needs a number, 1 for first after Everything.\n", exitCode: 2) }
                position = number
            }
            let saved = SavedFilter(id: options.positional[0], name: name, filter: filter,
                                    groupBy: parseGrouping(options.values["--group-by"] ?? ""),
                                    showsAsTab: !options.flags.contains("--hidden"))
            do throws(ConfigurationError) {
                try store.addSavedFilter(saved, at: position, author: .commandLine)
                return .success("Added the saved filter \(saved.name): \(saved.summary)\n" + historyWarning(store))
            } catch {
                return .failure(error.message + "\n")
            }

        case "change":
            guard options.positional.count == 1,
                  options.unknown(allowed: ["--name", "--new-id", "--filter", "--group-by", "--tab"]) == nil else {
                return .failure("filters change needs one id and what to change. \(usage)", exitCode: 2)
            }
            var filter: PullRequestFilter?
            if let text = options.values["--filter"] {
                switch parseFilter(text) {
                case .success(let parsed): filter = parsed
                case .failure(let error): return .failure(error.message + "\n")
                }
            }
            var tab: Bool?
            if let text = options.values["--tab"] {
                guard let flag = ["true": true, "false": false][text.lowercased()] else { return .failure("--tab is true or false.\n", exitCode: 2) }
                tab = flag
            }
            let grouping = options.values["--group-by"].map(parseGrouping)
            let name = options.values["--name"], newID = options.values["--new-id"]
            do throws(ConfigurationError) {
                let changed = try store.changeSavedFilter(id: options.positional[0], author: .commandLine) { saved in
                    if let name { saved.name = name }
                    if let newID { saved.id = newID }
                    if let filter { saved.filter = filter }
                    if let grouping { saved.groupBy = grouping }
                    if let tab { saved.showsAsTab = tab }
                }
                let summary = (try? store.versions(limit: 1).first?.summary) ?? nil
                return .success((summary ?? "Changed the saved filter \(changed.name)") + ".\n" + historyWarning(store))
            } catch {
                return .failure(error.message + "\n")
            }

        case "move":
            guard options.positional.count == 2, options.unknown(allowed: []) == nil, let position = Int(options.positional[1]) else {
                return .failure("filters move needs an id and a position, such as `filters move mine 1`.\n", exitCode: 2)
            }
            do throws(ConfigurationError) {
                try store.moveSavedFilter(id: options.positional[0], to: position, author: .commandLine)
                let order = store.snapshot.filters.map(\.name).joined(separator: ", ")
                return .success("The order is now: \(order).\n" + historyWarning(store))
            } catch {
                return .failure(error.message + "\n")
            }

        case "remove":
            guard options.positional.count == 1, options.unknown(allowed: []) == nil else {
                return .failure("filters remove needs one id.\n", exitCode: 2)
            }
            do throws(ConfigurationError) {
                try store.removeSavedFilter(id: options.positional[0], author: .commandLine)
                return .success("Removed the saved filter \(options.positional[0]). `\(name) config history` can bring it back.\n" + historyWarning(store))
            } catch {
                return .failure(error.message + "\n")
            }

        default:
            return .failure("Unknown command: filters \(command).\n\n\(filtersHelp)\n", exitCode: 2)
        }
    }

    static func noFilter(_ id: String, _ snapshot: ConfigurationSnapshot) -> String {
        "No filter has the id \"\(id)\". Filters: \(snapshot.filters.map(\.id).joined(separator: ", ")).\n"
    }

    static func filterText(_ report: SavedFilterReport) -> String {
        var text = "\(report.id)  \(report.name)\n"
        text += report.builtIn ? "Built in, always first. It cannot be changed.\n"
            : "Position \(report.position) after Everything, \(report.showsAsTab ? "shown as a tab" : "not on the tab bar").\n"
        text += report.groupBy.isEmpty ? "No grouping.\n" : "Grouped by \(report.groupBy.joined(separator: ", then ")).\n"
        if let counts = report.counts { text += counts.text + "\n" }
        text += "\n\(report.summary)\n"
        for (number, set) in report.filter.sets.enumerated() {
            text += number == 0 ? "\n" : "or\n"
            if set.conditions.isEmpty { text += "  (any pull request)\n" }
            for condition in set.conditions {
                text += "  \(condition.field.rawValue) \(condition.operator.rawValue) \(condition.values.joined(separator: ", "))\n"
            }
        }
        return text
    }
}

/// `--key value` options, flags with no value, and positional words.
struct FilterOptions {
    var positional: [String] = []
    var values: [String: String] = [:]
    var flags: Set<String> = []

    static func parse(_ arguments: [String], flags known: Set<String>) -> Result<FilterOptions, ControlCommand.ControlCommandResultError> {
        var options = FilterOptions()
        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            if known.contains(argument) {
                options.flags.insert(argument)
            } else if argument.hasPrefix("--") {
                guard let value = iterator.next() else { return .failure(.init("\(argument) needs a value.")) }
                options.values[argument] = value
            } else {
                options.positional.append(argument)
            }
        }
        return .success(options)
    }

    /// The first option not in `allowed`, or nil.
    func unknown(allowed: Set<String>) -> String? {
        (Set(values.keys).union(flags)).subtracting(allowed).sorted().first
    }
}
