import GitHubPRExplorerCore
import SwiftUI

/// The app's one window. Started from `main.swift`, which handles `--render-previews` first.
///
/// It reads the built-in mock world through the index: no network and no sign-in.
struct GitHubPRExplorerApp: App {
    @State private var model = AppModel(
        index: MockWorld.standard.index,
        now: MockWorld.now,
        library: .builtIn(),
        selection: MockWorld.workedExample,
        windowState: .standard)

    var body: some Scene {
        Window(AppName.display, id: "main") {
            MainWindowView(model: model)
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1480, height: 900)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .sidebar) {
                Button(model.showsList ? "Hide Pull Request List" : "Show Pull Request List") {
                    withAnimation(.snappy) { model.showsList.toggle() }
                }
                .keyboardShortcut("s", modifiers: [.control, .command])
            }
        }
    }
}
