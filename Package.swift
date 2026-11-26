// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "github-pr-explorer",
    platforms: [.macOS(.v27)],
    dependencies: [
        // The updater. Only the app links it, and only `AppUpdater.swift` imports it.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.1"),
    ],
    targets: [
        // Models, derived logic, the index protocol, page layouts, and the mock world. Foundation only.
        .target(
            name: "GitHubPRExplorerCore",
            // The layouts that ship, as the JSON files a person's own layout would be.
            resources: [.copy("Layout/BuiltInLayouts")]
        ),
        // The command line tool over the index: the mock world or the synced one, and one sync.
        .executableTarget(
            name: "github-pr-explorer-ctl",
            dependencies: ["GitHubPRExplorerCore"]
        ),
        // The app: one window, the pull request list and the page drawn from a layout. It also
        // draws its views to PNG files with `--render-previews`, for pull request evidence.
        .executableTarget(
            name: "github-pr-explorer",
            dependencies: ["GitHubPRExplorerCore", .product(name: "Sparkle", package: "Sparkle")]
        ),
        .testTarget(
            name: "GitHubPRExplorerCoreTests",
            dependencies: ["GitHubPRExplorerCore", "github-pr-explorer-ctl"],
            // Hand-written GitHub answers, read from the source folder by `FakeGitHub`.
            exclude: ["Fixtures"]
        ),
    ]
)
