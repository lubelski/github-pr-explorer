import Foundation

/// The version, build number and commit, as `scripts/bundle.sh` stamps them into `Info.plist`:
/// `CFBundleShortVersionString`, `CFBundleVersion` and `GitHubPRExplorerGitCommit`.
struct BuildInfo: Sendable, Hashable {
    var version: String
    var build: String
    var commit: String

    /// The running app's, read from its bundle. A binary run outside a bundle, such as a debug
    /// build from `swift run`, has no `Info.plist` and says so.
    static var current: BuildInfo {
        let info = Bundle.main.infoDictionary ?? [:]
        return BuildInfo(
            version: info["CFBundleShortVersionString"] as? String ?? "dev",
            build: info["CFBundleVersion"] as? String ?? "0",
            commit: info["GitHubPRExplorerGitCommit"] as? String ?? "unbundled")
    }

    /// A fixed value for renders, so a render reads the same at every commit.
    static let preview = BuildInfo(version: "0.1", build: "0", commit: "preview")

    /// "0.1 (4) · b41c422"
    var summary: String { "\(version) (\(build)) · \(commit)" }

    /// "Version 0.1, build 4, commit b41c422"
    var details: String { "Version \(version), build \(build), commit \(commit)" }
}
