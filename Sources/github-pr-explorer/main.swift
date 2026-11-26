import AppKit

// `--render-previews <folder> [state ...]` draws the window's states to PNG files and quits,
// without starting the app: no window on screen, no menu bar, no focus.
let arguments = CommandLine.arguments
if arguments.contains(PreviewRenderer.argument) {
    let status = MainActor.assumeIsolated { PreviewRenderer.run(arguments: arguments) }
    exit(status)
}

GitHubPRExplorerApp.main()
