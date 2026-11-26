import Foundation

/// A problem with one file in the configuration folder.
public struct ConfigurationProblem: Sendable, Hashable, CustomStringConvertible, Codable {
    /// The file, relative to the configuration folder, such as `layouts/mine.json`.
    public var file: String
    /// Where in the file, such as `tabs[0].columns[1].width`. Empty for the whole file.
    public var path: String
    public var problem: String
    /// True when the file was refused: it is not applied, and the last version that worked,
    /// if there was one, is still in use. False for a file that was applied but points at
    /// something missing, such as a default layout no layout has.
    public var refusesFile: Bool
    /// True when a refused file had an earlier version that worked, and that version is in use.
    public var lastGoodInUse: Bool

    public init(file: String, path: String = "", problem: String, refusesFile: Bool = true, lastGoodInUse: Bool = false) {
        self.file = file
        self.path = path
        self.problem = problem
        self.refusesFile = refusesFile
        self.lastGoodInUse = lastGoodInUse
    }

    init(_ error: LayoutFileError, file: String, lastGoodInUse: Bool) {
        self.init(file: file, path: error.path, problem: error.problem, refusesFile: true, lastGoodInUse: lastGoodInUse)
    }

    /// What happens because of the problem, in a sentence.
    public var consequence: String {
        guard refusesFile else { return "" }
        return lastGoodInUse ? "The last version that worked is still in use." : "It is not in use."
    }

    public var description: String {
        let place = path.isEmpty ? file : "\(file), at \(path)"
        let sentence = problem.last.map { ".!?".contains($0) } == true ? problem : problem + "."
        return [place + ": " + sentence, consequence].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// Where a layout in the library came from.
public enum LayoutSource: Sendable, Hashable {
    /// Ships with the app and cannot be changed. Duplicate it to edit.
    case builtIn
    /// A file in the configuration folder, relative to it, such as `layouts/mine.json`.
    /// `overridesBuiltIn` is true when its id is a built-in layout's, which it replaces.
    case file(String, overridesBuiltIn: Bool)

    public var file: String? {
        if case .file(let path, _) = self { return path }
        return nil
    }
}

public struct LayoutEntry: Sendable, Hashable, Identifiable {
    public var layout: PageLayout
    public var source: LayoutSource
    public var id: String { layout.id }
}

/// Everything the configuration folder says, as one value, and what is wrong with it.
public struct ConfigurationSnapshot: Sendable, Hashable {
    public var settings: ConfigurationSettings
    /// Built-in layouts first, in their order, each replaced by a file with its id, then the
    /// person's own layouts by name.
    public var layouts: [LayoutEntry]
    /// From `shorthands.json`. None when the file is missing.
    public var shorthands: Shorthands
    public var problems: [ConfigurationProblem]

    public init(settings: ConfigurationSettings = .defaults, layouts: [LayoutEntry], shorthands: Shorthands = .none,
                problems: [ConfigurationProblem] = []) {
        self.settings = settings
        self.layouts = layouts
        self.shorthands = shorthands
        self.problems = problems
    }

    /// The built-in layouts and nothing else, as before there is a folder.
    public static var builtIn: ConfigurationSnapshot {
        let library = LayoutLibrary.builtIn()
        return ConfigurationSnapshot(layouts: library.layouts.map { LayoutEntry(layout: $0, source: .builtIn) },
                                     problems: library.problems.map { ConfigurationProblem($0, file: "built in: \($0.fileName)", lastGoodInUse: false) })
    }

    /// The layouts as the window reads them. Its problems are the layout files' problems.
    public var library: LayoutLibrary {
        LayoutLibrary(layouts: layouts.map(\.layout),
                      problems: problems.filter { $0.file.hasPrefix(ConfigurationStore.layoutsFolderName + "/") }
                          .map { LayoutFileError(fileName: $0.file, path: $0.path, problem: $0.problem + ($0.consequence.isEmpty ? "" : " " + $0.consequence)) })
    }

    /// The layout pages open with: the default, or Decision first when no layout has its id.
    public var defaultLayout: PageLayout { library.layout(id: settings.defaultLayout) }

    public func entry(id: String) -> LayoutEntry? { layouts.first { $0.id == id } }
}

/// Why the store could not make a change. The files are as they were.
public struct ConfigurationError: Error, Sendable, Hashable, CustomStringConvertible {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

/// The configuration folder: reads it, checks it, writes changes to it, and keeps its history.
///
/// The folder holds `settings.json`, `shorthands.json` when any are set, one file per layout
/// under `layouts/`, and a `README.md` that explains them. A file that does not validate is never applied: the last version that
/// worked stays in use and the problem is reported with the file, where in it, and what is
/// wrong. Every valid change is committed to the folder's git repository, whoever made it, by
/// `ConfigurationHistory`. History never stops a save: when git fails, the change is made and
/// `historyProblem` says why it was not kept.
///
/// The store is not tied to a thread, but it is not meant to be shared between them: the app
/// uses it on the main actor, and `ctl` from its one thread.
public final class ConfigurationStore {
    public static let layoutsFolderName = "layouts"
    public static let readmeFileName = "README.md"

    /// `~/Library/Application Support/github-pr-explorer/config`. Only the app and `ctl` use it.
    /// Tests and renders always pass a temporary folder instead.
    public static var defaultFolder: URL {
        URL.applicationSupportDirectory.appending(path: "github-pr-explorer/config", directoryHint: .isDirectory)
    }

    public let folder: URL
    public let history: ConfigurationHistory
    public private(set) var snapshot: ConfigurationSnapshot = .builtIn
    /// Why the last history operation did not work, or nil when history is working.
    public private(set) var historyProblem: String?

    private var lastGoodSettings: ConfigurationSettings?
    private var lastGoodShorthands: ShorthandsFile?
    private var lastGoodLayouts: [String: PageLayout] = [:]
    private let builtIn = LayoutLibrary.builtIn()

    public init(folder: URL, gitPath: String = ConfigurationHistory.defaultGitPath, commitDate: (() -> Date)? = nil) {
        self.folder = folder
        self.history = ConfigurationHistory(folder: folder, gitPath: gitPath, commitDate: commitDate)
    }

    public var exists: Bool { FileManager.default.fileExists(atPath: folder.path) }
    public var settingsURL: URL { folder.appending(path: ConfigurationSettings.fileName) }
    public var shorthandsURL: URL { folder.appending(path: ShorthandsFile.fileName) }
    public var layoutsURL: URL { folder.appending(path: Self.layoutsFolderName, directoryHint: .isDirectory) }
    public func url(for file: String) -> URL { folder.appending(path: file) }
    public static func layoutFile(id: String) -> String { "\(layoutsFolderName)/\(id).json" }

    // MARK: Loading

    /// Makes the folder if it is not there: `settings.json` with the defaults, an empty
    /// `layouts/`, the README, and the history's first version, recorded as made by `author`.
    /// Then reads it, recording any change made on disk since the last version as "edited on
    /// disk". Copies of the built-in layouts are not written: Duplicate to Edit makes one.
    @discardableResult
    public func prepare(author: ChangeAuthor) throws(ConfigurationError) -> ConfigurationSnapshot {
        let manager = FileManager.default
        let isNew = !exists
        do {
            try manager.createDirectory(at: layoutsURL, withIntermediateDirectories: true)
            let readme = folder.appending(path: Self.readmeFileName)
            if !manager.fileExists(atPath: readme.path) {
                try Data(ConfigurationReadme.text.utf8).write(to: readme, options: .atomic)
            }
            let ignore = folder.appending(path: ".gitignore")
            if !manager.fileExists(atPath: ignore.path) {
                try Data(ConfigurationReadme.gitignore.utf8).write(to: ignore, options: .atomic)
            }
            if !manager.fileExists(atPath: settingsURL.path) {
                try ConfigurationSettings.defaults.encoded().write(to: settingsURL, options: .atomic)
            }
        } catch {
            throw ConfigurationError("Could not create the configuration folder at \(folder.path): \(error.localizedDescription)")
        }
        if isNew || !history.hasRepository {
            return reload(committingAs: author, summary: isNew ? "Created the configuration folder" : "Started keeping the configuration's history")
        }
        return reload(committingAs: .editedOnDisk)
    }

    /// Reads every file again and applies the ones that validate. With an author, any change
    /// on disk since the last version is committed, refused files left out. `ctl` reads
    /// without an author, so looking never writes history.
    @discardableResult
    public func reload(committingAs author: ChangeAuthor? = nil, summary: String? = nil) -> ConfigurationSnapshot {
        var problems: [ConfigurationProblem] = builtIn.problems.map {
            ConfigurationProblem($0, file: "built in: \($0.fileName)", lastGoodInUse: false)
        }

        // settings.json. Missing means the defaults.
        var settings = ConfigurationSettings.defaults
        if let data = try? Data(contentsOf: settingsURL) {
            do throws(LayoutFileError) {
                settings = try ConfigurationSettings.decode(data)
                lastGoodSettings = settings
            } catch {
                if lastGoodSettings == nil, let committed = committedContents(ConfigurationSettings.fileName) {
                    lastGoodSettings = try? ConfigurationSettings.decode(committed)
                }
                problems.append(ConfigurationProblem(error, file: ConfigurationSettings.fileName, lastGoodInUse: lastGoodSettings != nil))
                settings = lastGoodSettings ?? .defaults
            }
        } else {
            lastGoodSettings = nil
        }

        // shorthands.json. Missing means none.
        var shorthands = Shorthands.none
        if let data = try? Data(contentsOf: shorthandsURL) {
            do throws(LayoutFileError) {
                let file = try ShorthandsFile.decode(data)
                lastGoodShorthands = file
                shorthands = file.lookup
            } catch {
                if lastGoodShorthands == nil, let committed = committedContents(ShorthandsFile.fileName) {
                    lastGoodShorthands = try? ShorthandsFile.decode(committed)
                }
                problems.append(ConfigurationProblem(error, file: ShorthandsFile.fileName, lastGoodInUse: lastGoodShorthands != nil))
                shorthands = lastGoodShorthands?.lookup ?? .none
            }
        } else {
            lastGoodShorthands = nil
        }

        // layouts/*.json
        var fileLayouts: [String: PageLayout] = [:]
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: layoutsURL.path)) ?? [])
            .filter { $0.hasSuffix(".json") && !$0.hasPrefix(".") }
            .sorted()
        for name in names {
            let file = "\(Self.layoutsFolderName)/\(name)"
            do throws(LayoutFileError) {
                guard let data = try? Data(contentsOf: url(for: file)) else {
                    throw LayoutFileError(fileName: file, problem: "the file could not be read")
                }
                let layout = try PageLayout.decode(data, fileName: file)
                guard name == "\(layout.id).json" else {
                    throw LayoutFileError(fileName: file, path: "id",
                                          problem: "a layout's file is named after its id, so the layout with id \"\(layout.id)\" belongs in \(Self.layoutFile(id: layout.id))")
                }
                fileLayouts[file] = layout
                lastGoodLayouts[file] = layout
            } catch {
                if lastGoodLayouts[file] == nil, let committed = committedContents(file),
                   let layout = try? PageLayout.decode(committed, fileName: file), name == "\(layout.id).json" {
                    lastGoodLayouts[file] = layout
                }
                let lastGood = lastGoodLayouts[file]
                problems.append(ConfigurationProblem(error, file: file, lastGoodInUse: lastGood != nil))
                if let lastGood { fileLayouts[file] = lastGood }
            }
        }
        lastGoodLayouts = lastGoodLayouts.filter { names.contains(String($0.key.dropFirst(Self.layoutsFolderName.count + 1))) }

        // Built-ins in order, each replaced by a file with its id, then the rest by name.
        var entries: [LayoutEntry] = builtIn.layouts.map { builtInLayout in
            if let (file, layout) = fileLayouts.first(where: { $0.value.id == builtInLayout.id }) {
                return LayoutEntry(layout: layout, source: .file(file, overridesBuiltIn: true))
            }
            return LayoutEntry(layout: builtInLayout, source: .builtIn)
        }
        let builtInIDs = Set(builtIn.layouts.map(\.id))
        entries += fileLayouts.filter { !builtInIDs.contains($0.value.id) }
            .sorted { ($0.value.name.localizedLowercase, $0.key) < ($1.value.name.localizedLowercase, $1.key) }
            .map { LayoutEntry(layout: $0.value, source: .file($0.key, overridesBuiltIn: false)) }

        if !entries.contains(where: { $0.id == settings.defaultLayout }) {
            problems.append(ConfigurationProblem(
                file: ConfigurationSettings.fileName, path: "defaultLayout",
                problem: "no layout has the id \"\(settings.defaultLayout)\", so Decision first is used instead. Layouts: \(entries.map(\.id).joined(separator: ", ")).",
                refusesFile: false))
        }

        snapshot = ConfigurationSnapshot(settings: settings, layouts: entries, shorthands: shorthands, problems: problems)

        if let author, exists {
            let refused = Set(problems.filter(\.refusesFile).map(\.file))
            do throws(ConfigurationHistoryError) {
                try history.commitPending(summary: summary, author: author, excluding: refused)
                historyProblem = nil
            } catch {
                historyProblem = error.message
            }
        }
        return snapshot
    }

    /// A file as the last version recorded it, so a file that is wrong when the app starts, or
    /// when `ctl` reads it, still has a last good version to fall back on.
    private func committedContents(_ file: String) -> Data? {
        guard history.hasRepository, history.availability() == nil,
              let text = try? history.git(["show", "HEAD:\(file)"]) else { return nil }
        return Data(text.utf8)
    }

    /// Every problem, as `config validate` prints them.
    public var problems: [ConfigurationProblem] { snapshot.problems }

    // MARK: Changing

    /// Changes `settings.json`, writes it atomically, and records the change.
    ///
    /// It refuses when `settings.json` on disk has a problem, so a hand edit that is being
    /// fixed is never overwritten. Restore an earlier version, or fix the file, first.
    public func updateSettings(author: ChangeAuthor, summary: String, _ change: (inout ConfigurationSettings) -> Void) throws(ConfigurationError) {
        try prepare(author: author)
        if let problem = snapshot.problems.first(where: { $0.file == ConfigurationSettings.fileName && $0.refusesFile }) {
            throw ConfigurationError("settings.json has a problem, so it was not changed: \(problem). Fix the file, or restore an earlier version from History.")
        }
        var settings = snapshot.settings
        change(&settings)
        let data: Data
        do { data = try settings.encoded() } catch { throw ConfigurationError("Could not encode the settings: \(error)") }
        do throws(LayoutFileError) {
            _ = try ConfigurationSettings.decode(data)
        } catch {
            throw ConfigurationError(error.description)
        }
        try write(data, to: ConfigurationSettings.fileName)
        reload(committingAs: author, summary: summary)
    }

    /// The keys `set(key:value:)` takes.
    public static var settableKeys: [String] {
        ["appearance", "defaultLayout", "hidesBotEventsInActivity", "updatesAutomatically",
         "pullRequestSource", "syncIntervalSeconds", "watchedRepositories"] + Experiment.allCases.map { "experiments.\($0.key)" }
    }

    /// Sets one setting from text, as `ctl config set` does. Returns what changed, in a sentence.
    @discardableResult
    public func set(key: String, value: String, author: ChangeAuthor) throws(ConfigurationError) -> String {
        try prepare(author: author)
        let summary: String
        let change: (inout ConfigurationSettings) -> Void
        switch key {
        case "appearance":
            guard let appearance = Appearance(rawValue: value) else {
                throw ConfigurationError("appearance is one of \(Appearance.allCases.map(\.rawValue).joined(separator: ", ")), not \"\(value)\".")
            }
            summary = "Set appearance to \(appearance.title)"
            change = { $0.appearance = appearance }
        case "defaultLayout":
            guard let entry = snapshot.entry(id: value) else {
                throw ConfigurationError("No layout has the id \"\(value)\". Layouts: \(snapshot.layouts.map(\.id).joined(separator: ", ")).")
            }
            summary = "Set the default layout to \(entry.layout.name)"
            change = { $0.defaultLayout = value }
        case "hidesBotEventsInActivity":
            guard let flag = Self.bool(value) else { throw ConfigurationError("\(key) is true or false, not \"\(value)\".") }
            summary = flag ? "Bot events start hidden in Activity" : "Bot events start shown in Activity"
            change = { $0.hidesBotEventsInActivity = flag }
        case "updatesAutomatically":
            guard let flag = Self.bool(value) else { throw ConfigurationError("\(key) is true or false, not \"\(value)\".") }
            summary = flag ? "Updates install automatically" : "Updates wait to be checked for by hand"
            change = { $0.updatesAutomatically = flag }
        case "pullRequestSource":
            guard let source = PullRequestSource(rawValue: value) else {
                throw ConfigurationError("pullRequestSource is one of \(PullRequestSource.allCases.map(\.rawValue).joined(separator: ", ")), not \"\(value)\".")
            }
            summary = "Pull requests come from \(source == .mock ? "the mock data" : "GitHub")"
            change = { $0.pullRequestSource = source }
        case "syncIntervalSeconds":
            let range = ConfigurationSettings.syncIntervalRange
            guard let seconds = Int(value), range.contains(seconds) else {
                throw ConfigurationError("syncIntervalSeconds is a whole number of seconds from \(range.lowerBound) to \(range.upperBound), not \"\(value)\".")
            }
            summary = "Sync every \(seconds.isMultiple(of: 60) ? "\(seconds / 60) min" : "\(seconds) s")"
            change = { $0.syncIntervalSeconds = seconds }
        case "watchedRepositories":
            // A comma-separated list. An empty value watches none.
            let names = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            for name in names where Repository(fullName: name) == nil || !Repository.isPlainName(name) {
                throw ConfigurationError("\"\(name)\" is not a repository written as owner/name, such as acme/api. Separate several with commas.")
            }
            var unique: [String] = []
            for name in names where !unique.contains(where: { $0.lowercased() == name.lowercased() }) { unique.append(name) }
            summary = unique.isEmpty ? "Watch no repositories in full" : "Watch \(unique.joined(separator: ", ")) in full"
            change = { $0.watchedRepositories = unique }
        default:
            if key.hasPrefix("experiments."), let experiment = Experiment(key: String(key.dropFirst("experiments.".count))) {
                guard let flag = Self.bool(value) else { throw ConfigurationError("\(key) is true or false, not \"\(value)\".") }
                summary = "Turned \(flag ? "on" : "off") the experiment \(experiment.title)"
                change = { $0.set(experiment, on: flag) }
            } else {
                throw ConfigurationError("There is no setting \"\(key)\". Settings: \(Self.settableKeys.joined(separator: ", ")).")
            }
        }
        try updateSettings(author: author, summary: summary, change)
        return summary
    }

    private static func bool(_ text: String) -> Bool? {
        switch text.lowercased() {
        case "true", "yes", "on", "1": true
        case "false", "no", "off", "0": false
        default: nil
        }
    }

    // MARK: Shorthands

    /// Sets the shorthand for one repository or person, replacing the one it had, and writes
    /// `shorthands.json`. A shorthand another thing already has is allowed: Settings and
    /// `shorthands list` warn about it. Returns what changed, in a sentence.
    ///
    /// It refuses when `shorthands.json` on disk has a problem, so a hand edit that is being
    /// fixed is never overwritten.
    @discardableResult
    public func setShorthand(_ kind: ShorthandKind, for target: String, to shorthand: String, author: ChangeAuthor) throws(ConfigurationError) -> String {
        let identity = kind.normalizedIdentity(target)
        guard kind.isValidIdentity(identity) else {
            throw ConfigurationError("\"\(target)\" is not \(kind.identityDescription).")
        }
        let text = shorthand.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else {
            throw ConfigurationError("The shorthand for \(identity) is empty. To take it away, remove it instead.")
        }
        let entry = Shorthand(kind: kind, target: identity, shorthand: text)
        var summary = "Set the shorthand for \(identity) to \(text)"
        try updateShorthands(author: author) { file in
            if let position = file.shorthands.firstIndex(where: { $0.id == entry.id }) {
                // The identity keeps the spelling it was first written with.
                let target = file.shorthands[position].target
                summary = file.shorthands[position].shorthand == text
                    ? "\(target) already has the shorthand \(text)" : "Set the shorthand for \(target) to \(text)"
                file.shorthands[position].shorthand = text
            } else {
                file.shorthands.append(entry)
            }
            return summary
        }
        return summary
    }

    /// Takes away the shorthand for one repository or person, so its full name shows again.
    @discardableResult
    public func removeShorthand(_ kind: ShorthandKind, for target: String, author: ChangeAuthor) throws(ConfigurationError) -> String {
        let identity = kind.normalizedIdentity(target)
        var summary = ""
        try updateShorthands(author: author) { file throws(ConfigurationError) in
            guard let found = file.shorthands.first(where: { $0.id == Shorthand.key(kind, identity) }) else {
                throw ConfigurationError("\(identity) has no shorthand.")
            }
            file.shorthands.removeAll { $0.id == found.id }
            summary = "Removed the shorthand \(found.shorthand) for \(found.target)"
            return summary
        }
        return summary
    }

    private func updateShorthands(author: ChangeAuthor, _ change: (inout ShorthandsFile) throws(ConfigurationError) -> String) throws(ConfigurationError) {
        try prepare(author: author)
        if let problem = snapshot.problems.first(where: { $0.file == ShorthandsFile.fileName && $0.refusesFile }) {
            throw ConfigurationError("shorthands.json has a problem, so it was not changed: \(problem). Fix the file, or restore an earlier version from History.")
        }
        var file = (try? Data(contentsOf: shorthandsURL)).flatMap { try? ShorthandsFile.decode($0) } ?? ShorthandsFile()
        let summary = try change(&file)
        let data: Data
        do { data = try file.encoded() } catch { throw ConfigurationError("Could not encode the shorthands: \(error)") }
        do throws(LayoutFileError) {
            _ = try ShorthandsFile.decode(data)
        } catch {
            throw ConfigurationError(error.description)
        }
        try write(data, to: ShorthandsFile.fileName)
        reload(committingAs: author, summary: summary)
    }

    /// Writes a copy of a layout to `layouts/<newID>.json`, for editing. The copy is named after
    /// the original with " copy", unless a name is given.
    @discardableResult
    public func duplicateLayout(id: String, as newID: String? = nil, name: String? = nil, author: ChangeAuthor) throws(ConfigurationError) -> LayoutEntry {
        try prepare(author: author)
        guard let original = snapshot.entry(id: id) else {
            throw ConfigurationError("No layout has the id \"\(id)\". Layouts: \(snapshot.layouts.map(\.id).joined(separator: ", ")).")
        }
        let chosen = newID ?? freeID(for: "\(id)-copy")
        guard PageLayout.isValidID(chosen) else {
            throw ConfigurationError("\"\(chosen)\" cannot be a layout id. Use lowercase letters, digits and hyphens, such as \"my-layout\".")
        }
        let file = Self.layoutFile(id: chosen)
        if snapshot.layouts.contains(where: { $0.id == chosen }) || FileManager.default.fileExists(atPath: url(for: file).path) {
            throw ConfigurationError("A layout with the id \"\(chosen)\" already exists. Pick another id.")
        }
        var copy = original.layout
        copy.id = chosen
        copy.name = name ?? "\(original.layout.name) copy"
        let data: Data
        do { data = try copy.encoded() + Data([0x0A]) } catch { throw ConfigurationError("Could not encode the layout: \(error)") }
        try write(data, to: file)
        reload(committingAs: author, summary: "Duplicated \(original.layout.name) to \(file)")
        return snapshot.entry(id: chosen) ?? LayoutEntry(layout: copy, source: .file(file, overridesBuiltIn: false))
    }

    private func freeID(for base: String) -> String {
        var candidate = base
        var number = 2
        while snapshot.layouts.contains(where: { $0.id == candidate })
            || FileManager.default.fileExists(atPath: url(for: Self.layoutFile(id: candidate)).path) {
            candidate = "\(base)-\(number)"
            number += 1
        }
        return candidate
    }

    /// Deletes one of the person's layout files. A built-in layout cannot be deleted. The file
    /// stays in History and can be restored.
    public func deleteLayout(file: String, author: ChangeAuthor) throws(ConfigurationError) {
        guard file.hasPrefix(Self.layoutsFolderName + "/"), file.hasSuffix(".json"), !file.contains("..") else {
            throw ConfigurationError("\(file) is not a layout file.")
        }
        let name = snapshot.layouts.first { $0.source.file == file }?.layout.name
        do {
            try FileManager.default.removeItem(at: url(for: file))
        } catch {
            throw ConfigurationError("Could not delete \(file): \(error.localizedDescription)")
        }
        reload(committingAs: author, summary: "Deleted \(name.map { "the layout \($0), " } ?? "")\(file)")
    }

    // MARK: History

    /// The versions, newest first.
    public func versions(limit: Int? = nil) throws(ConfigurationError) -> [ConfigurationVersion] {
        do { return try history.versions(limit: limit) } catch { throw ConfigurationError(error.message) }
    }

    /// What a version changed, as a unified diff.
    public func diff(_ version: String) throws(ConfigurationError) -> String {
        do { return try history.diff(version) } catch { throw ConfigurationError(error.message) }
    }

    /// Brings back the whole folder, or one file, as it was in a version. The restore is itself
    /// a new version, so the versions after it are kept and can be brought back too.
    @discardableResult
    public func restore(_ version: String, file: String? = nil, author: ChangeAuthor) throws(ConfigurationError) -> ConfigurationVersion? {
        // Anything changed on disk and not recorded yet is recorded first, so the restore
        // cannot lose it.
        try prepare(author: author)
        let target: ConfigurationVersion
        do throws(ConfigurationHistoryError) {
            let id = try history.resolve(version)
            guard let found = try history.versions().first(where: { $0.id == id }) else {
                throw ConfigurationHistoryError("There is no version \(version) in the history.")
            }
            target = found
            try history.restoreFiles(to: id, file: file)
        } catch {
            throw ConfigurationError(error.message)
        }
        let what = file ?? "the configuration"
        let before = try versions(limit: 1).first?.id
        reload(committingAs: author, summary: "Restored \(what) to version \(target.shortID)")
        if let historyProblem { throw ConfigurationError("The files were restored, but the restore was not recorded: \(historyProblem)") }
        let latest = try versions(limit: 1).first
        return latest?.id == before ? nil : latest
    }

    // MARK: Writing

    /// Writes a file atomically: to a temporary file beside it, then renamed over it, so a
    /// reader never sees half a file.
    private func write(_ data: Data, to file: String) throws(ConfigurationError) {
        let target = url(for: file)
        do {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target, options: .atomic)
        } catch {
            throw ConfigurationError("Could not write \(file): \(error.localizedDescription)")
        }
    }
}

extension LayoutLibrary {
    /// A library of layouts already read, such as the configuration folder's.
    public init(layouts: [PageLayout], problems: [LayoutFileError]) {
        var layouts = layouts
        if !layouts.contains(where: { $0.id == Self.fallbackID }) {
            layouts.insert(.decisionFirst, at: 0)
        }
        self.layouts = layouts
        self.problems = problems
    }
}
