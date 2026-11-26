import Foundation

/// Why the last sync did not finish. The last data stays in the index and on screen.
/// None of these holds a token, and none holds pull request content.
public enum GitHubSyncProblem: Codable, Sendable, Hashable {
    case ghMissing
    case signedOut
    /// `gh` failed for another reason, with its message.
    case loginFailed(String)
    /// The network could not be reached.
    case offline
    /// GitHub said the rate limit is used up, or asked to slow down, until this time.
    case rateLimited(until: Date)
    /// The sync stopped itself to keep within its budget of half the hourly limit.
    case budgetPaused(until: Date)
    /// GitHub refused the token, or answered in a way the sync did not expect.
    case failed(String)

    /// A short phrase for the title bar.
    public func shortText(now: Date) -> String {
        switch self {
        case .ghMissing: "gh not found"
        case .signedOut: "Signed out of gh"
        case .loginFailed: "gh login failed"
        case .offline: "Offline"
        case .rateLimited(let until): "Rate limited, back \(Self.clock(until, now: now))"
        case .budgetPaused(let until): "Paused for the rate limit, back \(Self.clock(until, now: now))"
        case .failed: "Sync failed"
        }
    }

    /// A sentence saying what is wrong and what to do.
    public var explanation: String {
        switch self {
        case .ghMissing: GitHubAccessError.ghMissing.description + " Install it with `brew install gh`, then `gh auth login`."
        case .signedOut: GitHubAccessError.signedOut.description
        case .loginFailed(let message): "gh could not give a token: \(message)"
        case .offline: "GitHub could not be reached. The sync tries again at the next interval."
        case .rateLimited: "GitHub's rate limit is used up for now. The sync waits until it resets."
        case .budgetPaused: "The sync keeps to half of GitHub's hourly rate limit, so other tools have the rest. It waits until the limit resets."
        case .failed(let message): message
        }
    }

    /// The time the sync waits for before it tries again, if it waits.
    public var waitsUntil: Date? {
        switch self {
        case .rateLimited(let until), .budgetPaused(let until): until
        default: nil
        }
    }

    static func clock(_ date: Date, now: Date) -> String {
        let seconds = date.timeIntervalSince(now)
        if seconds <= 60 { return "in under a minute" }
        if seconds < 3600 { return "in \(Int((seconds / 60).rounded(.up))) min" }
        return "at " + date.formatted(date: .omitted, time: .shortened)
    }
}

/// The counts for one sync run or a whole session: how many requests, and what they cost.
public struct GitHubRequestCounts: Codable, Sendable, Hashable {
    public var graphQLRequests = 0
    /// GraphQL points, as each response's `rateLimit { cost }` reports them.
    public var graphQLPoints = 0
    public var restRequests = 0
    /// REST answers of 304 Not Modified. GitHub does not count these against the limit.
    public var restNotModified = 0

    public init() {}

    /// REST points: every REST request that was not a 304.
    public var restPoints: Int { restRequests - restNotModified }
    public var totalRequests: Int { graphQLRequests + restRequests }

    public static func + (lhs: Self, rhs: Self) -> Self {
        var sum = lhs
        sum.graphQLRequests += rhs.graphQLRequests
        sum.graphQLPoints += rhs.graphQLPoints
        sum.restRequests += rhs.restRequests
        sum.restNotModified += rhs.restNotModified
        return sum
    }
}

/// What the sync is doing and how it last went. The window, Settings and `ctl sync status`
/// all show this.
public struct GitHubSyncStatus: Codable, Sendable, Hashable {
    public enum Phase: String, Codable, Sendable, Hashable {
        case idle
        case checkingLogin
        case listing
        case fetchingDetail
    }

    public var phase: Phase = .idle
    /// The signed-in account's login, once GitHub has said who it is.
    public var accountLogin: String?
    /// Where the token comes from, such as "gh login (/opt/homebrew/bin/gh)".
    public var tokenSource: String?
    /// Whether `gh` was found and gave a token the last time it was asked.
    public var hasLogin: Bool?
    public var lastAttemptAt: Date?
    /// When the last run finished with no problem.
    public var lastSuccessAt: Date?
    /// When the list of pull requests was last read in full.
    public var lastListAt: Date?
    public var problem: GitHubSyncProblem?
    /// Problems that did not stop the run, such as a watched repository that was not found.
    public var warnings: [String] = []
    public var rateLimits: [String: RateLimitReading] = [:]
    /// The last run's requests.
    public var lastRun = GitHubRequestCounts()
    public var lastRunSeconds: Double?
    /// Every request since the app or `ctl` started.
    public var session = GitHubRequestCounts()
    public var pullRequestCount = 0
    /// Pull requests with their full detail fetched.
    public var detailedCount = 0

    public init() {}

    public var isSyncing: Bool { phase != .idle }
}

/// The sync's status as the title bar says it: a few words, whether they are a problem, and a
/// tooltip. Mock mode has no sync status, and the title bar stays as it was.
public struct SyncStatusSummary: Sendable, Hashable {
    public var text: String
    public var isProblem: Bool
    public var help: String

    public init(status: GitHubSyncStatus, now: Date) {
        var help: [String] = []
        if let login = status.accountLogin { help.append("Signed in as \(login), through the gh login.") }
        if let problem = status.problem {
            text = problem.shortText(now: now)
            isProblem = true
            help.append(problem.explanation)
            if let last = status.lastSuccessAt {
                help.append("Showing what was synced \(RelativeAge.ago(last, now: now)).")
            } else {
                help.append("Nothing has been synced yet.")
            }
        } else if status.isSyncing {
            text = "Syncing…"
            isProblem = false
            if let last = status.lastSuccessAt { help.append("Last synced \(RelativeAge.ago(last, now: now)).") }
        } else if let last = status.lastSuccessAt {
            text = "Synced \(RelativeAge.ago(last, now: now))"
            isProblem = false
        } else {
            text = "Not synced yet"
            isProblem = false
        }
        for warning in status.warnings { help.append(warning) }
        for key in status.rateLimits.keys.sorted() {
            if let reading = status.rateLimits[key] {
                help.append("\(key == "graphql" ? "GraphQL" : key == "core" ? "REST" : key): \(reading.summary)")
            }
        }
        self.help = help.joined(separator: "\n")
    }
}
