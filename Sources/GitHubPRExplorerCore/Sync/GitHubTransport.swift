import Foundation

/// Sends one HTTP request. The real one is URLSession. Tests give one that answers from
/// hand-written fixtures and never touches the network.
public protocol GitHubTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// URLSession with an ephemeral configuration: no disk cache, no cookies, so nothing fetched
/// from GitHub is written anywhere by the networking layer. Conditional requests are made by
/// the sync itself, with the ETags it keeps in the index.
public struct URLSessionGitHubTransport: GitHubTransport {
    private let session: URLSession

    public init(timeout: TimeInterval = 30) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = timeout
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

/// One rate limit as GitHub last reported it, from the `x-ratelimit-*` headers.
public struct RateLimitReading: Codable, Sendable, Hashable {
    /// `core` for REST, `graphql` for GraphQL.
    public var resource: String
    public var limit: Int
    public var remaining: Int
    public var resetAt: Date
    public var readAt: Date

    public init(resource: String, limit: Int, remaining: Int, resetAt: Date, readAt: Date) {
        self.resource = resource
        self.limit = limit
        self.remaining = remaining
        self.resetAt = resetAt
        self.readAt = readAt
    }

    /// Reads the headers, or nil when a response has none.
    public init?(headers response: HTTPURLResponse, now: Date) {
        func number(_ name: String) -> Int? { (response.value(forHTTPHeaderField: name)).flatMap { Int($0) } }
        guard let limit = number("x-ratelimit-limit"), let remaining = number("x-ratelimit-remaining"),
              let reset = number("x-ratelimit-reset")
        else { return nil }
        self.init(resource: response.value(forHTTPHeaderField: "x-ratelimit-resource") ?? "core",
                  limit: limit, remaining: remaining, resetAt: Date(timeIntervalSince1970: TimeInterval(reset)), readAt: now)
    }

    /// "4,812 of 5,000 left".
    public var summary: String {
        "\(remaining.formatted()) of \(limit.formatted()) left"
    }
}
