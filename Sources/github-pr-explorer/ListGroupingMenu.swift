import AppKit
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
            Divider()
            let sections = model.listSections
            Button("Collapse All") { withAnimation { model.setAllSections(collapsed: true) } }
                .disabled(!grouping.canCollapseAll(sections, collapsed: model.collapsedSections))
            Button("Expand All") { withAnimation { model.setAllSections(collapsed: false) } }
                .disabled(!grouping.canExpandAll(sections, collapsed: model.collapsedSections))
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

/// A section header in the grouped list: the group's name in bold, then how many rows it
/// holds, collapsed or not. The system draws its disclosure control at the trailing edge.
/// A click anywhere on the header collapses or expands the section, and Option-click does it
/// to every section, as in Finder.
struct ListSectionHeader: View {
    @Bindable var model: AppModel
    let section: ListGrouping.Section

    var body: some View {
        let collapsed = model.collapsedSections.contains(section.id)
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(section.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Text("\(section.count)")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .fixedSize()
                .layoutPriority(1)
            Spacer(minLength: 0)
        }
        // More space above a header than below, so it belongs to the rows under it.
        .padding(.top, 6)
        .padding(.bottom, 1)
        .contentShape(Rectangle())
        .onTapGesture {
            let all = NSEvent.modifierFlags.contains(.option)
            withAnimation { model.toggleSection(section.id, all: all) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(section.title), \(section.count) pull request\(section.count == 1 ? "" : "s")")
        .accessibilityValue(collapsed ? "Collapsed" : "Expanded")
        .accessibilityAddTraits(.isButton)
        .help(collapsed ? "Click to expand. Option-click to expand every section."
                        : "Click to collapse. Option-click to collapse every section.")
    }
}
