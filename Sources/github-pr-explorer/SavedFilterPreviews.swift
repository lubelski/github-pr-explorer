import AppKit
import GitHubPRExplorerCore
import SwiftUI

/// The render states for saved filters as tabs, the Filter popover, editing a saved filter on
/// its tab, and Settings, Saved Filters (Figma rows 11 and 13). Each fills a temporary
/// configuration folder of its own, removed when the renders are done. The data is the mock
/// world.
///
/// A popover or a menu cannot be drawn offscreen, so a popover's content is drawn over the
/// window where it would open, in a popover's rounded frame with a shadow, and the tab's menu
/// is drawn as a plain list of its items. The content is the real view.
@MainActor
enum SavedFilterPreviews {
    static let size = CGSize(width: 1560, height: 940)

    // MARK: Sample saved filters, placeholder names only

    static let blockedInAPI = SavedFilter(
        id: "blocked-in-api", name: "Blocked in api",
        filter: PullRequestFilter([FilterCondition(field: .status, values: ["blocked"]),
                                   FilterCondition(field: .repository, values: ["acme/api"])]),
        groupBy: ["author"])
    static let agents = SavedFilter(
        id: "agent-pull-requests", name: "Agent pull requests",
        filter: PullRequestFilter([FilterCondition(field: .author, values: [MockCast.agentOne.login, MockCast.agentTwo.login])]),
        showsAsTab: false)
    static let globex = SavedFilter(
        id: "globex", name: "Globex",
        filter: PullRequestFilter([FilterCondition(field: .organization, values: ["globex"])]),
        groupBy: ["repository"], showsAsTab: false)
    static let readyToMerge = SavedFilter(
        id: "ready-to-merge", name: "Ready to merge",
        filter: PullRequestFilter([FilterCondition(field: .status, values: ["ready"]),
                                   FilterCondition(field: .draft, values: ["false"])]))

    /// The filter Figma row 11 draws: blocked or changes requested in api or web, not by a bot,
    /// or waiting on me and not a draft.
    static let figmaFilter = PullRequestFilter(sets: [
        FilterConditionSet([FilterCondition(field: .status, values: ["blocked", "changesRequested"]),
                            FilterCondition(field: .repository, values: ["acme/api", "acme/web"]),
                            FilterCondition(field: .author, .isNot, values: [MockCast.deployPreviewBot.login])]),
        FilterConditionSet([FilterCondition(field: .reviewState, values: [FilterValues.waitingOnMe]),
                            FilterCondition(field: .draft, values: ["false"])]),
    ])

    /// A filter far longer than anyone writes, to show the middle scrolls and the top and
    /// bottom stay put.
    static let longFilter = PullRequestFilter(sets: figmaFilter.sets + [
        FilterConditionSet([FilterCondition(field: .organization, values: ["globex"]),
                            FilterCondition(field: .status, .isNot, values: ["draft", "ready"])]),
        FilterConditionSet([FilterCondition(field: .author, values: [MockCast.samRivera.login, MockCast.maxChen.login,
                                                                     MockCast.joLindqvist.login, MockCast.lenaOkafor.login,
                                                                     MockCast.tomasReyes.login, MockCast.miraHolm.login]),
                            FilterCondition(field: .reviewState, values: ["changesRequested", "reviewRequired"])]),
        FilterConditionSet([FilterCondition(field: .repository, values: ["acme/infra", "acme/docs", "globex/billing"]),
                            FilterCondition(field: .status, values: ["failing", "running"])]),
    ])

    /// A configuration whose saved filters are the defaults, two more tabs, and two kept off
    /// the tab bar.
    static func filterStore(_ filters: [SavedFilter] = [blockedInAPI, readyToMerge, agents, globex]) -> ConfigurationStore {
        let store = SettingsPreviews.store()
        _ = try? store.prepare(author: .app)
        for filter in filters { _ = try? store.addSavedFilter(filter, author: .mainWindow) }
        return store
    }

    /// The main window over that configuration, with the window writing saved filters to it
    /// and taking its changes back, as the app does.
    static func app(_ store: ConfigurationStore = filterStore(), configure: (AppModel) -> Void = { _ in }) -> AppModel {
        let world = MockWorld.standard
        let configuration = SettingsPreviews.model(store)
        let app = AppModel(index: world.index, now: world.now, library: .builtIn(), selection: MockWorld.workedExample, build: .preview)
        app.savedFilterStore = configuration
        configuration.onApply = { [weak app] snapshot, previous in app?.apply(snapshot, previous: previous) }
        app.apply(configuration.snapshot, previous: nil)
        configure(app)
        return app
    }

    static func window(_ app: AppModel) -> AnyView {
        AnyView(MainWindowView(model: app, updater: .unavailable())
            .environment(\.hidesBotEventsInActivity, app.hidesBotEventsInActivity))
    }

    /// The window with a popover's content drawn where it opens: `at` is its top-leading
    /// corner in the window's content.
    static func window(_ app: AppModel, popover: some View, at origin: CGPoint,
                       second: (view: AnyView, origin: CGPoint)? = nil) -> AnyView {
        AnyView(ZStack(alignment: .topLeading) {
            MainWindowView(model: app, updater: .unavailable())
                .environment(\.hidesBotEventsInActivity, app.hidesBotEventsInActivity)
            popover
                .modifier(PopoverChrome())
                .offset(x: origin.x, y: origin.y)
            if let second {
                second.view
                    .modifier(PopoverChrome())
                    .offset(x: second.origin.x, y: second.origin.y)
            }
        })
    }

    /// Where the Filter popover opens, under the filter button at the end of the tabs row.
    static let filterPopoverOrigin = CGPoint(x: 70, y: 72)
    /// Where a saved filter's popover opens, under its tab.
    static func tabPopoverOrigin(_ x: CGFloat) -> CGPoint { CGPoint(x: x, y: 72) }

    static func states() -> [SettingsPreviews.State] {
        [
            // The tabs: Everything chosen, Needs my review and Mine from the defaults, two more
            // tabs, and two saved filters kept in the » menu.
            State(name: "filters-tabs") { window(app()) },
            // A saved filter with a grouping: choosing it groups the list by author.
            State(name: "filters-tab-with-grouping") { window(app { $0.chooseFilter(blockedInAPI.id) }) },
            // The narrowest list: tabs that do not fit go into the » menu, and the chosen one
            // takes the last place that fits.
            State(name: "filters-tabs-narrowest") {
                window(app { app in
                    app.listWidth = AppModel.listWidthRange.lowerBound
                    app.chooseFilter(readyToMerge.id)
                })
            },
            // A saved filter that is not a tab, chosen from the » menu: a temporary last tab
            // with a dashed edge, grouped by repository.
            State(name: "filters-temporary-tab") { window(app { $0.chooseFilter(globex.id) }) },
            // The right-click menu on a tab, drawn as a list of its items.
            State(name: "filters-tab-menu") {
                let app = app { $0.chooseFilter(SavedFilter.needsMyReview.id) }
                return window(app, popover: TabMenuPreview(items: TabMenuPreview.savedFilterItems), at: CGPoint(x: 96, y: 84))
            },
            State(name: "filters-tab-menu-everything") {
                window(app(), popover: TabMenuPreview(items: TabMenuPreview.everythingItems), at: CGPoint(x: 12, y: 84))
            },

            // The Filter popover with nothing yet: the starter.
            State(name: "filters-popover-empty") {
                let app = app()
                return window(app, popover: FilterPopover(model: app), at: filterPopoverOrigin)
            },
            // The filter Figma row 11 draws, counted live.
            State(name: "filters-popover") {
                let app = app()
                return window(app, popover: FilterPopover(model: app, draft: FilterDraft(figmaFilter)), at: filterPopoverOrigin)
            },
            // Opened on a saved filter's tab, it starts from that filter.
            State(name: "filters-popover-from-a-tab") {
                let app = app { $0.chooseFilter(SavedFilter.mine.id) }
                var draft = FilterDraft(app.currentFilter)
                let line = draft.addCondition(toSet: draft.sets.first?.id, field: .status)
                draft.addValue("blocked", to: line)
                draft.addValue("failing", to: line)
                return window(app, popover: FilterPopover(model: app, draft: draft), at: filterPopoverOrigin)
            },
            // A very long filter: the middle scrolls, the top and the footer stay.
            State(name: "filters-popover-long") {
                let app = app()
                return window(app, popover: FilterPopover(model: app, draft: FilterDraft(longFilter)), at: filterPopoverOrigin)
            },
            // A line just added, with its value picker open over the popover: values with
            // their counts, narrowed by what is typed.
            State(name: "filters-popover-value-picker") {
                let app = app()
                var draft = FilterDraft(figmaFilter)
                let line = draft.addCondition(toSet: draft.sets[1].id, field: .author)
                let picker = ValuePicker(draft: .constant(draft), conditionID: line, choices: app.valueChoices(for: .author))
                return window(app, popover: FilterPopover(model: app, draft: draft), at: filterPopoverOrigin,
                              second: (AnyView(picker), CGPoint(x: 330, y: 360)))
            },
            State(name: "filters-popover-value-picker-statuses") {
                let app = app()
                var draft = FilterDraft(figmaFilter)
                let line = draft.sets[0].conditions[0].id
                let picker = ValuePicker(draft: .constant(draft), conditionID: line, choices: app.valueChoices(for: .status))
                return window(app, popover: FilterPopover(model: app, draft: draft), at: filterPopoverOrigin,
                              second: (AnyView(picker), CGPoint(x: 470, y: 205)))
            },
            // Save as Filter… asks for a name in the footer.
            State(name: "filters-popover-saving") {
                let app = app { $0.listGrouping = ListGrouping(.organization, then: .repository) }
                return window(app, popover: FilterPopover(model: app, draft: FilterDraft(figmaFilter), saving: true),
                              at: filterPopoverOrigin)
            },

            // Applied and not saved: a dot on Everything and a line under the tabs.
            State(name: "filters-applied") {
                window(app { app in
                    app.listGrouping = ListGrouping(.organization, then: .repository)
                    app.applyFilter(figmaFilter)
                })
            },
            // Applied on a tab that is a saved filter.
            State(name: "filters-applied-on-a-saved-tab") {
                window(app { app in
                    app.chooseFilter(SavedFilter.mine.id)
                    var draft = FilterDraft(app.currentFilter)
                    let line = draft.addCondition(toSet: draft.sets.first?.id, field: .status)
                    draft.addValue("blocked", to: line)
                    draft.addValue("changesRequested", to: line)
                    app.applyFilter(draft.filter)
                })
            },
            State(name: "filters-applied-no-matches") {
                window(app { app in
                    app.chooseFilter(SavedFilter.mine.id)
                    app.applyFilter(PullRequestFilter([FilterCondition(field: .organization, values: ["globex"]),
                                                       FilterCondition(field: .status, values: ["merging"])]))
                })
            },
            // Save… on the line: on Everything, a name and the grouping.
            State(name: "filters-save") {
                let app = app { app in
                    app.listGrouping = ListGrouping(.organization, then: .repository)
                    app.applyFilter(figmaFilter)
                }
                return window(app, popover: SaveFilterPopover(model: app, filter: figmaFilter, name: "My blocked work") {},
                              at: CGPoint(x: 150, y: 112))
            },
            // On a saved filter's tab: update it, or save as new.
            State(name: "filters-save-on-a-saved-tab") {
                let app = app { app in
                    app.chooseFilter(SavedFilter.mine.id)
                    app.applyFilter(PullRequestFilter([FilterCondition(field: .author, values: [FilterValues.me]),
                                                       FilterCondition(field: .status, values: ["blocked", "changesRequested"])]))
                }
                return window(app, popover: SaveFilterPopover(model: app, filter: app.currentFilter) {}, at: CGPoint(x: 150, y: 112))
            },

            // Editing a saved filter on its tab.
            State(name: "filters-edit-saved-filter") {
                let store = filterStore()
                _ = try? store.changeSavedFilter(id: SavedFilter.needsMyReview.id, author: .mainWindow) { saved in
                    saved.filter = PullRequestFilter(sets: [
                        FilterConditionSet([FilterCondition(field: .reviewState, values: [FilterValues.waitingOnMe]),
                                            FilterCondition(field: .draft, values: ["false"])]),
                        FilterConditionSet([FilterCondition(field: .status, values: ["blocked"]),
                                            FilterCondition(field: .repository, values: ["acme/api"])]),
                    ])
                    saved.groupBy = ["organization", "repository"]
                }
                let app = app(store) { $0.chooseFilter(SavedFilter.needsMyReview.id) }
                return window(app, popover: SavedFilterPopover(model: app, saved: app.selectedFilter),
                              at: tabPopoverOrigin(80))
            },
            // Delete Filter… asks in place, and says History keeps it.
            State(name: "filters-edit-saved-filter-delete") {
                let app = app { $0.chooseFilter(blockedInAPI.id) }
                return window(app, popover: SavedFilterPopover(model: app, saved: app.selectedFilter, confirmingDelete: true),
                              at: tabPopoverOrigin(150))
            },
            // A saved filter that is not a tab, edited from its temporary tab.
            State(name: "filters-edit-temporary-tab") {
                let app = app { $0.chooseFilter(agents.id) }
                return window(app, popover: SavedFilterPopover(model: app, saved: app.selectedFilter),
                              at: tabPopoverOrigin(150))
            },

            // Settings, Saved Filters.
            State(name: "settings-saved-filters", size: SettingsPreviews.size) {
                SettingsPreviews.window(SettingsPreviews.model(filterStore()), .savedFilters)
            },
            State(name: "settings-saved-filters-selected", size: SettingsPreviews.size) {
                AnyView(SettingsSavedFiltersPreview(configuration: SettingsPreviews.model(filterStore()),
                                                    selection: SavedFilter.needsMyReview.id))
            },
            State(name: "settings-saved-filters-only-everything", size: SettingsPreviews.size) {
                let store = SettingsPreviews.store()
                _ = try? store.prepare(author: .app)
                _ = try? store.replaceSavedFilters([], author: .settingsWindow, summary: "Removed every saved filter")
                return SettingsPreviews.window(SettingsPreviews.model(store), .savedFilters)
            },
        ]
    }

    private static func State(name: String, size: CGSize = size, _ view: @escaping () -> AnyView) -> SettingsPreviews.State {
        SettingsPreviews.State(name: name, size: size, view: view)
    }
}

/// The Settings window on Saved Filters with a row selected, which a render cannot do through
/// the list's own selection.
private struct SettingsSavedFiltersPreview: View {
    let configuration: ConfigurationModel
    let selection: String

    var body: some View {
        HStack(spacing: 0) {
            List {
                ForEach(SettingsSection.allCases) { item in
                    Label(item.title, systemImage: item.symbolName)
                        .listRowBackground(item == .savedFilters
                            ? RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .unemphasizedSelectedContentBackgroundColor)).padding(.horizontal, 10)
                            : nil)
                }
            }
            .listStyle(.sidebar)
            .frame(width: SettingsRootView.sidebarWidth)
            Divider()
            SavedFiltersSettingsView(configuration: configuration, index: MockWorld.standard.index, now: MockWorld.now,
                                     selection: selection)
        }
        .standardTitleBar()
    }
}

/// A tab's right-click menu, drawn as its items for a render. The items are the ones
/// `SavedFilterTab` puts in its menu.
struct TabMenuPreview: View {
    static let savedFilterItems = ["Edit Filter\u{2026}", "Rename\u{2026}", "Duplicate", "-", "Remove from Tab Bar", "Delete\u{2026}",
                                   "-", "Manage Saved Filters\u{2026}"]
    static let everythingItems = ["Manage Saved Filters\u{2026}"]
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { position, item in
                if item == "-" {
                    Divider().padding(.vertical, 4).padding(.horizontal, 8)
                } else {
                    Text(item)
                        .font(.system(size: 13))
                        .foregroundStyle(position == 0 ? Color.white : Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .frame(height: 22)
                        .background(RoundedRectangle(cornerRadius: 5).fill(position == 0 ? Color.accentColor : Color.clear))
                }
            }
        }
        .padding(5)
        .frame(width: 220)
    }
}
