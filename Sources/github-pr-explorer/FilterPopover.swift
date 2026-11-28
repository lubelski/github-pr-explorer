import GitHubPRExplorerCore
import SwiftUI

/// The filter button at the end of the tabs row. It opens the Filter popover, and fills with
/// the accent color while a filter is applied on the tab. Option-Command-F opens it too.
struct FilterButton: View {
    @Bindable var model: AppModel

    var body: some View {
        let isOn = model.hasUnsavedFilter
        Button {
            model.showsFilterPopover.toggle()
        } label: {
            Image(systemName: isOn ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .font(.system(size: 14))
                .foregroundStyle(isOn || model.showsFilterPopover ? Color.accentColor : Color.secondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .keyboardShortcut("f", modifiers: [.option, .command])
        .help(isOn ? "A filter is applied on this tab. Click to change it. (Option-Command-F)"
                   : "Filter the list by status, organization, repository, author, review state or draft (Option-Command-F)")
        .accessibilityLabel(isOn ? "Filter, applied" : "Filter")
        .popover(isPresented: $model.showsFilterPopover, arrowEdge: .bottom) {
            FilterPopover(model: model) { model.showsFilterPopover = false }
        }
    }
}

/// The Filter popover, after Figma row 11: a filter made on the spot. It starts from what the
/// tab shows now: its saved filter's conditions, or the filter already applied on it. Nothing
/// in the list changes until Apply. Cancel, Escape or a click outside discards the edits.
struct FilterPopover: View {
    let model: AppModel
    var close: () -> Void = {}
    @State private var draft: FilterDraft
    /// True while the footer asks for a name to save under.
    @State private var saving: Bool

    init(model: AppModel, draft: FilterDraft? = nil, saving: Bool = false, close: @escaping () -> Void = {}) {
        self.model = model
        self.close = close
        _draft = State(initialValue: draft ?? FilterDraft(model.currentFilter))
        _saving = State(initialValue: saving)
    }

    var body: some View {
        VStack(spacing: 0) {
            FilterPopoverHeader(summary: draft.filter.summary) {
                Text("Filter")
                    .font(.system(size: 15, weight: .semibold))
                if !model.selectedFilter.isEverything {
                    Text("from \(model.selectedFilter.name)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } trailing: {
                FilterLinkButton("Clear All") { withAnimation(.snappy(duration: 0.2)) { draft.removeAll() } }
                    .disabled(draft.sets.isEmpty)
            }
            Divider()
            FilterSetsEditor(draft: $draft, model: model)
            Divider()
            VStack(spacing: 12) {
                FilterMatchRow(evaluation: model.evaluate(draft.filter)) {
                    withAnimation(.snappy(duration: 0.22)) { _ = draft.addSet() }
                }
                if saving {
                    SaveFilterForm(model: model, filter: draft.filter) {
                        close()
                    } cancel: {
                        withAnimation(.snappy(duration: 0.2)) { saving = false }
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    HStack {
                        FilterLinkButton("Save as Filter\u{2026}") { withAnimation(.snappy(duration: 0.2)) { saving = true } }
                            .disabled(!model.canChangeSavedFilters || draft.isEmpty)
                            .help(model.canChangeSavedFilters ? "Keep this filter as a tab" : "Saved filters cannot be changed here")
                        Spacer()
                        Button("Cancel", action: close)
                            .keyboardShortcut(.cancelAction)
                        Button("Apply") {
                            model.applyFilter(draft.filter)
                            close()
                        }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                    }
                    .controlSize(.regular)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: FilterPopoverMetrics.width)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Saving a filter: a name and whether to keep the list's grouping. On a tab that is already a
/// saved filter it offers to update that one or to save a new one. Used in the Filter popover's
/// footer and in the popover from Save… on the line under the tabs.
struct SaveFilterForm: View {
    enum Choice: Hashable { case update, new }

    let model: AppModel
    let filter: PullRequestFilter
    let done: () -> Void
    let cancel: () -> Void
    var cancelTitle = "Back"
    @State private var name = ""
    @State private var choice: Choice
    @State private var keepsGrouping = true
    @FocusState private var nameFocused: Bool

    init(model: AppModel, filter: PullRequestFilter, name: String = "", choice: Choice? = nil, cancelTitle: String = "Back",
         done: @escaping () -> Void, cancel: @escaping () -> Void) {
        self.model = model
        self.cancelTitle = cancelTitle
        self.filter = filter
        self.done = done
        self.cancel = cancel
        _name = State(initialValue: name)
        _choice = State(initialValue: choice ?? (model.selectedFilter.isEverything ? .new : .update))
    }

    private var current: SavedFilter { model.selectedFilter }
    private var canSave: Bool { choice == .update || !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !current.isEverything {
                Picker("Save", selection: $choice) {
                    Text("Update \u{201C}\(current.name)\u{201D}").tag(Choice.update)
                    Text("Save as a new filter").tag(Choice.new)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }
            if choice == .new {
                HStack(spacing: 8) {
                    Text("Name")
                        .foregroundStyle(.secondary)
                    TextField("Name", text: $name, prompt: Text(suggestedName))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .focused($nameFocused)
                        .onSubmit(save)
                }
            }
            if !model.listGrouping.isNone {
                Toggle("Keep the grouping: \(model.listGrouping.name)", isOn: $keepsGrouping)
                    .toggleStyle(.checkbox)
                    .help("Choosing the tab groups the list this way again")
            }
            HStack {
                Text(choice == .new ? "It becomes the last tab, saved in saved-filters.json."
                                    : "\u{201C}\(current.name)\u{201D} changes for good, in saved-filters.json.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                Spacer()
                Button(cancelTitle, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button(choice == .update ? "Update" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
        }
        .onAppear { nameFocused = choice == .new }
        .onChange(of: choice) { _, new in nameFocused = new == .new }
    }

    /// A name drawn from the filter, offered as the field's placeholder: its plain words, short.
    private var suggestedName: String {
        let words = filter.summary.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return words.count > 40 ? String(words.prefix(39)) + "\u{2026}" : words
    }

    private func save() {
        guard canSave else { return }
        let made = switch choice {
        case .update: model.updateSelectedFilter(with: filter, keepsGrouping: keepsGrouping && !model.listGrouping.isNone)
        case .new: model.saveNewFilter(filter, name: name, keepsGrouping: keepsGrouping && !model.listGrouping.isNone)
        }
        if made { done() }
    }
}

/// The line under the tabs while a filter is applied and not saved, after Figma row 11's third
/// stage: what the filter is, in plain words, with Save… and Clear. The list never hides pull
/// requests without saying so.
struct AppliedFilterLine: View {
    @Bindable var model: AppModel
    @State private var saving = false

    var body: some View {
        let filter = model.appliedFilter ?? .everything
        let words = filter.summary
        HStack(spacing: 6) {
            Circle()
                .fill(Color.orange)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(model.selectedFilter.isEverything ? words : "\(model.selectedFilter.name), changed: \(words)")
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(words)
            Button("Save\u{2026}") { saving = true }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.accentColor)
                .disabled(!model.canChangeSavedFilters)
                .help(model.selectedFilter.isEverything ? "Save this filter as a tab" : "Update \u{201C}\(model.selectedFilter.name)\u{201D}, or save as a new filter")
                .popover(isPresented: $saving, arrowEdge: .bottom) {
                    SaveFilterPopover(model: model, filter: filter) { saving = false }
                }
            Button("Clear") { withAnimation(.snappy(duration: 0.2)) { model.clearAppliedFilter() } }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.accentColor)
                .help("Go back to \u{201C}\(model.selectedFilter.name)\u{201D} as saved")
        }
        .font(Style.secondary)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Filter applied, not saved")
    }
}

/// The popover from Save… on the line under the tabs, after Figma row 11's fourth stage.
struct SaveFilterPopover: View {
    let model: AppModel
    let filter: PullRequestFilter
    var name = ""
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.selectedFilter.isEverything ? "Save Filter" : "Save Changes")
                .font(.system(size: 13, weight: .semibold))
            Text(filter.summary)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            SaveFilterForm(model: model, filter: filter, name: name, cancelTitle: "Cancel", done: close, cancel: close)
        }
        .padding(14)
        .frame(width: 360)
    }
}
