import Foundation
import Testing
@testable import GitHubPRExplorerCore

/// `saved-filters.json` through `ConfigurationStore`, always in a temporary folder.
@Suite struct SavedFilterStoreTests {
    let config = TemporaryConfiguration()

    var blockedInAPI: SavedFilter {
        SavedFilter(id: "blocked-in-api", name: "Blocked in api",
                    filter: PullRequestFilter([FilterCondition(field: .status, values: ["blocked"]),
                                               FilterCondition(field: .repository, values: ["acme/api"])]),
                    groupBy: ["author"])
    }

    @Test func aNewFolderStartsWithEverythingAndTodaysViews() throws {
        let snapshot = try config.store.prepare(author: .app)
        #expect(config.exists("saved-filters.json"))
        #expect(try SavedFilterFile.decode(Data(config.read("saved-filters.json").utf8)) == .defaults)
        #expect(snapshot.filters.map(\.id) == ["everything", "needs-my-review", "mine"])
        #expect(snapshot.filters.map(\.name) == ["Everything", "Needs my review", "Mine"])
        #expect(snapshot.problems.isEmpty, "\(snapshot.problems)")
    }

    @Test func aFolderWithNoFileUsesTheDefaultsAndDoesNotWriteOne() throws {
        try config.store.prepare(author: .app)
        try FileManager.default.removeItem(at: config.store.savedFiltersURL)
        let snapshot = config.store.reload(committingAs: .editedOnDisk)
        #expect(snapshot.savedFilters == SavedFilterFile.defaults.savedFilters)
        #expect(snapshot.problems.isEmpty)
        // A second prepare, as at the next launch, does not write it back.
        try config.store.prepare(author: .app)
        #expect(!config.exists("saved-filters.json"))
        // The first change writes it, with the defaults kept.
        try config.store.addSavedFilter(blockedInAPI, author: .commandLine)
        #expect(config.store.snapshot.savedFilters.map(\.id) == ["needs-my-review", "mine", "blocked-in-api"])
    }

    @Test func addChangeMoveRemoveAreEachAVersion() throws {
        let store = config.store
        try store.addSavedFilter(blockedInAPI, author: .commandLine)
        #expect(store.snapshot.filters.map(\.id) == ["everything", "needs-my-review", "mine", "blocked-in-api"])

        try store.moveSavedFilter(id: "blocked-in-api", to: 1, author: .commandLine)
        #expect(store.snapshot.savedFilters.map(\.id) == ["blocked-in-api", "needs-my-review", "mine"])

        try store.changeSavedFilter(id: "mine", author: .settingsWindow) {
            $0.name = "My pull requests"
            $0.showsAsTab = false
            $0.groupBy = ["organization", "repository"]
        }
        let mine = try #require(store.snapshot.filter(id: "mine"))
        #expect(mine.name == "My pull requests" && !mine.showsAsTab && mine.groupBy == ["organization", "repository"])

        try store.removeSavedFilter(id: "needs-my-review", author: .mcp)
        #expect(store.snapshot.savedFilters.map(\.id) == ["blocked-in-api", "mine"])

        let versions = try config.versions()
        #expect(versions.map(\.summary).prefix(4) == [
            "Removed the saved filter Needs my review",
            "Saved filter Mine: renamed it My pull requests, grouped it by organization, then repository, took it off the tab bar",
            "Moved the saved filter Blocked in api to position 1",
            "Added the saved filter Blocked in api",
        ])
        #expect(versions[0].author == "MCP")
        #expect(versions[1].author == "Settings window")
        #expect(versions[0].files == ["saved-filters.json"])
    }

    @Test func everythingCannotBeTouched() throws {
        let store = config.store
        #expect(throws: ConfigurationError.self) { try store.removeSavedFilter(id: "everything", author: .commandLine) }
        #expect(throws: ConfigurationError.self) { try store.moveSavedFilter(id: "everything", to: 2, author: .commandLine) }
        #expect(throws: ConfigurationError.self) { try store.changeSavedFilter(id: "everything", author: .commandLine) { $0.name = "All" } }
        var copy = blockedInAPI
        copy.id = "everything"
        #expect(throws: ConfigurationError.self) { try store.addSavedFilter(copy, author: .commandLine) }
        #expect(throws: ConfigurationError.self) { try store.changeSavedFilter(id: "mine", author: .commandLine) { $0.id = "everything" } }
        #expect(store.snapshot.filters.first == .everything)
    }

    @Test func refusesWhatTheFileCannotHold() throws {
        let store = config.store
        try store.addSavedFilter(blockedInAPI, author: .commandLine)
        #expect(throws: ConfigurationError.self) { try store.addSavedFilter(blockedInAPI, author: .commandLine) }
        #expect(throws: ConfigurationError.self) { try store.changeSavedFilter(id: "mine", author: .commandLine) { $0.id = "blocked-in-api" } }
        #expect(throws: ConfigurationError.self) { try store.changeSavedFilter(id: "mine", author: .commandLine) { $0.groupBy = ["a", "b", "c"] } }
        #expect(throws: ConfigurationError.self) { try store.changeSavedFilter(id: "mine", author: .commandLine) { $0.name = " " } }
        #expect(throws: ConfigurationError.self) { try store.changeSavedFilter(id: "mine", author: .commandLine) { $0.id = "Not OK" } }
        #expect(throws: ConfigurationError.self) { try store.moveSavedFilter(id: "mine", to: 9, author: .commandLine) }
        #expect(throws: ConfigurationError.self) { try store.removeSavedFilter(id: "nope", author: .commandLine) }
        #expect(throws: ConfigurationError.self) {
            try store.changeSavedFilter(id: "mine", author: .commandLine) {
                $0.filter = PullRequestFilter([FilterCondition(field: .status, values: ["purple"])])
            }
        }
        #expect(store.snapshot.savedFilters.map(\.id) == ["needs-my-review", "mine", "blocked-in-api"])
    }

    @Test func aBrokenFileKeepsTheLastGoodVersionAndRefusesChanges() throws {
        let store = config.store
        try store.addSavedFilter(blockedInAPI, author: .commandLine)
        try config.write(#"{"formatVersion": 1, "savedFilters": [{"id": "x", "name": "X", "filter": {"sets": [{"conditions": [{"field": "colour", "values": ["red"]}]}]}}]}"#,
                         to: "saved-filters.json")
        let snapshot = store.reload(committingAs: .editedOnDisk)
        let problem = try #require(snapshot.problems.first { $0.file == "saved-filters.json" })
        #expect(problem.path == "savedFilters[0].filter.sets[0].conditions[0].field")
        #expect(problem.lastGoodInUse)
        #expect(snapshot.savedFilters.map(\.id) == ["needs-my-review", "mine", "blocked-in-api"])
        #expect(throws: ConfigurationError.self) { try store.removeSavedFilter(id: "mine", author: .commandLine) }

        // A fresh store, as at the next launch, falls back to the recorded version too.
        let fresh = ConfigurationStore(folder: config.folder).reload()
        #expect(fresh.savedFilters.map(\.id) == ["needs-my-review", "mine", "blocked-in-api"])
    }

    @Test(arguments: [
        (#"{"savedFilters": []}"#, "formatVersion"),
        (#"{"formatVersion": 2, "savedFilters": []}"#, "formatVersion"),
        (#"{"formatVersion": 1, "savedFilters": [{"id": "a", "name": "A", "filter": {"sets": []}, "colour": "red"}]}"#, "savedFilters[0].colour"),
        (#"{"formatVersion": 1, "savedFilters": [{"id": "a", "name": "A", "filter": {"sets": []}}, {"id": "a", "name": "B", "filter": {"sets": []}}]}"#, "savedFilters[1].id"),
        (#"{"formatVersion": 1, "savedFilters": [{"id": "everything", "name": "A", "filter": {"sets": []}}]}"#, "savedFilters[0].id"),
        (#"{"formatVersion": 1, "savedFilters": [{"id": "a", "name": "A", "filter": {"sets": []}, "groupBy": ["repository", "repository"]}]}"#, "savedFilters[0].groupBy[1]"),
        (#"{"formatVersion": 1, "savedFilters": [{"id": "a", "name": "A", "filter": {"sets": []}, "groupBy": ["none"]}]}"#, "savedFilters[0].groupBy[0]"),
        (#"{"formatVersion": 1, "savedFilters": [{"id": "a", "name": "A"}]}"#, "savedFilters[0].filter"),
    ])
    func badFilesNameWhere(text: String, path: String) {
        #expect {
            try SavedFilterFile.decode(Data(text.utf8))
        } throws: { error in
            (error as? LayoutFileError)?.path == path
        }
    }

    @Test func groupByAndShowsAsTabMayBeLeftOut() throws {
        let text = #"{"formatVersion": 1, "savedFilters": [{"id": "a", "name": "A", "filter": {"sets": []}}]}"#
        let file = try SavedFilterFile.decode(Data(text.utf8))
        #expect(file.savedFilters[0].groupBy.isEmpty)
        #expect(file.savedFilters[0].showsAsTab)
        // A grouping this file does not know yet, such as one the window adds later, is kept.
        let later = #"{"formatVersion": 1, "savedFilters": [{"id": "a", "name": "A", "filter": {"sets": []}, "groupBy": ["organization", "repository"]}]}"#
        #expect(try SavedFilterFile.decode(Data(later.utf8)).savedFilters[0].groupBy == ["organization", "repository"])
    }
}
