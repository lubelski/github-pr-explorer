import Foundation

/// The rules for updating the app, kept apart from Sparkle so they can be tested.
///
/// Only a release build updates itself. `scripts/release.sh` has `scripts/bundle.sh` write the
/// feed address and the public signing key into Info.plist. A build without them never
/// updates itself, so a development copy is never replaced by a release.
public enum AppUpdates {
    /// Whether a bundle with this Info.plist has a feed to update from.
    public static func hasFeed(_ info: [String: Any]?) -> Bool {
        guard let feed = info?["SUFeedURL"] as? String, let key = info?["SUPublicEDKey"] as? String else {
            return false
        }
        return !feed.isEmpty && !key.isEmpty
    }

    /// The version with the build number, such as "0.2.0 (512)".
    public static func version(_ info: [String: Any]?) -> String {
        let version = info?["CFBundleShortVersionString"] as? String ?? "development"
        let build = info?["CFBundleVersion"] as? String
        return version + (build.map { " (\($0))" } ?? "")
    }

    /// An update Sparkle has found, as the title bar shows it. When nothing is pending the
    /// title bar shows nothing extra.
    public struct Pending: Equatable, Sendable {
        public enum Stage: Equatable, Sendable {
            /// A newer release is in the feed and is not downloaded. Clicking shows Sparkle's
            /// own window, which offers to download and install it.
            case available
            /// A newer release is downloaded and checked. Clicking quits and relaunches into it.
            /// It also installs on its own the next time the app quits.
            case readyToInstall
        }

        public var stage: Stage
        /// The release's version as people read it, such as "0.3.0".
        public var version: String

        public init(stage: Stage, version: String) {
            self.stage = stage
            self.version = version
        }

        /// The indicator's short text.
        public var title: String {
            switch stage {
            case .available: "Update available"
            case .readyToInstall: "Restart to update"
            }
        }

        /// The SF Symbol beside it.
        public var symbolName: String {
            switch stage {
            case .available: "arrow.down.circle"
            case .readyToInstall: "arrow.clockwise.circle"
            }
        }

        /// The tooltip, which says what clicking does.
        public var help: String {
            switch stage {
            case .available:
                "Version \(version) is available. Click to see it and install it."
            case .readyToInstall:
                "Version \(version) is downloaded. Click to restart into it now, or it installs the next time the app quits."
            }
        }
    }
}
