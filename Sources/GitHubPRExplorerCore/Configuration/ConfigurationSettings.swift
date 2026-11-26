import Foundation

/// The general settings, stored as `settings.json` in the configuration folder.
///
/// Only `formatVersion` is required. A key left out takes its default, so a person or an agent
/// can write just the one setting they care about. A key the app does not know makes the file
/// invalid, so a misspelled setting is reported instead of ignored. The schema is
/// `schemas/settings.schema.json` in the repository, and a test keeps the two in step.
public struct ConfigurationSettings: Codable, Sendable, Hashable {
    public static let currentFormatVersion = 1
    public static let fileName = "settings.json"

    public var formatVersion: Int
    /// Light, dark, or whatever the system uses.
    public var appearance: Appearance
    /// The layout every pull request page opens with. The layout menu in the window changes
    /// the layout of the open window only.
    public var defaultLayout: String
    /// Whether Activity starts with bot events folded into one row.
    public var hidesBotEventsInActivity: Bool
    /// The experiments that are on, by name. One left out is off.
    public var experiments: [String: Bool]

    public init(formatVersion: Int = currentFormatVersion, appearance: Appearance = .system,
                defaultLayout: String = LayoutLibrary.fallbackID, hidesBotEventsInActivity: Bool = true,
                experiments: [String: Bool] = [:]) {
        self.formatVersion = formatVersion
        self.appearance = appearance
        self.defaultLayout = defaultLayout
        self.hidesBotEventsInActivity = hidesBotEventsInActivity
        self.experiments = experiments
    }

    public static let defaults = ConfigurationSettings()

    /// The keys a settings file may hold, for the unknown-key check and `config set`.
    public static let keys = ["formatVersion", "appearance", "defaultLayout", "hidesBotEventsInActivity", "experiments"]

    enum CodingKeys: String, CodingKey {
        case formatVersion, appearance, defaultLayout, hidesBotEventsInActivity, experiments
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.defaults
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        appearance = try container.decodeIfPresent(Appearance.self, forKey: .appearance) ?? defaults.appearance
        defaultLayout = try container.decodeIfPresent(String.self, forKey: .defaultLayout) ?? defaults.defaultLayout
        hidesBotEventsInActivity = try container.decodeIfPresent(Bool.self, forKey: .hidesBotEventsInActivity)
            ?? defaults.hidesBotEventsInActivity
        experiments = try container.decodeIfPresent([String: Bool].self, forKey: .experiments) ?? defaults.experiments
    }

    public func isOn(_ experiment: Experiment) -> Bool { experiments[experiment.key] ?? false }

    public mutating func set(_ experiment: Experiment, on: Bool) {
        experiments[experiment.key] = on ? true : nil
    }

    /// Sorted keys and pretty printed, the same bytes on every run.
    public func encoded() throws -> Data {
        var data = try GitHubPRExplorerJSON.encoder().encode(self)
        data.append(0x0A)
        return data
    }

    /// Reads a settings file. Problems name where in the file and what is wrong.
    public static func decode(_ data: Data, fileName: String = fileName) throws(LayoutFileError) -> ConfigurationSettings {
        try JSONKeyCheck.check(data, fileName: fileName, allowed: JSONKeyCheck.settingsShape)
        let settings: ConfigurationSettings
        do {
            settings = try GitHubPRExplorerJSON.decoder().decode(ConfigurationSettings.self, from: data)
        } catch let error as DecodingError {
            throw LayoutFileError.describe(error, fileName: fileName)
        } catch {
            throw LayoutFileError(fileName: fileName, problem: error.localizedDescription)
        }
        guard settings.formatVersion == currentFormatVersion else {
            throw LayoutFileError(fileName: fileName, path: "formatVersion",
                                  problem: "format version \(settings.formatVersion) is not one this app reads. It reads version \(currentFormatVersion).")
        }
        if settings.defaultLayout.trimmingCharacters(in: .whitespaces).isEmpty {
            throw LayoutFileError(fileName: fileName, path: "defaultLayout", problem: "the default layout is empty")
        }
        for name in settings.experiments.keys.sorted() where Experiment(key: name) == nil {
            let known = Experiment.allCases.map(\.key)
            throw LayoutFileError(fileName: fileName, path: "experiments.\(name)",
                                  problem: "there is no experiment \"\(name)\". " + (known.isEmpty
                                    ? "There are no experiments right now, so this must be {}."
                                    : "Known experiments: \(known.joined(separator: ", "))."))
        }
        return settings
    }
}

/// Light, dark, or the system's choice.
public enum Appearance: String, Codable, Sendable, Hashable, CaseIterable {
    case system
    case light
    case dark

    public init(from decoder: any Decoder) throws {
        self = try decodeNamedValue(decoder, as: Appearance.self)
    }

    public var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

/// Features being tried. Each is a switch in Settings, Experiments, off by default, and stored
/// in `settings.json` under `experiments` by its key. With a switch off, the app is as it was.
///
/// There are none right now. A case added here shows in Settings with its title and
/// description, and `config set experiments.<key> true` turns it on.
public enum Experiment: CaseIterable, Sendable, Hashable, Identifiable {
    // No experiments yet. Add a case, then its key, title and description below.

    public var id: String { key }

    /// The name in `settings.json`, such as `slidingDiffPane`.
    public var key: String {
        switch self {}
    }

    /// The switch's title in Settings.
    public var title: String {
        switch self {}
    }

    /// One line under the switch: what turning it on changes.
    public var summary: String {
        switch self {}
    }

    public init?(key: String) {
        guard let found = Self.allCases.first(where: { $0.key == key }) else { return nil }
        self = found
    }
}

/// Decodes a string that must be one of an enum's names, with an error that lists the names,
/// instead of the decoder's own "Cannot initialize ... from invalid String value".
func decodeNamedValue<T: RawRepresentable & CaseIterable>(_ decoder: any Decoder, as type: T.Type) throws -> T where T.RawValue == String {
    let container = try decoder.singleValueContainer()
    let text = try container.decode(String.self)
    guard let value = T(rawValue: text) else {
        let known = T.allCases.map { "\"\($0.rawValue)\"" }.joined(separator: ", ")
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "\"\(text)\" is not one of \(known)")
    }
    return value
}
