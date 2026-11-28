import GitHubPRExplorerCore
import SwiftUI

/// The tabs above the list, after Figma rows 11 and 13: Everything first and fixed, then the
/// saved filters shown as tabs, in order, each with its count. Those that do not fit, and those
/// not shown as tabs, sit in the » menu, which ends with Manage Saved Filters…. The chosen tab
/// always shows: when it would not fit, it takes the last place that does.
///
/// A right-click on a tab offers Edit Filter…, Rename…, Duplicate, Remove from Tab Bar, Delete…
/// and Manage Saved Filters…; on Everything only the last. A double-click edits it. Tabs can be
/// dragged into order, and Command-1 to Command-9 choose them.
struct SavedFilterTabBar: View {
    @Bindable var model: AppModel
    @Environment(\.openSettings) private var openSettings
    @State private var renaming: SavedFilter?
    @State private var newName = ""
    @State private var deleting: SavedFilter?
    /// Each tab's width, with and without its count, as last measured.
    @State private var widths: [String: CGFloat] = [:]
    @State private var available: CGFloat = 0

    static let spacing: CGFloat = 3
    /// The » menu's width, with the spacing before it.
    static let moreWidth: CGFloat = 22
    /// The narrowest a tab's name gives way to.
    static let shortestTruncatedTab: CGFloat = 64

    var body: some View {
        let tabs = model.tabFilters
        let counts = model.countsByFilter
        let fit = fitting(tabs)
        row(tabs: tabs, counts: counts, shown: fit.shown, chosenCountOnly: fit.chosenCountOnly, compact: fit.compact,
            truncatesLast: fit.truncatesLast)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { available = $0 }
            // Every tab measured at its own size, out of sight, so the row can choose how
            // many fit.
            .background(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(tabs) { saved in
                        ForEach([true, false], id: \.self) { withCount in
                            SavedFilterTabLabel(name: saved.name, count: counts[saved.id] ?? 0, selected: true,
                                                showsCount: withCount)
                                .fixedSize()
                                .onGeometryChange(for: CGFloat.self, of: \.size.width) { widths["\(saved.id)|\(withCount)"] = $0 }
                        }
                    }
                }
                .fixedSize()
                .hidden()
                .accessibilityHidden(true)
            }
            .background { shortcuts(tabs) }
        .alert("Rename Saved Filter", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") {
                if let renaming { model.renameFilter(renaming.id, to: newName) }
                renaming = nil
            }
            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancel", role: .cancel) { renaming = nil }
        } message: {
            Text("The tab, the \u{00BB} menu and Settings show the new name. Its id stays the same.")
        }
        .confirmationDialog(deleting.map { "Delete \u{201C}\($0.name)\u{201D}?" } ?? "",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) {
                if let deleting { model.deleteFilter(deleting.id) }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            Text("Settings, History keeps it, and can bring it back.")
        }
    }

    /// How many tabs fit: the most that do, first with every count, then with only the chosen
    /// tab's count, and when not even two fit, the chosen tab alone, its name giving way.
    private func fitting(_ tabs: [SavedFilter]) -> (shown: Int, chosenCountOnly: Bool, compact: Bool, truncatesLast: Bool) {
        guard available > 0, !tabs.isEmpty else { return (tabs.count, false, false, false) }
        let room = available - Self.moreWidth
        for shown in (1...tabs.count).reversed() {
            for chosenCountOnly in [false, true] {
                let visible = visibleTabs(tabs, shown: shown)
                let total = visible.reduce(CGFloat(0)) { sum, saved in
                    let withCount = !chosenCountOnly || saved.id == model.selectedFilterID
                    return sum + (widths["\(saved.id)|\(withCount)"] ?? .infinity)
                } + Self.spacing * CGFloat(max(0, visible.count - 1))
                if total <= room { return (shown, chosenCountOnly, false, false) }
                // The last tab's name may give way, down to a short stub, when it is not the
                // chosen one.
                if chosenCountOnly, let last = visible.last, last.id != model.selectedFilterID, visible.count > 1,
                   let lastWidth = widths["\(last.id)|false"],
                   total - lastWidth + min(lastWidth, Self.shortestTruncatedTab) <= room {
                    return (shown, true, false, true)
                }
            }
        }
        return (0, false, true, false)
    }

    private func visibleTabs(_ tabs: [SavedFilter], shown: Int) -> [SavedFilter] {
        var visible = Array(tabs.prefix(shown))
        if !visible.contains(where: { $0.id == model.selectedFilterID }),
           let chosen = tabs.first(where: { $0.id == model.selectedFilterID }) {
            if visible.count > 1 { visible.removeLast() }
            visible.append(chosen)
        }
        return visible
    }

    /// The first `shown` tabs, with the chosen one put in the last place if it is not among
    /// them, then the » menu holding the rest.
    private func row(tabs: [SavedFilter], counts: [String: Int], shown: Int, chosenCountOnly: Bool = false,
                     compact: Bool = false, truncatesLast: Bool = false) -> some View {
        let visible = visibleTabs(tabs, shown: shown)
        let overflow = tabs.filter { tab in !visible.contains { $0.id == tab.id } }
        return HStack(spacing: Self.spacing) {
            ForEach(visible) { saved in
                SavedFilterTab(model: model, saved: saved, count: counts[saved.id] ?? 0,
                               actions: actions, showsCount: !chosenCountOnly || saved.id == model.selectedFilterID,
                               compact: compact || (truncatesLast && saved.id == visible.last?.id))
            }
            MoreFiltersMenu(model: model, overflow: overflow, counts: counts, manage: manage)
            Spacer(minLength: 0)
        }
        .font(.system(size: 12))
    }

    private var actions: SavedFilterTab.Actions {
        SavedFilterTab.Actions(
            rename: { saved in newName = saved.name; renaming = saved },
            delete: { saved in deleting = saved },
            manage: manage)
    }

    private func manage() {
        SavedFiltersSettingsView.open(openSettings)
    }

    /// Command-1 to Command-9 choose the tabs in order.
    private func shortcuts(_ tabs: [SavedFilter]) -> some View {
        ForEach(Array(tabs.prefix(9).enumerated()), id: \.element.id) { position, saved in
            Button(saved.name) { model.chooseFilter(saved.id) }
                .keyboardShortcut(KeyEquivalent(Character("\(position + 1)")), modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }
}

/// One tab: the name and the count in a capsule. The chosen one is filled with the accent
/// color, carries a dot while a filter is applied on it and not saved, and a saved filter
/// that is not a tab, chosen from the » menu, has a dashed edge for as long as it is shown.
struct SavedFilterTab: View {
    struct Actions {
        let rename: (SavedFilter) -> Void
        let delete: (SavedFilter) -> Void
        let manage: () -> Void
    }

    @Bindable var model: AppModel
    let saved: SavedFilter
    let count: Int
    let actions: Actions
    /// The name gives way instead of the row growing, for the narrowest list.
    var showsCount = true
    var compact = false
    @State private var targeted = false

    var body: some View {
        let selected = model.selectedFilterID == saved.id
        let temporary = model.isTemporaryTab(saved.id)
        let unsaved = selected && model.hasUnsavedFilter
        Button {
            model.chooseFilter(saved.id)
        } label: {
            SavedFilterTabLabel(name: saved.name, count: count, selected: selected, showsCount: showsCount)
            .fixedSize(horizontal: !compact, vertical: false)
            .background { Capsule().fill(selected ? Color.accentColor.opacity(0.16) : Color.clear) }
            .overlay {
                Capsule().strokeBorder(selected ? Color.accentColor.opacity(0.45) : temporary ? Color.secondary.opacity(0.5) : Color.clear,
                                       style: StrokeStyle(lineWidth: 1, dash: temporary ? [3, 2] : []))
            }
            .overlay(alignment: .topTrailing) {
                if unsaved {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                        .overlay(Circle().stroke(Style.surface, lineWidth: 1.5))
                        .offset(x: 1, y: -1)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .overlay(alignment: .leading) {
                if targeted {
                    Capsule().fill(Color.accentColor).frame(width: 2).offset(x: -3)
                }
            }
            .contentShape(Capsule())
            .animation(.snappy(duration: 0.2), value: unsaved)
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? .primary : .secondary)
        .accessibilityLabel("\(saved.name), \(count)")
        .help(showsCount ? help : "\(count) open\n\(help)")
        .accessibilityValue(unsaved ? "Filter applied, not saved" : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            if !saved.isEverything, model.canChangeSavedFilters { model.editingFilterID = saved.id }
        })
        .contextMenu { menu }
        .popover(isPresented: Binding(get: { model.editingFilterID == saved.id },
                                      set: { if !$0, model.editingFilterID == saved.id { model.editingFilterID = nil } }),
                 arrowEdge: .bottom) {
            SavedFilterPopover(model: model, saved: saved) { model.editingFilterID = nil }
        }
        .modifier(TabReordering(model: model, saved: saved, targeted: $targeted))
    }

    private var help: String {
        if saved.isEverything { return "Every open pull request" }
        let words = saved.summary
        return model.isTemporaryTab(saved.id) ? "\(words)\nNot in the tab bar: shown while it is chosen." : "\(words)\nRight-click to edit. Drag to reorder."
    }

    @ViewBuilder private var menu: some View {
        if !saved.isEverything {
            Group {
                Button("Edit Filter\u{2026}") { model.editingFilterID = saved.id }
                Button("Rename\u{2026}") { actions.rename(saved) }
                Button("Duplicate") { model.duplicateFilter(saved.id) }
                Divider()
                if saved.showsAsTab {
                    Button("Remove from Tab Bar") { model.removeFromTabBar(saved.id) }
                } else {
                    Button("Show in Tab Bar") { model.showInTabBar(saved.id) }
                }
                Button("Delete\u{2026}") { actions.delete(saved) }
            }
            .disabled(!model.canChangeSavedFilters)
            Divider()
        }
        Button("Manage Saved Filters\u{2026}", action: actions.manage)
    }
}

/// Dragging a tab onto another moves it to that place. Everything stays first, so nothing is
/// dragged onto it or from it.
private struct TabReordering: ViewModifier {
    let model: AppModel
    let saved: SavedFilter
    @Binding var targeted: Bool

    func body(content: Content) -> some View {
        if saved.isEverything || !model.canChangeSavedFilters {
            content
        } else {
            content
                .draggable(saved.id)
                .dropDestination(for: String.self) { ids, _ in
                    guard let id = ids.first, id != saved.id,
                          let target = model.savedFilters.dropFirst().firstIndex(where: { $0.id == saved.id }) else { return false }
                    // Positions count from 1, the first after Everything, which is index 0.
                    withAnimation(.snappy) { _ = model.savedFilterStore?.moveSavedFilter(id: id, to: target) }
                    return true
                } isTargeted: { targeted = $0 }
        }
    }
}

/// The » menu: tabs that did not fit, then saved filters that are not tabs, each with its
/// count, and Manage Saved Filters… last. Choosing a filter that is not a tab shows it as a
/// temporary last tab.
struct MoreFiltersMenu: View {
    let model: AppModel
    let overflow: [SavedFilter]
    let counts: [String: Int]
    let manage: () -> Void

    var body: some View {
        let hidden = model.hiddenFilters
        Menu {
            if !overflow.isEmpty {
                Section("More Tabs") {
                    ForEach(overflow) { item($0) }
                }
            }
            if !hidden.isEmpty {
                Section("Not in the Tab Bar") {
                    ForEach(hidden) { item($0) }
                }
            }
            if !overflow.isEmpty || !hidden.isEmpty { Divider() }
            Button("Manage Saved Filters\u{2026}", action: manage)
        } label: {
            Text("\u{00BB}")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(overflow.isEmpty && hidden.isEmpty ? .tertiary : .secondary)
                .frame(width: 16, height: 20)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(overflow.isEmpty && hidden.isEmpty ? "Manage saved filters"
              : "\(overflow.count + hidden.count) more saved filter\(overflow.count + hidden.count == 1 ? "" : "s")")
        .accessibilityLabel("More saved filters")
    }

    private func item(_ saved: SavedFilter) -> some View {
        Toggle(isOn: Binding(get: { model.selectedFilterID == saved.id }, set: { if $0 { model.chooseFilter(saved.id) } })) {
            Text("\(saved.name)    \(counts[saved.id] ?? 0)")
        }
    }
}

/// A tab's name and count in its capsule's padding, without the capsule.
struct SavedFilterTabLabel: View {
    let name: String
    let count: Int
    let selected: Bool
    var showsCount = true

    var body: some View {
        HStack(spacing: 4) {
            Text(verbatim: name)
                .fontWeight(selected ? .semibold : .regular)
                .lineLimit(1)
                .truncationMode(.tail)
            if showsCount {
                Text("\(count)")
                    .monospacedDigit()
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                    .contentTransition(.numericText())
                    .fixedSize()
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }
}
