import Foundation
import GitHubPRExplorerCore
import Testing

@Suite struct AppUpdatesTests {
    @Test func aBuildWithTheFeedAndKeyUpdatesItself() {
        #expect(AppUpdates.hasFeed([
            "SUFeedURL": "https://example.com/appcast.xml",
            "SUPublicEDKey": "a-public-key",
        ]))
    }

    @Test func aBuildWithoutBothKeysNeverUpdatesItself() {
        #expect(!AppUpdates.hasFeed(nil))
        #expect(!AppUpdates.hasFeed([:]))
        #expect(!AppUpdates.hasFeed(["SUFeedURL": "https://example.com/appcast.xml"]))
        #expect(!AppUpdates.hasFeed(["SUPublicEDKey": "a-public-key"]))
        #expect(!AppUpdates.hasFeed(["SUFeedURL": "", "SUPublicEDKey": "a-public-key"]))
        #expect(!AppUpdates.hasFeed(["SUFeedURL": "https://example.com/appcast.xml", "SUPublicEDKey": ""]))
    }

    @Test func theVersionShowsTheBuildNumber() {
        #expect(AppUpdates.version(["CFBundleShortVersionString": "0.2.0", "CFBundleVersion": "512"]) == "0.2.0 (512)")
        #expect(AppUpdates.version(nil) == "development")
    }

    @Test func anAvailableUpdateOffersToShowItself() {
        let pending = AppUpdates.Pending(stage: .available, version: "0.3.0")
        #expect(pending.title == "Update available")
        #expect(pending.help.contains("0.3.0"))
        #expect(pending.symbolName == "arrow.down.circle")
    }

    @Test func aDownloadedUpdateOffersToRestart() {
        let pending = AppUpdates.Pending(stage: .readyToInstall, version: "0.3.0")
        #expect(pending.title == "Restart to update")
        #expect(pending.help.contains("0.3.0"))
        #expect(pending.help.contains("next time the app quits"))
    }

    /// The feed and the public key that `scripts/release.sh` passes to `bundle.sh`: the feed is
    /// in the latest release of this repo, and the key is the one every app shares.
    @Test func theReleaseScriptPointsAtThisRepoAndTheSharedKey() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let release = try String(contentsOf: root.appendingPathComponent("scripts/release.sh"), encoding: .utf8)
        #expect(release.contains("lubelski/github-pr-explorer"))
        #expect(release.contains("https://github.com/$REPO/releases/latest/download/appcast.xml"))
        let key = try String(contentsOf: root.appendingPathComponent("scripts/sparkle-public-key.txt"), encoding: .utf8)
        #expect(key.trimmingCharacters(in: .whitespacesAndNewlines).count == 44)
        let bundle = try String(contentsOf: root.appendingPathComponent("scripts/bundle.sh"), encoding: .utf8)
        for plistKey in ["SUFeedURL", "SUPublicEDKey", "SUEnableAutomaticChecks", "SUAutomaticallyUpdate"] {
            #expect(bundle.contains("<key>\(plistKey)</key>"), "bundle.sh does not write \(plistKey)")
        }
    }
}
