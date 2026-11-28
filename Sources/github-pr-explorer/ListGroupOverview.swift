import GitHubPRExplorerCore
import SwiftUI

/// What the right side shows while a title row of the list is selected. For now a plain
/// placeholder: what the row is, its name, and how many pull requests it holds. A real
/// overview of an organization, a repository or a person replaces this view later, with the
/// same inputs.
struct ListGroupOverview: View {
    @Bindable var model: AppModel
    let group: ListGroup

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(verbatim: name)
            } icon: {
                Image(systemName: symbol)
            }
        } description: {
            Text(summary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// The group's full name. Under its organization a repository's row says only "api",
    /// but here it says "acme/api".
    private var name: String {
        if group.property == .repository, let repository = group.pullRequests.first?.repository {
            return repository.fullName
        }
        return group.title
    }

    /// "8 pull requests in 3 repositories", or "4 pull requests".
    private var summary: String {
        let count = "\(group.count) pull request\(group.count == 1 ? "" : "s")"
        guard let level = group.children.first?.property else { return "\(group.property.name), \(count)" }
        let children = group.children.count
        return "\(group.property.name), \(count) in \(children) \(plural(level, children))"
    }

    private func plural(_ property: ListGrouping.Property, _ count: Int) -> String {
        let one = switch property {
        case .organization: "organization"
        case .repository: "repository"
        case .author: "author"
        case .status: "status"
        case .reviewState: "review state"
        }
        guard count != 1 else { return one }
        return switch property {
        case .repository: "repositories"
        case .status: "statuses"
        default: one + "s"
        }
    }

    private var symbol: String {
        switch group.property {
        case .organization: "building.2"
        case .repository: "folder"
        case .author: "person"
        case .status: "circle.dashed"
        case .reviewState: "checkmark.bubble"
        }
    }
}
