import Foundation

/// Why a GitHub token could not be had. None of these ever holds the token.
public enum GitHubAccessError: Error, Sendable, Hashable, CustomStringConvertible {
    /// No `gh` program was found where it is usually installed.
    case ghMissing
    /// `gh` is there but has no login for github.com.
    case signedOut
    /// `gh` ran and failed for another reason. The text is `gh`'s own message, with anything
    /// that looks like a token taken out.
    case failed(String)

    public var description: String {
        switch self {
        case .ghMissing: "The GitHub command line tool, gh, was not found in /opt/homebrew/bin, /usr/local/bin or the PATH."
        case .signedOut: "gh is not signed in to github.com. Run `gh auth login` in Terminal."
        case .failed(let message): "gh could not give a token: \(message)"
        }
    }
}

/// Hands out a GitHub token when one is needed. The sync asks each time it starts a run and
/// keeps the token in memory only for that run. A token is never stored, logged, written to a
/// file, or put in an error message.
public protocol GitHubTokenProvider: Sendable {
    /// Where the token comes from, for Settings and diagnostics. Never the token.
    var sourceDescription: String { get }
    func token() async throws(GitHubAccessError) -> String
}

/// Finds the `gh` program. A GUI app does not inherit the shell's PATH, so the usual Homebrew
/// places are tried first, then whatever PATH the process has.
public enum GitHubCLILocator {
    public static let standardFolders = ["/opt/homebrew/bin", "/usr/local/bin"]

    public static func find(environment: [String: String] = ProcessInfo.processInfo.environment,
                            isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> URL? {
        let pathFolders = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        var seen: Set<String> = []
        for folder in standardFolders + pathFolders where !folder.isEmpty && seen.insert(folder).inserted {
            let candidate = (folder as NSString).appendingPathComponent("gh")
            if isExecutable(candidate) { return URL(filePath: candidate) }
        }
        return nil
    }
}

/// Gets the token from the `gh` login on this Mac by running `gh auth token`.
public struct GitHubCLITokenProvider: GitHubTokenProvider {
    /// The `gh` to run. Nil looks for it each time, so installing it later is noticed.
    public let executable: URL?

    public init(executable: URL? = nil) {
        self.executable = executable
    }

    private var found: URL? { executable ?? GitHubCLILocator.find() }

    public var sourceDescription: String {
        found.map { "gh login (\($0.path))" } ?? "gh login (gh not found)"
    }

    public func token() async throws(GitHubAccessError) -> String {
        guard let executable = found else { throw .ghMissing }
        let result: (status: Int32, output: String, error: String)
        do {
            result = try await Self.run(executable, arguments: ["auth", "token", "--hostname", "github.com"])
        } catch {
            throw .failed("could not start \(executable.lastPathComponent): \(error.localizedDescription)")
        }
        let token = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.status == 0, !token.isEmpty, !token.contains(where: \.isWhitespace) {
            return token
        }
        let message = Self.redacted(result.error.trimmingCharacters(in: .whitespacesAndNewlines))
        if result.status != 0, message.lowercased().contains("not logged in") || message.lowercased().contains("no oauth token") || message.isEmpty {
            throw .signedOut
        }
        throw .failed(message.isEmpty ? "gh exited with status \(result.status)" : message)
    }

    /// Takes out anything shaped like a GitHub token, in case `gh` ever echoes one.
    static func redacted(_ text: String) -> String {
        text.replacing(/(gh[opusr]_|github_pat_)[A-Za-z0-9_]+/, with: "[token removed]")
    }

    private static func run(_ executable: URL, arguments: [String]) async throws -> (status: Int32, output: String, error: String) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        // gh reads its config from HOME, and must not prompt or open a pager.
        environment["GH_PROMPT_DISABLED"] = "1"
        environment["GH_NO_UPDATE_NOTIFIER"] = "1"
        environment["NO_COLOR"] = "1"
        process.environment = environment
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        process.standardInput = FileHandle.nullDevice
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { finished in
                let out = output.fileHandleForReading.readDataToEndOfFile()
                let err = error.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: (finished.terminationStatus, String(decoding: out, as: UTF8.self), String(decoding: err, as: UTF8.self)))
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }
}

/// A token given up front, for tests.
public struct FixedTokenProvider: GitHubTokenProvider {
    public var result: Result<String, GitHubAccessError>
    public init(_ result: Result<String, GitHubAccessError>) { self.result = result }
    public var sourceDescription: String { "fixed token for tests" }
    public func token() async throws(GitHubAccessError) -> String { try result.get() }
}
