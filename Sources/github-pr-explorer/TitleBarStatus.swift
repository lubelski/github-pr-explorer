import GitHubPRExplorerCore
import SwiftUI

/// Quiet status at the right end of the title bar, right-aligned, in this order: in GitHub
/// mode, the sync's state when it is syncing, has a problem, or no pull request is open; how
/// fresh the selected pull request is; a warning when a layout file could not be read; the
/// version and commit; an update indicator when an update waits; and the layout menu last.
///
/// It is hosted in the title bar by `standardTitleBar(trailing:)`, outside the window's own
/// SwiftUI tree, so it gets nothing from the window's environment. What it needs is passed in.
struct TitleBarStatus: View {
    @Bindable var model: AppModel
    var updater: AppUpdater
    /// A narrow window: the update indicator shows its symbol only.
    var compact = false

    var body: some View {
        HStack(spacing: 6) {
            if let summary = model.syncSummary,
               summary.isProblem || model.selectedPullRequest == nil || summary.text == "Syncing…" {
                syncLabel(summary)
                separator
            }
            if let pr = model.selectedPullRequest {
                let freshness = Freshness(provenance: pr.provenance, now: model.now)
                Text(freshness.summary)
                    .help(freshness.details.joined(separator: "\n"))
                separator
            }
            if !model.library.problems.isEmpty {
                let count = model.library.problems.count
                Label(count == 1 ? "A layout file could not be read" : "\(count) layout files could not be read",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .help(model.library.problems.map(\.description).joined(separator: "\n"))
                separator
            }
            Text(model.build.summary)
                .help(model.build.details)
            if let pending = updater.pending {
                updateIndicator(pending)
            }
            layoutMenu
                .padding(.leading, 6)
        }
        .font(Style.secondary)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .fixedSize()
    }

    /// The sync's state. A problem is orange with a warning sign, and its tooltip says what is
    /// wrong, what to do, and how old the data on screen is.
    /// In a narrow window it shows only a symbol, with the words in its tooltip, so it does not
    /// run into the centered name.
    @ViewBuilder private func syncLabel(_ summary: SyncStatusSummary) -> some View {
        let help = summary.text + "\n" + summary.help
        if summary.isProblem {
            Label(summary.text, systemImage: "exclamationmark.triangle")
                .labelStyle(compact ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
                .foregroundStyle(.orange)
                .help(help)
                .accessibilityLabel(summary.text)
        } else if compact {
            Image(systemName: "arrow.triangle.2.circlepath")
                .help(help)
                .accessibilityLabel(summary.text)
        } else {
            Text(summary.text)
                .help(help)
        }
    }

    /// A small button that offers the waiting update. It shows only while one waits.
    private func updateIndicator(_ pending: AppUpdates.Pending) -> some View {
        Button {
            updater.installPendingUpdate()
        } label: {
            if compact {
                Label(pending.title, systemImage: pending.symbolName)
                    .labelStyle(.iconOnly)
            } else {
                Label(pending.title, systemImage: pending.symbolName)
                    .labelStyle(.titleAndIcon)
            }
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .foregroundStyle(.tint)
        .fixedSize()
        .help(pending.help)
        .accessibilityLabel(pending.title)
        .padding(.leading, 6)
    }

    private var separator: some View {
        Text(verbatim: "·").foregroundStyle(.tertiary)
    }

    /// The current layout's name, and a menu of the layouts.
    private var layoutMenu: some View {
        Menu {
            Picker("Layout", selection: $model.layoutID) {
                ForEach(model.library.layouts) { layout in
                    Text(layout.name).tag(layout.id)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Label(model.layout.name, systemImage: "rectangle.3.group")
                .labelStyle(.titleAndIcon)
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .controlSize(.small)
        .fixedSize()
        .help("Layout: \(model.layout.name)")
    }
}

/// A label style chosen at run time.
struct AnyLabelStyle: LabelStyle {
    private let make: (Configuration) -> AnyView
    init<Style: LabelStyle>(_ style: Style) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}
