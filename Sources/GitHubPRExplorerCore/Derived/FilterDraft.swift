import Foundation

/// A filter while it is being edited in the window: the Filter popover and the popover that
/// edits a saved filter both hold one. It is the filter language's sets and conditions, with
/// an identity on each so a view can keep track of them while they move, and with room for a
/// condition that has no value yet.
///
/// It is not a second way to write a filter. `filter` gives it in the language, leaving out
/// what is not finished: a condition with no value, and a set with nothing finished in it.
public struct FilterDraft: Sendable, Hashable {
    public struct Condition: Sendable, Hashable, Identifiable {
        public let id: Int
        public var field: FilterField
        public var `operator`: FilterOperator
        public var values: [String]

        public var isFinished: Bool { !values.isEmpty }

        public var condition: FilterCondition { FilterCondition(field: field, `operator`, values: values) }
    }

    public struct ConditionSet: Sendable, Hashable, Identifiable {
        public let id: Int
        public var conditions: [Condition]
    }

    public private(set) var sets: [ConditionSet]
    /// Hands out the identities. A plain counter, so the same edits give the same draft.
    private var nextID = 0

    /// A draft of the filter given. A filter that keeps everything starts with no sets.
    public init(_ filter: PullRequestFilter = .everything) {
        sets = []
        for set in filter.sets where !set.conditions.isEmpty {
            var conditions: [Condition] = []
            for condition in set.conditions {
                conditions.append(Condition(id: makeID(), field: condition.field, operator: condition.operator,
                                            values: condition.values))
            }
            sets.append(ConditionSet(id: makeID(), conditions: conditions))
        }
    }

    private mutating func makeID() -> Int {
        nextID += 1
        return nextID
    }

    /// The draft in the filter language. Unfinished conditions are left out, and so is a set
    /// with nothing finished in it, so an empty line added a moment ago never widens the
    /// filter to everything.
    public var filter: PullRequestFilter {
        let finished = sets.map { set in FilterConditionSet(set.conditions.filter(\.isFinished).map(\.condition)) }
            .filter { !$0.conditions.isEmpty }
        return PullRequestFilter(sets: finished)
    }

    /// True when nothing is set, so the draft keeps every pull request.
    public var isEmpty: Bool { filter.sets.isEmpty }

    /// The fields used anywhere in the draft, for suggesting what to add next.
    public var usedFields: Set<FilterField> { Set(sets.flatMap { $0.conditions.map(\.field) }) }

    // MARK: Editing

    /// Adds a set holding one condition with no value yet, and gives the new condition's id.
    @discardableResult
    public mutating func addSet(field: FilterField = .status) -> Int {
        let condition = Condition(id: makeID(), field: field, operator: .is, values: [])
        sets.append(ConditionSet(id: makeID(), conditions: [condition]))
        return condition.id
    }

    /// Adds a condition with no value yet to a set, and gives its id. With no set yet, it
    /// starts the first one.
    @discardableResult
    public mutating func addCondition(toSet setID: Int?, field: FilterField? = nil) -> Int {
        guard let setID, let position = sets.firstIndex(where: { $0.id == setID }) else {
            return addSet(field: field ?? .status)
        }
        let used = Set(sets[position].conditions.map(\.field))
        let chosen = field ?? FilterField.allCases.first { !used.contains($0) } ?? .status
        let condition = Condition(id: makeID(), field: chosen, operator: .is, values: [])
        sets[position].conditions.append(condition)
        return condition.id
    }

    /// Removes a condition. A set left with nothing in it goes too.
    public mutating func removeCondition(_ id: Int) {
        for position in sets.indices {
            sets[position].conditions.removeAll { $0.id == id }
        }
        sets.removeAll { $0.conditions.isEmpty }
    }

    public mutating func removeSet(_ id: Int) {
        sets.removeAll { $0.id == id }
    }

    /// Changes a condition's field. Values of the old field mean nothing to the new one, so
    /// they are dropped.
    public mutating func setField(_ field: FilterField, of id: Int) {
        update(id) { condition in
            guard condition.field != field else { return }
            condition.field = field
            condition.values = []
        }
    }

    public mutating func setOperator(_ op: FilterOperator, of id: Int) {
        update(id) { $0.operator = op }
    }

    /// Adds a value as one more alternative. A value already there is not added twice. Draft
    /// takes one value, so choosing one replaces the other.
    public mutating func addValue(_ value: String, to id: Int) {
        update(id) { condition in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if condition.field == .draft {
                condition.values = [trimmed]
                return
            }
            let ignoresCase = condition.field.ignoresCase
            let present = condition.values.contains { ignoresCase ? $0.lowercased() == trimmed.lowercased() : $0 == trimmed }
            if !present { condition.values.append(trimmed) }
        }
    }

    public mutating func removeValue(_ value: String, from id: Int) {
        update(id) { $0.values.removeAll { $0 == value } }
    }

    /// Adds the value when it is missing and removes it when it is there, as a checked item does.
    public mutating func toggleValue(_ value: String, in id: Int) {
        guard let condition = condition(id) else { return }
        if condition.values.contains(value) { removeValue(value, from: id) } else { addValue(value, to: id) }
    }

    public func condition(_ id: Int) -> Condition? {
        sets.lazy.flatMap(\.conditions).first { $0.id == id }
    }

    /// Clears everything: Clear All.
    public mutating func removeAll() { sets = [] }

    private mutating func update(_ id: Int, _ change: (inout Condition) -> Void) {
        for setPosition in sets.indices {
            if let position = sets[setPosition].conditions.firstIndex(where: { $0.id == id }) {
                change(&sets[setPosition].conditions[position])
                return
            }
        }
    }
}

/// The values a condition can offer for its field, each with how many open pull requests have
/// it, so choosing a value shows at once what it would keep.
///
/// Values come from the open pull requests in the index, as the filter menu's did. Fixed
/// vocabularies (status, review state, draft) list every value in their own order, with a
/// count of 0 for what nothing has right now. Names from the index (organization, repository,
/// author) are listed most used first, and `@me` leads the authors.
public struct FilterValueChoices: Sendable {
    public struct Choice: Sendable, Hashable, Identifiable {
        public var value: String
        public var title: String
        /// Extra words to match while typing, such as an author's login under their name.
        public var detail: String?
        public var count: Int

        public var id: String { value }
    }

    public let field: FilterField
    public let choices: [Choice]

    public init(field: FilterField, pullRequests: [PullRequest], context: FilterContext, names: FilterValueNames) {
        self.field = field
        var counts: [String: Int] = [:]
        var spelling: [String: String] = [:]
        for pr in pullRequests where pr.state == .open {
            for value in field.values(of: pr, context: context) {
                let key = field.ignoresCase ? value.lowercased() : value
                counts[key, default: 0] += 1
                if spelling[key] == nil { spelling[key] = value }
            }
        }
        let viewerLogin = context.viewer.person.login
        if let fixed = FilterValues.fixed(for: field) {
            choices = fixed.map { value in
                Choice(value: value, title: names.title(value, field: field), count: counts[value] ?? 0)
            }
        } else {
            choices = counts.keys.map { key in
                let value = spelling[key] ?? key
                let detail: String? = field == .author && value != FilterValues.me ? value : nil
                return Choice(value: value, title: names.title(value, field: field), detail: detail, count: counts[key] ?? 0)
            }
            .filter { !(field == .author && $0.value.lowercased() == viewerLogin.lowercased()) }
            .sorted { lhs, rhs in
                if (lhs.value == FilterValues.me) != (rhs.value == FilterValues.me) { return lhs.value == FilterValues.me }
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
        }
    }

    /// The choices that match what is typed, by title, value or detail, ignoring case and
    /// accents. Those that start with it come first.
    public func matching(_ text: String) -> [Choice] {
        let wanted = text.trimmingCharacters(in: .whitespaces)
        guard !wanted.isEmpty else { return choices }
        func fold(_ string: String) -> String { string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
        let needle = fold(wanted)
        let found = choices.filter { choice in
            [choice.title, choice.value, choice.detail ?? ""].contains { fold($0).contains(needle) }
        }
        let starts = found.filter { [ $0.title, $0.value ].contains { fold($0).hasPrefix(needle) } }
        return starts + found.filter { !starts.contains($0) }
    }

    /// Whether a typed value can be used as it is, for a name the index does not hold yet.
    public func accepts(typed text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, FilterValues.fixed(for: field) == nil else { return false }
        return FilterCondition(field: field, values: [value]).problem() == nil
    }
}

/// How the window names a filter value: a status by its badge's long name, a review state in
/// words, a draft as Yes or No, `@me` as "me", and a person by their display name.
public struct FilterValueNames: Sendable {
    /// Display names by login, lowercased.
    private var people: [String: String]
    private var shorthands: Shorthands

    public init(pullRequests: [PullRequest] = [], shorthands: Shorthands = .none) {
        var people: [String: String] = [:]
        for pr in pullRequests where people[pr.author.login.lowercased()] == nil {
            people[pr.author.login.lowercased()] = pr.author.displayName
        }
        self.people = people
        self.shorthands = shorthands
    }

    public func title(_ value: String, field: FilterField) -> String {
        switch field {
        case .status:
            return StatusSentence.Badge(rawValue: value)?.name ?? value
        case .reviewState:
            if value == FilterValues.waitingOnMe { return "Waiting on me" }
            return ListFilter.ReviewState(rawValue: value)?.name ?? value
        case .draft:
            return value == "true" ? "Yes" : value == "false" ? "No" : value
        case .author:
            if value == FilterValues.me { return "Me" }
            if let short = shorthands.shorthand(.person, for: value) { return short }
            return people[value.lowercased()] ?? value
        case .repository:
            return shorthands.shorthand(.repository, for: value) ?? value
        case .organization:
            return value
        }
    }
}

extension SavedFilter {
    /// An id made from a name, such as `blocked-in-api` from "Blocked in api", that none of
    /// `taken` has. Everything's id is always taken.
    public static func id(forName name: String, taken: some Collection<String>) -> String {
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
        var slug = ""
        for character in folded {
            if character.isASCII, character.isLetter || character.isNumber {
                slug.append(character)
            } else if !slug.isEmpty, slug.last != "-" {
                slug.append("-")
            }
        }
        while slug.hasSuffix("-") { slug.removeLast() }
        if slug.isEmpty { slug = "filter" }
        if slug.count > 48 {
            slug = String(slug.prefix(48))
            while slug.hasSuffix("-") { slug.removeLast() }
        }
        let used = Set(taken).union([everythingID])
        guard used.contains(slug) else { return slug }
        var number = 2
        while used.contains("\(slug)-\(number)") { number += 1 }
        return "\(slug)-\(number)"
    }

    /// The grouping it asks for, as the list knows it. A level the list does not know is
    /// dropped, and none means it leaves the list's grouping as it is.
    public var grouping: ListGrouping? {
        let levels = groupBy.compactMap(ListGrouping.Property.init(rawValue:))
        return levels.isEmpty ? nil : ListGrouping(levels)
    }
}

extension ListGrouping {
    /// The grouping as a saved filter writes it, such as `["organization", "repository"]`.
    public var savedFilterGroupBy: [String] { levels.map(\.rawValue) }
}
