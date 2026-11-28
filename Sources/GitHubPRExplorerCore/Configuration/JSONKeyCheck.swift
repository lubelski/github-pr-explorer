import Foundation

/// Refuses keys a configuration file's format does not have.
///
/// `Codable` ignores a key it does not know, so a misspelled setting such as
/// `"defaultLayuot"` would be dropped without a word. Configuration is written by people and
/// agents, so a key that is not in the format is reported with where it is and which keys are
/// allowed there. The shapes here match the schemas in `schemas/`, and a test checks them.
enum JSONKeyCheck {
    indirect enum Shape: Sendable {
        /// An object with exactly these keys allowed.
        case object([String: Shape])
        /// An object whose keys are names, such as `experiments`, each holding this.
        case dictionary(Shape)
        case array(Shape)
        /// A string, number or true or false: checked by the decoder, not here.
        case value
    }

    /// Allowed at the top of every file, so an editor can be pointed at the schema.
    static let schemaKey = "$schema"

    static let settingsShape = Shape.object([
        "formatVersion": .value, "appearance": .value, "defaultLayout": .value,
        "hidesBotEventsInActivity": .value, "updatesAutomatically": .value, "experiments": .dictionary(.value),
        "pullRequestSource": .value, "syncIntervalSeconds": .value, "watchedRepositories": .array(.value),
    ])

    static let layoutShape = Shape.object([
        "formatVersion": .value, "id": .value, "name": .value,
        "tabs": .array(.object([
            "name": .value,
            "columns": .array(.object([
                "width": .value,
                "blocks": .array(.object(["kind": .value, "size": .value])),
            ])),
        ])),
    ])

    /// Throws for the first unknown key. Text that is not JSON passes, for the decoder to report.
    static func check(_ data: Data, fileName: String, allowed shape: Shape, allowsSchemaKey: Bool = true) throws(LayoutFileError) {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return }
        if let problem = walk(object, shape: shape, path: "", isTop: allowsSchemaKey) {
            throw LayoutFileError(fileName: fileName, path: problem.path, problem: problem.message)
        }
    }

    private static func walk(_ value: Any, shape: Shape, path: String, isTop: Bool = false) -> (path: String, message: String)? {
        switch shape {
        case .value:
            return nil
        case .array(let element):
            guard let items = value as? [Any] else { return nil }
            for (index, item) in items.enumerated() {
                if let problem = walk(item, shape: element, path: "\(path)[\(index)]") { return problem }
            }
            return nil
        case .dictionary(let element):
            guard let object = value as? [String: Any] else { return nil }
            for key in object.keys.sorted() {
                if let problem = walk(object[key]!, shape: element, path: join(path, key)) { return problem }
            }
            return nil
        case .object(let keys):
            guard let object = value as? [String: Any] else { return nil }
            for key in object.keys.sorted() {
                if isTop && key == schemaKey { continue }
                guard let inner = keys[key] else {
                    return (join(path, key), "unknown key \"\(key)\". Allowed here: \(keys.keys.sorted().joined(separator: ", ")).")
                }
                if let problem = walk(object[key]!, shape: inner, path: join(path, key)) { return problem }
            }
            return nil
        }
    }

    private static func join(_ path: String, _ key: String) -> String { path.isEmpty ? key : "\(path).\(key)" }
}
