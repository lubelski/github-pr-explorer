import Foundation

/// Why one request to GitHub failed, sorted into what the sync does about it. Messages never
/// hold the token or request headers.
public enum GitHubRequestError: Error, Sendable, Hashable {
    case offline
    case unauthorized
    case rateLimited(until: Date)
    /// The sync's own budget, half of the hourly limit, is spent until this time.
    case budget(until: Date)
    /// GraphQL said the query was too heavy or took too long. The sync splits the batch.
    case tooExpensive(String)
    case http(status: Int, message: String)
    case graphQL([String])
    case decoding(String)

    var problem: GitHubSyncProblem {
        switch self {
        case .offline: .offline
        case .unauthorized: .failed("GitHub refused the gh login's token (401). Run `gh auth refresh` or `gh auth login` in Terminal.")
        case .rateLimited(let until): .rateLimited(until: until)
        case .budget(let until): .budgetPaused(until: until)
        case .tooExpensive(let message): .failed("GitHub could not answer a query in time: \(message)")
        case .http(let status, let message): .failed("GitHub answered \(status): \(message)")
        case .graphQL(let messages): .failed("GitHub's GraphQL API said: \(messages.joined(separator: " "))")
        case .decoding(let message): .failed("A GitHub answer could not be read: \(message)")
        }
    }
}

/// One GraphQL answer: its data, any errors GitHub sent along with partial data, and its cost.
struct GraphQLAnswer<Payload: Decodable & Sendable>: Sendable {
    var data: Payload
    var errors: [GraphQLErrorEntry]
    var cost: Int
    var rateLimit: RateLimitReading?
}

struct GraphQLErrorEntry: Decodable, Sendable, Hashable {
    var type: String?
    var message: String
    var path: [GraphQLPathPart]?

    enum GraphQLPathPart: Decodable, Sendable, Hashable {
        case key(String)
        case index(Int)
        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Int.self) { self = .index(number) } else { self = .key(try container.decode(String.self)) }
        }
        var key: String? { if case .key(let key) = self { key } else { nil } }
    }
}

/// A REST answer: the body and its ETag, or Not Modified.
enum RESTAnswer: Sendable {
    case notModified
    case ok(Data, etag: String?, hasNextPage: Bool)
}

/// Builds requests to GitHub's APIs, sends them through the transport, and reads the answers.
/// It holds no state: the sync keeps the token, the counts and the budget.
struct GitHubAPIClient: Sendable {
    static let graphQLURL = URL(string: "https://api.github.com/graphql")!
    static let restBase = URL(string: "https://api.github.com")!
    static let userAgent = "github-pr-explorer"

    let transport: any GitHubTransport
    let now: @Sendable () -> Date

    private func request(_ url: URL, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    private func send(_ request: URLRequest) async throws(GitHubRequestError) -> (Data, HTTPURLResponse) {
        do {
            return try await transport.send(request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
                 .dnsLookupFailed, .timedOut, .internationalRoamingOff, .dataNotAllowed, .secureConnectionFailed:
                throw .offline
            default:
                throw .http(status: 0, message: "the request failed (URL error \(error.code.rawValue))")
            }
        } catch {
            throw .http(status: 0, message: "the request failed: \(type(of: error))")
        }
    }

    /// Sorts a failed HTTP status into what the sync does about it.
    private func failure(_ response: HTTPURLResponse, data: Data) -> GitHubRequestError {
        let status = response.statusCode
        let message = (try? JSONDecoder().decode(RESTMessage.self, from: data))?.message ?? HTTPURLResponse.localizedString(forStatusCode: status)
        if status == 401 { return .unauthorized }
        if status == 403 || status == 429 {
            let now = now()
            if let retry = response.value(forHTTPHeaderField: "retry-after").flatMap(TimeInterval.init) {
                return .rateLimited(until: now.addingTimeInterval(max(retry, 1)))
            }
            if let reading = RateLimitReading(headers: response, now: now), reading.remaining == 0 {
                return .rateLimited(until: reading.resetAt)
            }
            if message.lowercased().contains("rate limit") {
                // A secondary limit with no time given. GitHub asks for at least a minute.
                return .rateLimited(until: now.addingTimeInterval(60))
            }
        }
        if status == 502 || status == 504 { return .tooExpensive("HTTP \(status)") }
        return .http(status: status, message: message)
    }

    private struct RESTMessage: Decodable { var message: String }

    private struct GraphQLBody: Encodable {
        var query: String
        var variables: [String: GraphQLValue]
    }

    private struct GraphQLEnvelope<Payload: Decodable>: Decodable {
        var data: Payload?
        var errors: [GraphQLErrorEntry]?
    }

    private struct RateLimitOnly: Decodable { var rateLimit: GraphQLRateLimit? }

    func graphQL<Payload: Decodable & Sendable>(_ query: String, variables: [String: GraphQLValue] = [:], token: String,
                                                 as type: Payload.Type) async throws(GitHubRequestError) -> GraphQLAnswer<Payload> {
        var request = request(Self.graphQLURL, token: token)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONEncoder().encode(GraphQLBody(query: query, variables: variables))
        } catch {
            throw .decoding("the query could not be encoded")
        }
        let (data, response) = try await send(request)
        let reading = RateLimitReading(headers: response, now: now())
        guard response.statusCode == 200 else { throw failure(response, data: data) }
        let envelope: GraphQLEnvelope<Payload>
        do {
            envelope = try GitHubJSON.decoder.decode(GraphQLEnvelope<Payload>.self, from: data)
        } catch {
            throw .decoding(Self.describe(error))
        }
        let errors = envelope.errors ?? []
        if errors.contains(where: { $0.type == "RATE_LIMITED" }) {
            throw .rateLimited(until: reading?.resetAt ?? now().addingTimeInterval(60))
        }
        let heavy = errors.first { error in
            let text = error.message.lowercased()
            return error.type == "MAX_NODE_LIMIT_EXCEEDED" || text.contains("resource limits") || text.contains("timeout") || text.contains("timed out")
        }
        if let heavy { throw .tooExpensive(heavy.message) }
        guard let payload = envelope.data else {
            throw .graphQL(errors.map(\.message))
        }
        let cost = (try? GitHubJSON.decoder.decode(GraphQLEnvelope<RateLimitOnly>.self, from: data))?.data?.rateLimit?.cost ?? 1
        return GraphQLAnswer(data: payload, errors: errors, cost: cost, rateLimit: reading)
    }

    /// GETs a REST path such as `/repos/acme/api/pulls/1/files?per_page=100&page=1`, with
    /// `If-None-Match` when an ETag is known. A 304 is free against the rate limit.
    func rest(_ pathAndQuery: String, etag: String?, token: String) async throws(GitHubRequestError) -> (RESTAnswer, RateLimitReading?) {
        guard let url = URL(string: pathAndQuery, relativeTo: Self.restBase) else { throw .decoding("bad path") }
        var request = request(url, token: token)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let (data, response) = try await send(request)
        let reading = RateLimitReading(headers: response, now: now())
        if response.statusCode == 304 { return (.notModified, reading) }
        guard (200..<300).contains(response.statusCode) else { throw failure(response, data: data) }
        let link = response.value(forHTTPHeaderField: "Link") ?? ""
        return (.ok(data, etag: response.value(forHTTPHeaderField: "ETag"), hasNextPage: link.contains("rel=\"next\"")), reading)
    }

    static func describe(_ error: any Error) -> String {
        guard let error = error as? DecodingError else { return "\(type(of: error))" }
        func path(_ context: DecodingError.Context) -> String {
            context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined()
        }
        switch error {
        case .keyNotFound(let key, let context): return "missing \(key.stringValue) at \(path(context))"
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            return "\(context.debugDescription) at \(path(context))"
        @unknown default: return "unreadable"
        }
    }
}

/// A GraphQL variable's value.
enum GraphQLValue: Encodable, Sendable, Hashable {
    case string(String)
    case int(Int)
    case strings([String])
    case null

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let text): try container.encode(text)
        case .int(let number): try container.encode(number)
        case .strings(let list): try container.encode(list)
        case .null: try container.encodeNil()
        }
    }
}

/// GitHub's dates are ISO 8601, sometimes with fractional seconds.
enum GitHubJSON {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = try? Date(text, strategy: .iso8601) { return date }
            if let date = try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "not an ISO 8601 date")
        }
        return decoder
    }()
}
