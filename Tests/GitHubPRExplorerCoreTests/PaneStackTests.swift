import CoreGraphics
import Foundation
import Testing
@testable import GitHubPRExplorerCore

// The first two suites follow `mac-os-agent`'s `PaneStackTests`, from which the pane stack was
// ported, with ids from this app.

@Suite struct PaneStackPathTests {
    @Test func opensAnyNumberOfLevelsAndGoesBackOneAtATime() {
        var path = PaneStackPath()
        #expect(path.isAtBase)
        for (index, id) in ["a", "b", "c", "d", "e", "f"].enumerated() {
            path.open(id)
            #expect(path.depth == index + 1)
            #expect(path.entry(at: path.depth) == id)
        }
        #expect(path.entries == ["a", "b", "c", "d", "e", "f"])
        #expect(path.opened(from: 0) == "a")
        #expect(path.opened(from: 5) == "f")
        #expect(path.opened(from: 6) == nil)
        #expect(path.entry(at: 0) == nil)

        var steps = 0
        while path.goBack() { steps += 1 }
        #expect(steps == 6)
        #expect(path.isAtBase)
        // Nothing is open, so going back does nothing and says so, and Escape keeps its old meaning.
        let wentBack = path.goBack()
        #expect(!wentBack)
        #expect(path == PaneStackPath())
    }

    @Test func goingBackToADepthClosesEveryPaneAboveIt() {
        var path = PaneStackPath(["a", "b", "c", "d"])
        path.goBack(to: 2)
        #expect(path.entries == ["a", "b"])
        path.goBack(to: 2)
        path.goBack(to: 7)
        #expect(path.entries == ["a", "b"])
        path.goBack(to: 0)
        #expect(path.isAtBase)
        path.goBack(to: -1)
        #expect(path.isAtBase)
    }

    @Test func openingFromACoveredPaneReplacesEverythingAboveIt() {
        var path = PaneStackPath(["file:auth/middleware.ts", "thread:t1"])
        path.open("file:auth/session.ts", from: 0)
        #expect(path.entries == ["file:auth/session.ts"])
        path.open("thread:t2")
        path.open("thread:t3", from: 1)
        #expect(path.entries == ["file:auth/session.ts", "thread:t3"])
    }

    @Test func aClickOnAStripOpensAnotherRowOrGoesBack() {
        var path = PaneStackPath(["file:a.ts", "thread:t1"])
        path.clickStrip(at: 0, on: nil)
        #expect(path.isAtBase)

        path = PaneStackPath(["file:a.ts", "thread:t1"])
        // The open file's own row in the page's strip goes back to the page too.
        path.clickStrip(at: 0, on: "file:a.ts")
        #expect(path.isAtBase)

        path = PaneStackPath(["file:a.ts", "thread:t1"])
        path.clickStrip(at: 0, on: "file:b.ts")
        #expect(path.entries == ["file:b.ts"])

        path = PaneStackPath(["file:a.ts", "thread:t1"])
        path.clickStrip(at: 1, on: "thread:t2")
        #expect(path.entries == ["file:a.ts", "thread:t2"])
        path.clickStrip(at: 1, on: nil)
        #expect(path.entries == ["file:a.ts"])
    }

    @Test func prefixDescriptionAndReplace() {
        var path = PaneStackPath(["file:a.ts", "thread:t1"])
        #expect(path.prefix(1).entries == ["file:a.ts"])
        #expect(path.prefix(-3).isAtBase)
        #expect(path.description == "file:a.ts/thread:t1")
        path.replace(with: ["file:b.ts"])
        #expect(path.entries == ["file:b.ts"])
    }
}

@Suite struct PaneStackLayoutTests {
    @Test func stripsKeepTheirWidthWhenTheTopPaneHasRoom() {
        let widths = PaneStackLayout.stripWidths(preferred: [56, 170], available: 700)
        #expect(widths == [56, 170])
        #expect(PaneStackLayout.leadingEdges(stripWidths: widths) == [0, 56, 226])
        #expect(PaneStackLayout.stripWidths(preferred: [], available: 100) == [])
        #expect(PaneStackLayout.topEdges(stripWidths: widths) == [0, 10, 20])
    }

    @Test func olderStripsCollapseFirst() {
        let collapsed = PaneStackLayout.collapsedWidth
        let widths = PaneStackLayout.stripWidths(preferred: [56, 170, 170], available: 600)
        #expect(widths == [collapsed, collapsed, 170])
        #expect(widths.reduce(0, +) <= 600 - PaneStackLayout.minimumTopWidth)
    }

    @Test func sliversGoAwayOldestFirstAndTheNearestStripStaysLongest() {
        let collapsed = PaneStackLayout.collapsedWidth
        let preferred = [CGFloat](repeating: 56, count: 9) + [170]
        let widths = PaneStackLayout.stripWidths(preferred: preferred, available: 560)
        #expect(widths.last == 170)
        #expect(widths.reduce(0, +) <= 240)
        let kept = widths.dropLast().enumerated().filter { $0.element > 0 }.map(\.offset)
        #expect(kept == Array((9 - kept.count)..<9))
        #expect(widths.dropLast().allSatisfy { $0 == 0 || $0 == collapsed })

        let tight = PaneStackLayout.stripWidths(preferred: [200, 200], available: 400)
        #expect(tight == [0, 80])
        #expect(PaneStackLayout.stripWidths(preferred: [200], available: 100) == [0])
        #expect(PaneStackLayout.topEdges(stripWidths: [0, 0, 24, 170]) == [0, 0, 0, 10, 20])
    }
}

@Suite struct PullRequestPaneTests {
    let world = MockWorld.standard
    var pr: PullRequest { world.index.pullRequest(MockWorld.workedExample)! }

    @Test func entriesRoundTrip() {
        for pane in [PullRequestPane.files(path: "auth/middleware.ts"), .thread(id: "PR_1_thread_1"), .files(path: "a:b/c.ts")] {
            #expect(PullRequestPane(entry: pane.entry) == pane)
        }
        #expect(PullRequestPane(entry: "something") == nil)
        let path = PaneStackPath(["file:auth/session.ts", "thread:t2"])
        #expect(path.openFilePath == "auth/session.ts")
        #expect(path.openThreadID == "t2")
        #expect(PaneStackPath().openFilePath == nil)
        #expect(PaneStackPath(["file:x"]).openThreadID == nil)
    }

    @Test func aThreadOpensOverItsFile() throws {
        let thread = try #require(pr.reviewThreads.first { $0.path == "auth/middleware.ts" })
        let path = try #require(pr.paneStack(showingThread: thread.id))
        #expect(path.openFilePath == "auth/middleware.ts")
        #expect(path.openThreadID == thread.id)
        #expect(pr.paneStack(showingThread: "no-such-thread") == nil)
    }

    @Test func aPathThatNamesWhatIsGoneFallsBackToWhatIsThere() throws {
        let thread = try #require(pr.reviewThreads.first { $0.path == "auth/middleware.ts" })
        #expect(pr.validPrefix(of: PaneStackPath(["file:gone.ts", "thread:\(thread.id)"])).isAtBase)
        #expect(pr.validPrefix(of: PaneStackPath(["thread:\(thread.id)"])).isAtBase)
        #expect(pr.validPrefix(of: PaneStackPath(["file:auth/session.ts", "thread:\(thread.id)"]))
                == PaneStackPath(["file:auth/session.ts"]))
        let full = PaneStackPath(["file:auth/middleware.ts", "thread:\(thread.id)", "more"])
        #expect(pr.validPrefix(of: full) == full.prefix(2))
    }

    @Test func arrowKeysMoveThroughTheTreeInItsOrder() {
        let groups = FileGroups(files: pr.files, codeOwners: pr.codeOwners)
        let paths = groups.orderedPaths
        #expect(paths.count == 9)
        #expect(Array(paths.prefix(3)) == ["auth/session.ts", "auth/middleware.ts", "auth/middleware.test.ts"])
        #expect(groups.path(movingFrom: "auth/session.ts", by: 1) == "auth/middleware.ts")
        #expect(groups.path(movingFrom: "auth/middleware.test.ts", by: 1) == paths[3])
        #expect(groups.path(movingFrom: paths[0], by: -1) == paths[0])
        #expect(groups.path(movingFrom: paths.last, by: 1) == paths.last)
        #expect(groups.path(movingFrom: nil, by: 1) == paths.first)
        #expect(groups.path(movingFrom: nil, by: -1) == paths.last)
        #expect(FileGroups(files: [], codeOwners: []).path(movingFrom: nil, by: 1) == nil)
    }
}

@Suite struct DiffPaneLayoutTests {
    typealias Layout = DiffPaneLayout

    @Test func atTheBaseThereAreNoStrips() {
        #expect(Layout.widths(available: 1200, mode: .inline, depth: 0) == .init(strips: [], treeIsRail: false))
    }

    @Test func inlineInAWideAreaKeepsThePageStripAndTheTree() {
        // 1260 - 300 - 220 leaves 740 for the diff.
        let widths = Layout.widths(available: 1260, mode: .inline, depth: 1)
        #expect(widths.strips == [300])
        #expect(!widths.treeIsRail)
    }

    @Test func thePageNarrowsFirstWhenTheDiffWouldBeUnder720() {
        // 1180 - 300 - 220 is 660, too little. With a sliver, 1180 - 24 - 220 is 936.
        let widths = Layout.widths(available: 1180, mode: .inline, depth: 1)
        #expect(widths.strips == [24])
        #expect(!widths.treeIsRail)
        // Exactly 720 is enough.
        #expect(Layout.widths(available: 1240, mode: .inline, depth: 1).strips == [300])
        #expect(Layout.widths(available: 1239, mode: .inline, depth: 1).strips == [24])
    }

    @Test func thenTheTreeNarrowsToARail() {
        // 900 - 24 - 220 is 656, so the tree goes to a rail too.
        let widths = Layout.widths(available: 900, mode: .inline, depth: 1)
        #expect(widths.strips == [24])
        #expect(widths.treeIsRail)
        #expect(!Layout.widths(available: 964, mode: .inline, depth: 1).treeIsRail)
        #expect(Layout.widths(available: 963, mode: .inline, depth: 1).treeIsRail)
    }

    @Test func sideBySideAlwaysTakesTheRoom() {
        let widths = Layout.widths(available: 2400, mode: .sideBySide, depth: 1)
        #expect(widths.strips == [24])
        #expect(widths.treeIsRail)
    }

    @Test func aThreadOverTheDiffNarrowsThePageAndLeavesTheDiffBesideIt() {
        let widths = Layout.widths(available: 1260, mode: .inline, depth: 2)
        // The page is a sliver, the thread pane is 420, and the diff shows in between.
        #expect(widths.strips == [24, 1260 - 24 - 420])
        #expect(PaneStackLayout.leadingEdges(stripWidths: widths.strips) == [0, 24, 840])
        #expect(PaneStackLayout.topEdges(stripWidths: widths.strips) == [0, 10, 20])
        // The diff under the thread keeps the tree it had at its own width.
        #expect(!widths.treeIsRail)
    }

    @Test func aVeryNarrowAreaStillLeavesTheTopPaneItsMinimum() {
        let widths = Layout.widths(available: 500, mode: .inline, depth: 2)
        #expect(widths.strips.reduce(0, +) <= 500 - PaneStackLayout.minimumTopWidth)
        #expect(widths.treeIsRail)
        let one = Layout.widths(available: 330, mode: .sideBySide, depth: 1)
        #expect(one.strips == [10])
    }
}
