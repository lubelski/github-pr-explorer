import Foundation

/// What the sync knows about one pull request besides the pull request itself: what it saw in
/// the last list pass, and when each tier was last fetched.
public struct PullRequestSyncRecord: Codable, Sendable, Hashable {
    /// `updatedAt` and the head commit as the list pass last saw them.
    public var listUpdatedAt: Date
    public var listHeadCommitID: String
    /// When the detail tier was fetched, and the `updatedAt` it was fetched for.
    public var detailFetchedAt: Date?
    public var detailForUpdatedAt: Date?
    /// When the computed fields (checks, mergeability, review decision) were fetched.
    public var computedFetchedAt: Date?
    /// The files' ETag, for a conditional request, and the head commit they were fetched for.
    public var filesETag: String?
    public var filesFetchedAt: Date?
    public var filesForHeadCommitID: String?

    public init(listUpdatedAt: Date, listHeadCommitID: String) {
        self.listUpdatedAt = listUpdatedAt
        self.listHeadCommitID = listHeadCommitID
    }
}

/// A repository's CODEOWNERS rules as last read, so they are not read on every run.
public struct CodeOwnersRecord: Codable, Sendable, Hashable {
    public var rules: [CodeOwnerRule]
    public var fetchedAt: Date
}

/// The synced index as it is saved on disk. It is a cache: deleting it is always safe, and
/// the next sync builds it again.
public struct GitHubIndexSnapshot: Codable, Sendable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var savedAt: Date
    public var viewer: Viewer?
    public var viewerFetchedAt: Date?
    /// Most recently updated first.
    public var pullRequests: [PullRequest]
    /// By pull request id.
    public var records: [String: PullRequestSyncRecord]
    /// By repository, as `owner/name`.
    public var codeOwners: [String: CodeOwnersRecord]
    public var status: GitHubSyncStatus

    public init(formatVersion: Int = currentFormatVersion, savedAt: Date, viewer: Viewer? = nil, viewerFetchedAt: Date? = nil,
                pullRequests: [PullRequest] = [], records: [String: PullRequestSyncRecord] = [:],
                codeOwners: [String: CodeOwnersRecord] = [:], status: GitHubSyncStatus = GitHubSyncStatus()) {
        self.formatVersion = formatVersion
        self.savedAt = savedAt
        self.viewer = viewer
        self.viewerFetchedAt = viewerFetchedAt
        self.pullRequests = pullRequests
        self.records = records
        self.codeOwners = codeOwners
        self.status = status
    }

    /// Who the index is seen by before GitHub has said who is signed in.
    public static let unknownViewer = Viewer(person: Person(login: "", displayName: "Not signed in"), teams: [])

    public var index: InMemoryPullRequestIndex {
        InMemoryPullRequestIndex(pullRequests: pullRequests, viewer: viewer ?? Self.unknownViewer)
    }
}

/// Where the synced index is kept. A database can take the place of the JSON file later
/// without the sync or the views changing.
public protocol GitHubIndexStorage: Sendable {
    /// Where it is, for Settings, diagnostics and `ctl`.
    var location: URL { get }
    /// Nil when nothing has been saved yet. Throws when a file is there but cannot be read.
    func load() throws -> GitHubIndexSnapshot?
    func save(_ snapshot: GitHubIndexSnapshot) throws
}

/// The synced index as one JSON file, `github.json`, in
/// `~/Library/Application Support/github-pr-explorer/index/`. That folder is next to the
/// configuration folder and never inside it: the configuration folder is a git repository
/// and must never hold fetched data. Tests pass a temporary folder.
public struct JSONFileIndexStorage: GitHubIndexStorage {
    public static let fileName = "github.json"

    /// `~/Library/Application Support/github-pr-explorer/index`. Only the app and `ctl` use it.
    public static var defaultFolder: URL {
        URL.applicationSupportDirectory.appending(path: "github-pr-explorer/index", directoryHint: .isDirectory)
    }

    public let folder: URL

    public init(folder: URL = Self.defaultFolder) {
        self.folder = folder
    }

    public var location: URL { folder.appending(path: Self.fileName) }

    public func load() throws -> GitHubIndexSnapshot? {
        guard FileManager.default.fileExists(atPath: location.path) else { return nil }
        let data = try Data(contentsOf: location)
        let snapshot = try GitHubPRExplorerJSON.decoder().decode(GitHubIndexSnapshot.self, from: data)
        guard snapshot.formatVersion == GitHubIndexSnapshot.currentFormatVersion else { return nil }
        return snapshot
    }

    public func save(_ snapshot: GitHubIndexSnapshot) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: location, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: location.path)
    }
}

/// Keeps the snapshot in memory, for tests and renders.
public final class InMemoryIndexStorage: GitHubIndexStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: GitHubIndexSnapshot?
    public private(set) var saveCount = 0

    public init(_ snapshot: GitHubIndexSnapshot? = nil) { stored = snapshot }

    public var location: URL { URL(filePath: "/dev/null") }

    public func load() throws -> GitHubIndexSnapshot? {
        lock.withLock { stored }
    }

    public func save(_ snapshot: GitHubIndexSnapshot) throws {
        lock.withLock {
            stored = snapshot
            saveCount += 1
        }
    }
}
