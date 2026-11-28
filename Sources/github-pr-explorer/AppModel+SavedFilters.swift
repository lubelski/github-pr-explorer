import Foundation
import GitHubPRExplorerCore

/// Where the main window writes saved filters. `ConfigurationModel` is the one the app uses, so
/// every change lands in `saved-filters.json` through `ConfigurationStore`, is kept in History,
/// and comes back to the window through `AppModel.apply`, as a change made on disk does.
@MainActor
protocol SavedFilterStore: AnyObject {
    /// Each returns whether the change was made. A refused change is logged and beeps.
    @discardableResult func addSavedFilter(_ saved: SavedFilter, at position: Int?) -> Bool
    @discardableResult func changeSavedFilter(id: String, _ change: @escaping (inout SavedFilter) -> Void) -> Bool
    @discardableResult func moveSavedFilter(id: String, to position: Int) -> Bool
    @discardableResult func removeSavedFilter(id: String) -> Bool
}

/// The list's tabs: Everything and the saved filters, a filter applied on a tab and not saved,
/// and the changes the window makes to saved filters.
extension AppModel {
    /// The saved filter chosen, or Everything when its id is gone.
    var selectedFilter: SavedFilter {
        savedFilters.first { $0.id == selectedFilterID } ?? .everything
    }

    /// The tabs in order: Everything, the saved filters shown as tabs, and last a saved filter
    /// chosen from the » menu while it is chosen.
    var tabFilters: [SavedFilter] {
        var tabs = savedFilters.filter { $0.isEverything || $0.showsAsTab }
        if let temporaryFilterID, let temporary = savedFilters.first(where: { $0.id == temporaryFilterID }),
           !tabs.contains(where: { $0.id == temporary.id }) {
            tabs.append(temporary)
        }
        return tabs
    }

    /// True when the tab is the » menu's saved filter, shown for as long as it is chosen.
    func isTemporaryTab(_ id: String) -> Bool {
        id == temporaryFilterID && savedFilters.first { $0.id == id }?.showsAsTab == false
    }

    /// The saved filters that are not tabs, for the » menu. The tabs that do not fit are added
    /// to it by the tab bar.
    var hiddenFilters: [SavedFilter] {
        savedFilters.filter { !$0.isEverything && !$0.showsAsTab && $0.id != temporaryFilterID }
    }

    /// The filter the list shows: the one applied on the tab, or else the tab's own.
    var currentFilter: PullRequestFilter {
        appliedFilter ?? selectedFilter.filter
    }

    /// True when a filter is applied on the chosen tab that its saved filter does not have, so
    /// the tab shows a dot and the line under the tabs offers Save and Clear.
    var hasUnsavedFilter: Bool {
        appliedFilter.map { $0 != selectedFilter.filter } ?? false
    }

    /// How many open pull requests each tab holds within the search. The chosen tab counts
    /// what the list shows, a filter applied on it included.
    var countsByFilter: [String: Int] {
        let found = searchedOpen
        let context = filterContext
        var counts: [String: Int] = [:]
        for saved in savedFilters {
            let filter = saved.id == selectedFilterID ? currentFilter : saved.filter
            counts[saved.id] = filter.matchesEverything ? found.count : found.count { filter.matches($0, context: context) }
        }
        return counts
    }

    /// The open pull requests in the index, which a filter's count is out of.
    var openPullRequests: [PullRequest] {
        index.allPullRequests.filter { $0.state == .open }
    }

    /// What a filter keeps of the open pull requests, with a count by status, for the
    /// popovers' footers. The search is left out: the count is the filter's own.
    func evaluate(_ filter: PullRequestFilter) -> FilterEvaluation {
        filter.evaluate(openPullRequests, context: filterContext)
    }

    /// How the popovers name values: people by their names, and shorthands where set.
    var filterValueNames: FilterValueNames {
        FilterValueNames(pullRequests: index.allPullRequests, shorthands: shorthands)
    }

    /// The values a condition offers for a field, with counts.
    func valueChoices(for field: FilterField) -> FilterValueChoices {
        FilterValueChoices(field: field, pullRequests: index.allPullRequests, context: filterContext, names: filterValueNames)
    }

    // MARK: Choosing

    /// Chooses a saved filter. One that is not a tab shows as a temporary last tab.
    func chooseFilter(_ id: String) {
        if let saved = savedFilters.first(where: { $0.id == id }), !saved.isEverything, !saved.showsAsTab {
            temporaryFilterID = id
        }
        selectedFilterID = id
    }

    /// Called when the chosen tab changes: a filter applied on the old tab is dropped, the
    /// temporary tab goes when another is chosen, and a saved filter with a grouping groups
    /// the list by it.
    func didChooseFilter(from old: String) {
        appliedFilter = nil
        showsFilterPopover = false
        if temporaryFilterID != selectedFilterID { temporaryFilterID = nil }
        if let grouping = selectedFilter.grouping { listGrouping = grouping }
    }

    /// Takes in the saved filters after a change from anywhere: the window, Settings, a hand
    /// edit, `ctl` or MCP. A chosen filter that is gone gives way to Everything.
    func applySavedFilters(_ filters: [SavedFilter]) {
        guard filters != savedFilters else { return }
        let before = savedFilters.first { $0.id == selectedFilterID }
        savedFilters = filters
        if !filters.contains(where: { $0.id == selectedFilterID }) {
            selectedFilterID = SavedFilter.everythingID
        } else if let before, let now = filters.first(where: { $0.id == before.id }),
                  before.groupBy != now.groupBy, let grouping = now.grouping {
            // The chosen filter's grouping was changed, such as in its popover: the list follows.
            listGrouping = grouping
        }
        if let temporaryFilterID, !filters.contains(where: { $0.id == temporaryFilterID }) {
            self.temporaryFilterID = nil
        }
        if let editingFilterID, !filters.contains(where: { $0.id == editingFilterID }) {
            self.editingFilterID = nil
        }
    }

    // MARK: Applying

    /// Apply in the Filter popover. A filter the tab already has is no change, so the dot
    /// does not show.
    func applyFilter(_ filter: PullRequestFilter) {
        appliedFilter = filter == selectedFilter.filter ? nil : filter
    }

    /// Clear on the line under the tabs: back to the tab's own filter.
    func clearAppliedFilter() {
        appliedFilter = nil
    }

    // MARK: Changing saved filters

    /// Whether the window can change saved filters at all.
    var canChangeSavedFilters: Bool { savedFilterStore != nil }

    /// Saves a filter as a new saved filter, last among the tabs, and chooses it. With
    /// `keepsGrouping`, the list's grouping goes with it.
    @discardableResult
    func saveNewFilter(_ filter: PullRequestFilter, name: String, keepsGrouping: Bool) -> Bool {
        guard let savedFilterStore else { return false }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let id = SavedFilter.id(forName: trimmed, taken: savedFilters.map(\.id))
        let saved = SavedFilter(id: id, name: trimmed, filter: filter,
                                groupBy: keepsGrouping ? listGrouping.savedFilterGroupBy : [])
        guard savedFilterStore.addSavedFilter(saved, at: nil) else { return false }
        selectedFilterID = id
        return true
    }

    /// Update on a tab that is a saved filter: the filter applied on it becomes its own.
    @discardableResult
    func updateSelectedFilter(with filter: PullRequestFilter, keepsGrouping: Bool) -> Bool {
        let saved = selectedFilter
        guard !saved.isEverything, let savedFilterStore else { return false }
        let groupBy = keepsGrouping ? listGrouping.savedFilterGroupBy : saved.groupBy
        guard savedFilterStore.changeSavedFilter(id: saved.id, { $0.filter = filter; $0.groupBy = groupBy }) else { return false }
        appliedFilter = nil
        return true
    }

    /// Save in a saved filter's popover.
    @discardableResult
    func saveEdits(to id: String, name: String, filter: PullRequestFilter, groupBy: [String], showsAsTab: Bool) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let savedFilterStore else { return false }
        let done = savedFilterStore.changeSavedFilter(id: id) { saved in
            saved.name = trimmed
            saved.filter = filter
            saved.groupBy = groupBy
            saved.showsAsTab = showsAsTab
        }
        // A filter taken off the tab bar while chosen stays on screen as the temporary tab.
        if done, !showsAsTab, selectedFilterID == id { temporaryFilterID = id }
        return done
    }

    @discardableResult
    func renameFilter(_ id: String, to name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let savedFilterStore else { return false }
        return savedFilterStore.changeSavedFilter(id: id) { $0.name = trimmed }
    }

    /// A copy just after the original, named "… copy", shown as a tab, and chosen.
    func duplicateFilter(_ id: String) {
        guard let savedFilterStore, let original = savedFilters.first(where: { $0.id == id }), !original.isEverything,
              let position = savedFilters.firstIndex(where: { $0.id == id }) else { return }
        let name = Self.copyName(original.name, taken: Set(savedFilters.map(\.name)))
        var copy = original
        copy.id = SavedFilter.id(forName: name, taken: savedFilters.map(\.id))
        copy.name = name
        copy.showsAsTab = true
        // `position` counts Everything, so it is the 1-based place just after the original.
        if savedFilterStore.addSavedFilter(copy, at: position + 1) { selectedFilterID = copy.id }
    }

    static func copyName(_ name: String, taken: Set<String>) -> String {
        var candidate = "\(name) copy"
        var number = 2
        while taken.contains(candidate) {
            candidate = "\(name) copy \(number)"
            number += 1
        }
        return candidate
    }

    /// Remove from Tab Bar: the filter stays, in the » menu and Settings.
    func removeFromTabBar(_ id: String) {
        guard let savedFilterStore else { return }
        if savedFilterStore.changeSavedFilter(id: id, { $0.showsAsTab = false }), selectedFilterID == id {
            temporaryFilterID = id
        }
    }

    /// Shows a saved filter as a tab again, last among the tabs.
    func showInTabBar(_ id: String) {
        savedFilterStore?.changeSavedFilter(id: id) { $0.showsAsTab = true }
    }

    /// Deletes a saved filter. It stays in History and can be restored from there.
    func deleteFilter(_ id: String) {
        guard let savedFilterStore else { return }
        if editingFilterID == id { editingFilterID = nil }
        savedFilterStore.removeSavedFilter(id: id)
    }
}
