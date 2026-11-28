import Foundation

/// How the overview of a title row of the list is arranged: blocks, top to bottom.
///
/// The pull request page's `PageLayout` places blocks that each draw one pull request, and its
/// `BlockKind` has no meaning for a set of them. So the overview has a block kind and a layout
/// of its own, in the same shape at its smallest: an id, a name and blocks in order, each a
/// kind and a size, reusing `BlockSize`. It has one column and no tabs, because one built-in
/// layout is all it needs today. Columns, tabs and a file in the configuration folder come when
/// a person can change it, with Edit Layout, and build on this shape.
public struct OverviewLayout: Codable, Sendable, Hashable, Identifiable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    /// Stable and file-name safe, such as `overview`.
    public var id: String
    public var name: String
    /// Top to bottom.
    public var blocks: [OverviewBlockPlacement]

    public init(formatVersion: Int = OverviewLayout.currentFormatVersion, id: String, name: String,
                blocks: [OverviewBlockPlacement]) {
        self.formatVersion = formatVersion
        self.id = id
        self.name = name
        self.blocks = blocks
    }

    /// The one overview that ships: the summary, then the pull requests as cards.
    public static let standard = OverviewLayout(
        id: "overview",
        name: "Overview",
        blocks: [OverviewBlockPlacement(.summary), OverviewBlockPlacement(.pullRequests)]
    )
}

/// One block put somewhere on the overview.
public struct OverviewBlockPlacement: Codable, Sendable, Hashable {
    public var kind: OverviewBlockKind
    public var size: BlockSize

    public init(_ kind: OverviewBlockKind, _ size: BlockSize = .large) {
        self.kind = kind
        self.size = size
    }
}

/// The kinds of block an overview can place. A new piece of information about a set of pull
/// requests is a new kind.
public enum OverviewBlockKind: String, Codable, Sendable, Hashable, CaseIterable {
    /// The group's name, kind and count, and how many pull requests are in each status.
    /// Small: the name and one line of counts.
    case summary
    /// The group's pull requests as cards, under a heading for each group one level down.
    /// Small: each card is its title, badge and number only.
    case pullRequests

    public var title: String {
        switch self {
        case .summary: "Summary"
        case .pullRequests: "Pull requests"
        }
    }

    public init(from decoder: any Decoder) throws {
        self = try decodeNamedValue(decoder, as: OverviewBlockKind.self)
    }
}
