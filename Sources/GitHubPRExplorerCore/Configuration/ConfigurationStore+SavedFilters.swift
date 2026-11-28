import Foundation

/// Adding, changing, moving and removing saved filters. Each change writes `saved-filters.json`
/// whole, atomically, and records it as one version. Everything is built in and none of these
/// touch it.
extension ConfigurationStore {
    /// Adds a saved filter, last or at `position`: 1 is first after Everything.
    @discardableResult
    public func addSavedFilter(_ saved: SavedFilter, at position: Int? = nil, author: ChangeAuthor) throws(ConfigurationError) -> SavedFilter {
        try changeSavedFilters(author: author, summary: "Added the saved filter \(saved.name)") { (filters) throws(ConfigurationError) in
            if saved.id == SavedFilter.everythingID {
                throw ConfigurationError("Everything is built in and always first. Pick another id.")
            }
            if filters.contains(where: { $0.id == saved.id }) {
                throw ConfigurationError("A saved filter with the id \"\(saved.id)\" already exists. Pick another id, or change that one.")
            }
            try Self.check(saved)
            let index = try Self.index(for: position ?? filters.count + 1, count: filters.count + 1)
            filters.insert(saved, at: index)
        }
        return saved
    }

    /// Changes one saved filter. The change may give it a new id, as long as no other filter has it.
    @discardableResult
    public func changeSavedFilter(id: String, author: ChangeAuthor,
                                  _ change: (inout SavedFilter) -> Void) throws(ConfigurationError) -> SavedFilter {
        var changed: SavedFilter?
        try changeSavedFilters(author: author, summary: nil) { (filters) throws(ConfigurationError) in
            let index = try Self.existing(id, in: filters)
            var saved = filters[index]
            change(&saved)
            if saved.id != id, filters.contains(where: { $0.id == saved.id }) {
                throw ConfigurationError("A saved filter with the id \"\(saved.id)\" already exists. Pick another id.")
            }
            try Self.check(saved)
            filters[index] = saved
            changed = saved
        } summarize: { before, after in
            guard let old = before.first(where: { $0.id == id }), let new = changed else { return "Changed the saved filter \(id)" }
            return Self.describeChange(from: old, to: new)
        }
        return changed!
    }

    /// Moves a saved filter to `position`: 1 is first after Everything.
    public func moveSavedFilter(id: String, to position: Int, author: ChangeAuthor) throws(ConfigurationError) {
        var name = id
        try changeSavedFilters(author: author, summary: nil) { (filters) throws(ConfigurationError) in
            let from = try Self.existing(id, in: filters)
            let to = try Self.index(for: position, count: filters.count)
            let saved = filters.remove(at: from)
            filters.insert(saved, at: to)
            name = saved.name
        } summarize: { _, _ in
            "Moved the saved filter \(name) to position \(position)"
        }
    }

    /// Removes a saved filter. It stays in History and can be restored.
    public func removeSavedFilter(id: String, author: ChangeAuthor) throws(ConfigurationError) {
        var name = id
        try changeSavedFilters(author: author, summary: nil) { (filters) throws(ConfigurationError) in
            let index = try Self.existing(id, in: filters)
            name = filters[index].name
            filters.remove(at: index)
        } summarize: { _, _ in
            "Removed the saved filter \(name)"
        }
    }

    /// Replaces the whole list in one version, such as after a drag in Settings.
    public func replaceSavedFilters(_ savedFilters: [SavedFilter], author: ChangeAuthor, summary: String) throws(ConfigurationError) {
        try changeSavedFilters(author: author, summary: summary) { (filters) throws(ConfigurationError) in
            filters = savedFilters
        }
    }

    // MARK: Helpers

    /// Reads the folder, refuses when `saved-filters.json` has a problem, changes the list,
    /// checks the result as a file, writes it, and records the change.
    private func changeSavedFilters(author: ChangeAuthor, summary: String?,
                                    _ change: (inout [SavedFilter]) throws(ConfigurationError) -> Void,
                                    summarize: (([SavedFilter], [SavedFilter]) -> String)? = nil) throws(ConfigurationError) {
        try prepare(author: author)
        if let problem = snapshot.problems.first(where: { $0.file == SavedFilterFile.fileName && $0.refusesFile }) {
            throw ConfigurationError("\(SavedFilterFile.fileName) has a problem, so it was not changed: \(problem). Fix the file, or restore an earlier version from History.")
        }
        let before = snapshot.savedFilters
        var filters = before
        try change(&filters)
        let file = SavedFilterFile(savedFilters: filters)
        let data: Data
        do { data = try file.encoded() } catch { throw ConfigurationError("Could not encode the saved filters: \(error)") }
        do throws(LayoutFileError) {
            _ = try SavedFilterFile.decode(data)
        } catch {
            throw ConfigurationError(error.description)
        }
        try write(data, to: SavedFilterFile.fileName)
        reload(committingAs: author, summary: summary ?? summarize?(before, filters) ?? "Changed the saved filters")
    }

    private static func check(_ saved: SavedFilter) throws(ConfigurationError) {
        if let problem = saved.problem() {
            throw ConfigurationError("\(problem.path): \(problem.message).".replacingOccurrences(of: "..", with: "."))
        }
    }

    private static func existing(_ id: String, in filters: [SavedFilter]) throws(ConfigurationError) -> Int {
        if id == SavedFilter.everythingID {
            throw ConfigurationError("Everything is built in: it is always first and cannot be renamed, moved, changed or removed.")
        }
        guard let index = filters.firstIndex(where: { $0.id == id }) else {
            let ids = filters.map(\.id)
            throw ConfigurationError("No saved filter has the id \"\(id)\". Saved filters: \(ids.isEmpty ? "none" : ids.joined(separator: ", ")).")
        }
        return index
    }

    /// A 1-based position after Everything, as a 0-based index into the saved filters.
    private static func index(for position: Int, count: Int) throws(ConfigurationError) -> Int {
        guard (1...max(count, 1)).contains(position) else {
            throw ConfigurationError("The position is from 1, first after Everything, to \(max(count, 1)), not \(position).")
        }
        return position - 1
    }

    static func describeChange(from old: SavedFilter, to new: SavedFilter) -> String {
        var parts: [String] = []
        if old.name != new.name { parts.append("renamed it \(new.name)") }
        if old.id != new.id { parts.append("gave it the id \(new.id)") }
        if old.filter != new.filter { parts.append("changed its conditions") }
        if old.groupBy != new.groupBy {
            parts.append(new.groupBy.isEmpty ? "turned off its grouping" : "grouped it by \(new.groupBy.joined(separator: ", then "))")
        }
        if old.showsAsTab != new.showsAsTab { parts.append(new.showsAsTab ? "showed it as a tab" : "took it off the tab bar") }
        let what = parts.isEmpty ? "changed nothing" : parts.joined(separator: ", ")
        return "Saved filter \(old.name): \(what)"
    }
}
