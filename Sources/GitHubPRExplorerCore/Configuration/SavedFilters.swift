import Foundation

/// A filter the person keeps, with a name, shown as a tab above the list or kept in the »
/// menu. Its conditions are the filter language's (`PullRequestFilter`).
///
/// Saved filters apply to open pull requests, as the list's views always have: a filter's
/// count is out of the open pull requests in the index.
public struct SavedFilter: Codable, Sendable, Hashable, Identifiable {
    /// Lowercase letters, digits and hyphens, such as `needs-my-review`. It stays the same when
    /// the name changes, so the command line, MCP and window state can point at a filter.
    public var id: String
    public var name: String
    public var filter: PullRequestFilter
    /// How the list is grouped while this filter is chosen: no grouping, or one or two levels,
    /// outer first, such as `["organization", "repository"]`. Each is a grouping's plain
    /// identifier. They are kept as text so this file does not depend on the list's grouping
    /// code: the window reads them, and treats one it does not know as no grouping.
    public var groupBy: [String]
    /// True when the filter is a tab above the list. False keeps it in the » menu and Settings.
    public var showsAsTab: Bool

    public init(id: String, name: String, filter: PullRequestFilter, groupBy: [String] = [], showsAsTab: Bool = true) {
        self.id = id
        self.name = name
        self.filter = filter
        self.groupBy = groupBy
        self.showsAsTab = showsAsTab
    }

    enum CodingKeys: String, CodingKey { case id, name, filter, groupBy, showsAsTab }

    /// `groupBy` and `showsAsTab` may be left out: no grouping, and shown as a tab.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        filter = try container.decode(PullRequestFilter.self, forKey: .filter)
        groupBy = try container.decodeIfPresent([String].self, forKey: .groupBy) ?? []
        showsAsTab = try container.decodeIfPresent(Bool.self, forKey: .showsAsTab) ?? true
    }

    /// The most levels of grouping a saved filter holds.
    public static let maximumGroupingLevels = 2

    /// The filter's own id, which no saved filter may take.
    public static let everythingID = "everything"

    /// "Everything": always first, every open pull request, and not in the file. It cannot be
    /// renamed, moved or removed.
    public static let everything = SavedFilter(id: everythingID, name: "Everything", filter: .everything)

    /// "Needs my review", the same pull requests as the list's fixed view of that name.
    public static let needsMyReview = SavedFilter(
        id: "needs-my-review", name: "Needs my review",
        filter: PullRequestFilter([FilterCondition(field: .reviewState, values: [FilterValues.waitingOnMe])]))

    /// "Mine", the same pull requests as the list's fixed view of that name.
    public static let mine = SavedFilter(
        id: "mine", name: "Mine",
        filter: PullRequestFilter([FilterCondition(field: .author, values: [FilterValues.me])]))

    /// True for Everything, which is fixed.
    public var isEverything: Bool { id == Self.everythingID }

    public var summary: String { filter.summary }

    /// Lowercase letters, digits and hyphens, starting with a letter or digit.
    public static func isValidID(_ id: String) -> Bool { PageLayout.isValidID(id) }

    /// The filter applied to the open pull requests among those given.
    public func evaluate(_ pullRequests: [PullRequest], context: FilterContext) -> FilterEvaluation {
        filter.evaluate(pullRequests.filter { $0.state == .open }, context: context)
    }

    /// What is wrong with the saved filter, with where in it, or nil when it is fine.
    public func problem() -> (path: String, message: String)? {
        if !Self.isValidID(id) {
            return ("id", "\"\(id)\" cannot be a saved filter's id. Use lowercase letters, digits and hyphens, such as \"blocked-in-api\".")
        }
        if id == Self.everythingID {
            return ("id", "\"\(Self.everythingID)\" is the id of Everything, which is built in. Pick another id.")
        }
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ("name", "a saved filter needs a name")
        }
        if groupBy.count > Self.maximumGroupingLevels {
            return ("groupBy", "a saved filter groups by at most \(Self.maximumGroupingLevels) levels, not \(groupBy.count)")
        }
        for (position, level) in groupBy.enumerated() {
            if level.wholeMatch(of: /[a-z][A-Za-z]*/) == nil || level == "none" {
                return ("groupBy[\(position)]", "\"\(level)\" is not a grouping, such as repository or author. Leave groupBy out for no grouping.")
            }
        }
        if groupBy.count == 2, groupBy[0] == groupBy[1] {
            return ("groupBy[1]", "the two levels of grouping are both \(groupBy[0])")
        }
        if let problem = filter.problem() {
            return ("filter.\(problem.path)", problem.message)
        }
        return nil
    }
}

/// `saved-filters.json`: the saved filters in their order. Everything is not in it, because it
/// is always first and never changes.
public struct SavedFilterFile: Codable, Sendable, Hashable {
    public static let currentFormatVersion = 1
    public static let fileName = "saved-filters.json"

    public var formatVersion: Int
    public var savedFilters: [SavedFilter]

    public init(formatVersion: Int = currentFormatVersion, savedFilters: [SavedFilter]) {
        self.formatVersion = formatVersion
        self.savedFilters = savedFilters
    }

    /// What a new configuration starts with, and what a folder with no file uses: the two
    /// views the list had before saved filters, so nothing is lost. Both can be changed and
    /// removed like any other.
    public static let defaults = SavedFilterFile(savedFilters: [.needsMyReview, .mine])

    static let shape = JSONKeyCheck.Shape.object([
        "formatVersion": .value,
        "savedFilters": .array(.object([
            "id": .value, "name": .value, "filter": PullRequestFilter.shape,
            "groupBy": .array(.value), "showsAsTab": .value,
        ])),
    ])

    /// Sorted keys and pretty printed, the same bytes on every run.
    public func encoded() throws -> Data {
        var data = try GitHubPRExplorerJSON.encoder().encode(self)
        data.append(0x0A)
        return data
    }

    /// Reads the file. Problems name where in the file and what is wrong.
    public static func decode(_ data: Data, fileName: String = fileName) throws(LayoutFileError) -> SavedFilterFile {
        try JSONKeyCheck.check(data, fileName: fileName, allowed: shape)
        let file: SavedFilterFile
        do {
            file = try GitHubPRExplorerJSON.decoder().decode(SavedFilterFile.self, from: data)
        } catch let error as DecodingError {
            throw LayoutFileError.describe(error, fileName: fileName)
        } catch {
            throw LayoutFileError(fileName: fileName, problem: error.localizedDescription)
        }
        guard file.formatVersion == currentFormatVersion else {
            throw LayoutFileError(fileName: fileName, path: "formatVersion",
                                  problem: "format version \(file.formatVersion) is not one this app reads. It reads version \(currentFormatVersion).")
        }
        if let problem = file.problem() {
            throw LayoutFileError(fileName: fileName, path: problem.path, problem: problem.message)
        }
        return file
    }

    /// What is wrong with the list, or nil when it is fine.
    func problem() -> (path: String, message: String)? {
        var seen: Set<String> = []
        for (position, saved) in savedFilters.enumerated() {
            if let problem = saved.problem() {
                return ("savedFilters[\(position)].\(problem.path)", problem.message)
            }
            if !seen.insert(saved.id).inserted {
                return ("savedFilters[\(position)].id", "two saved filters have the id \"\(saved.id)\"")
            }
        }
        return nil
    }
}
