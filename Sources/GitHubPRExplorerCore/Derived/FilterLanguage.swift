import Foundation

// The one filter language.
//
// A filter is one or more sets of conditions. A pull request matches when any set matches, and
// a set matches when every condition in it does. A condition tests one field with "is" or "is
// not" against one or more values, and several values on one condition are alternatives. Sets
// do not nest.
//
// This grew out of `ListFilter.Clause`, the "field is one of values" condition the filter menu
// already produced. That condition is now `FilterCondition`, and `ListFilter.Clause` is a name
// for it, so the menu, saved filters, and later search and layout rules all write conditions
// the same way. The extension is the smallest that carries saved filters: an operator ("is" or
// "is not") on each condition, an `organization` field, the review state "waiting on me", the
// author "@me", and sets joined by "or".
//
// In a file a filter is JSON:
//
//     {"sets": [{"conditions": [{"field": "status", "operator": "is", "values": ["blocked"]}]}]}
//
// `schemas/saved-filters.schema.json` describes it, and a test keeps the two in step.

/// A field a condition can test. Each reads one or more plain values from a pull request, and a
/// condition compares them with its own values.
///
/// More fields, such as label, path and checks, are a new case here, its values in
/// `values(of:context:)`, its check in `FilterCondition.problem`, and its words in
/// `FilterSummary`. Nothing else changes.
public enum FilterField: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    /// The status badge's raw value, such as `blocked` or `ready`.
    case status
    /// The repository's owner, such as `acme`.
    case organization
    /// The repository as `owner/name`, such as `acme/api`.
    case repository
    /// The author's login. The value `@me` stands for the viewer.
    case author
    /// GitHub's review decision (`approved`, `changesRequested`, `reviewRequired`,
    /// `noDecision`), and also `waitingOnMe` when a review is asked of the viewer or one of
    /// the viewer's teams.
    case reviewState
    /// `true` for a draft, `false` otherwise.
    case draft

    public var id: String { rawValue }

    public init(from decoder: any Decoder) throws {
        self = try decodeNamedValue(decoder, as: FilterField.self)
    }

    /// The field's name in a condition's menu.
    public var name: String {
        switch self {
        case .status: "Status"
        case .organization: "Organization"
        case .repository: "Repository"
        case .author: "Author"
        case .reviewState: "Review state"
        case .draft: "Draft"
        }
    }

    /// Whether values are compared ignoring case. GitHub's names of people, organizations and
    /// repositories ignore case. The other fields' values are fixed words.
    var ignoresCase: Bool {
        switch self {
        case .organization, .repository, .author: true
        case .status, .reviewState, .draft: false
        }
    }

    /// The values the pull request has for this field. Most fields have one. The author also
    /// has `@me` when the viewer wrote it, and the review state also has `waitingOnMe`.
    public func values(of pr: PullRequest, context: FilterContext) -> [String] {
        switch self {
        case .status:
            return [context.status(pr).badge.rawValue]
        case .organization:
            return [pr.repository.owner]
        case .repository:
            return [pr.repository.fullName]
        case .author:
            return context.viewer.isViewer(pr.author) ? [pr.author.login, FilterValues.me] : [pr.author.login]
        case .reviewState:
            let decision = ListFilter.ReviewState(pr.reviewDecision).rawValue
            return pr.isReviewRequested(from: context.viewer) ? [decision, FilterValues.waitingOnMe] : [decision]
        case .draft:
            return [pr.isDraft ? "true" : "false"]
        }
    }
}

/// Whether a condition's field must have one of its values, or none of them.
public enum FilterOperator: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    case `is`
    case isNot

    public var id: String { rawValue }

    public init(from decoder: any Decoder) throws {
        self = try decodeNamedValue(decoder, as: FilterOperator.self)
    }

    /// The operator's words in a condition's menu.
    public var name: String {
        switch self {
        case .is: "is"
        case .isNot: "is not"
        }
    }
}

/// The special values and the fixed vocabularies of the fields that have one.
public enum FilterValues {
    /// For `author`: the viewer, whoever is signed in.
    public static let me = "@me"
    /// For `reviewState`: a review is asked of the viewer or one of the viewer's teams.
    public static let waitingOnMe = "waitingOnMe"

    /// The values a field allows, or nil when it takes names from the index (organization,
    /// repository, author).
    public static func fixed(for field: FilterField) -> [String]? {
        switch field {
        case .status: StatusSentence.Badge.allCases.map(\.rawValue)
        case .reviewState: ListFilter.ReviewState.allCases.map(\.rawValue) + [waitingOnMe]
        case .draft: ["true", "false"]
        case .organization, .repository, .author: nil
        }
    }
}

/// One condition: the field is, or is not, one of the values.
public struct FilterCondition: Codable, Sendable, Hashable {
    public var field: FilterField
    public var `operator`: FilterOperator
    /// Alternatives: "is" passes when the pull request has any of them, "is not" when it has
    /// none. At least one.
    public var values: [String]

    public init(field: FilterField, _ operator: FilterOperator = .is, values: [String]) {
        self.field = field
        self.operator = `operator`
        self.values = values
    }

    /// The form `ListFilter.clauses` has always used: the field is one of the values.
    public init(field: FilterField, values: [String]) {
        self.init(field: field, .is, values: values)
    }

    enum CodingKeys: String, CodingKey { case field, `operator`, values }

    /// `operator` may be left out, and then it is "is".
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        field = try container.decode(FilterField.self, forKey: .field)
        self.operator = try container.decodeIfPresent(FilterOperator.self, forKey: .operator) ?? .is
        values = try container.decode([String].self, forKey: .values)
    }

    public func matches(_ pr: PullRequest, context: FilterContext) -> Bool {
        let has = field.values(of: pr, context: context)
        let found: Bool
        if field.ignoresCase {
            let wanted = Set(values.map { $0.lowercased() })
            found = has.contains { wanted.contains($0.lowercased()) }
        } else {
            found = has.contains { values.contains($0) }
        }
        return `operator` == .is ? found : !found
    }

    /// What is wrong with the condition, with where in it, or nil when it is fine.
    public func problem() -> (path: String, message: String)? {
        if values.isEmpty { return ("values", "a condition needs at least one value") }
        for (position, value) in values.enumerated() {
            let path = "values[\(position)]"
            if let fixed = FilterValues.fixed(for: field) {
                if !fixed.contains(value) {
                    return (path, "\"\(value)\" is not a value of \(field.rawValue). Values: \(fixed.joined(separator: ", ")).")
                }
                continue
            }
            switch field {
            case .organization:
                if value.wholeMatch(of: /[A-Za-z0-9_.-]+/) == nil {
                    return (path, "\"\(value)\" is not an organization name, such as acme")
                }
            case .repository:
                if Repository(fullName: value) == nil || !Repository.isPlainName(value) {
                    return (path, "\"\(value)\" is not a repository written as owner/name, such as acme/api")
                }
            case .author:
                if value != FilterValues.me, value.wholeMatch(of: /[A-Za-z0-9_.-]+(\[bot\])?/) == nil {
                    return (path, "\"\(value)\" is not a login, such as ada-park, or \(FilterValues.me) for you")
                }
            case .status, .reviewState, .draft:
                break
            }
        }
        return nil
    }
}

/// Conditions that must all match. A set with no conditions matches every pull request.
public struct FilterConditionSet: Codable, Sendable, Hashable {
    public var conditions: [FilterCondition]

    public init(_ conditions: [FilterCondition] = []) {
        self.conditions = conditions
    }

    public func matches(_ pr: PullRequest, context: FilterContext) -> Bool {
        conditions.allSatisfy { $0.matches(pr, context: context) }
    }
}

/// What a filter needs besides the pull request: who "me" is, and each pull request's status,
/// which the caller usually has already.
public struct FilterContext {
    public var viewer: Viewer
    public var status: (PullRequest) -> StatusSentence

    public init(viewer: Viewer, status: @escaping (PullRequest) -> StatusSentence) {
        self.viewer = viewer
        self.status = status
    }

    /// Works out each status sentence from the viewer and a clock.
    public init(viewer: Viewer, now: Date) {
        self.init(viewer: viewer) { $0.statusSentence(for: viewer, now: now) }
    }
}

/// A filter: sets of conditions joined by "or". A filter with no sets matches every pull request.
public struct PullRequestFilter: Codable, Sendable, Hashable {
    public var sets: [FilterConditionSet]

    public init(sets: [FilterConditionSet] = []) {
        self.sets = sets
    }

    /// A filter of one set.
    public init(_ conditions: [FilterCondition]) {
        self.init(sets: [FilterConditionSet(conditions)])
    }

    /// Matches every pull request.
    public static let everything = PullRequestFilter()

    /// True when it keeps every pull request: no sets, or a set with no conditions.
    public var matchesEverything: Bool {
        sets.isEmpty || sets.contains { $0.conditions.isEmpty }
    }

    public func matches(_ pr: PullRequest, context: FilterContext) -> Bool {
        sets.isEmpty || sets.contains { $0.matches(pr, context: context) }
    }

    /// The pull requests that match, in the order given.
    public func pullRequests(in pullRequests: [PullRequest], context: FilterContext) -> [PullRequest] {
        pullRequests.filter { matches($0, context: context) }
    }

    /// The matches among the pull requests given, with a count by status.
    public func evaluate(_ pullRequests: [PullRequest], context: FilterContext) -> FilterEvaluation {
        var counts: [StatusSentence.Badge: Int] = [:]
        var matches: [PullRequest] = []
        for pr in pullRequests where self.matches(pr, context: context) {
            matches.append(pr)
            counts[context.status(pr).badge, default: 0] += 1
        }
        let byStatus = StatusSentence.Badge.allCases.compactMap { badge in
            counts[badge].map { FilterEvaluation.StatusCount(status: badge, count: $0) }
        }
        return FilterEvaluation(matches: matches, total: pullRequests.count, byStatus: byStatus)
    }

    /// The filter in plain words, such as "Blocked or changes requested, in acme/api, not by
    /// ci-bot. Or waiting on me and not a draft."
    public var summary: String { FilterSummary.text(for: self) }

    /// What is wrong with the filter, with where in it, or nil when it is fine.
    public func problem() -> (path: String, message: String)? {
        for (setPosition, set) in sets.enumerated() {
            for (position, condition) in set.conditions.enumerated() {
                if let problem = condition.problem() {
                    return ("sets[\(setPosition)].conditions[\(position)].\(problem.path)", problem.message)
                }
            }
        }
        return nil
    }

    /// The keys a filter object may hold, as `JSONKeyCheck` checks them.
    static let shape = JSONKeyCheck.Shape.object([
        "sets": .array(.object([
            "conditions": .array(.object(["field": .value, "operator": .value, "values": .array(.value)])),
        ])),
    ])

    /// Reads a filter written as JSON, such as `ctl filters evaluate --filter` takes. Problems
    /// name where in it and what is wrong, as a configuration file's do.
    public static func decode(_ data: Data, fileName: String = "filter") throws(LayoutFileError) -> PullRequestFilter {
        try JSONKeyCheck.check(data, fileName: fileName, allowed: shape, allowsSchemaKey: false)
        let filter: PullRequestFilter
        do {
            filter = try GitHubPRExplorerJSON.decoder().decode(PullRequestFilter.self, from: data)
        } catch let error as DecodingError {
            throw LayoutFileError.describe(error, fileName: fileName)
        } catch {
            throw LayoutFileError(fileName: fileName, problem: error.localizedDescription)
        }
        if let problem = filter.problem() {
            throw LayoutFileError(fileName: fileName, path: problem.path, problem: problem.message)
        }
        return filter
    }

    /// Sorted keys and pretty printed.
    public func encoded() throws -> Data {
        try GitHubPRExplorerJSON.encoder().encode(self)
    }
}

/// What a filter kept from a list of pull requests: the matches, how many there were to start
/// with, and how many matches have each status.
public struct FilterEvaluation: Sendable, Hashable {
    public struct StatusCount: Codable, Sendable, Hashable {
        public var status: StatusSentence.Badge
        public var count: Int

        /// Such as "3 blocked" or "2 changes requested".
        public var text: String { "\(count) \(FilterSummary.countWord(status))" }
    }

    public var matches: [PullRequest]
    /// How many pull requests the filter was given.
    public var total: Int
    /// In the badges' order, leaving out statuses no match has.
    public var byStatus: [StatusCount]

    public var count: Int { matches.count }

    /// "7 of 218 match"
    public var countText: String { "\(count) of \(total) match" }

    /// "3 blocked · 2 waiting · 2 ready", empty when nothing matches.
    public var breakdownText: String { byStatus.map(\.text).joined(separator: " · ") }

    /// "7 of 218 match, 3 blocked · 2 waiting · 2 ready"
    public var text: String { breakdownText.isEmpty ? countText : "\(countText), \(breakdownText)" }
}

/// Says a filter in plain words. Conditions in a set are joined with "and" when there are two
/// and with commas when there are more, and sets are sentences joined by "Or".
public enum FilterSummary {
    public static func text(for filter: PullRequestFilter) -> String {
        if filter.sets.isEmpty { return "Every open pull request." }
        let sentences = filter.sets.enumerated().map { position, set in
            let text = phrase(for: set)
            return position == 0 ? text.capitalizedFirst : "Or " + text
        }
        return sentences.map { $0 + "." }.joined(separator: " ")
    }

    static func phrase(for set: FilterConditionSet) -> String {
        let parts = set.conditions.map(phrase(for:))
        switch parts.count {
        case 0: return "any pull request"
        case 1: return parts[0]
        case 2: return "\(parts[0]) and \(parts[1])"
        default: return parts.joined(separator: ", ")
        }
    }

    static func phrase(for condition: FilterCondition) -> String {
        let not = condition.operator == .isNot
        let values = condition.values
        func alternatives(_ words: [String]) -> String {
            switch words.count {
            case 0: return ""
            case 1: return words[0]
            default: return words.dropLast().joined(separator: ", ") + " or " + words.last!
            }
        }
        switch condition.field {
        case .status:
            let words = values.map { StatusSentence.Badge(rawValue: $0).map(statusWord) ?? $0 }
            return (not ? "not " : "") + alternatives(words)
        case .organization, .repository:
            return (not ? "not in " : "in ") + alternatives(values)
        case .author:
            return (not ? "not by " : "by ") + alternatives(values.map { $0 == FilterValues.me ? "me" : $0 })
        case .reviewState:
            return (not ? "not " : "") + alternatives(values.map(reviewWord))
        case .draft:
            let wantsDraft = Set(values) == ["true"] ? true : Set(values) == ["false"] ? false : nil
            guard let wantsDraft else { return not ? "nothing" : "a draft or not" }
            return wantsDraft != not ? "a draft" : "not a draft"
        }
    }

    /// The badge's long name, lowercase, for the middle of a sentence.
    static func statusWord(_ badge: StatusSentence.Badge) -> String {
        switch badge {
        case .running: "CI running or queued"
        default: badge.name.prefix(1).lowercased() + badge.name.dropFirst()
        }
    }

    static func reviewWord(_ value: String) -> String {
        if value == FilterValues.waitingOnMe { return "waiting on me" }
        guard let state = ListFilter.ReviewState(rawValue: value) else { return value }
        return state.name.prefix(1).lowercased() + state.name.dropFirst()
    }

    /// The badge's short word for a count, such as "3 blocked".
    static func countWord(_ badge: StatusSentence.Badge) -> String {
        switch badge {
        case .changesRequested: "changes requested"
        case .threads: "with threads"
        case .failing: "failing"
        default: badge.label.lowercased()
        }
    }
}
