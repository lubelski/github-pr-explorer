import GitHubPRExplorerCore
import SwiftUI

/// Quiet status at the right end of the title bar, right-aligned, in this order: how fresh the
/// selected pull request is, a warning when a layout file could not be read, the version and
/// commit, and the layout menu last.
///
/// It is hosted in the title bar by `standardTitleBar(trailing:)`, outside the window's own
/// SwiftUI tree, so it gets nothing from the window's environment. What it needs is passed in.
struct TitleBarStatus: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 6) {
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
            // The update indicator goes here, between the version and the layout menu, when
            // the app gets an updater (MAC-47).
            layoutMenu
                .padding(.leading, 6)
        }
        .font(Style.secondary)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .fixedSize()
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
