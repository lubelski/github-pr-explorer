import GitHubPRExplorerCore
import SwiftUI

/// Settings, Layouts: every layout with a small drawing of its arrangement, where it comes from,
/// and which is the default, and every layout file that failed with its problem.
struct LayoutsSettingsView: View {
    let configuration: ConfigurationModel
    @State private var deleting: LayoutEntry?

    var body: some View {
        let snapshot = configuration.snapshot
        let problems = snapshot.problems.filter { $0.file.hasPrefix(ConfigurationStore.layoutsFolderName + "/") || $0.file.hasPrefix("built in") }
        Form {
            Section {
                FolderLine(configuration: configuration)
            }
            if !problems.isEmpty {
                Section {
                    ForEach(problems, id: \.self) { problem in
                        ProblemRow(problem: problem, configuration: configuration)
                    }
                } header: {
                    Text(problems.count == 1 ? "A layout file could not be used" : "\(problems.count) layout files could not be used")
                }
            }
            Section {
                ForEach(snapshot.layouts) { entry in
                    LayoutRow(entry: entry, isDefault: entry.id == snapshot.defaultLayout.id,
                              configuration: configuration, deleting: $deleting)
                }
            } header: {
                Text("Layouts")
            } footer: {
                FileFootnote(text: "Built-in layouts cannot be changed. Duplicate to Edit writes a copy to layouts/, where you or your agent can rearrange it. A file with a built-in layout's id replaces it.")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Delete \(deleting?.layout.name ?? "this layout")?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { entry in
            Button("Delete", role: .destructive) {
                if let file = entry.source.file { configuration.delete(file: file) }
            }
        } message: { entry in
            Text("\(entry.source.file ?? "The file") is removed from the configuration folder. It stays in History, where you can restore it.")
        }
    }
}

/// Where the configuration folder is, and that an agent can edit it.
struct FolderLine: View {
    let configuration: ConfigurationModel
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Layouts are files in the configuration folder. A coding agent can edit them, and the app picks up a change as soon as it is saved.")
                .fixedSize(horizontal: false, vertical: true)
            Text(configuration.displayPath)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
            HStack {
                Button(copied ? "Copied" : "Copy Folder Path") {
                    configuration.copyFolderPath()
                    copied = true
                }
                Button("Show in Finder") { configuration.showInFinder() }
            }
        }
    }
}

struct LayoutRow: View {
    let entry: LayoutEntry
    let isDefault: Bool
    let configuration: ConfigurationModel
    @Binding var deleting: LayoutEntry?

    var body: some View {
        HStack(spacing: 14) {
            LayoutThumbnail(layout: entry.layout)
                .frame(width: 112, height: 72)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.layout.name).fontWeight(.medium)
                    if isDefault { Tag(text: "Default", color: .accentColor) }
                }
                Text(sourceText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text(shapeText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Set as Default") { configuration.setDefaultLayout(entry.id) }
                .disabled(isDefault)
            Button("Duplicate to Edit") { configuration.duplicate(entry.id) }
            Group {
            if let file = entry.source.file {
                Menu {
                    Button("Show in Finder") { configuration.showInFinder(file) }
                    Divider()
                    Button("Delete…", role: .destructive) { deleting = entry }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Show in Finder or delete")
            } else {
                // Keeps the buttons of every row lined up.
                Color.clear
            }
            }
            .frame(width: 24)
        }
        .padding(.vertical, 2)
    }

    private var sourceText: String {
        switch entry.source {
        case .builtIn: "Built in"
        case .file(let file, let overrides): overrides ? "\(file), replacing the built-in" : file
        }
    }

    private var shapeText: String {
        let tabs = entry.layout.tabs.count
        let blocks = entry.layout.placements.count
        return "\(tabs) \(tabs == 1 ? "tab" : "tabs"), \(blocks) \(blocks == 1 ? "block" : "blocks")"
    }
}

/// A small drawing of a layout: its tabs across the top when it has more than one, and the
/// first tab's columns at their widths, each block a grey rectangle, a small block shorter
/// than a large one.
struct LayoutThumbnail: View {
    let layout: PageLayout

    var body: some View {
        let tab = layout.tabs.first
        VStack(alignment: .leading, spacing: 4) {
            if layout.tabs.count > 1 {
                HStack(spacing: 3) {
                    ForEach(Array(layout.tabs.enumerated()), id: \.offset) { index, _ in
                        Capsule()
                            .fill(index == 0 ? Color.accentColor.opacity(0.8) : Color.secondary.opacity(0.35))
                            .frame(width: 14, height: 4)
                    }
                }
            }
            GeometryReader { proxy in
                let columns = tab?.columns ?? []
                let spacing: CGFloat = 3
                let total = columns.reduce(0) { $0 + $1.width }
                let available = max(0, proxy.size.width - spacing * CGFloat(max(0, columns.count - 1)))
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                        VStack(spacing: spacing) {
                            ForEach(Array(column.blocks.enumerated()), id: \.offset) { _, block in
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(Color.secondary.opacity(0.45))
                                    .frame(height: block.size == .large ? 10 : 5)
                            }
                        }
                        .frame(width: total > 0 ? available * column.width / total : 0, alignment: .top)
                    }
                }
            }
            .clipped()
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Style.hairline))
        .accessibilityLabel("A drawing of the layout \(layout.name)")
    }
}
