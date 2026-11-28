import GitHubPRExplorerCore
import SwiftUI

/// The list's group by button, beside the filter button at the end of the views row. Its menu
/// picks None, Repository, Author, Status or Review state, with the current choice checked.
/// The button fills with the accent color while a grouping is on, as the filter button does.
///
/// Grouping is `ListGrouping` in the core library. It arranges the listed rows in sections and
/// keeps none out, so it is not a filter.
struct ListGroupingMenu: View {
    @Bindable var model: AppModel

    var body: some View {
        let grouping = model.listGrouping
        let isOn = grouping != .none
        Menu {
            Picker("Group By", selection: $model.listGrouping) {
                ForEach(ListGrouping.allCases) { choice in
                    Text(choice.name).tag(choice)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: isOn ? "rectangle.3.group.fill" : "rectangle.3.group")
                .font(.system(size: 13))
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                .accessibilityLabel(isOn ? "Group by \(grouping.name)" : "Group By")
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        // A menu button draws its label in its tint, not the label's own color.
        .tint(isOn ? Color.accentColor : Color.secondary)
        .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
        .fixedSize()
        .help(isOn ? "Grouped by \(grouping.name.lowercased()). Click to change." : "Group by repository, author, status or review state")
    }
}

/// A section header in the grouped list: the group's name, and how many rows it holds.
struct ListSectionHeader: View {
    let section: ListGrouping.Section

    var body: some View {
        HStack(spacing: 6) {
            Text(section.title)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Text("\(section.count)")
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
        // The sidebar list draws a header nearer its trailing edge than its rows, so the count
        // is brought in to line up with the badges.
        .padding(.trailing, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(section.title), \(section.count) pull request\(section.count == 1 ? "" : "s")")
    }
}
