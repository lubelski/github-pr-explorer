import GitHubPRExplorerCore
import SwiftUI

/// Render states for the list's right-click menu and Set Shorthand. A menu and a popover do not
/// draw offscreen, so these draw the popover's content on its own, the tree and the flat list
/// with an organization's shorthand set, and Settings, Shorthands with all three kinds. The
/// menus' contents are covered by `ListRowMenuTests` instead. Every state uses a temporary
/// configuration folder of its own.
@MainActor
enum RowMenuPreviews {
    /// The sample shorthands, and two organizations'.
    static let organizationShorthands: [(ShorthandKind, String, String)] = [
        (.organization, "globex", "Gx"), (.organization, "acme", "Acme Co"),
    ]

    static func states(model: @escaping (ConfigurationSnapshot) -> AppModel) -> [SettingsPreviews.State] {
        func mainWindow(_ store: ConfigurationStore, configure: (AppModel) -> Void) -> AnyView {
            store.reload()
            let snapshot = store.snapshot
            let app = model(snapshot)
            app.apply(snapshot, previous: nil)
            app.chooseFilter(SavedFilter.everythingID)
            configure(app)
            return AnyView(MainWindowView(model: app, updater: .unavailable())
                .environment(\.hidesBotEventsInActivity, app.hidesBotEventsInActivity))
        }
        func editor(_ target: ShorthandTarget, _ shorthands: [Shorthand] = [], text: String? = nil) -> AnyView {
            let lookup = Shorthands(shorthands)
            return AnyView(ShorthandEditor(edit: ShorthandEdit(target: target, shorthands: lookup), shorthands: lookup,
                                           text: text) {}
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top))
        }
        let popover = CGSize(width: ShorthandEditor.width, height: 200)
        let api = Repository(owner: "acme", name: "api")
        return [
            // Set Shorthand on a repository with none: the suggestion is filled in.
            SettingsPreviews.State(name: "row-menu-set-shorthand-repository", size: popover) {
                editor(.repository(api))
            },
            // Changing one that is set, to a shorthand another repository has: a warning, and
            // Remove.
            SettingsPreviews.State(name: "row-menu-set-shorthand-clash", size: CGSize(width: popover.width, height: 250)) {
                editor(.repository(Repository(owner: "acme", name: "docs")),
                       [Shorthand(kind: .repository, target: "acme/docs", shorthand: "Docs"),
                        Shorthand(kind: .repository, target: "acme/web", shorthand: "Web")], text: "Web")
            },
            SettingsPreviews.State(name: "row-menu-set-shorthand-person", size: popover) {
                editor(.person(MockCast.adaPark))
            },
            SettingsPreviews.State(name: "row-menu-set-shorthand-organization", size: CGSize(width: popover.width, height: 220)) {
                editor(.organization("globex"))
            },
            // The tree by organization then repository, with globex shortened to Gx and acme
            // to Acme Co. Repositories under them keep their own names or shorthands.
            SettingsPreviews.State(name: "organization-shorthand-tree", size: CGSize(width: 1560, height: 940)) {
                mainWindow(SettingsPreviews.shorthandStore(organizationShorthands)) { app in
                    app.listGrouping = ListGrouping(.organization, then: .repository)
                    app.closedGroups = ["organization:acme"]
                    app.listSelection = .group("organization:globex")
                }
            },
            // The flat list searched by the organization's shorthand: a repository with no
            // shorthand of its own reads Gx/billing.
            SettingsPreviews.State(name: "organization-shorthand-flat-search", size: CGSize(width: 1560, height: 940)) {
                mainWindow(SettingsPreviews.shorthandStore(organizationShorthands)) { app in
                    app.searchText = "Gx"
                    app.selection = app.listedPullRequests.first?.id
                }
            },
            SettingsPreviews.State(name: "settings-shorthands-three-kinds", size: CGSize(width: 900, height: 1180)) {
                SettingsPreviews.window(SettingsPreviews.model(SettingsPreviews.shorthandStore(organizationShorthands)), .shorthands)
            },
        ]
    }
}
