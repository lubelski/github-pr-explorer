import Foundation
@testable import GitHubPRExplorerCore

/// A GitHub that answers from the hand-written fixtures in `Fixtures/GitHub`, in GitHub's own
/// response shapes, with placeholder people and repositories. It never touches the network.
///
/// GraphQL requests are told apart by what their query asks for. REST answers carry an ETag
/// and answer 304 when it is sent back. Every answer carries rate limit headers.
final class FakeGitHub: GitHubTransport, @unchecked Sendable {
    static let token = "gho_FAKE0TOKEN0FOR0TESTS0ONLY0000000000"
    static let folder = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/GitHub")
    static let now = MockWorld.date("2026-11-25T18:00:00Z")

    static func fixture(_ name: String) -> Data {
        (try? Data(contentsOf: folder.appending(path: name))) ?? Data()
    }

    enum Kind: String, CaseIterable {
        case viewer, teams, search, repository, detail, computed, codeOwners, files, unknown
    }

    struct Sent {
        var kind: Kind
        var body: String
        var path: String
        var authorization: String?
        var ifNoneMatch: String?
        var status: Int
    }

    private let lock = NSLock()
    private var _sent: [Sent] = []
    var sent: [Sent] { lock.withLock { _sent } }
    func count(_ kind: Kind) -> Int { sent.count { $0.kind == kind } }

    /// Answers to use instead of the fixture, by kind.
    var overrides: [Kind: @Sendable (Sent) -> (Int, Data, [String: String])] = [:]
    /// Throw this for every request, as when offline.
    var failure: (any Error)?
    /// Rate limit headers on every answer.
    var remaining = 4900
    var limit = 5000
    var resetAt = MockWorld.date("2026-11-25T19:00:00Z")
    /// Replace text in the search fixture, to make a pull request look changed.
    var searchEdits: [(String, String)] = []
    var watchedRepositoryFixture = "repository-docs.json"

    func clearSent() { lock.withLock { _sent = [] } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let body = request.httpBody.map { String(decoding: $0, as: UTF8.self) } ?? ""
        let path = request.url?.path() ?? ""
        let query = request.url?.query() ?? ""
        let kind: Kind
        if path.hasSuffix("/files") { kind = .files }
        else if body.contains("CODEOWNERS") { kind = .codeOwners }
        else if body.contains("organizations") { kind = .teams }
        else if body.contains("viewer { login name }") { kind = .viewer }
        else if body.contains("search(") { kind = .search }
        else if body.contains("pullRequests(states") { kind = .repository }
        else if body.contains("nodes(ids:") { kind = .detail }
        else if body.contains("pr0: node") { kind = .computed }
        else { kind = .unknown }
        var sent = Sent(kind: kind, body: body, path: path + (query.isEmpty ? "" : "?" + query),
                        authorization: request.value(forHTTPHeaderField: "Authorization"),
                        ifNoneMatch: request.value(forHTTPHeaderField: "If-None-Match"), status: 200)
        if let failure {
            lock.withLock { _sent.append(sent) }
            throw failure
        }

        var status = 200
        var data: Data
        var headers: [String: String] = [:]
        if let override = overrides[kind] {
            (status, data, headers) = override(sent)
        } else {
            switch kind {
            case .viewer: data = Self.fixture("viewer.json")
            case .teams: data = Self.fixture("viewer-teams.json")
            case .search:
                if body.contains("involves:@me") || body.contains("review-requested:@me") {
                    var text = String(decoding: Self.fixture("search-involves.json"), as: UTF8.self)
                    for (old, new) in searchEdits { text = text.replacingOccurrences(of: old, with: new) }
                    data = Data(text.utf8)
                } else {
                    data = Self.fixture("search-empty.json")
                }
            case .repository: data = Self.fixture(watchedRepositoryFixture)
            case .detail: data = Self.fixture("detail.json")
            case .computed: data = Self.fixture("computed.json")
            case .codeOwners: data = Self.fixture("codeowners.json")
            case .files:
                let name = path.contains("/acme/api/") ? "files-api-101.json" : "files-web-55.json"
                let etag = "\"etag-\(name)\""
                if sent.ifNoneMatch == etag {
                    status = 304
                    data = Data()
                } else {
                    data = Self.fixture(name)
                }
                headers["ETag"] = etag
            case .unknown: (status, data) = (400, Data(#"{"message":"unknown request"}"#.utf8))
            }
        }
        let resource = kind == .files ? "core" : "graphql"
        var all = ["x-ratelimit-limit": "\(limit)", "x-ratelimit-remaining": "\(remaining)",
                   "x-ratelimit-reset": "\(Int(resetAt.timeIntervalSince1970))", "x-ratelimit-resource": resource]
        all.merge(headers) { _, new in new }
        sent.status = status
        lock.withLock { _sent.append(sent) }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: all)!
        return (data, response)
    }
}

/// A clock tests move by hand.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ date: Date = FakeGitHub.now) { current = date }
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}

/// Every update the sync published, for tests to read.
final class UpdateLog: @unchecked Sendable {
    private let lock = NSLock()
    private var updates: [GitHubSync.Update] = []
    func append(_ update: GitHubSync.Update) { lock.withLock { updates.append(update) } }
    var all: [GitHubSync.Update] { lock.withLock { updates } }
    var last: GitHubSync.Update? { all.last }
}
