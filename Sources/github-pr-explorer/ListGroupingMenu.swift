import AppKit
import GitHubPRExplorerCore
import SwiftUI

/// The list's group by button, beside the filter button at the end of the views row. Its menu
/// is nested: None, then each thing to group by opens a second menu. That menu's first item
/// keeps one level ("Organization Only"), and under "Then By" come the second levels that make
/// sense under the first. Collapse All and Expand All end the main menu. The button fills with
/// the accent color while a grouping is on.
///
/// Grouping is `ListGrouping` in the core library, and `ListTree` builds the tree. It arranges
/// the listed rows and keeps none out, so it is not a filter.
struct ListGroupingMenu: View {
    @Bindable var model: AppModel

    var body: some View {
        let grouping = model.listGrouping
        let isOn = !grouping.isNone
        Menu {
            Section("Group By") {
                Toggle("None", isOn: choice(.none))
                ForEach(ListGrouping.Property.allCases) { first in
                    Menu {
                        Toggle("\(first.name) Only", isOn: choice(ListGrouping(first)))
                        Section("Then By") {
                            ForEach(first.secondLevelChoices) { second in
                                Toggle(second.name, isOn: choice(ListGrouping(first, then: second)))
                            }
                        }
                    } label: {
                        if grouping.first == first {
                            Label(first.name, systemImage: "checkmark")
                        } else {
                            Text(first.name)
                        }
                    }
                }
            }
            Divider()
            let tree = model.listTree
            Button("Collapse All") { withAnimation { model.setAllGroups(closed: true) } }
                .disabled(!tree.canCloseAll(closed: model.closedGroups))
            Button("Expand All") { withAnimation { model.setAllGroups(closed: false) } }
                .disabled(!tree.canOpenAll(closed: model.closedGroups))
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
        .help(isOn ? "Grouped by \(grouping.name.lowercased()). Click to change."
                   : "Group by organization, repository, author, status or review state")
    }

    /// A menu item that is checked while it is the grouping and picks it when chosen.
    private func choice(_ grouping: ListGrouping) -> Binding<Bool> {
        Binding {
            model.listGrouping == grouping
        } set: { isOn in
            if isOn { withAnimation { model.listGrouping = grouping } }
        }
    }
}

/// How rows sit in the tree: each level is indented by one step, a title row's triangle fills
/// the step at its own level, and the guide line of each title row runs down the middle of its
/// triangle's step, past everything the row holds.
enum ListTreeMetrics {
    static let indentStep: CGFloat = 16
    static let triangleWidth: CGFloat = 16

    /// Where the guide line of a title row at `depth` runs, from the row's content edge.
    static func guideX(depth: Int) -> CGFloat {
        CGFloat(depth) * indentStep + triangleWidth / 2
    }
}

/// The faint vertical lines a row at `depth` sits on: one for each title row that holds it.
/// They reach a little above and below the row, so the lines of adjacent rows join.
///
/// An open title row passes `startsBelowTriangle`, so its own line starts just under its
/// triangle rather than at the next row.
struct ListTreeGuides: View {
    let depth: Int
    var startsBelowTriangle = false

    /// How far the lines reach past the row, into the space between rows.
    private static let overlap: CGFloat = 6

    var body: some View {
        Canvas { context, size in
            func line(at level: Int, from top: CGFloat) {
                let x = ListTreeMetrics.guideX(depth: level).rounded(.down) + 0.5
                var path = Path()
                path.move(to: CGPoint(x: x, y: top))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .style(Style.treeGuide), lineWidth: 1)
            }
            for level in 0..<depth { line(at: level, from: 0) }
            if startsBelowTriangle { line(at: depth, from: size.height / 2 + 9) }
        }
        .padding(.vertical, -Self.overlap)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A title row of the tree: the disclosure triangle at the leading edge, the group's name in
/// bold, and at the trailing edge how many pull requests it holds at any depth, open or closed.
///
/// A click on the row selects it, like any other row. The triangle opens and closes it, and
/// Option-click on the triangle does every row at its level, as in Finder. The arrow keys and
/// a double-click open and close it too; the list handles those.
struct ListGroupRow: View {
    @Bindable var model: AppModel
    let group: ListGroup
    let isOpen: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Spacer().frame(width: CGFloat(group.depth) * ListTreeMetrics.indentStep)
            DisclosureTriangle(isOpen: isOpen) { all in
                withAnimation(.snappy(duration: 0.2)) { model.toggleGroup(group.id, level: all) }
            }
            .help(isOpen ? "Close. Option-click to close every row at this level."
                         : "Open. Option-click to open every row at this level.")
            ShortenedName(group.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.leading, 2)
            Spacer(minLength: 8)
            Text("\(group.count)")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .fixedSize()
                .layoutPriority(1)
        }
        .padding(.vertical, 3)
        .background(alignment: .leading) { ListTreeGuides(depth: group.depth, startsBelowTriangle: isOpen) }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(group.name.accessibilityLabel), \(group.count) pull request\(group.count == 1 ? "" : "s")")
        .accessibilityValue(isOpen ? "Expanded" : "Collapsed")
        .accessibilityAction(named: isOpen ? "Collapse" : "Expand") { model.toggleGroup(group.id) }
    }
}

/// The triangle at the leading edge of a title row. It points right when closed and down when
/// open, and turns between the two.
struct DisclosureTriangle: View {
    let isOpen: Bool
    /// Called with whether Option was held, to act on every row at the level.
    let toggle: (Bool) -> Void
    @State private var hovering = false

    var body: some View {
        Button {
            toggle(NSEvent.modifierFlags.contains(.option))
        } label: {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(hovering ? .primary : .secondary)
                .rotationEffect(.degrees(isOpen ? 90 : 0))
                .frame(width: ListTreeMetrics.triangleWidth, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityHidden(true)
    }
}
