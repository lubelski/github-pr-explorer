import GitHubPRExplorerCore
import SwiftUI

/// Settings, History: every version of the configuration folder, newest first, what each one
/// changed, and Restore. Restoring adds a new version, so nothing is ever lost.
struct HistorySettingsView: View {
    let configuration: ConfigurationModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Every change to the configuration is kept as a version, whoever made it: this window, an agent or editor changing a file, or github-pr-explorer-ctl.")
                Text("Restoring a version adds a new version with the files as they were then. Nothing is lost: the versions after it stay here and can be restored too.")
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder private var content: some View {
        if configuration.versions.isEmpty {
            if let problem = configuration.historyProblem {
                ContentUnavailableView {
                    Label("History Is Not Being Kept", systemImage: "clock.badge.exclamationmark")
                } description: {
                    Text("\(problem)\n\nYour changes are still saved to the files. Only earlier versions are not kept.")
                }
            } else {
                ContentUnavailableView("No Versions Yet", systemImage: "clock.arrow.circlepath",
                                       description: Text("A version is added each time the configuration changes."))
            }
        } else {
            HStack(spacing: 0) {
                VersionList(configuration: configuration)
                    .frame(width: 270)
                Divider()
                if let version = selected {
                    VersionDetail(configuration: configuration, version: version,
                                  isLatest: version.id == configuration.versions.first?.id)
                        .id(version.id)
                }
            }
        }
    }

    private var selected: ConfigurationVersion? {
        let versions = configuration.versions
        return versions.first { $0.id == configuration.selectedVersionID } ?? versions.first
    }
}

extension ConfigurationVersion {
    /// "Today, 10:42", "Yesterday, 16:03" or "Nov 20, 2026 at 09:15", in the Mac's time zone.
    func timeText(relativeTo now: Date = Date()) -> String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) { return "Today, \(time)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday, \(time)"
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    var authorText: String {
        switch author {
        case "": "Unknown"
        case ChangeAuthor.editedOnDisk.rawValue: "Edited on disk"
        case ChangeAuthor.commandLine.rawValue: "github-pr-explorer-ctl"
        case ChangeAuthor.app.rawValue: "The app"
        case ChangeAuthor.mainWindow.rawValue: "The main window"
        default: author
        }
    }

    var authorSymbol: String {
        switch author {
        case ChangeAuthor.settingsWindow.rawValue: "gearshape"
        case ChangeAuthor.editedOnDisk.rawValue: "doc.text"
        case ChangeAuthor.commandLine.rawValue: "terminal"
        case ChangeAuthor.mainWindow.rawValue: "macwindow"
        default: "app"
        }
    }
}

/// The time versions are measured from: now, or a render's fixed moment.
extension EnvironmentValues {
    @Entry var historyNow = Date()
}

struct VersionList: View {
    @Bindable var configuration: ConfigurationModel
    @Environment(\.isRenderingPreview) private var rendering
    @Environment(\.historyNow) private var now

    var body: some View {
        let selectedID = configuration.selectedVersionID ?? configuration.versions.first?.id
        List(selection: Binding<String?>(
            get: { rendering ? nil : selectedID },
            set: { configuration.selectedVersionID = $0 }
        )) {
            ForEach(configuration.versions) { version in
                VStack(alignment: .leading, spacing: 2) {
                    Text(version.summary)
                        .lineLimit(2)
                    HStack(spacing: 4) {
                        Image(systemName: version.authorSymbol)
                        Text("\(version.authorText) · \(version.timeText(relativeTo: now))")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                .padding(.vertical, 3)
                .tag(version.id)
                .listRowBackground(rendering && version.id == selectedID
                    ? RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.18)).padding(.horizontal, 6)
                    : nil)
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }
}

struct VersionDetail: View {
    let configuration: ConfigurationModel
    let version: ConfigurationVersion
    let isLatest: Bool
    @State private var confirming: String??
    @Environment(\.historyNow) private var now

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(version.summary)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(version.authorText) · \(version.timeText(relativeTo: now)) · version \(version.shortID)")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            HStack {
                Button(isLatest ? "This Is the Current Version" : "Restore This Version…") { confirming = .some(nil) }
                    .disabled(isLatest)
                    .help(isLatest ? "The files are already as this version has them." : "Puts every file back as it was in this version, as a new version.")
                if !isLatest && version.files.count > 1 {
                    Menu("Restore One File") {
                        ForEach(version.files, id: \.self) { file in
                            Button(file) { confirming = .some(file) }
                        }
                    }
                    .fixedSize()
                }
            }
            Text(version.files.count == 1 ? "Changed 1 file" : "Changed \(version.files.count) files")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            DiffText(text: configuration.diff(version))
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .confirmationDialog(
            confirmTitle,
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } })
        ) {
            Button("Restore") {
                if let choice = confirming { configuration.restore(version, file: choice) }
            }
        } message: {
            Text("This adds a new version with \(confirmFile ?? "the files") as \(confirmFile == nil ? "they were" : "it was") in version \(version.shortID). Nothing is lost: every version stays in History, so you can go back by restoring the one before.")
        }
    }

    private var confirmFile: String? { confirming.flatMap { $0 } }

    private var confirmTitle: String {
        "Restore \(confirmFile ?? "the configuration") to \(version.timeText(relativeTo: now))?"
    }
}

/// A unified diff, added lines green and removed lines red.
struct DiffText: View {
    let text: String

    var body: some View {
        // Vertical only, with long lines wrapped, so a whole change reads without scrolling
        // sideways.
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line.isEmpty ? " " : line)
                        .foregroundStyle(color(line))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(background(line))
                }
            }
            .font(.system(size: 11.5, design: .monospaced))
            .textSelection(.enabled)
            .padding(8)
        }
        .background(RoundedRectangle(cornerRadius: 6).fill(Style.surface))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Style.hairline))
    }

    /// The diff without git's index lines, which mean nothing to a person.
    private var lines: [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            .filter { !$0.hasPrefix("index ") && !$0.hasPrefix("new file mode") && !$0.hasPrefix("deleted file mode") }
            .reversed().drop { $0.isEmpty }.reversed()
    }

    private func color(_ line: String) -> Color {
        if line.hasPrefix("diff --git") || line.hasPrefix("+++") || line.hasPrefix("---") { return .primary }
        if line.hasPrefix("+") { return Style.added }
        if line.hasPrefix("-") { return Style.removed }
        if line.hasPrefix("@@") { return .secondary }
        return .primary
    }

    private func background(_ line: String) -> Color {
        if line.hasPrefix("diff --git") { return Color.primary.opacity(0.06) }
        if line.hasPrefix("+"), !line.hasPrefix("+++") { return Style.added.opacity(0.1) }
        if line.hasPrefix("-"), !line.hasPrefix("---") { return Style.removed.opacity(0.1) }
        return .clear
    }
}
