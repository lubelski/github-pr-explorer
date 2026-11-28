import Foundation

/// Who made a change to the configuration. It is written into each version's commit message
/// as a `Changed-By:` line, and History shows it.
public enum ChangeAuthor: String, Sendable, Hashable, CaseIterable {
    /// The app's Settings window.
    case settingsWindow = "Settings window"
    /// The main window, such as Set Shorthand on a row of the pull request list, or saving a filter from the Filter popover or a tab's menu.
    case mainWindow = "main window"
    /// A person, an editor, or an agent changed a file, and the app or `ctl` noticed it.
    case editedOnDisk = "edited on disk"
    /// `github-pr-explorer-ctl`.
    case commandLine = "ctl"
    /// An agent, through `github-pr-explorer-ctl mcp`.
    case mcp = "MCP"
    /// The app itself, such as creating the folder on first run.
    case app = "app"
}

/// One version of the configuration folder: one commit in its git repository.
public struct ConfigurationVersion: Sendable, Hashable, Identifiable, Codable {
    /// The full commit id.
    public var id: String
    public var date: Date
    /// What changed, in a sentence, such as "Set the default layout to Tabbed".
    public var summary: String
    /// Who made the change, as `ChangeAuthor` words it. Empty for a commit made some other way.
    public var author: String
    /// The files the version touched, relative to the folder.
    public var files: [String]

    public var shortID: String { String(id.prefix(7)) }

    public init(id: String, date: Date, summary: String, author: String, files: [String]) {
        self.id = id
        self.date = date
        self.summary = summary
        self.author = author
        self.files = files
    }
}

/// Why a history operation did not work. History never stops a save: the store reports this
/// and carries on.
public struct ConfigurationHistoryError: Error, Sendable, Hashable, CustomStringConvertible {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

/// The configuration folder's history, kept as a local git repository in the folder itself.
///
/// Every command runs `/usr/bin/git` as a subprocess, with its own identity and with the
/// user's global and system git configuration switched off, so history never depends on or
/// changes how the person has set git up. Nothing here uses the network: the repository has
/// no remote.
public final class ConfigurationHistory {
    public static let defaultGitPath = "/usr/bin/git"
    /// The name and email on every version. They are placeholders, not a person.
    public static let identityName = "github-pr-explorer"
    public static let identityEmail = "github-pr-explorer@localhost"
    static let authorTrailer = "Changed-By"

    public let folder: URL
    public let gitPath: String
    /// When set, every new version is dated by this instead of the clock. Renders and tests use
    /// it so their history reads the same on every run.
    public var commitDate: (() -> Date)?

    public init(folder: URL, gitPath: String = defaultGitPath, commitDate: (() -> Date)? = nil) {
        self.folder = folder
        self.gitPath = gitPath
        self.commitDate = commitDate
    }

    /// Whether git can be run here. On macOS `/usr/bin/git` is a stub that offers to install
    /// the developer tools when they are missing, which would put a dialog in front of the
    /// person. So when the stub is used, the tools are looked for first, and history is
    /// reported as unavailable instead of running it.
    public func availability() -> ConfigurationHistoryError? {
        if let checkedAvailability { return checkedAvailability }
        let found = findAvailability()
        checkedAvailability = .some(found)
        return found
    }

    /// Checked once: whether git is there does not change while the app runs.
    private var checkedAvailability: ConfigurationHistoryError??

    private func findAvailability() -> ConfigurationHistoryError? {
        guard FileManager.default.isExecutableFile(atPath: gitPath) else {
            return ConfigurationHistoryError("git was not found at \(gitPath), so changes are not being kept as versions.")
        }
        if gitPath == Self.defaultGitPath {
            let developerDirectory = ProcessInfo.processInfo.environment["DEVELOPER_DIR"]
                ?? (try? Self.run("/usr/bin/xcode-select", ["-p"], in: folder, environment: [:]))?.output
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let developerDirectory, !developerDirectory.isEmpty,
                  FileManager.default.isExecutableFile(atPath: developerDirectory + "/usr/bin/git")
            else {
                return ConfigurationHistoryError("git needs the Command Line Developer Tools, which are not installed, so changes are not being kept as versions. Install them with `xcode-select --install`.")
            }
        }
        return nil
    }

    public var hasRepository: Bool {
        FileManager.default.fileExists(atPath: folder.appending(path: ".git").path)
    }

    /// Makes the folder a git repository if it is not one yet.
    public func ensureRepository() throws(ConfigurationHistoryError) {
        if let problem = availability() { throw problem }
        if hasRepository { return }
        try git(["init", "--quiet", "--initial-branch=main"])
    }

    // MARK: Recording

    /// Commits every change in the folder except the files in `excluding`, which are the files
    /// that did not validate. Returns the new version, or nil when nothing had changed.
    ///
    /// - Parameter summary: What changed. When nil, it is worked out from the files: "Changed
    ///   settings.json", "Added layouts/mine.json".
    @discardableResult
    public func commitPending(summary: String?, author: ChangeAuthor, excluding: Set<String> = []) throws(ConfigurationHistoryError) -> ConfigurationVersion? {
        try ensureRepository()
        let changes = try pendingChanges().filter { !excluding.contains($0.path) }
        guard !changes.isEmpty else { return nil }
        try git(["add", "--all", "--"] + changes.map(\.path))
        let message = summary ?? Self.describe(changes)
        try git(["commit", "--quiet", "--no-verify", "-m", message, "-m", "\(Self.authorTrailer): \(author.rawValue)"],
                dated: true)
        return try versions(limit: 1).first
    }

    struct Change: Hashable {
        enum Kind { case added, changed, removed }
        var path: String
        var kind: Kind
    }

    /// Changed, added and removed files in the folder, against the last version.
    func pendingChanges() throws(ConfigurationHistoryError) -> [Change] {
        let output = try git(["status", "--porcelain=v1", "-z", "--untracked-files=all"])
        var changes: [Change] = []
        var fields = output.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)[...]
        while let entry = fields.popFirst() {
            guard entry.count > 3 else { continue }
            let code = entry.prefix(2)
            let path = String(entry.dropFirst(3))
            // A rename or copy is followed by the old path.
            if code.contains("R") || code.contains("C") { _ = fields.popFirst() }
            let kind: Change.Kind = code == "??" || code.contains("A") ? .added : code.contains("D") ? .removed : .changed
            changes.append(Change(path: path, kind: kind))
        }
        return changes
    }

    static func describe(_ changes: [Change]) -> String {
        func list(_ paths: [String]) -> String {
            switch paths.count {
            case 0: ""
            case 1: paths[0]
            case 2: "\(paths[0]) and \(paths[1])"
            default: "\(paths.dropLast().joined(separator: ", ")) and \(paths.last!)"
            }
        }
        var parts: [String] = []
        let changed = changes.filter { $0.kind == .changed }.map(\.path).sorted()
        let added = changes.filter { $0.kind == .added }.map(\.path).sorted()
        let removed = changes.filter { $0.kind == .removed }.map(\.path).sorted()
        if !changed.isEmpty { parts.append("Changed " + list(changed)) }
        if !added.isEmpty { parts.append((parts.isEmpty ? "Added " : "added ") + list(added)) }
        if !removed.isEmpty { parts.append((parts.isEmpty ? "Removed " : "removed ") + list(removed)) }
        return parts.joined(separator: ", ")
    }

    // MARK: Reading

    /// The versions, newest first. Empty when there are none yet.
    public func versions(limit: Int? = nil) throws(ConfigurationHistoryError) -> [ConfigurationVersion] {
        guard hasRepository else { return [] }
        guard (try? git(["rev-parse", "--verify", "--quiet", "HEAD"])) != nil else { return [] }
        var arguments = ["log", "--no-color", "--name-only",
                         "--format=%x1e%H%x1f%ct%x1f%s%x1f%(trailers:key=\(Self.authorTrailer),valueonly,separator=%x2C)%x1f"]
        if let limit { arguments.append("--max-count=\(max(1, limit))") }
        let output = try git(arguments)
        return output.split(separator: "\u{1e}").compactMap { record in
            let fields = record.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 5, let seconds = TimeInterval(fields[1]) else { return nil }
            let files = fields[4].split(separator: "\n").map(String.init).filter { !$0.isEmpty }
            return ConfigurationVersion(id: fields[0], date: Date(timeIntervalSince1970: seconds), summary: fields[2],
                                        author: fields[3].trimmingCharacters(in: .whitespacesAndNewlines), files: files)
        }
    }

    /// The full commit id for a version written in full, shortened, or as `HEAD~2`.
    public func resolve(_ version: String) throws(ConfigurationHistoryError) -> String {
        guard !version.hasPrefix("-"),
              let id = try? git(["rev-parse", "--verify", "--quiet", "\(version)^{commit}"]).trimmingCharacters(in: .whitespacesAndNewlines),
              !id.isEmpty
        else { throw ConfigurationHistoryError("There is no version \(version) in the history.") }
        return id
    }

    /// What a version changed, as a unified diff against the version before it.
    public func diff(_ version: String) throws(ConfigurationHistoryError) -> String {
        let id = try resolve(version)
        return try git(["show", "--no-color", "--no-ext-diff", "--format=", "--patch", id, "--"])
    }

    /// Whether a file exists in a version.
    func contains(_ file: String, in id: String) -> Bool {
        (try? git(["cat-file", "-e", "\(id):\(file)"])) != nil
    }

    // MARK: Restoring

    /// Puts the folder, or one file, back as it was in a version. It only changes the files: the
    /// store then checks them and records the restore as a new version, so nothing is lost.
    /// Files added since that version are removed, as they were not there then.
    public func restoreFiles(to version: String, file: String? = nil) throws(ConfigurationHistoryError) {
        let id = try resolve(version)
        if let file {
            if contains(file, in: id) {
                try git(["restore", "--source=\(id)", "--worktree", "--", file])
            } else {
                // The file did not exist then, so bringing that version back removes it.
                try? FileManager.default.removeItem(at: folder.appending(path: file))
            }
        } else {
            try git(["restore", "--source=\(id)", "--worktree", "--", "."])
        }
    }

    // MARK: Running git

    @discardableResult
    func git(_ arguments: [String], dated: Bool = false) throws(ConfigurationHistoryError) -> String {
        // Switch off everything that could come from the person's own git setup.
        let isolation = [
            "-c", "user.name=\(Self.identityName)", "-c", "user.email=\(Self.identityEmail)",
            "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", "-c", "core.excludesFile=/dev/null",
            "-c", "core.attributesFile=/dev/null", "-c", "core.autocrlf=false", "-c", "core.quotePath=false",
            "-c", "core.fsmonitor=false", "-c", "init.defaultBranch=main", "-c", "log.showSignature=false",
        ]
        var environment = [
            "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_TERMINAL_PROMPT": "0",
            "GIT_AUTHOR_NAME": Self.identityName, "GIT_AUTHOR_EMAIL": Self.identityEmail,
            "GIT_COMMITTER_NAME": Self.identityName, "GIT_COMMITTER_EMAIL": Self.identityEmail,
            "GIT_OPTIONAL_LOCKS": "0", "LC_ALL": "C",
        ]
        if dated, let commitDate {
            let stamp = "@\(Int(commitDate().timeIntervalSince1970)) +0000"
            environment["GIT_AUTHOR_DATE"] = stamp
            environment["GIT_COMMITTER_DATE"] = stamp
        }
        // A second process, such as `ctl` while the app is open, may hold the index for a moment.
        var attempt = 0
        while true {
            let result: (output: String, error: String, status: Int32)
            do {
                result = try Self.run(gitPath, isolation + ["-C", folder.path] + arguments, in: folder, environment: environment)
            } catch {
                throw ConfigurationHistoryError("Could not run git: \(error.localizedDescription)")
            }
            if result.status == 0 { return result.output }
            if result.error.contains("index.lock"), attempt < 10 {
                attempt += 1
                Thread.sleep(forTimeInterval: 0.1)
                continue
            }
            let message = result.error.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ConfigurationHistoryError("git \(arguments.first ?? "") failed: \(message.isEmpty ? "exit status \(result.status)" : message)")
        }
    }

    static func run(_ path: String, _ arguments: [String], in folder: URL, environment: [String: String]) throws -> (output: String, error: String, status: Int32) {
        let process = Process()
        process.executableURL = URL(filePath: path)
        process.arguments = arguments
        var merged = environment
        // Only what git and its macOS stub need from the outside: where the tools are.
        let outside = ProcessInfo.processInfo.environment
        merged["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        for key in ["DEVELOPER_DIR", "TMPDIR", "HOME"] { if let value = outside[key] { merged[key] = value } }
        process.environment = merged
        if FileManager.default.fileExists(atPath: folder.path) { process.currentDirectoryURL = folder }
        // Errors go to a temporary file and the output to a pipe read here, so a large diff
        // cannot fill a pipe and stall git, and nothing waits on another thread.
        let errorFile = FileManager.default.temporaryDirectory.appending(path: "github-pr-explorer-git-\(UUID().uuidString).txt")
        FileManager.default.createFile(atPath: errorFile.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: errorFile) }
        let errorHandle = try FileHandle(forWritingTo: errorFile)
        defer { try? errorHandle.close() }
        let output = Pipe()
        process.standardOutput = output
        process.standardError = errorHandle
        process.standardInput = FileHandle.nullDevice
        // `waitUntilExit` runs the current run loop while it waits, which lets AppKit handle
        // events and draw in the middle of whatever called this, such as a view's body. A
        // semaphore waits without doing that.
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        try process.run()
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        exited.wait()
        let errorData = (try? Data(contentsOf: errorFile)) ?? Data()
        return (String(decoding: outputData, as: UTF8.self), String(decoding: errorData, as: UTF8.self), process.terminationStatus)
    }
}
