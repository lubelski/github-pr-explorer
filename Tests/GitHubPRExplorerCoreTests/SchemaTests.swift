import Foundation
import Testing
@testable import GitHubPRExplorerCore

/// Keeps the hand-written schemas in `schemas/` in step with the Swift types.
///
/// It is not a full JSON Schema validator. `MiniSchemaValidator` checks the keywords these two
/// schemas use: type, properties, required, additionalProperties, items, $ref to $defs, enum,
/// pattern, minLength, maxLength, minItems, maxItems, exclusiveMinimum, minimum, maximum and propertyNames. The tests check
/// that the names and enums match the types, that the built-in layouts and the default settings
/// pass, and that files the app refuses are refused by the schema too.
@Suite struct SchemaTests {
    static let schemasFolder = URL(filePath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appending(path: "schemas")

    static func schema(_ name: String) throws -> [String: Any] {
        let data = try Data(contentsOf: schemasFolder.appending(path: name))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    static func json(_ data: Data) throws -> Any { try JSONSerialization.jsonObject(with: data) }

    @Test func settingsSchemaNamesMatchTheType() throws {
        let schema = try Self.schema("settings.schema.json")
        let properties = try #require(schema["properties"] as? [String: [String: Any]])
        #expect(Set(properties.keys) == Set(ConfigurationSettings.keys + ["$schema"]))
        guard case .object(let shape) = JSONKeyCheck.settingsShape else { Issue.record("not an object"); return }
        #expect(Set(shape.keys) == Set(ConfigurationSettings.keys))
        #expect(properties["appearance"]?["enum"] as? [String] == Appearance.allCases.map(\.rawValue))
        let experimentNames = (properties["experiments"]?["propertyNames"] as? [String: Any])?["enum"] as? [String]
        #expect(experimentNames == Experiment.allCases.map(\.key))
        #expect(schema["required"] as? [String] == ["formatVersion"])
        #expect(properties["formatVersion"]?["enum"] as? [Int] == [ConfigurationSettings.currentFormatVersion])
        for (name, property) in properties {
            #expect((property["description"] as? String)?.isEmpty == false, "\(name) has no description")
        }
        // The defaults the schema states are the type's.
        let defaults = try #require(try Self.json(ConfigurationSettings.defaults.encoded()) as? [String: Any])
        #expect(properties["appearance"]?["default"] as? String == defaults["appearance"] as? String)
        #expect(properties["defaultLayout"]?["default"] as? String == defaults["defaultLayout"] as? String)
        #expect(properties["hidesBotEventsInActivity"]?["default"] as? Bool == defaults["hidesBotEventsInActivity"] as? Bool)
        #expect(properties["updatesAutomatically"]?["default"] as? Bool == defaults["updatesAutomatically"] as? Bool)
        #expect(properties["pullRequestSource"]?["enum"] as? [String] == PullRequestSource.allCases.map(\.rawValue))
        #expect(properties["pullRequestSource"]?["default"] as? String == defaults["pullRequestSource"] as? String)
        #expect(properties["syncIntervalSeconds"]?["default"] as? Int == defaults["syncIntervalSeconds"] as? Int)
        #expect(properties["syncIntervalSeconds"]?["minimum"] as? Int == ConfigurationSettings.syncIntervalRange.lowerBound)
        #expect(properties["syncIntervalSeconds"]?["maximum"] as? Int == ConfigurationSettings.syncIntervalRange.upperBound)
        #expect((properties["watchedRepositories"]?["default"] as? [String])?.isEmpty == true)
    }

    @Test func layoutSchemaNamesMatchTheTypes() throws {
        let schema = try Self.schema("page-layout.schema.json")
        let definitions = try #require(schema["$defs"] as? [String: [String: Any]])
        let block = try #require(definitions["block"]?["properties"] as? [String: [String: Any]])
        #expect(block["kind"]?["enum"] as? [String] == BlockKind.allCases.map(\.rawValue))
        #expect(block["size"]?["enum"] as? [String] == BlockSize.allCases.map(\.rawValue))

        // Every object in the schema allows exactly the keys the key check allows.
        func keys(_ object: [String: Any]) -> Set<String> {
            Set((object["properties"] as? [String: Any] ?? [:]).keys).subtracting(["$schema"])
        }
        guard case .object(let top) = JSONKeyCheck.layoutShape,
              case .array(.object(let tab)) = top["tabs"],
              case .array(.object(let column)) = tab["columns"],
              case .array(.object(let placement)) = column["blocks"]
        else { Issue.record("unexpected shape"); return }
        #expect(keys(schema) == Set(top.keys))
        #expect(keys(definitions["tab"] ?? [:]) == Set(tab.keys))
        #expect(keys(definitions["column"] ?? [:]) == Set(column.keys))
        #expect(keys(definitions["block"] ?? [:]) == Set(placement.keys))

        // Every property everywhere is described.
        for (name, definition) in [("layout", schema)] + definitions.map({ ($0.key, $0.value) }) {
            for (property, value) in definition["properties"] as? [String: [String: Any]] ?? [:] {
                #expect((value["description"] as? String)?.isEmpty == false, "\(name).\(property) has no description")
            }
        }
    }

    @Test func theBuiltInLayoutsAndDefaultSettingsPass() throws {
        let layoutSchema = try Self.schema("page-layout.schema.json")
        for file in LayoutLibrary.builtInFiles() {
            let problems = MiniSchemaValidator(root: layoutSchema).validate(try Self.json(file.data))
            #expect(problems.isEmpty, "\(file.name): \(problems)")
        }
        let settingsSchema = try Self.schema("settings.schema.json")
        let problems = MiniSchemaValidator(root: settingsSchema).validate(try Self.json(ConfigurationSettings.defaults.encoded()))
        #expect(problems.isEmpty, "\(problems)")
    }

    static let badLayouts = [
        #"{"formatVersion": 1, "id": "x", "name": "X", "tabs": []}"#,
        #"{"formatVersion": 2, "id": "x", "name": "X", "tabs": [{"name": "T", "columns": []}]}"#,
        #"{"formatVersion": 1, "id": "Not OK", "name": "X", "tabs": [{"name": "T", "columns": []}]}"#,
        #"{"formatVersion": 1, "id": "x", "name": "", "tabs": [{"name": "T", "columns": []}]}"#,
        #"{"formatVersion": 1, "id": "x", "name": "X", "colour": "red", "tabs": [{"name": "T", "columns": []}]}"#,
        #"{"formatVersion": 1, "id": "x", "name": "X", "tabs": [{"name": "T", "columns": [{"width": 0, "blocks": []}]}]}"#,
        #"{"formatVersion": 1, "id": "x", "name": "X", "tabs": [{"name": "T", "columns": [{"width": 1, "blocks": [{"kind": "summary", "size": "large"}]}]}]}"#,
        #"{"formatVersion": 1, "id": "x", "name": "X", "tabs": [{"name": "T", "columns": [{"width": 1, "blocks": [{"kind": "files", "size": "huge"}]}]}]}"#,
        #"{"formatVersion": 1, "id": "x", "name": "X", "tabs": [{"name": "T", "columns": [{"width": 1, "blocks": [{"kind": "files"}]}]}]}"#,
    ]

    static let badSettings = [
        #"{"appearance": "dark"}"#,
        #"{"formatVersion": 1, "appearance": "purple"}"#,
        #"{"formatVersion": 1, "defaultLayuot": "tabbed"}"#,
        #"{"formatVersion": 1, "hidesBotEventsInActivity": "yes"}"#,
        #"{"formatVersion": 1, "experiments": {"warpDrive": true}}"#,
        #"{"formatVersion": 1, "defaultLayout": ""}"#,
        #"{"formatVersion": 1, "pullRequestSource": "gitlab"}"#,
        #"{"formatVersion": 1, "syncIntervalSeconds": 10}"#,
        #"{"formatVersion": 1, "syncIntervalSeconds": 7200}"#,
        #"{"formatVersion": 1, "watchedRepositories": ["acme"]}"#,
        #"{"formatVersion": 1, "watchedRepositories": ["acme/api/extra"]}"#,
        #"{"formatVersion": 1, "watchedRepositories": "acme/api"}"#,
    ]

    @Test func filesTheAppRefusesTheSchemaRefuses() throws {
        let layoutSchema = MiniSchemaValidator(root: try Self.schema("page-layout.schema.json"))
        for text in Self.badLayouts {
            #expect(throws: LayoutFileError.self, "the app accepted \(text)") { try PageLayout.decode(Data(text.utf8), fileName: "x.json") }
            #expect(!layoutSchema.validate(try Self.json(Data(text.utf8))).isEmpty, "the schema accepted \(text)")
        }
        let settingsSchema = MiniSchemaValidator(root: try Self.schema("settings.schema.json"))
        for text in Self.badSettings {
            #expect(throws: LayoutFileError.self, "the app accepted \(text)") { try ConfigurationSettings.decode(Data(text.utf8)) }
            #expect(!settingsSchema.validate(try Self.json(Data(text.utf8))).isEmpty, "the schema accepted \(text)")
        }
        // And a file with only some keys passes both.
        let partial = #"{"$schema": "../schemas/settings.schema.json", "formatVersion": 1, "defaultLayout": "tabbed"}"#
        #expect(settingsSchema.validate(try Self.json(Data(partial.utf8))).isEmpty)
        #expect(try ConfigurationSettings.decode(Data(partial.utf8)).defaultLayout == "tabbed")
    }
}

extension SchemaTests {
    @Test func savedFiltersSchemaMatchesTheTypes() throws {
        let schema = try Self.schema("saved-filters.schema.json")
        let definitions = try #require(schema["$defs"] as? [String: [String: Any]])
        func keys(_ object: [String: Any]) -> Set<String> {
            Set((object["properties"] as? [String: Any] ?? [:]).keys).subtracting(["$schema"])
        }
        // Every object allows exactly the keys the key check allows.
        guard case .object(let top) = SavedFilterFile.shape,
              case .array(.object(let saved)) = top["savedFilters"],
              case .object(let filter) = PullRequestFilter.shape,
              case .array(.object(let set)) = filter["sets"],
              case .array(.object(let condition)) = set["conditions"]
        else { Issue.record("unexpected shape"); return }
        #expect(keys(schema) == Set(top.keys))
        #expect(keys(definitions["savedFilter"] ?? [:]) == Set(saved.keys))
        #expect(keys(definitions["filter"] ?? [:]) == Set(filter.keys))
        #expect(keys(definitions["set"] ?? [:]) == Set(set.keys))
        #expect(keys(definitions["condition"] ?? [:]) == Set(condition.keys))

        let conditionProperties = try #require(definitions["condition"]?["properties"] as? [String: [String: Any]])
        #expect(conditionProperties["field"]?["enum"] as? [String] == FilterField.allCases.map(\.rawValue))
        #expect(conditionProperties["operator"]?["enum"] as? [String] == FilterOperator.allCases.map(\.rawValue))
        // The values the schema describes are the ones the app takes.
        let valuesText = try #require(conditionProperties["values"]?["description"] as? String)
        for field in FilterField.allCases {
            for value in FilterValues.fixed(for: field) ?? [] where field != .draft {
                #expect(valuesText.contains(value), "\(field.rawValue) \(value) is not described")
            }
        }
        let groupBy = try #require((definitions["savedFilter"]?["properties"] as? [String: [String: Any]])?["groupBy"])
        #expect(groupBy["maxItems"] as? Int == SavedFilter.maximumGroupingLevels)
        #expect(schema["properties"].flatMap { ($0 as? [String: [String: Any]])?["formatVersion"]?["enum"] as? [Int] } == [SavedFilterFile.currentFormatVersion])

        for (name, definition) in [("file", schema)] + definitions.map({ ($0.key, $0.value) }) {
            for (property, value) in definition["properties"] as? [String: [String: Any]] ?? [:] {
                #expect((value["description"] as? String)?.isEmpty == false, "\(name).\(property) has no description")
            }
        }
    }

    static let badSavedFilters = [
        #"{"savedFilters": []}"#,
        #"{"formatVersion": 2, "savedFilters": []}"#,
        #"{"formatVersion": 1, "savedFilters": [{"id": "Not OK", "name": "A", "filter": {"sets": []}}]}"#,
        #"{"formatVersion": 1, "savedFilters": [{"id": "a", "name": "", "filter": {"sets": []}}]}"#,
        #"{"formatVersion": 1, "savedFilters": [{"id": "a", "name": "A"}]}"#,
        #"{"formatVersion": 1, "savedFilters": [{"id": "a", "name": "A", "filter": {"sets": []}, "colour": "red"}]}"#,
        #"{"formatVersion": 1, "savedFilters": [{"id": "a", "name": "A", "filter": {"sets": []}, "groupBy": ["a", "b", "c"]}]}"#,
        #"{"formatVersion": 1, "savedFilters": [{"id": "a", "name": "A", "filter": {"sets": [{"conditions": [{"field": "label", "values": ["x"]}]}]}}]}"#,
        #"{"formatVersion": 1, "savedFilters": [{"id": "a", "name": "A", "filter": {"sets": [{"conditions": [{"field": "status", "operator": "isn't", "values": ["blocked"]}]}]}}]}"#,
        #"{"formatVersion": 1, "savedFilters": [{"id": "a", "name": "A", "filter": {"sets": [{"conditions": [{"field": "status", "values": []}]}]}}]}"#,
        #"{"formatVersion": 1, "savedFilters": [{"id": "a", "name": "A", "filter": {"sets": [{"conditions": [{"field": "status"}]}]}}]}"#,
    ]

    @Test func theDefaultSavedFiltersPassAndBadOnesFailBoth() throws {
        let validator = MiniSchemaValidator(root: try Self.schema("saved-filters.schema.json"))
        let defaults = validator.validate(try Self.json(SavedFilterFile.defaults.encoded()))
        #expect(defaults.isEmpty, "\(defaults)")
        for text in Self.badSavedFilters {
            #expect(throws: LayoutFileError.self, "the app accepted \(text)") { try SavedFilterFile.decode(Data(text.utf8)) }
            #expect(!validator.validate(try Self.json(Data(text.utf8))).isEmpty, "the schema accepted \(text)")
        }
        let minimal = #"{"$schema": "../schemas/saved-filters.schema.json", "formatVersion": 1, "savedFilters": [{"id": "a", "name": "A", "filter": {"sets": [{"conditions": [{"field": "author", "values": ["@me"]}]}]}}]}"#
        #expect(validator.validate(try Self.json(Data(minimal.utf8))).isEmpty)
        #expect(try SavedFilterFile.decode(Data(minimal.utf8)).savedFilters[0].filter == SavedFilter.mine.filter)
    }
}

/// The JSON Schema keywords the two schemas use, and no more.
struct MiniSchemaValidator {
    let root: [String: Any]

    func validate(_ value: Any) -> [String] { check(value, against: root, at: "$") }

    private func resolve(_ schema: [String: Any]) -> [String: Any] {
        guard let reference = schema["$ref"] as? String, reference.hasPrefix("#/$defs/") else { return schema }
        let name = String(reference.dropFirst("#/$defs/".count))
        return (root["$defs"] as? [String: [String: Any]])?[name] ?? [:]
    }

    private func typeMatches(_ value: Any, _ type: String) -> Bool {
        switch type {
        case "object": return value is [String: Any]
        case "array": return value is [Any]
        case "string": return value is String
        case "boolean": return (value as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false
        case "integer":
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return false }
            return number.doubleValue.rounded() == number.doubleValue
        case "number":
            guard let number = value as? NSNumber else { return false }
            return CFGetTypeID(number) != CFBooleanGetTypeID()
        default: return true
        }
    }

    private func check(_ value: Any, against unresolved: [String: Any], at path: String) -> [String] {
        let schema = resolve(unresolved)
        var problems: [String] = []
        if let type = schema["type"] as? String, !typeMatches(value, type) {
            return ["\(path): expected \(type)"]
        }
        if let options = schema["enum"] as? [Any] {
            let matches = options.contains { option in
                if let text = option as? String { return (value as? String) == text }
                if let number = option as? NSNumber, let other = value as? NSNumber { return number == other }
                return false
            }
            if !matches { problems.append("\(path): not one of \(options)") }
        }
        if let text = value as? String {
            if let minimum = schema["minLength"] as? Int, text.count < minimum { problems.append("\(path): shorter than \(minimum)") }
            if let maximum = schema["maxLength"] as? Int, text.count > maximum { problems.append("\(path): longer than \(maximum)") }
            if let pattern = schema["pattern"] as? String, text.range(of: pattern, options: .regularExpression) == nil {
                problems.append("\(path): does not match \(pattern)")
            }
        }
        if let number = value as? NSNumber, let minimum = schema["exclusiveMinimum"] as? NSNumber, number.doubleValue <= minimum.doubleValue {
            problems.append("\(path): not above \(minimum)")
        }
        if let number = value as? NSNumber, let minimum = schema["minimum"] as? NSNumber, number.doubleValue < minimum.doubleValue {
            problems.append("\(path): below \(minimum)")
        }
        if let number = value as? NSNumber, let maximum = schema["maximum"] as? NSNumber, number.doubleValue > maximum.doubleValue {
            problems.append("\(path): above \(maximum)")
        }
        if let items = value as? [Any] {
            if let minimum = schema["minItems"] as? Int, items.count < minimum { problems.append("\(path): fewer than \(minimum) items") }
            if let maximum = schema["maxItems"] as? Int, items.count > maximum { problems.append("\(path): more than \(maximum) items") }
            if let itemSchema = schema["items"] as? [String: Any] {
                for (index, item) in items.enumerated() { problems += check(item, against: itemSchema, at: "\(path)[\(index)]") }
            }
        }
        if let object = value as? [String: Any] {
            for required in schema["required"] as? [String] ?? [] where object[required] == nil {
                problems.append("\(path): \(required) is missing")
            }
            let properties = schema["properties"] as? [String: [String: Any]] ?? [:]
            let names = (schema["propertyNames"] as? [String: Any])?["enum"] as? [String]
            for (key, inner) in object {
                if let names, !names.contains(key) { problems.append("\(path).\(key): not an allowed name") }
                if let propertySchema = properties[key] {
                    problems += check(inner, against: propertySchema, at: "\(path).\(key)")
                } else if let additional = schema["additionalProperties"] as? [String: Any] {
                    problems += check(inner, against: additional, at: "\(path).\(key)")
                } else if (schema["additionalProperties"] as? Bool) == false {
                    problems.append("\(path).\(key): not allowed")
                }
            }
        }
        return problems
    }
}
