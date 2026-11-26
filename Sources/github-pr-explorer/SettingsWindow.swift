import AppKit
import GitHubPRExplorerCore
import SwiftUI

/// The sections of the Settings window, in sidebar order.
///
/// Experiments is second to last and Debugging is always last. A new section goes above
/// Experiments, with its view in `SettingsRootView.detail`.
enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case layouts
    case history
    case experiments
    case debugging

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .layouts: "Layouts"
        case .history: "History"
        case .experiments: "Experiments"
        case .debugging: "Debugging"
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .layouts: "rectangle.split.3x1"
        case .history: "clock.arrow.circlepath"
        case .experiments: "flask"
        case .debugging: "ladybug"
        }
    }
}

/// What the Settings window needs besides the configuration: what Debugging reports, and the
/// updater for General's Updates group.
struct SettingsContext {
    var build: BuildInfo
    var world: MockWorld
    var updater: AppUpdater
}

/// The Settings window's content: a fixed-width sidebar of sections, and the section beside it.
/// The selected section is window state, not configuration, so it is kept in the preferences
/// as the owner's other apps keep it.
struct SettingsRootView: View {
    static let sidebarWidth: CGFloat = 200
    static let size = CGSize(width: 900, height: 620)
    static let minimumSize = CGSize(width: 760, height: 480)
    static let selectedSectionKey = "SettingsSelectedSection"

    let configuration: ConfigurationModel
    let context: SettingsContext
    @AppStorage(Self.selectedSectionKey) private var storedSection: SettingsSection = .general
    /// Set by a render, which never reads or writes the preferences.
    var renderedSection: SettingsSection?
    @Environment(\.isRenderingPreview) private var rendering

    private var section: SettingsSection { renderedSection ?? storedSection }

    var body: some View {
        // A plain row rather than a split view, so the sidebar keeps its width: it cannot be
        // dragged or collapsed, and there is no sidebar button.
        HStack(spacing: 0) {
            List(selection: Binding<SettingsSection?>(
                get: { rendering ? nil : section },
                set: { if let new = $0 { storedSection = new } }
            )) {
                ForEach(SettingsSection.allCases) { item in
                    // The sidebar draws the selected row's title heavier, which widens it. A
                    // weight on the title's own Text keeps one weight across hover and selection.
                    Label {
                        Text(item.title).fontWeight(.regular)
                    } icon: {
                        Image(systemName: item.symbolName)
                    }
                    .tag(item)
                    // Offscreen, a list's selection does not draw, so a render draws it.
                    .listRowBackground(rendering && section == item
                        ? RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .unemphasizedSelectedContentBackgroundColor))
                            .padding(.horizontal, 10)
                        : nil)
                }
            }
            .listStyle(.sidebar)
            .frame(width: Self.sidebarWidth)
            Divider()
            detail
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        }
        .frame(minWidth: Self.minimumSize.width, idealWidth: Self.size.width, maxWidth: .infinity,
               minHeight: Self.minimumSize.height, idealHeight: Self.size.height, maxHeight: .infinity)
        .standardTitleBar()
        // An edit on disk is normally seen by the folder watcher. Coming forward reads the
        // folder again too, in case one was missed.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            if !rendering { configuration.reloadFromDisk() }
        }
    }

    @ViewBuilder private var detail: some View {
        switch section {
        case .general: GeneralSettingsView(configuration: configuration, context: context)
        case .layouts: LayoutsSettingsView(configuration: configuration)
        case .history: HistorySettingsView(configuration: configuration)
        case .experiments: ExperimentsSettingsView(configuration: configuration)
        case .debugging: DebuggingSettingsView(configuration: configuration, context: context)
        }
    }
}

/// Where a section's values are kept, as a line at the foot of its form.
struct FileFootnote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct GeneralSettingsView: View {
    let configuration: ConfigurationModel
    let context: SettingsContext
    @Environment(\.isRenderingPreview) private var rendering

    var body: some View {
        let settings = configuration.snapshot.settings
        Form {
            Section {
                Picker(selection: Binding(get: { settings.appearance }, set: { configuration.setAppearance($0) })) {
                    ForEach(Appearance.allCases, id: \.self) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                } label: {
                    Text("Appearance")
                    Text("System follows the Mac's light or dark setting.")
                }
                .pickerStyle(.segmented)
                Picker(selection: Binding(get: { configuration.snapshot.defaultLayout.id }, set: { configuration.setDefaultLayout($0) })) {
                    ForEach(configuration.snapshot.layouts) { entry in
                        Text(entry.layout.name).tag(entry.id)
                    }
                } label: {
                    Text("Default layout")
                    Text("Every pull request page opens with it. The layout menu in the window changes only the window you are in.")
                }
                Toggle(isOn: Binding(get: { settings.hidesBotEventsInActivity }, set: { configuration.setHidesBotEvents($0) })) {
                    Text("Hide bot events in Activity at first")
                    Text("Events from bots are folded into one row, which opens with Show.")
                }
            } footer: {
                FileFootnote(text: "Saved in settings.json in the configuration folder. Editing that file, or `github-pr-explorer-ctl config set`, changes these too.")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
            }
            // Only a release build can update itself, so only it shows Updates. A render shows
            // the group as a release build would.
            if context.updater.isAvailable || rendering {
                updatesSection(settings)
            }
            if let problem = configuration.snapshot.problems.first(where: { $0.file == ConfigurationSettings.fileName }) {
                Section {
                    ProblemRow(problem: problem, configuration: configuration)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func updatesSection(_ settings: ConfigurationSettings) -> some View {
        Section {
            Toggle(isOn: Binding(get: { settings.updatesAutomatically }, set: { configuration.setUpdatesAutomatically($0) })) {
                Text("Update automatically")
                Text("Checks about once a day and downloads a newer release. Restart to update shows in the title bar, and the update installs when the app quits.")
            }
            LabeledContent {
                Button(AppUpdater.checkTitle) { context.updater.checkForUpdates() }
                    .disabled(!context.updater.canCheck && !rendering)
            } label: {
                Text("Version")
                Text(context.build.summary)
            }
        } header: {
            Text("Updates")
        } footer: {
            FileFootnote(text: "Update automatically is saved in settings.json as updatesAutomatically. Check for Updates is also in the app menu.")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
        }
    }
}

/// Features being tried, each a switch, off until turned on. See `Experiment`.
struct ExperimentsSettingsView: View {
    let configuration: ConfigurationModel

    var body: some View {
        if Experiment.allCases.isEmpty {
            ContentUnavailableView {
                Label("No Experiments Right Now", systemImage: "flask")
            } description: {
                Text("A feature being tried shows here as a switch, off until you turn it on. Its switch is saved in settings.json under experiments.")
            }
        } else {
            Form {
                Section {
                    ForEach(Experiment.allCases) { experiment in
                        Toggle(isOn: Binding(
                            get: { configuration.snapshot.settings.isOn(experiment) },
                            set: { configuration.setExperiment(experiment, on: $0) })) {
                            Text(experiment.title)
                            Text(experiment.summary)
                        }
                    }
                } footer: {
                    FileFootnote(text: "Saved in settings.json under experiments. With a switch off, the app is as it was.")
                }
            }
            .formStyle(.grouped)
        }
    }
}

/// One file that failed: the file, where in it, what is wrong, and what the app does about it.
struct ProblemRow: View {
    let problem: ConfigurationProblem
    let configuration: ConfigurationModel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(problem.path.isEmpty ? problem.file : "\(problem.file), at \(problem.path)")
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                Text(problem.problem)
                    .fixedSize(horizontal: false, vertical: true)
                if !problem.consequence.isEmpty {
                    Text(problem.consequence)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if !problem.file.hasPrefix("built in") {
                Button("Show in Finder") { configuration.showInFinder(problem.file) }
            }
        }
    }
}
