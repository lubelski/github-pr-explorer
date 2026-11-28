import GitHubPRExplorerCore
import SwiftUI

/// The popover that edits one saved filter, anchored on its tab, after Figma row 13. It is a
/// sibling of the Filter popover and shares its parts: where that one has its title, this one
/// has the name field, and it adds a strip with Group By and "Show in the tab bar". Save writes
/// `saved-filters.json` through `ConfigurationStore`. Cancel, Escape or a click outside
/// discards.
struct SavedFilterPopover: View {
    let model: AppModel
    let saved: SavedFilter
    var close: () -> Void = {}
    @State private var name: String
    @State private var draft: FilterDraft
    @State private var grouping: ListGrouping
    @State private var showsAsTab: Bool
    @State private var confirmingDelete: Bool
    @FocusState private var nameFocused: Bool

    init(model: AppModel, saved: SavedFilter, draft: FilterDraft? = nil, confirmingDelete: Bool = false,
         close: @escaping () -> Void = {}) {
        self.model = model
        self.saved = saved
        self.close = close
        _name = State(initialValue: saved.name)
        _draft = State(initialValue: draft ?? FilterDraft(saved.filter))
        _grouping = State(initialValue: saved.grouping ?? .none)
        _showsAsTab = State(initialValue: saved.showsAsTab)
        _confirmingDelete = State(initialValue: confirmingDelete)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasChanges: Bool {
        trimmedName != saved.name || draft.filter != saved.filter
            || grouping.savedFilterGroupBy != saved.groupBy || showsAsTab != saved.showsAsTab
    }

    var body: some View {
        VStack(spacing: 0) {
            FilterPopoverHeader(summary: draft.filter.summary) {
                TextField("Name", text: $name, prompt: Text("Name"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: 300)
                    .focused($nameFocused)
                    .onSubmit(save)
            } trailing: {
                Text("Saved filter")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Divider()
            FilterSetsEditor(draft: $draft, model: model)
            Divider()
            HStack(spacing: 14) {
                HStack(spacing: 8) {
                    Text("Group by")
                        .foregroundStyle(.secondary)
                        .fixedSize()
                    GroupingPicker(grouping: $grouping)
                }
                Spacer(minLength: 8)
                Toggle("Show in the tab bar", isOn: $showsAsTab)
                    .toggleStyle(.checkbox)
                    .help("Off keeps it in the \u{00BB} menu and in Settings")
            }
            .font(.system(size: 12))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Divider()
            VStack(spacing: 12) {
                FilterMatchRow(evaluation: model.evaluate(draft.filter)) {
                    withAnimation(.snappy(duration: 0.22)) { _ = draft.addSet() }
                }
                if confirmingDelete {
                    DeleteFilterConfirmation(name: saved.name) {
                        close()
                        model.deleteFilter(saved.id)
                    } cancel: {
                        withAnimation(.snappy(duration: 0.2)) { confirmingDelete = false }
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    HStack {
                        FilterLinkButton("Delete Filter\u{2026}", role: .destructive) {
                            withAnimation(.snappy(duration: 0.2)) { confirmingDelete = true }
                        }
                        Spacer()
                        Button("Cancel", action: close)
                            .keyboardShortcut(.cancelAction)
                        Button("Save", action: save)
                            .keyboardShortcut(.defaultAction)
                            .buttonStyle(.borderedProminent)
                            .disabled(trimmedName.isEmpty || !hasChanges)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: FilterPopoverMetrics.width)
        .fixedSize(horizontal: false, vertical: true)
        .disabled(!model.canChangeSavedFilters)
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        guard hasChanges else { close(); return }
        if model.saveEdits(to: saved.id, name: trimmedName, filter: draft.filter,
                           groupBy: grouping.savedFilterGroupBy, showsAsTab: showsAsTab) {
            close()
        }
    }
}

/// Asking before a saved filter is deleted, in place of the footer's buttons, so the popover
/// stays where it is. It says plainly that History keeps it.
struct DeleteFilterConfirmation: View {
    let name: String
    let delete: () -> Void
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "trash")
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 2) {
                Text("Delete \u{201C}\(name)\u{201D}?")
                    .font(.system(size: 12, weight: .semibold))
                Text("Settings, History keeps it, and can bring it back.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Keep", action: cancel)
                .keyboardShortcut(.cancelAction)
            Button("Delete", role: .destructive, action: delete)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(.red)
        }
    }
}

/// Group By for a saved filter, up to two levels, with the same choices as the list's group
/// by menu: None, then each thing to group by, alone or with a second level.
struct GroupingPicker: View {
    @Binding var grouping: ListGrouping

    var body: some View {
        Menu {
            Toggle("None", isOn: choice(.none))
            Divider()
            ForEach(ListGrouping.Property.allCases) { first in
                Menu(first.name) {
                    Toggle("\(first.name) Only", isOn: choice(ListGrouping(first)))
                    Section("Then By") {
                        ForEach(first.secondLevelChoices) { second in
                            Toggle(second.name, isOn: choice(ListGrouping(first, then: second)))
                        }
                    }
                }
            }
        } label: {
            Text(grouping.isNone ? "None" : grouping.name)
        }
        .fixedSize()
        .accessibilityLabel("Group by, \(grouping.name)")
    }

    private func choice(_ value: ListGrouping) -> Binding<Bool> {
        Binding { grouping == value } set: { if $0 { grouping = value } }
    }
}
