import Foundation
import GitHubPRExplorerCore

/// `github-pr-explorer-ctl mcp`: a Model Context Protocol server over standard input and
/// output, so an agent in a chat can do what `ctl` does without a shell.
///
/// It speaks JSON-RPC 2.0, one message per line, and offers tools. Today the tools are the
/// saved filters, the first setting to come with MCP, and shorthands
/// (`MCPServer+Shorthands.swift`). They call the same functions as `ctl filters` and
/// `ctl shorthands`, so the two always agree, and every change is recorded in the configuration's
/// history as made by "MCP". The other settings join it as tools in later changes.
extension ControlCommand {
    static let mcpHelp = """
        \(name) mcp [--config <folder>] [--source mock|github] [--index <folder>]

        Runs a Model Context Protocol server on standard input and output, one JSON-RPC
        message per line, until standard input closes. Point an MCP client at this command.

        Tools: \(MCPServer.tools.map(\.name).joined(separator: ", ")).

        Example client configuration:
          {"mcpServers": {"github-pr-explorer": {"command": "\(name)", "args": ["mcp"]}}}
        """

    /// Runs the server when the command is `mcp`, reading lines from `input` until it returns
    /// nil and writing each response to `output`. Returns nil for any other command.
    static func serveMCPIfAsked(_ arguments: [String], sourceFromSettings: Bool,
                                input: () -> String?, output: (String) -> Void) -> ControlCommandResult? {
        var arguments = arguments
        let folder: URL
        switch configurationFolder(from: &arguments) {
        case .success(let url): folder = url
        case .failure: return nil
        }
        let indexFolder: URL
        switch Self.indexFolder(from: &arguments) {
        case .success(let url): indexFolder = url
        case .failure: return nil
        }
        var source: PullRequestSource?
        if let flag = arguments.firstIndex(of: "--source"), flag + 1 < arguments.count,
           let parsed = PullRequestSource(rawValue: arguments[flag + 1]) {
            source = parsed
            arguments.removeSubrange(flag...flag + 1)
        }
        guard arguments.first == "mcp" else { return nil }
        if arguments.contains("--help") || arguments.contains("-h") { return .success(mcpHelp + "\n") }
        guard arguments.count == 1 else { return .failure("Unknown option for mcp: \(arguments.dropFirst().joined(separator: " ")).\n\n\(mcpHelp)\n", exitCode: 2) }
        let server = MCPServer(folder: folder) {
            let chosen = source ?? (sourceFromSettings ? settingsSource(folder) : .mock)
            return chosen == .mock ? .success(IndexChoice(world: .standard)) : IndexChoice.synced(indexFolder)
        }
        while let line = input() {
            if let response = server.handle(line) { output(response) }
        }
        return .success("")
    }
}

/// The protocol and the tools, apart from where lines come from, so tests can feed it lines.
final class MCPServer {
    struct Tool {
        var name: String
        var description: String
        var inputSchema: [String: Any]
        var readOnly: Bool
    }

    static let supportedProtocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    let folder: URL
    let index: () -> Result<ControlCommand.IndexChoice, ControlCommand.ControlCommandResultError>

    init(folder: URL, index: @escaping () -> Result<ControlCommand.IndexChoice, ControlCommand.ControlCommandResultError>) {
        self.folder = folder
        self.index = index
    }

    // MARK: JSON-RPC

    /// Answers one line. Nil for a notification, which gets no answer.
    func handle(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let message = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)) as? [String: Any] else {
            return Self.encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error: not a JSON object."]])
        }
        let id = message["id"]
        guard let method = message["method"] as? String else {
            // A response from the client, which this server never asks for. Ignore it.
            return nil
        }
        let params = message["params"] as? [String: Any] ?? [:]
        guard let id else { return nil }   // A notification, such as notifications/initialized.

        let result: [String: Any]
        switch method {
        case "initialize":
            let asked = params["protocolVersion"] as? String
            let version = asked.flatMap { Self.supportedProtocolVersions.contains($0) ? $0 : nil } ?? Self.supportedProtocolVersions[0]
            result = [
                "protocolVersion": version,
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "github-pr-explorer", "version": "1"],
                "instructions": "Saved filters and shorthands for github-pr-explorer's pull request list. Everything is built in and always first. Try a filter with filter_evaluate before saving it. Filters use one language: sets joined by OR, each holding conditions joined by AND.",
            ]
        case "ping":
            result = [:]
        case "tools/list":
            result = ["tools": Self.tools.map { tool in
                ["name": tool.name, "description": tool.description, "inputSchema": tool.inputSchema,
                 "annotations": ["readOnlyHint": tool.readOnly]] as [String: Any]
            }]
        case "tools/call":
            guard let name = params["name"] as? String else {
                return Self.encode(["jsonrpc": "2.0", "id": id, "error": ["code": -32602, "message": "tools/call needs a tool name."]])
            }
            guard Self.tools.contains(where: { $0.name == name }) else {
                return Self.encode(["jsonrpc": "2.0", "id": id, "error": ["code": -32602, "message": "There is no tool \(name)."]])
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            switch call(name, arguments) {
            case .success(let text): result = ["content": [["type": "text", "text": text]], "isError": false]
            case .failure(let error): result = ["content": [["type": "text", "text": error.message]], "isError": true]
            }
        default:
            return Self.encode(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Method not found: \(method)."]])
        }
        return Self.encode(["jsonrpc": "2.0", "id": id, "result": result])
    }

    static func encode(_ object: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Tools

    typealias Failure = ControlCommand.ControlCommandResultError

    private var store: ConfigurationStore { ConfigurationStore(folder: folder) }

    func call(_ name: String, _ arguments: [String: Any]) -> Result<String, Failure> {
        switch name {
        case "saved_filters_list":
            let snapshot = ControlCommand.currentSnapshot(store)
            return json(ControlCommand.savedFilterReports(snapshot, choice: try? index().get()))

        case "saved_filter_show":
            guard let id = arguments["id"] as? String else { return .failure(.init("saved_filter_show needs an id.")) }
            let snapshot = ControlCommand.currentSnapshot(store)
            guard let report = ControlCommand.savedFilterReports(snapshot, choice: try? index().get()).first(where: { $0.id == id }) else {
                return .failure(.init(ControlCommand.noFilter(id, snapshot)))
            }
            return json(report)

        case "filter_evaluate":
            let filter: PullRequestFilter
            if let object = arguments["filter"] {
                switch Self.filter(from: object) {
                case .success(let parsed): filter = parsed
                case .failure(let error): return .failure(error)
                }
            } else if let id = arguments["id"] as? String {
                let snapshot = ControlCommand.currentSnapshot(store)
                guard let saved = snapshot.filter(id: id) else { return .failure(.init(ControlCommand.noFilter(id, snapshot))) }
                filter = saved.filter
            } else {
                return .failure(.init("filter_evaluate needs a saved filter's id or a filter."))
            }
            let limit = (arguments["limit"] as? Int) ?? 50
            return index().flatMap { json(ControlCommand.evaluationReport(filter, choice: $0, limit: max(0, limit))) }

        case "saved_filter_add":
            guard let id = arguments["id"] as? String, let filterName = arguments["name"] as? String, let object = arguments["filter"] else {
                return .failure(.init("saved_filter_add needs id, name and filter."))
            }
            let filter: PullRequestFilter
            switch Self.filter(from: object) {
            case .success(let parsed): filter = parsed
            case .failure(let error): return .failure(error)
            }
            let saved = SavedFilter(id: id, name: filterName, filter: filter,
                                    groupBy: arguments["groupBy"] as? [String] ?? [],
                                    showsAsTab: arguments["showsAsTab"] as? Bool ?? true)
            let store = store
            do throws(ConfigurationError) {
                try store.addSavedFilter(saved, at: arguments["position"] as? Int, author: .mcp)
                return reportAfterChange(store, id: saved.id)
            } catch {
                return .failure(.init(error.message))
            }

        case "saved_filter_change":
            guard let id = arguments["id"] as? String else { return .failure(.init("saved_filter_change needs the id of the filter to change.")) }
            var filter: PullRequestFilter?
            if let object = arguments["filter"] {
                switch Self.filter(from: object) {
                case .success(let parsed): filter = parsed
                case .failure(let error): return .failure(error)
                }
            }
            let newName = arguments["name"] as? String, newID = arguments["newId"] as? String
            let grouping = arguments["groupBy"] as? [String], tab = arguments["showsAsTab"] as? Bool
            let store = store
            do throws(ConfigurationError) {
                let changed = try store.changeSavedFilter(id: id, author: .mcp) { saved in
                    if let newName { saved.name = newName }
                    if let newID { saved.id = newID }
                    if let filter { saved.filter = filter }
                    if let grouping { saved.groupBy = grouping }
                    if let tab { saved.showsAsTab = tab }
                }
                return reportAfterChange(store, id: changed.id)
            } catch {
                return .failure(.init(error.message))
            }

        case "saved_filter_move":
            guard let id = arguments["id"] as? String, let position = arguments["position"] as? Int else {
                return .failure(.init("saved_filter_move needs id and position."))
            }
            let store = store
            do throws(ConfigurationError) {
                try store.moveSavedFilter(id: id, to: position, author: .mcp)
                return json(ControlCommand.savedFilterReports(store.snapshot, choice: nil).map(\.id))
            } catch {
                return .failure(.init(error.message))
            }

        case "saved_filter_remove":
            guard let id = arguments["id"] as? String else { return .failure(.init("saved_filter_remove needs an id.")) }
            let store = store
            do throws(ConfigurationError) {
                try store.removeSavedFilter(id: id, author: .mcp)
                return .success("Removed the saved filter \(id). The configuration's history keeps it.")
            } catch {
                return .failure(.init(error.message))
            }

        default:
            return callShorthandTool(name, arguments) ?? .failure(.init("There is no tool \(name)."))
        }
    }

    private func reportAfterChange(_ store: ConfigurationStore, id: String) -> Result<String, Failure> {
        guard let report = ControlCommand.savedFilterReports(store.snapshot, choice: try? index().get()).first(where: { $0.id == id }) else {
            return .failure(.init("The change was made, but the filter \(id) could not be read back."))
        }
        var text = (try? json(report).get()) ?? ""
        if let problem = store.historyProblem { text += "\nThe change was made, but it was not kept as a version: \(problem)" }
        return .success(text)
    }

    /// Reads a filter from a tool's arguments through the same checks a file gets.
    static func filter(from object: Any) -> Result<PullRequestFilter, Failure> {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object) else {
            return .failure(.init("filter must be an object with sets, such as {\"sets\": [{\"conditions\": [...]}]}."))
        }
        return ControlCommand.parseFilter(String(decoding: data, as: UTF8.self))
    }

    private func json(_ value: some Encodable) -> Result<String, Failure> {
        do {
            return .success(String(decoding: try GitHubPRExplorerJSON.encoder().encode(value), as: UTF8.self))
        } catch {
            return .failure(.init("Could not encode the result: \(error)"))
        }
    }

    // MARK: Tool list

    /// The filter's input schema, the same shape as `schemas/saved-filters.schema.json`.
    static var filterSchema: [String: Any] { [
        "type": "object",
        "description": "Sets joined by OR. A set is conditions joined by AND. No sets match every open pull request.",
        "required": ["sets"],
        "additionalProperties": false,
        "properties": [
            "sets": [
                "type": "array",
                "items": [
                    "type": "object", "required": ["conditions"], "additionalProperties": false,
                    "properties": [
                        "conditions": [
                            "type": "array",
                            "items": [
                                "type": "object", "required": ["field", "values"], "additionalProperties": false,
                                "properties": [
                                    "field": ["type": "string", "enum": FilterField.allCases.map(\.rawValue)],
                                    "operator": ["type": "string", "enum": FilterOperator.allCases.map(\.rawValue), "default": "is"],
                                    "values": [
                                        "type": "array", "minItems": 1, "items": ["type": "string"],
                                        "description": "Alternatives. status: \(StatusSentence.Badge.allCases.map(\.rawValue).joined(separator: ", ")). reviewState: \((FilterValues.fixed(for: .reviewState) ?? []).joined(separator: ", ")) (waitingOnMe: a review asked of the signed-in person or their team). draft: true or false. author: a login, or @me. repository: owner/name. organization: a name.",
                                    ] as [String: Any],
                                ] as [String: Any],
                            ] as [String: Any],
                        ] as [String: Any],
                    ] as [String: Any],
                ] as [String: Any],
            ] as [String: Any],
        ] as [String: Any],
    ] }

    static var groupBySchema: [String: Any] { [
        "type": "array", "maxItems": 2, "items": ["type": "string"],
        "description": "One or two groupings, outer first, such as [\"organization\", \"repository\"]. Empty for none.",
    ] }

    static var tools: [Tool] { [
        Tool(name: "saved_filters_list",
             description: "List every filter in tab order, Everything first: id, name, whether it is a tab, grouping, the filter in plain words and as JSON, and how many open pull requests match, by status.",
             inputSchema: ["type": "object", "properties": [String: Any]()], readOnly: true),
        Tool(name: "saved_filter_show",
             description: "One filter by id, with its conditions and counts.",
             inputSchema: ["type": "object", "required": ["id"], "properties": ["id": ["type": "string"]]], readOnly: true),
        Tool(name: "filter_evaluate",
             description: "Run a saved filter by id, or a filter not yet saved, over the open pull requests: the plain-words summary, \"7 of 218 match\" with the count by status, and the matches.",
             inputSchema: ["type": "object", "properties": [
                "id": ["type": "string", "description": "A saved filter's id. Give this or filter."],
                "filter": filterSchema,
                "limit": ["type": "integer", "minimum": 0, "default": 50, "description": "At most this many matches in the answer."],
             ] as [String: Any]], readOnly: true),
        Tool(name: "saved_filter_add",
             description: "Add a saved filter, last or at a position (1 is first after Everything).",
             inputSchema: ["type": "object", "required": ["id", "name", "filter"], "properties": [
                "id": ["type": "string", "pattern": "^[a-z0-9][a-z0-9-]*$", "description": "Lowercase letters, digits and hyphens."],
                "name": ["type": "string", "minLength": 1],
                "filter": filterSchema,
                "groupBy": groupBySchema,
                "showsAsTab": ["type": "boolean", "default": true],
                "position": ["type": "integer", "minimum": 1],
             ] as [String: Any]], readOnly: false),
        Tool(name: "saved_filter_change",
             description: "Change a saved filter's name, id, filter, grouping, or whether it is a tab. Only the fields given change. Everything cannot be changed.",
             inputSchema: ["type": "object", "required": ["id"], "properties": [
                "id": ["type": "string", "description": "The filter to change."],
                "newId": ["type": "string", "pattern": "^[a-z0-9][a-z0-9-]*$"],
                "name": ["type": "string", "minLength": 1],
                "filter": filterSchema,
                "groupBy": groupBySchema,
                "showsAsTab": ["type": "boolean"],
             ] as [String: Any]], readOnly: false),
        Tool(name: "saved_filter_move",
             description: "Move a saved filter to a position: 1 is first after Everything. Returns the new order.",
             inputSchema: ["type": "object", "required": ["id", "position"], "properties": [
                "id": ["type": "string"], "position": ["type": "integer", "minimum": 1],
             ] as [String: Any]], readOnly: false),
        Tool(name: "saved_filter_remove",
             description: "Remove a saved filter. The configuration's history keeps it, so it can be restored.",
             inputSchema: ["type": "object", "required": ["id"], "properties": ["id": ["type": "string"]]], readOnly: false),
    ] + shorthandTools }
}
