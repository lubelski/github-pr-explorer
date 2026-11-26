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
    /// Whether a release build checks for, downloads and installs updates without asking.
    /// A build with no update feed ignores it.
    public var updatesAutomatically: Bool
    /// The experiments that are on, by name. One left out is off.
    public var experiments: [String: Bool]
    /// Where the pull requests the window shows come from: the built-in mock world, or GitHub
    /// through the `gh` login. Mock by default, so nothing changes until a person opts in.
    public var pullRequestSource: PullRequestSource
    /// How often the light list pass runs while the source is GitHub, in seconds.
    public var syncIntervalSeconds: Int
    /// Repositories, as `owner/name`, whose every open pull request is fetched, besides the
    /// ones that involve the signed-in person.
    public var watchedRepositories: [String]

    public static let syncIntervalRange = 60...3600

    public init(formatVersion: Int = currentFormatVersion, appearance: Appearance = .system,
                defaultLayout: String = LayoutLibrary.fallbackID, hidesBotEventsInActivity: Bool = true,
                updatesAutomatically: Bool = true, experiments: [String: Bool] = [:],
                pullRequestSource: PullRequestSource = .mock, syncIntervalSeconds: Int = 300,
                watchedRepositories: [String] = []) {
        self.formatVersion = formatVersion
        self.appearance = appearance
        self.defaultLayout = defaultLayout
        self.hidesBotEventsInActivity = hidesBotEventsInActivity
        self.updatesAutomatically = updatesAutomatically
        self.experiments = experiments
        self.pullRequestSource = pullRequestSource
        self.syncIntervalSeconds = syncIntervalSeconds
        self.watchedRepositories = watchedRepositories
    }

    /// The watched repositories that parse as `owner/name`. `decode` refuses a file with one
    /// that does not, so in a file the app applied this is all of them.
    public var watchedRepositoryList: [Repository] {
        watchedRepositories.compactMap(Repository.init(fullName:))
    }

    public static let defaults = ConfigurationSettings()

    /// The keys a settings file may hold, for the unknown-key check and `config set`.
    public static let keys = ["formatVersion", "appearance", "defaultLayout", "hidesBotEventsInActivity", "updatesAutomatically", "experiments",
                              "pullRequestSource", "syncIntervalSeconds", "watchedRepositories"]

    enum CodingKeys: String, CodingKey {
        case formatVersion, appearance, defaultLayout, hidesBotEventsInActivity, updatesAutomatically, experiments
        case pullRequestSource, syncIntervalSeconds, watchedRepositories
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.defaults
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        appearance = try container.decodeIfPresent(Appearance.self, forKey: .appearance) ?? defaults.appearance
        defaultLayout = try container.decodeIfPresent(String.self, forKey: .defaultLayout) ?? defaults.defaultLayout
        hidesBotEventsInActivity = try container.decodeIfPresent(Bool.self, forKey: .hidesBotEventsInActivity)
            ?? defaults.hidesBotEventsInActivity
        updatesAutomatically = try container.decodeIfPresent(Bool.self, forKey: .updatesAutomatically)
            ?? defaults.updatesAutomatically
        experiments = try container.decodeIfPresent([String: Bool].self, forKey: .experiments) ?? defaults.experiments
        pullRequestSource = try container.decodeIfPresent(PullRequestSource.self, forKey: .pullRequestSource) ?? defaults.pullRequestSource
        syncIntervalSeconds = try container.decodeIfPresent(Int.self, forKey: .syncIntervalSeconds) ?? defaults.syncIntervalSeconds
        watchedRepositories = try container.decodeIfPresent([String].self, forKey: .watchedRepositories) ?? defaults.watchedRepositories
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
        if !syncIntervalRange.contains(settings.syncIntervalSeconds) {
            throw LayoutFileError(fileName: fileName, path: "syncIntervalSeconds",
                                  problem: "the sync interval is \(settings.syncIntervalSeconds) seconds. It must be from \(syncIntervalRange.lowerBound) to \(syncIntervalRange.upperBound).")
        }
        for (position, name) in settings.watchedRepositories.enumerated() where Repository(fullName: name) == nil || !Repository.isPlainName(name) {
            throw LayoutFileError(fileName: fileName, path: "watchedRepositories[\(position)]",
                                  problem: "\"\(name)\" is not a repository written as owner/name, such as acme/api")
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

/// Where the window's pull requests come from.
public enum PullRequestSource: String, Codable, Sendable, Hashable, CaseIterable {
    /// The built-in mock world: placeholder pull requests, no network, no sign-in.
    case mock
    /// GitHub, read through the `gh` login on this Mac.
    case github

    public init(from decoder: any Decoder) throws {
        self = try decodeNamedValue(decoder, as: PullRequestSource.self)
    }

    public var title: String {
        switch self {
        case .mock: "Mock data"
        case .github: "GitHub"
        }
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
