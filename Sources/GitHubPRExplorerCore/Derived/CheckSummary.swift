import Foundation

/// Check counts by state, in the order a reader needs them: failed first, then running, then passed.
public struct CheckSummary: Codable, Sendable, Hashable {
    public struct Entry: Codable, Sendable, Hashable {
        public var state: CheckState
        public var count: Int
    }

    /// The order entries are listed in. What needs attention comes first.
    public static let displayOrder: [CheckState] = [.failed, .running, .queued, .passed, .cancelled, .skipped]

    /// Only states with at least one check, in `displayOrder`.
    public var entries: [Entry]

    public init(checks: [Check]) {
        entries = Self.displayOrder.compactMap { state in
            let count = checks.count { $0.state == state }
            return count > 0 ? Entry(state: state, count: count) : nil
        }
    }

    public var total: Int { entries.reduce(0) { $0 + $1.count } }

    public func count(of state: CheckState) -> Int {
        entries.first { $0.state == state }?.count ?? 0
    }

    /// "1 failed, 1 running, 12 passed", or "No checks".
    public var text: String {
        if entries.isEmpty { return "No checks" }
        return entries.map { "\($0.count) \($0.state.rawValue)" }.joined(separator: ", ")
    }
}

extension PullRequest {
    public var checkSummary: CheckSummary { CheckSummary(checks: checks) }
}
