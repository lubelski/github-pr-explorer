import Foundation

/// How a pull request page is arranged: named tabs, each split into columns of blocks.
///
/// A layout is data, not code. It is stored as JSON with sorted keys, and the layouts that ship
/// are JSON files read through the same decoding a person's own file goes through
/// (`PageLayout.decode(_:fileName:)`). Rules that pick a layout, and Edit Layout, come later and
/// build on this shape.
public struct PageLayout: Codable, Sendable, Hashable, Identifiable {
    /// The format this code reads and writes. A file with another version is refused, so an
    /// older app never half-reads a newer file.
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    /// Stable and file-name safe, such as `decision-first`.
    public var id: String
    /// What a person sees, such as "Decision first".
    public var name: String
    /// In order. A layout with one tab shows no tab strip.
    public var tabs: [LayoutTab]

    public init(formatVersion: Int = PageLayout.currentFormatVersion, id: String, name: String, tabs: [LayoutTab]) {
        self.formatVersion = formatVersion
        self.id = id
        self.name = name
        self.tabs = tabs
    }

    /// Every block placed anywhere in the layout, in tab, column and block order.
    public var placements: [BlockPlacement] {
        tabs.flatMap { $0.columns.flatMap(\.blocks) }
    }
}

/// One tab of a page.
public struct LayoutTab: Codable, Sendable, Hashable {
    public var name: String
    /// Left to right. A tab may have no columns, and a column no blocks: an empty tab is allowed.
    public var columns: [LayoutColumn]

    public init(name: String, columns: [LayoutColumn]) {
        self.name = name
        self.columns = columns
    }

    public var placements: [BlockPlacement] { columns.flatMap(\.blocks) }
}

/// One column of a tab.
public struct LayoutColumn: Codable, Sendable, Hashable {
    /// The column's share of the tab's width, relative to the other columns: widths 2 and 1
    /// give two thirds and one third. Must be above zero.
    public var width: Double
    /// Top to bottom.
    public var blocks: [BlockPlacement]

    public init(width: Double, blocks: [BlockPlacement]) {
        self.width = width
        self.blocks = blocks
    }
}

/// One block put somewhere on the page.
public struct BlockPlacement: Codable, Sendable, Hashable {
    public var kind: BlockKind
    public var size: BlockSize

    public init(_ kind: BlockKind, _ size: BlockSize = .large) {
        self.kind = kind
        self.size = size
    }
}

/// How much a block shows. Every block works at both sizes.
public enum BlockSize: String, Codable, Sendable, Hashable, CaseIterable {
    /// A line or two: a summary of the block.
    case small
    /// The block's full content.
    case large
}

/// The kinds of block a layout can place. A new piece of pull request information is a new kind.
///
/// The header (repository and number, title, status sentence, actions) is not a block yet. It
/// is fixed above the tabs for now: `planning/decided.md` says why, and that it is temporary.
public enum BlockKind: String, Codable, Sendable, Hashable, CaseIterable {
    case description
    case checks
    case reviewers
    case ownersTouched
    case files
    case threads
    case activity
    case commits
    case labelsAndMetadata

    /// The block's title, as its header shows it.
    public var title: String {
        switch self {
        case .description: "Description"
        case .checks: "Checks"
        case .reviewers: "Reviewers"
        case .ownersTouched: "Owners touched"
        case .files: "Files"
        case .threads: "Threads"
        case .activity: "Activity"
        case .commits: "Commits"
        case .labelsAndMetadata: "Labels and metadata"
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let kind = BlockKind(rawValue: text) else {
            let known = BlockKind.allCases.map(\.rawValue).joined(separator: ", ")
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "unknown block kind \"\(text)\". Known kinds: \(known)")
        }
        self = kind
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Why a layout file could not be used. `description` names the file and what is wrong.
public struct LayoutFileError: Error, Sendable, Hashable, CustomStringConvertible {
    public var fileName: String
    /// Where in the file, such as `tabs[0].columns[1].blocks[2].kind`. Empty for the whole file.
    public var path: String
    public var problem: String

    public init(fileName: String, path: String = "", problem: String) {
        self.fileName = fileName
        self.path = path
        self.problem = problem
    }

    public var description: String {
        path.isEmpty ? "\(fileName): \(problem)" : "\(fileName), at \(path): \(problem)"
    }
}

extension PageLayout {
    /// Reads a layout file. Every layout, built in or not, comes through here.
    public static func decode(_ data: Data, fileName: String) throws(LayoutFileError) -> PageLayout {
        let layout: PageLayout
        do {
            layout = try GitHubPRExplorerJSON.decoder().decode(PageLayout.self, from: data)
        } catch let error as DecodingError {
            throw describe(error, fileName: fileName)
        } catch {
            throw LayoutFileError(fileName: fileName, problem: error.localizedDescription)
        }
        try layout.validate(fileName: fileName)
        return layout
    }

    /// The JSON form: sorted keys and pretty printed, the same bytes on every run.
    public func encoded() throws -> Data {
        try GitHubPRExplorerJSON.encoder().encode(self)
    }

    /// Checks what the types alone cannot.
    public func validate(fileName: String) throws(LayoutFileError) {
        guard formatVersion == Self.currentFormatVersion else {
            throw LayoutFileError(fileName: fileName, path: "formatVersion",
                                  problem: "format version \(formatVersion) is not one this app reads. It reads version \(Self.currentFormatVersion).")
        }
        if id.trimmingCharacters(in: .whitespaces).isEmpty {
            throw LayoutFileError(fileName: fileName, path: "id", problem: "the id is empty")
        }
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            throw LayoutFileError(fileName: fileName, path: "name", problem: "the name is empty")
        }
        if tabs.isEmpty {
            throw LayoutFileError(fileName: fileName, path: "tabs", problem: "a layout needs at least one tab")
        }
        for (tabIndex, tab) in tabs.enumerated() {
            if tab.name.trimmingCharacters(in: .whitespaces).isEmpty {
                throw LayoutFileError(fileName: fileName, path: "tabs[\(tabIndex)].name", problem: "the tab name is empty")
            }
            for (columnIndex, column) in tab.columns.enumerated() where !(column.width > 0) || !column.width.isFinite {
                throw LayoutFileError(fileName: fileName, path: "tabs[\(tabIndex)].columns[\(columnIndex)].width",
                                      problem: "a column's width must be a number above zero, not \(column.width)")
            }
        }
    }

    private static func describe(_ error: DecodingError, fileName: String) -> LayoutFileError {
        func path(_ codingPath: [any CodingKey]) -> String {
            var text = ""
            for key in codingPath {
                if let index = key.intValue {
                    text += "[\(index)]"
                } else {
                    text += text.isEmpty ? key.stringValue : ".\(key.stringValue)"
                }
            }
            return text
        }
        switch error {
        case .dataCorrupted(let context):
            if context.codingPath.isEmpty {
                let reason = (context.underlyingError as NSError?)?.userInfo[NSDebugDescriptionErrorKey] as? String
                return LayoutFileError(fileName: fileName, problem: "this is not valid JSON" + (reason.map { " (\($0))" } ?? ""))
            }
            return LayoutFileError(fileName: fileName, path: path(context.codingPath), problem: context.debugDescription)
        case .keyNotFound(let key, let context):
            return LayoutFileError(fileName: fileName, path: path(context.codingPath + [key]), problem: "\"\(key.stringValue)\" is missing")
        case .typeMismatch(let type, let context):
            return LayoutFileError(fileName: fileName, path: path(context.codingPath), problem: "expected \(readable(type))")
        case .valueNotFound(let type, let context):
            return LayoutFileError(fileName: fileName, path: path(context.codingPath), problem: "expected \(readable(type)), found null")
        @unknown default:
            return LayoutFileError(fileName: fileName, problem: String(describing: error))
        }
    }

    private static func readable(_ type: Any.Type) -> String {
        switch type {
        case is String.Type: "text"
        case is Int.Type: "a whole number"
        case is Double.Type: "a number"
        case is Bool.Type: "true or false"
        default:
            String(describing: type).hasPrefix("Array") ? "a list" : "an object"
        }
    }
}
