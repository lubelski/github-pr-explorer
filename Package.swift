// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "github-pr-explorer",
    platforms: [.macOS(.v27)],
    targets: [
        // Models, derived logic, the index protocol, and the mock world. Foundation only.
        .target(name: "GitHubPRExplorerCore"),
        // The command line tool over the index. Today it reads the mock world.
        .executableTarget(
            name: "github-pr-explorer-ctl",
            dependencies: ["GitHubPRExplorerCore"]
        ),
        .testTarget(
            name: "GitHubPRExplorerCoreTests",
            dependencies: ["GitHubPRExplorerCore", "github-pr-explorer-ctl"]
        ),
    ]
)
