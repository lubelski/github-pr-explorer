import GitHubPRExplorerCore
import SwiftUI

/// Settings, Saved Filters, after Figma row 13: the list of saved filters, managed as a list
/// only. Drag to set the order of the tabs, a checkbox for whether each is a tab, and Rename
/// and Delete. Each row shows the name, the filter in plain words and its count. Everything is
/// first and fixed.
///
/// There is no condition editor here and no way to make a new filter: a filter is made in the
/// Filter popover with Save as Filter…, and changed from its tab with Edit Filter…. Everything
/// here is `saved-filters.json`.
struct SavedFiltersSettingsView: View {
    let configuration: ConfigurationModel
    /// The open pull requests counts are worked out over, and who "me" is.
    let pullRequests: [PullRequest]
    let context: FilterContext
    @State private var selection: String?
    @State private var renaming: SavedFilter?
    @State private var newName = ""
    @State private var deleting: SavedFilter?

    init(configuration: ConfigurationModel, index: any PullRequestIndex, now: Date, selection: String? = nil) {
        self.configuration = configuration
        pullRequests = index.allPullRequests
        context = FilterContext(viewer: index.viewer, now: now)
        _selection = State(initialValue: selection)
    }

    /// Opens Settings on this section, as Manage Saved Filters… in the window does.
    @MainActor
    static func open(_ openSettings: OpenSettingsAction) {
        UserDefaults.standard.set(SettingsSection.savedFilters.rawValue, forKey: SettingsRootView.selectedSectionKey)
        openSettings()
    }

    private var saved: [SavedFilter] { configuration.snapshot.savedFilters }
    private var selected: SavedFilter? { saved.first { $0.id == selection } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Saved Filters")
                    .font(.system(size: 20, weight: .semibold))
                Text("Each checked filter is a tab above the list, in this order. Drag to reorder.")
                    .foregroundStyle(.secondary)
            }
            if let problem = configuration.snapshot.problems.first(where: { $0.file == SavedFilterFile.fileName }) {
                ProblemRow(problem: problem, configuration: configuration)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.1)))
            }
            List(selection: $selection) {
                SavedFilterSettingsRow(saved: .everything, count: count(.everything), isFixed: true, showsAsTab: .constant(true))
                    .selectionDisabled()
                ForEach(saved) { filter in
                    SavedFilterSettingsRow(saved: filter, count: count(filter), isFixed: false,
                                           showsAsTab: Binding(get: { filter.showsAsTab }, set: { on in
                                               configuration.changeSavedFilter(id: filter.id, fromSettings: true) { $0.showsAsTab = on }
                                           }))
                        .tag(filter.id)
                        .contextMenu {
                            Button("Rename\u{2026}") { rename(filter) }
                            Button("Delete\u{2026}") { deleting = filter }
                        }
                }
                .onMove(perform: move)
            }
            .listStyle(.bordered)
            .alternatingRowBackgrounds(.disabled)
            .frame(minHeight: 200)
            .overlay {
                if saved.isEmpty {
                    Text("Only Everything. Make a filter in the Filter popover above the list, then Save as Filter\u{2026}")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.top, 60)
                        .padding(.horizontal, 40)
                }
            }
            HStack(spacing: 8) {
                Button("Rename\u{2026}") { if let selected { rename(selected) } }
                    .disabled(selected == nil)
                Button("Delete\u{2026}") { deleting = selected }
                    .disabled(selected == nil)
                Spacer()
            }
            FileFootnote(text: "Saved in saved-filters.json in the configuration folder, which `github-pr-explorer-ctl filters` and MCP change too. To change what a filter shows, right-click its tab above the list and choose Edit Filter\u{2026}")
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .alert("Rename Saved Filter", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") {
                if let renaming {
                    let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty { configuration.changeSavedFilter(id: renaming.id, fromSettings: true) { $0.name = name } }
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .confirmationDialog(deleting.map { "Delete \u{201C}\($0.name)\u{201D}?" } ?? "",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) {
                if let deleting { configuration.removeSavedFilter(id: deleting.id, fromSettings: true) }
                deleting = nil
                selection = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            Text("History keeps it, and can bring it back.")
        }
    }

    private func count(_ filter: SavedFilter) -> Int {
        filter.evaluate(pullRequests, context: context).count
    }

    private func rename(_ filter: SavedFilter) {
        newName = filter.name
        renaming = filter
    }

    /// One drag is one change and one version.
    private func move(from source: IndexSet, to destination: Int) {
        var reordered = saved
        reordered.move(fromOffsets: source, toOffset: destination)
        guard reordered != saved, let moved = source.first.map({ saved[$0] }),
              let position = reordered.firstIndex(of: moved) else { return }
        configuration.moveSavedFilter(id: moved.id, to: position + 1, fromSettings: true)
    }
}

/// A row: the drag handle, the checkbox for "is a tab", the name with its plain words under it,
/// and the count. Everything shows "fixed" in place of a handle and a count it cannot lose.
struct SavedFilterSettingsRow: View {
    let saved: SavedFilter
    let count: Int
    let isFixed: Bool
    @Binding var showsAsTab: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .opacity(isFixed ? 0 : 1)
                .accessibilityHidden(true)
            Toggle("Show as a tab", isOn: $showsAsTab)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(isFixed)
                .help(isFixed ? "Everything is always the first tab" : "Show as a tab above the list")
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: saved.name)
                    .foregroundStyle(showsAsTab ? .primary : .secondary)
                Text(saved.isEverything ? "Every open pull request" : saved.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(saved.summary)
            }
            Spacer(minLength: 8)
            if isFixed {
                Text("fixed").foregroundStyle(.tertiary)
            }
            Text("\(count)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}
