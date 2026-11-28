import Foundation
import GitHubPRExplorerCore

extension PreviewRenderer {
    /// A title row selected, so the right side shows its overview (Figma row 10): an
    /// organization, a repository and an author, a group of one, a group of about 200, a group
    /// narrowed by the filters, shorthands, and the smallest window. `base` makes a model on
    /// the mock world with the worked example open.
    static func overviewStates(base: @escaping () -> AppModel) -> [State] {
        let orgThenRepository = ListGrouping(.organization, then: .repository)
        func selecting(_ view: FixedListView, _ grouping: ListGrouping, filter: ListFilter = .none,
                       pick: @escaping (ListTree) -> ListGroup?) -> () -> AppModel {
            {
                let model = base()
                model.listView = view
                model.listGrouping = grouping
                model.listFilter = filter
                if let group = pick(model.listTree) { model.listSelection = .group(group.id) }
                return model
            }
        }
        func id(_ id: String) -> (ListTree) -> ListGroup? { { $0.group(id: id) } }
        let largestAuthor: (ListTree) -> ListGroup? = { tree in tree.groups.max { $0.count < $1.count } }
        return [
            // As the design draws it: "Mine", by organization then repository, acme selected.
            State(name: "overview-organization", model: selecting(.mine, orgThenRepository, pick: id("organization:acme"))),
            // Everything open: acme holds about 200, in a section per repository.
            State(name: "overview-organization-everything",
                  model: selecting(.everythingOpen, orgThenRepository, pick: id("organization:acme"))),
            // By organization only, so the cards are in sections by status.
            State(name: "overview-organization-one-level-everything",
                  model: selecting(.everythingOpen, ListGrouping(.organization), pick: id("organization:acme"))),
            // A repository at the last level: sections by status.
            State(name: "overview-repository",
                  model: selecting(.everythingOpen, orgThenRepository, pick: id("organization:acme|repository:acme/web"))),
            // An author with the most reviews waiting on the viewer, grouped then by status.
            State(name: "overview-author",
                  model: selecting(.needsMyReview, ListGrouping(.author, then: .status), pick: largestAuthor)),
            // A group of one pull request: acme/docs in "Mine".
            State(name: "overview-one-pull-request",
                  model: selecting(.mine, orgThenRepository) { tree in tree.allGroups.first { $0.count == 1 } }),
            // Narrowed by the filters: blocked and waiting only. The summary says so.
            State(name: "overview-narrowed",
                  model: selecting(.everythingOpen, orgThenRepository, filter: ListFilter(statuses: [.blocked, .waiting]),
                                   pick: id("organization:acme"))),
            // Shorthands for two repositories and two people, drawn in the headings and cards.
            State(name: "overview-shorthands") {
                let model = selecting(.everythingOpen, orgThenRepository, pick: id("organization:acme"))()
                model.shorthands = Shorthands([
                    Shorthand(kind: .repository, target: "acme/api", shorthand: "API"),
                    Shorthand(kind: .repository, target: "acme/web", shorthand: "Web"),
                    Shorthand(kind: .person, target: "ada-park", shorthand: "Ada"),
                    Shorthand(kind: .person, target: "sam-rivera", shorthand: "Sam"),
                ])
                return model
            },
            State(name: "overview-window-smallest", size: CGSize(width: 900, height: 560),
                  model: selecting(.mine, orgThenRepository, pick: id("organization:acme"))),
        ]
    }
}
