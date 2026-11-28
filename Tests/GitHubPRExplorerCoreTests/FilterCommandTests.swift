import Foundation
import Testing
@testable import github_pr_explorer_ctl
@testable import GitHubPRExplorerCore

let blockedInAPIFilter = #"{"sets": [{"conditions": [{"field": "status", "values": ["blocked"]}, {"field": "repository", "values": ["acme/api"]}]}]}"#

/// `ctl filters`, always with `--config` and a temporary folder, on the mock world.
@Suite struct FilterCommandTests {
    let config = TemporaryConfiguration()

    func run(_ arguments: String...) -> ControlCommandResult {
        ControlCommand.run(arguments + ["--config", config.folder.path])
    }

    @Test func listBeforeTheFolderExists() {
        let result = run("filters", "list")
        #expect(result.exitCode == 0, "\(result.errorOutput)")
        #expect(result.output == """
            everything\tfixed\t218\tEverything\tEvery open pull request.
            needs-my-review\ttab\t53\tNeeds my review\tWaiting on me.
            mine\ttab\t12\tMine\tBy me.

            """)
        #expect(!config.store.exists, "looking never creates the folder")
    }

    @Test func addEvaluateMoveChangeRemove() throws {
        var result = run("filters", "add", "blocked-in-api", "--name", "Blocked in api", "--filter", blockedInAPIFilter, "--group-by", "author", "--hidden")
        #expect(result.exitCode == 0, "\(result.errorOutput)")
        #expect(result.output == "Added the saved filter Blocked in api: Blocked and in acme/api.\n")

        result = run("filters", "evaluate", "blocked-in-api", "--json")
        let report = try JSONDecoder().decode(ControlCommand.FilterEvaluationReport.self, from: Data(result.output.utf8))
        #expect(report.counts.total == 218)
        #expect(report.counts.matching == report.matches.count)
        #expect(report.counts.byStatus == ["blocked": report.counts.matching])
        #expect(report.matches.allSatisfy { $0.reference.hasPrefix("acme/api#") && $0.status == "blocked" })

        result = run("filters", "move", "blocked-in-api", "1")
        #expect(result.output == "The order is now: Everything, Blocked in api, Needs my review, Mine.\n")

        result = run("filters", "change", "blocked-in-api", "--tab", "true", "--group-by", "", "--name", "API blocked")
        #expect(result.exitCode == 0, "\(result.errorOutput)")
        #expect(result.output == "Saved filter Blocked in api: renamed it API blocked, turned off its grouping, showed it as a tab.\n")

        result = run("filters", "show", "blocked-in-api", "--json")
        let shown = try JSONDecoder().decode(ControlCommand.SavedFilterReport.self, from: Data(result.output.utf8))
        #expect(shown.name == "API blocked" && shown.showsAsTab && shown.groupBy.isEmpty && shown.position == 1)

        result = run("filters", "remove", "blocked-in-api")
        #expect(result.exitCode == 0)
        #expect(config.store.reload().savedFilters.map(\.id) == ["needs-my-review", "mine"])
        #expect(try config.versions().allSatisfy { $0.author == "ctl" })
    }

    @Test func evaluateAFilterNotSaved() {
        let result = run("filters", "evaluate", "--filter", blockedInAPIFilter, "--limit", "2")
        #expect(result.exitCode == 0, "\(result.errorOutput)")
        let lines = result.output.split(separator: "\n")
        #expect(lines[0] == "Blocked and in acme/api.")
        #expect(lines[1].hasSuffix(" of 218 match, \(lines[1].split(separator: " ")[0]) blocked"))
        #expect(lines.last?.hasPrefix("… and ") == true)
        #expect(!config.store.exists)
    }

    @Test func mistakesSayWhatIsWrong() {
        var result = run("filters", "add", "x", "--name", "X", "--filter", #"{"sets": [{"conditions": [{"field": "status", "values": ["purple"]}]}]}"#)
        #expect(result.exitCode == 1)
        #expect(result.errorOutput.contains("sets[0].conditions[0].values[0]: \"purple\" is not a value of status"))
        result = run("filters", "remove", "everything")
        #expect(result.exitCode == 1)
        #expect(result.errorOutput.contains("Everything is built in"))
        result = run("filters", "show", "nope")
        #expect(result.errorOutput == "No filter has the id \"nope\". Filters: everything, needs-my-review, mine.\n")
        result = run("filters", "add", "x", "--name", "X")
        #expect(result.exitCode == 2)
        result = run("filters", "list", "--bogus", "1")
        #expect(result.exitCode == 2)
    }

    @Test func validateAndShowIncludeTheFile() throws {
        try config.store.prepare(author: .app)
        try config.write(#"{"formatVersion": 1, "savedFilters": "none"}"#, to: "saved-filters.json")
        var result = run("config", "validate")
        #expect(result.exitCode == 1)
        #expect(result.output.contains("invalid\tsaved-filters.json"))
        result = run("config", "show")
        #expect(result.output.contains("Saved filters (saved-filters.json), in tab order\n  everything\tEverything\tfixed"))
    }
}

/// `ctl mcp`, fed lines directly.
@Suite struct MCPServerTests {
    let config = TemporaryConfiguration()

    var server: MCPServer {
        MCPServer(folder: config.folder) { .success(ControlCommand.IndexChoice(world: .standard)) }
    }

    func send(_ server: MCPServer, _ object: [String: Any]) throws -> [String: Any] {
        let line = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        let response = try #require(server.handle(line))
        #expect(!response.contains("\n"), "one message per line")
        return try #require(try JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any])
    }

    func call(_ server: MCPServer, _ tool: String, _ arguments: [String: Any] = [:], id: Int = 9) throws -> (text: String, isError: Bool) {
        let response = try send(server, ["jsonrpc": "2.0", "id": id, "method": "tools/call", "params": ["name": tool, "arguments": arguments]])
        let result = try #require(response["result"] as? [String: Any])
        let content = try #require(result["content"] as? [[String: Any]])
        return (content.first?["text"] as? String ?? "", result["isError"] as? Bool ?? false)
    }

    @Test func initializeAndListTools() throws {
        let server = server
        let hello = try send(server, ["jsonrpc": "2.0", "id": 1, "method": "initialize",
                                      "params": ["protocolVersion": "2025-06-18", "capabilities": [:], "clientInfo": ["name": "test", "version": "1"]]])
        let result = try #require(hello["result"] as? [String: Any])
        #expect(result["protocolVersion"] as? String == "2025-06-18")
        #expect(server.handle(#"{"jsonrpc": "2.0", "method": "notifications/initialized"}"#) == nil)
        let list = try send(server, ["jsonrpc": "2.0", "id": 2, "method": "tools/list"])
        let tools = try #require((list["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        #expect(tools.compactMap { $0["name"] as? String } == [
            "saved_filters_list", "saved_filter_show", "filter_evaluate", "saved_filter_add",
            "saved_filter_change", "saved_filter_move", "saved_filter_remove",
            "shorthands_list", "shorthand_set", "shorthand_remove",
        ])
        #expect(tools.allSatisfy { ($0["inputSchema"] as? [String: Any])?["type"] as? String == "object" })
        let unknown = try send(server, ["jsonrpc": "2.0", "id": 3, "method": "resources/list"])
        #expect((unknown["error"] as? [String: Any])?["code"] as? Int == -32601)
        let garbage = try #require(server.handle("not json"))
        #expect(garbage.contains("-32700"))
    }

    @Test func theSameOperationsAsTheCommandLine() throws {
        let server = server
        let filter = try JSONSerialization.jsonObject(with: Data(blockedInAPIFilter.utf8))

        var answer = try call(server, "filter_evaluate", ["filter": filter, "limit": 1])
        #expect(!answer.isError, "\(answer.text)")
        let report = try JSONDecoder().decode(ControlCommand.FilterEvaluationReport.self, from: Data(answer.text.utf8))
        #expect(report.summary == "Blocked and in acme/api.")
        #expect(report.matches.count == 1 && report.truncated)

        answer = try call(server, "saved_filter_add", ["id": "blocked-in-api", "name": "Blocked in api", "filter": filter,
                                                       "groupBy": ["organization", "repository"], "position": 1])
        #expect(!answer.isError, "\(answer.text)")
        let added = try JSONDecoder().decode(ControlCommand.SavedFilterReport.self, from: Data(answer.text.utf8))
        #expect(added.position == 1 && added.groupBy == ["organization", "repository"] && added.counts?.matching == report.counts.matching)

        answer = try call(server, "saved_filter_change", ["id": "mine", "showsAsTab": false])
        #expect(!answer.isError, "\(answer.text)")
        answer = try call(server, "saved_filter_move", ["id": "mine", "position": 1])
        #expect(try JSONDecoder().decode([String].self, from: Data(answer.text.utf8)) == ["everything", "mine", "blocked-in-api", "needs-my-review"])

        answer = try call(server, "saved_filters_list")
        let listed = try JSONDecoder().decode([ControlCommand.SavedFilterReport].self, from: Data(answer.text.utf8))
        #expect(listed.map(\.id) == ["everything", "mine", "blocked-in-api", "needs-my-review"])
        #expect(listed[0].builtIn && listed[0].counts?.matching == 218)

        // The command line sees the same file.
        let fromCommandLine = ControlCommand.run(["filters", "list", "--config", config.folder.path])
        #expect(fromCommandLine.output.split(separator: "\n").map { String($0.split(separator: "\t")[0]) }
                == ["everything", "mine", "blocked-in-api", "needs-my-review"])

        answer = try call(server, "saved_filter_remove", ["id": "blocked-in-api"])
        #expect(!answer.isError)
        #expect(try config.versions().first?.author == "MCP")
    }

    @Test func mistakesAreToolErrors() throws {
        let server = server
        var answer = try call(server, "saved_filter_remove", ["id": "everything"])
        #expect(answer.isError && answer.text.contains("Everything is built in"))
        answer = try call(server, "filter_evaluate", ["filter": ["sets": [["conditions": [["field": "colour", "values": ["red"]]]]]]])
        #expect(answer.isError && answer.text.contains("sets[0].conditions[0].field"))
        answer = try call(server, "saved_filter_show", [:])
        #expect(answer.isError)
        let missing = try send(server, ["jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": ["name": "warp_drive"]])
        #expect(missing["error"] != nil)
        // As with `config set`, a change prepares the folder first, so only its creation is recorded.
        #expect(try config.versions().map(\.summary) == ["Created the configuration folder"], "mistakes change nothing")
    }

    @Test func servesLinesUntilInputCloses() {
        var lines = [#"{"jsonrpc": "2.0", "id": 1, "method": "ping"}"#, #"{"jsonrpc": "2.0", "method": "notifications/initialized"}"#]
        var written: [String] = []
        let result = ControlCommand.serveMCPIfAsked(["mcp", "--config", config.folder.path], sourceFromSettings: false,
                                                    input: { lines.isEmpty ? nil : lines.removeFirst() },
                                                    output: { written.append($0) })
        #expect(result?.exitCode == 0)
        #expect(written == [#"{"id":1,"jsonrpc":"2.0","result":{}}"#])
        #expect(ControlCommand.serveMCPIfAsked(["filters", "list"], sourceFromSettings: false, input: { nil }, output: { _ in }) == nil)
    }
}
