import Foundation

/// How the pull request list is arranged: as one run of rows, or as a tree with up to two
/// levels, such as by organization and then by repository.
///
/// Grouping only arranges the rows the list already holds. It keeps no pull request out and
/// adds none, so it is not a filter and has no syntax. `ListTree` builds the tree.
public struct ListGrouping: Sendable, Hashable, Codable, CustomStringConvertible {
    /// One thing the list can be grouped by.
    public enum Property: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
        case organization
        case repository
        case author
        case status
        case reviewState

        public var id: String { rawValue }

        public var name: String {
            switch self {
            case .organization: "Organization"
            case .repository: "Repository"
            case .author: "Author"
            case .status: "Status"
            case .reviewState: "Review State"
            }
        }

        /// What can be the second level under this one. Never itself, and never something
        /// this level already decides: a repository has only one organization.
        public var secondLevelChoices: [Property] {
            Property.allCases.filter { allowsSecondLevel($0) }
        }

        public func allowsSecondLevel(_ second: Property) -> Bool {
            second != self && !(self == .repository && second == .organization)
        }
    }

    /// The most levels the tree has.
    public static let maximumLevels = 2

    /// The levels from the outermost in. Empty is the flat list.
    public let levels: [Property]

    /// Keeps the levels that make sense together: no repeats, nothing the level above
    /// already decides, and at most `maximumLevels`.
    public init(_ levels: [Property]) {
        var kept: [Property] = []
        for level in levels where kept.count < Self.maximumLevels {
            if let first = kept.first, !first.allowsSecondLevel(level) { continue }
            kept.append(level)
        }
        self.levels = kept
    }

    public init(_ first: Property, then second: Property? = nil) {
        self.init([first] + (second.map { [$0] } ?? []))
    }

    /// The flat list, with no title rows.
    public static let none = ListGrouping([])

    /// The grouping the list starts with when nothing was chosen before.
    public static let standard: ListGrouping = .none

    public var isNone: Bool { levels.isEmpty }
    public var first: Property? { levels.first }
    public var second: Property? { levels.count > 1 ? levels[1] : nil }

    /// "None", "Organization", or "Organization, then Repository".
    public var name: String {
        guard let first else { return "None" }
        guard let second else { return first.name }
        return "\(first.name), then \(second.name)"
    }

    public var description: String { storedValue }

    // MARK: Remembering

    /// How the choice is remembered: `none`, `repository`, or `organization>repository`.
    /// A single level is written the way the one-level grouping wrote it, so a value saved
    /// before there were two levels reads back as the same choice.
    public var storedValue: String {
        isNone ? "none" : levels.map(\.rawValue).joined(separator: ">")
    }

    /// Reads a remembered choice. Unknown words are dropped, so a value from a newer or
    /// older version still gives something sensible, and an empty result is the flat list.
    public init(storedValue: String) {
        self.init(storedValue.split(separator: ">").compactMap { Property(rawValue: String($0)) })
    }

    public init(from decoder: any Decoder) throws {
        self.init(storedValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(storedValue)
    }
}
