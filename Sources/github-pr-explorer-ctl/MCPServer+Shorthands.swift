import Foundation
import GitHubPRExplorerCore

/// The shorthand tools of `ctl mcp`: the same as `ctl shorthands list`, `set` and `remove`,
/// through the same store, with changes recorded as made by "MCP".
extension MCPServer {
    static var shorthandTools: [Tool] {
        let kinds = ShorthandKind.allCases.map(\.rawValue)
        let identity = "What it is for: owner/name for a repository, such as acme/web; a login for a person, such as ada-park; a name for an organization, such as acme."
        return [
            Tool(name: "shorthands_list",
                 description: "List every shorthand: the short names the app draws in place of repositories, people and organizations, with any two that share one. Display only.",
                 inputSchema: ["type": "object", "properties": [String: Any]()], readOnly: true),
            Tool(name: "shorthand_set",
                 description: "Set or replace the shorthand for one repository, person or organization. Two things may share a shorthand; the answer warns when they do.",
                 inputSchema: ["type": "object", "required": ["kind", "for", "shorthand"], "properties": [
                    "kind": ["type": "string", "enum": kinds],
                    "for": ["type": "string", "description": identity],
                    "shorthand": ["type": "string", "minLength": 1, "description": "What the app draws instead of the full name."],
                 ] as [String: Any]], readOnly: false),
            Tool(name: "shorthand_remove",
                 description: "Take away the shorthand for one repository, person or organization, so its full name shows again. The configuration's history keeps it.",
                 inputSchema: ["type": "object", "required": ["kind", "for"], "properties": [
                    "kind": ["type": "string", "enum": kinds],
                    "for": ["type": "string", "description": identity],
                 ] as [String: Any]], readOnly: false),
        ]
    }

    /// Runs a shorthand tool. Nil when `name` is not one.
    func callShorthandTool(_ name: String, _ arguments: [String: Any]) -> Result<String, Failure>? {
        let store = ConfigurationStore(folder: folder)
        func kind() -> ShorthandKind? { (arguments["kind"] as? String).flatMap(ShorthandKind.init(rawValue:)) }
        let kinds = ShorthandKind.allCases.map(\.rawValue).joined(separator: ", ")
        switch name {
        case "shorthands_list":
            let snapshot = store.exists ? store.reload() : .builtIn
            do {
                let data = try GitHubPRExplorerJSON.encoder().encode(ControlCommand.ShorthandsReport(snapshot.shorthands))
                return .success(String(decoding: data, as: UTF8.self))
            } catch {
                return .failure(.init("Could not encode the result: \(error)"))
            }
        case "shorthand_set":
            guard let kind = kind(), let target = arguments["for"] as? String, let text = arguments["shorthand"] as? String else {
                return .failure(.init("shorthand_set needs kind (\(kinds)), for and shorthand."))
            }
            do throws(ConfigurationError) {
                var answer = try store.setShorthand(kind, for: target, to: text, author: .mcp) + "."
                let lookup = store.snapshot.shorthands
                if let entry = lookup.entries.first(where: { $0.id == Shorthand.key(kind, kind.normalizedIdentity(target)) }),
                   let clash = lookup.clash(for: entry) {
                    answer += "\nWarning: " + clash.warning(for: entry)
                }
                if let problem = store.historyProblem { answer += "\nThe change was made, but it was not kept as a version: \(problem)" }
                return .success(answer)
            } catch {
                return .failure(.init(error.message))
            }
        case "shorthand_remove":
            guard let kind = kind(), let target = arguments["for"] as? String else {
                return .failure(.init("shorthand_remove needs kind (\(kinds)) and for."))
            }
            do throws(ConfigurationError) {
                return .success(try store.removeShorthand(kind, for: target, author: .mcp) + ".")
            } catch {
                return .failure(.init(error.message))
            }
        default:
            return nil
        }
    }
}
