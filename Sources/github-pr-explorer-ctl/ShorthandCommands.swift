import Foundation
import GitHubPRExplorerCore

/// `shorthands`: read and change `shorthands.json`, the short names the app draws in place of
/// repositories and people. The same file Settings, Shorthands writes. Every change is recorded
/// in the folder's history as made by "ctl".
extension ControlCommand {
    static let shorthandsHelp = """
        \(name) shorthands <command> [--config <folder>]

        A shorthand is a short text the app draws in place of a repository's owner/name or a
        person's name, such as Web for acme/web. It is display only: titles, descriptions,
        comments, links, copied values and anything sent to GitHub are unchanged. Hovering a
        shortened label shows the full name, and the search finds both.

        Commands:
          shorthands list [--json]                     Every shorthand: kind, what it is for, the
                                                       shorthand, and a warning when two share one.
          shorthands set <kind> <for> <shorthand>      Set or replace one. Kinds: \(ShorthandKind.allCases.map(\.rawValue).joined(separator: ", ")).
          shorthands remove <kind> <for>               Take one away, so the full name shows again.

        A repository is written owner/name. A person is their login, with or without @.

        Examples:
          \(name) shorthands set repository acme/web Web
          \(name) shorthands set person ada-park Ada
          \(name) shorthands remove person ada-park
        """

    static func shorthands(_ arguments: [String], folder: URL) -> ControlCommandResult {
        guard let command = arguments.first, command != "--help", command != "-h" else {
            return arguments.isEmpty ? .failure(shorthandsHelp + "\n", exitCode: 2) : .success(shorthandsHelp + "\n")
        }
        let rest = Array(arguments.dropFirst())
        if rest.contains("--help") || rest.contains("-h") { return .success(shorthandsHelp + "\n") }
        let store = ConfigurationStore(folder: folder)
        func kind(_ text: String) -> ShorthandKind? { ShorthandKind(rawValue: text) }
        let kinds = ShorthandKind.allCases.map(\.rawValue).joined(separator: " or ")
        switch command {
        case "list":
            let json = rest.contains("--json")
            if let unknown = rest.first(where: { $0 != "--json" }) {
                return .failure("Unknown option: \(unknown).\n\n\(shorthandsHelp)\n", exitCode: 2)
            }
            let snapshot = store.exists ? store.reload() : .builtIn
            if json { return encodeJSON(ShorthandsReport(snapshot.shorthands)) }
            return .success(shorthandLines(snapshot.shorthands) + problemLines(snapshot.problems.filter { $0.file == ShorthandsFile.fileName }))
        case "set":
            guard rest.count == 3, let chosen = kind(rest[0]) else {
                return .failure("shorthands set needs a kind (\(kinds)), what it is for, and the shorthand, such as `shorthands set repository acme/web Web`.\n", exitCode: 2)
            }
            do throws(ConfigurationError) {
                let summary = try store.setShorthand(chosen, for: rest[1], to: rest[2], author: .commandLine)
                let clash = store.snapshot.shorthands.entries
                    .first { $0.id == Shorthand.key(chosen, chosen.normalizedIdentity(rest[1])) }
                    .flatMap { entry in store.snapshot.shorthands.clash(for: entry).map { "warning\t" + $0.warning(for: entry) + "\n" } } ?? ""
                return .success(summary + ".\n" + clash + historyWarning(store))
            } catch {
                return .failure(error.message + "\n")
            }
        case "remove":
            guard rest.count == 2, let chosen = kind(rest[0]) else {
                return .failure("shorthands remove needs a kind (\(kinds)) and what it is for, such as `shorthands remove person ada-park`.\n", exitCode: 2)
            }
            do throws(ConfigurationError) {
                let summary = try store.removeShorthand(chosen, for: rest[1], author: .commandLine)
                return .success(summary + ".\n" + historyWarning(store))
            } catch {
                return .failure(error.message + "\n")
            }
        default:
            return .failure("Unknown command: shorthands \(command).\n\n\(shorthandsHelp)\n", exitCode: 2)
        }
    }

    /// One line per shorthand, tab separated, then a warning line for each clash.
    static func shorthandLines(_ shorthands: Shorthands) -> String {
        guard !shorthands.isEmpty else { return "No shorthands. Full names are shown everywhere.\n" }
        var text = shorthands.entries.map { "\($0.kind.rawValue)\t\($0.target)\t\($0.shorthand)\n" }.joined()
        text += clashLines(shorthands)
        return text
    }

    static func clashLines(_ shorthands: Shorthands) -> String {
        shorthands.clashes.map { "warning\t\($0.summary)\n" }.joined()
    }

    struct ShorthandsReport: Codable {
        struct Entry: Codable {
            var kind: String
            var `for`: String
            var shorthand: String
        }
        struct Clash: Codable {
            var shorthand: String
            var `for`: [String]
        }
        var shorthands: [Entry]
        /// Things that share a shorthand. Allowed, and warned about.
        var clashes: [Clash]

        init(_ shorthands: Shorthands) {
            self.shorthands = shorthands.entries.map { Entry(kind: $0.kind.rawValue, for: $0.target, shorthand: $0.shorthand) }
            clashes = shorthands.clashes.map { Clash(shorthand: $0.shorthand, for: $0.entries.map(\.target)) }
        }
    }

    /// The shorthands to search with: the configuration folder's, when the command was given
    /// `--config` or reads the settings as the real tool does. Tests that name neither read none,
    /// so they never touch the real folder.
    static func searchShorthands(_ folder: URL, readsFolder: Bool) -> Shorthands {
        guard readsFolder else { return .none }
        let store = ConfigurationStore(folder: folder)
        guard store.exists else { return .none }
        return store.reload().shorthands
    }
}
