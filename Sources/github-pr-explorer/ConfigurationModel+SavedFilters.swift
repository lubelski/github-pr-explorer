import GitHubPRExplorerCore

/// Saved filters, changed from the main window or from Settings, Saved Filters. Each change is
/// one write of `saved-filters.json` and one version in History, through the store.
extension ConfigurationModel: SavedFilterStore {
    /// Who a change from here is recorded as. Settings passes its own name.
    private func author(_ fromSettings: Bool) -> ChangeAuthor { fromSettings ? .settingsWindow : .mainWindow }

    /// Runs a change and says whether it was made. A refused change is logged and beeps.
    private func attempt(_ action: () throws -> Void) -> Bool {
        change(action)
    }

    @discardableResult
    func addSavedFilter(_ saved: SavedFilter, at position: Int?) -> Bool {
        attempt { try store.addSavedFilter(saved, at: position, author: .mainWindow) }
    }

    @discardableResult
    func changeSavedFilter(id: String, _ change: @escaping (inout SavedFilter) -> Void) -> Bool {
        changeSavedFilter(id: id, fromSettings: false, change)
    }

    @discardableResult
    func changeSavedFilter(id: String, fromSettings: Bool, _ change: @escaping (inout SavedFilter) -> Void) -> Bool {
        attempt { try store.changeSavedFilter(id: id, author: author(fromSettings), change) }
    }

    @discardableResult
    func moveSavedFilter(id: String, to position: Int) -> Bool {
        moveSavedFilter(id: id, to: position, fromSettings: false)
    }

    @discardableResult
    func moveSavedFilter(id: String, to position: Int, fromSettings: Bool) -> Bool {
        attempt { try store.moveSavedFilter(id: id, to: position, author: author(fromSettings)) }
    }

    @discardableResult
    func removeSavedFilter(id: String) -> Bool {
        removeSavedFilter(id: id, fromSettings: false)
    }

    @discardableResult
    func removeSavedFilter(id: String, fromSettings: Bool) -> Bool {
        attempt { try store.removeSavedFilter(id: id, author: author(fromSettings)) }
    }
}
