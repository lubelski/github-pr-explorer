import Foundation
import GitHubPRExplorerCore

extension PreviewRenderer {
    /// A title row selected, so the right side shows its overview (Figma row 10): an
    /// organization, a repository and an author, a group of one, a group of about 200, a group
    /// narrowed by an applied filter and by the search too, shorthands, and the smallest window.
    /// Each chooses a tab by its saved filter's id. `base` makes a model on
    /// the mock world with the worked example open.
    static func overviewStates(base: @escaping () -> AppModel) -> [State] {
        let orgThenRepository = ListGrouping(.organization, then: .repository)
        func selecting(_ tab: String, _ grouping: ListGrouping, filter: PullRequestFilter? = nil, search: String = "",
                       pick: @escaping (ListTree) -> ListGroup?) -> () -> AppModel {
            {
                let model = base()
                model.chooseFilter(tab)
                model.listGrouping = grouping
                if let filter { model.applyFilter(filter) }
                model.searchText = search
                if let group = pick(model.listTree) { model.listSelection = .group(group.id) }
                return model
            }
        }
        func id(_ id: String) -> (ListTree) -> ListGroup? { { $0.group(id: id) } }
        let everything = SavedFilter.everythingID, mine = SavedFilter.mine.id, needsMyReview = SavedFilter.needsMyReview.id
        let blockedOrWaiting = PullRequestFilter([FilterCondition(field: .status, values: ["blocked", "waiting"])])
        let largestAuthor: (ListTree) -> ListGroup? = { tree in tree.groups.max { $0.count < $1.count } }
        return [
            // As the design draws it: "Mine", by organization then repository, acme selected.
            State(name: "overview-organization", model: selecting(mine, orgThenRepository, pick: id("organization:acme"))),
            // Everything open: acme holds about 200, in a section per repository.
            State(name: "overview-organization-everything",
                  model: selecting(everything, orgThenRepository, pick: id("organization:acme"))),
            // By organization only, so the cards are in sections by status.
            State(name: "overview-organization-one-level-everything",
                  model: selecting(everything, ListGrouping(.organization), pick: id("organization:acme"))),
            // A repository at the last level: sections by status.
            State(name: "overview-repository",
                  model: selecting(everything, orgThenRepository, pick: id("organization:acme|repository:acme/web"))),
            // An author with the most reviews waiting on the viewer, grouped then by status.
            State(name: "overview-author",
                  model: selecting(needsMyReview, ListGrouping(.author, then: .status), pick: largestAuthor)),
            // A group of one pull request: acme/docs in "Mine".
            State(name: "overview-one-pull-request",
                  model: selecting(mine, orgThenRepository) { tree in tree.allGroups.first { $0.count == 1 } }),
            // Narrowed by a filter applied on Everything: blocked and waiting only. The summary
            // says so.
            State(name: "overview-narrowed",
                  model: selecting(everything, orgThenRepository, filter: blockedOrWaiting, pick: id("organization:acme"))),
            // Narrowed by the same filter and a search, so the summary names both.
            State(name: "overview-narrowed-search-and-filter",
                  model: selecting(everything, orgThenRepository, filter: blockedOrWaiting, search: "api",
                                   pick: id("organization:acme"))),
            // Shorthands for two repositories and two people, drawn in the headings and cards.
            State(name: "overview-shorthands") {
                let model = selecting(everything, orgThenRepository, pick: id("organization:acme"))()
                model.shorthands = Shorthands([
                    Shorthand(kind: .repository, target: "acme/api", shorthand: "API"),
                    Shorthand(kind: .repository, target: "acme/web", shorthand: "Web"),
                    Shorthand(kind: .person, target: "ada-park", shorthand: "Ada"),
                    Shorthand(kind: .person, target: "sam-rivera", shorthand: "Sam"),
                ])
                return model
            },
            State(name: "overview-window-smallest", size: CGSize(width: 900, height: 560),
                  model: selecting(mine, orgThenRepository, pick: id("organization:acme"))),
        ]
    }
}
