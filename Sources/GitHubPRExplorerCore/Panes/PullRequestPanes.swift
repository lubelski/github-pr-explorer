import CoreGraphics
import Foundation

/// A pane that slides over the pull request page. Its id is a `PaneStackPath` entry.
///
/// The page is the base. A file's diff opens over it, and a review thread opens over the diff.
public enum PullRequestPane: Sendable, Hashable {
    /// The diff, with the file tree, showing this file.
    case files(path: String)
    /// One review thread.
    case thread(id: String)

    /// Reads a path entry, `file:<path>` or `thread:<id>`. Nil for anything else.
    public init?(entry: String) {
        if entry.hasPrefix("file:") {
            self = .files(path: String(entry.dropFirst("file:".count)))
        } else if entry.hasPrefix("thread:") {
            self = .thread(id: String(entry.dropFirst("thread:".count)))
        } else {
            return nil
        }
    }

    /// The path entry for this pane.
    public var entry: String {
        switch self {
        case .files(let path): "file:\(path)"
        case .thread(let id): "thread:\(id)"
        }
    }
}

extension PaneStackPath {
    /// The pane at a depth, or nil for the base or an entry that is not a pane.
    public func pane(at depth: Int) -> PullRequestPane? {
        entry(at: depth).flatMap(PullRequestPane.init(entry:))
    }

    /// The file whose diff is open, if any.
    public var openFilePath: String? {
        if case .files(let path) = pane(at: 1) { return path }
        return nil
    }

    /// The thread open over the diff, if any.
    public var openThreadID: String? {
        if case .thread(let id) = pane(at: 2) { return id }
        return nil
    }
}

extension PullRequest {
    /// The panes that show a review thread: its file's diff with the thread on top. Nil when the
    /// thread is not on this pull request, or its file is no longer among the changed files.
    public func paneStack(showingThread id: String) -> PaneStackPath? {
        guard let thread = reviewThreads.first(where: { $0.id == id }),
              files.contains(where: { $0.path == thread.path })
        else { return nil }
        return PaneStackPath([PullRequestPane.files(path: thread.path).entry, PullRequestPane.thread(id: id).entry])
    }

    /// The longest start of `path` this pull request can show: a file it changes, then a thread
    /// on that file. Anything after the first entry that does not fit is dropped.
    public func validPrefix(of path: PaneStackPath) -> PaneStackPath {
        guard case .files(let filePath) = path.pane(at: 1), files.contains(where: { $0.path == filePath }) else {
            return PaneStackPath()
        }
        guard case .thread(let id) = path.pane(at: 2),
              reviewThreads.contains(where: { $0.id == id && $0.path == filePath })
        else { return path.prefix(1) }
        return path.prefix(2)
    }
}

/// How a diff is drawn.
public enum DiffMode: String, Codable, Sendable, Hashable, CaseIterable {
    /// One column, removed lines above the added lines that replace them.
    case inline
    /// The old file on the left and the new on the right, line against line.
    case sideBySide

    public var title: String {
        switch self {
        case .inline: "Inline"
        case .sideBySide: "Side by side"
        }
    }
}

/// How wide the parts of the diff stack are: the page's strip, the diff's strip under a thread,
/// and whether the diff's file tree is full or a narrow rail.
///
/// The rule, in order:
///
/// 1. The page's strip is 300 points, so the page stays readable beside the diff.
/// 2. It narrows to a 24-point sliver when the diff needs the room: in side by side mode, with
///    a thread open over the diff, or when a full strip and a full tree would leave the diff
///    less than 720 points.
/// 3. Then the file tree narrows to a rail, in side by side mode or when the full tree would
///    still leave the diff less than 720 points.
/// 4. A thread pane is 420 points. The diff's strip is what is left of the diff beside it.
/// 5. Whatever these ask, `PaneStackLayout` has the last word, so the top pane keeps at least
///    its minimum in a very narrow window.
///
/// The page gives way before the tree, as the oldest strip gives way first in the stack.
public enum DiffPaneLayout {
    public static let pageStripWidth: CGFloat = 300
    public static let sliverWidth: CGFloat = PaneStackLayout.collapsedWidth
    public static let minimumDiffWidth: CGFloat = 720
    public static let treeWidth: CGFloat = 220
    public static let railWidth: CGFloat = 40
    public static let threadPaneWidth: CGFloat = 420

    public struct Widths: Sendable, Equatable {
        /// Each covered pane's strip, oldest (the page's) first. Empty at the base.
        public var strips: [CGFloat]
        /// The diff pane's file tree is a rail of marks instead of names.
        public var treeIsRail: Bool

        public init(strips: [CGFloat], treeIsRail: Bool) {
            self.strips = strips
            self.treeIsRail = treeIsRail
        }
    }

    /// The widths for a stack `depth` panes deep (1 is the diff, 2 a thread over it), in a pane
    /// area `available` points wide.
    public static func widths(available: CGFloat, mode: DiffMode, depth: Int) -> Widths {
        guard depth >= 1 else { return Widths(strips: [], treeIsRail: false) }
        let wantsSliver = mode == .sideBySide || depth >= 2
            || available - pageStripWidth - treeWidth < minimumDiffWidth
        let page = wantsSliver ? sliverWidth : pageStripWidth
        let diffPaneWidth = available - page
        let treeIsRail = mode == .sideBySide || diffPaneWidth - treeWidth < minimumDiffWidth

        var preferred = [page]
        if depth >= 2 {
            preferred.append(max(0, diffPaneWidth - threadPaneWidth))
            // Deeper panes, if any are ever added, keep a sliver of each pane under them.
            preferred.append(contentsOf: Array(repeating: sliverWidth, count: max(0, depth - 2)))
        }
        return Widths(strips: PaneStackLayout.stripWidths(preferred: preferred, available: available), treeIsRail: treeIsRail)
    }
}

extension FileGroups {
    /// Every listed file's path, in the order the tree shows them: by folder, then within it.
    public var orderedPaths: [String] { groups.flatMap { $0.files.map(\.path) } }

    /// The file `offset` places from `current` in tree order, for the arrow keys. It stops at
    /// either end rather than wrapping. With no current file, down picks the first and up the last.
    public func path(movingFrom current: String?, by offset: Int) -> String? {
        let paths = orderedPaths
        guard !paths.isEmpty else { return nil }
        guard let current, let position = paths.firstIndex(of: current) else {
            return offset >= 0 ? paths.first : paths.last
        }
        return paths[min(max(0, position + offset), paths.count - 1)]
    }
}
