import GitHubPRExplorerCore
import SwiftUI

/// The list's filter button, at the end of the views row. Its menu has a submenu for each
/// field: status, repository, author, review, and drafts, with the choices built from the open
/// pull requests in the index. The button fills with the accent color while any filter is on,
/// and the menu ends with Clear All Filters.
///
/// The filters are `ListFilter`, plain predicates in the core library. They are not the filter
/// language and have no syntax.
struct ListFilterMenu: View {
    @Bindable var model: AppModel

    var body: some View {
        let filter = model.listFilter
        let choices = model.filterChoices
        Menu {
            Menu(title("Status", count: filter.statuses.count)) {
                ForEach(choices.statuses) { badge in
                    Toggle(badge.name, isOn: member(badge, of: \.statuses))
                }
            }
            Menu(title("Repository", count: filter.repositories.count)) {
                ForEach(choices.repositories, id: \.self) { repository in
                    Toggle(repository.fullName, isOn: member(repository, of: \.repositories))
                }
            }
            Menu(title("Author", count: filter.authors.count)) {
                ForEach(choices.authors, id: \.login) { person in
                    Toggle(authorName(person), isOn: member(person.login, of: \.authors))
                }
            }
            Menu(title("Review", count: filter.reviewStates.count)) {
                ForEach(choices.reviewStates) { state in
                    Toggle(state.name, isOn: member(state, of: \.reviewStates))
                }
            }
            if choices.hasDrafts {
                Picker(filter.drafts == .shown ? "Drafts" : "Drafts: \(filter.drafts.name)", selection: $model.listFilter.drafts) {
                    ForEach(ListFilter.Drafts.allCases) { choice in
                        Text(choice.name).tag(choice)
                    }
                }
                .pickerStyle(.menu)
            }
            Divider()
            Button("Clear All Filters") { model.listFilter = .none }
                .disabled(filter.isEmpty)
        } label: {
            Image(systemName: filter.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(filter.isEmpty ? Color.secondary : Color.accentColor)
                .accessibilityLabel(filter.isEmpty ? "Filters" : "Filters, \(filter.activeCount) on")
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        // A menu button draws its label in its tint, not the label's own color.
        .tint(filter.isEmpty ? Color.secondary : Color.accentColor)
        .foregroundStyle(filter.isEmpty ? Color.secondary : Color.accentColor)
        .fixedSize()
        .help(filter.isEmpty ? "Filter by status, repository, author, review or drafts" : "Filters are on. Click to change or clear them.")
    }

    private func title(_ name: String, count: Int) -> String {
        count == 0 ? name : "\(name) (\(count))"
    }

    private func authorName(_ person: Person) -> String {
        model.index.viewer.isViewer(person) ? "\(person.displayName) (you)" : person.displayName
    }

    /// A checked menu item's state: whether the value is in that set of the filter.
    private func member<Value: Hashable>(_ value: Value, of path: WritableKeyPath<ListFilter, Set<Value>>) -> Binding<Bool> {
        Binding {
            model.listFilter[keyPath: path].contains(value)
        } set: { _ in
            ListFilter.toggle(value, in: &model.listFilter[keyPath: path])
        }
    }
}

/// A line under the views row while filters are on, saying which, with a button that clears
/// them. The list never hides pull requests without saying so.
struct ActiveFiltersLine: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease")
                .foregroundStyle(Color.accentColor)
            Text(summary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(summary)
            Button("Clear") { model.listFilter = .none }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Clear all filters")
        }
        .font(Style.secondary)
        .foregroundStyle(.secondary)
    }

    /// Each facet that is on, in the menu's order, such as "Blocked, Running · acme/api · Hide drafts".
    private var summary: String {
        let filter = model.listFilter
        let names = Dictionary(model.filterChoices.authors.map { ($0.login, $0) }, uniquingKeysWith: { first, _ in first })
        var parts: [String] = []
        if !filter.statuses.isEmpty {
            parts.append(StatusSentence.Badge.allCases.filter(filter.statuses.contains).map(\.label).joined(separator: ", "))
        }
        if !filter.repositories.isEmpty {
            parts.append(filter.repositories.sorted().map(\.fullName).joined(separator: ", "))
        }
        if !filter.authors.isEmpty {
            parts.append(filter.authors.sorted().map { login in
                guard let person = names[login] else { return login }
                return model.index.viewer.isViewer(person) ? "you" : person.displayName
            }.joined(separator: ", "))
        }
        if !filter.reviewStates.isEmpty {
            parts.append(ListFilter.ReviewState.allCases.filter(filter.reviewStates.contains).map(\.name).joined(separator: ", "))
        }
        if filter.drafts != .shown { parts.append(filter.drafts.name) }
        return parts.joined(separator: " · ")
    }
}
