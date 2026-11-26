import Foundation

/// The review threads on one line of a diff, as the line's marker shows them.
public struct DiffThreadMarker: Sendable, Hashable {
    /// Oldest first. The marker opens the first.
    public var threadIDs: [String]
    /// The person who started the first thread.
    public var firstCommenter: String

    /// "1 thread · Ada Park", "2 threads · Ada Park".
    public var label: String {
        "\(threadIDs.count) \(threadIDs.count == 1 ? "thread" : "threads") · \(firstCommenter)"
    }
}

/// One row of a diff in inline mode: a hunk header or a line.
public struct DiffRow: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable {
        case hunkHeader
        case context
        case added
        case removed
    }

    /// The row's position in the document, so ids are stable and cheap.
    public var id: Int
    public var kind: Kind
    public var oldLineNumber: Int?
    public var newLineNumber: Int?
    /// The line without its marker, tabs expanded. For a hunk header, the header as written.
    public var text: String
    /// The patch said `\ No newline at end of file` after this line.
    public var hasNoNewlineAtEnd: Bool
    public var threads: DiffThreadMarker?

    public init(id: Int, kind: Kind, oldLineNumber: Int? = nil, newLineNumber: Int? = nil, text: String,
                hasNoNewlineAtEnd: Bool = false, threads: DiffThreadMarker? = nil) {
        self.id = id
        self.kind = kind
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
        self.text = text
        self.hasNoNewlineAtEnd = hasNoNewlineAtEnd
        self.threads = threads
    }

    /// `−` for removed, `+` for added, a space otherwise. The symbol is always drawn beside the
    /// color, so the color is never the only sign.
    public var marker: String {
        switch kind {
        case .added: "+"
        case .removed: "−"
        case .context, .hunkHeader: " "
        }
    }
}

/// One row of a diff in side by side mode: a hunk header across both sides, or the old line on
/// the left and the new on the right. A side with no line is blank filler.
public struct SideBySideRow: Sendable, Hashable, Identifiable {
    public var id: Int
    /// Set for a hunk header row, which has no sides.
    public var hunk: HunkSummary?
    /// The old line: context or removed.
    public var left: DiffRow?
    /// The new line: context or added.
    public var right: DiffRow?

    public init(id: Int, hunk: HunkSummary? = nil, left: DiffRow? = nil, right: DiffRow? = nil) {
        self.id = id
        self.hunk = hunk
        self.left = left
        self.right = right
    }
}

/// A hunk's line ranges, for its header in side by side mode: "Old · 98–107", "New · 98–115".
public struct HunkSummary: Sendable, Hashable {
    public var oldStart: Int, oldCount: Int, newStart: Int, newCount: Int
    public var section: String

    public var oldRange: String { Self.range(oldStart, oldCount) }
    public var newRange: String { Self.range(newStart, newCount) }

    /// `@@ -98,10 +98,18 @@ authMiddleware`
    public var header: String {
        var text = "@@ -\(oldStart),\(oldCount) +\(newStart),\(newCount) @@"
        if !section.isEmpty { text += " \(section)" }
        return text
    }

    static func range(_ start: Int, _ count: Int) -> String {
        switch count {
        case 0: "none"
        case 1: "\(start)"
        default: "\(start)–\(start + count - 1)"
        }
    }
}

/// One file's diff, worked out once from its patch: the rows for both modes, where each review
/// thread sits, and the longest line, so a view can size every row the same without measuring
/// them. Building it reads the patch once; nothing in it grows with the screen.
///
/// It is a plain value and `Sendable`, so it can be built off the main thread and cached per file.
public struct DiffDocument: Sendable, Hashable {
    /// What the body of the diff is.
    public enum Body: Sendable, Hashable {
        /// Lines to show, in `rows` and `sideBySideRows`.
        case lines
        /// A binary file. Nothing is shown line by line.
        case binary
        /// A rename with no change to the content.
        case renamedWithoutChanges
        /// No patch: GitHub sends none for very large files, and an empty file has none.
        case noPatch
        /// The patch did not parse.
        case unreadable(String)
    }

    public var path: String
    public var previousPath: String?
    public var changeKind: FileChangeKind
    public var additions: Int
    public var deletions: Int
    public var body: Body
    public var rows: [DiffRow]
    public var sideBySideRows: [SideBySideRow]
    /// The longest line's length in characters, tabs expanded.
    public var longestLineLength: Int
    /// The inline row each thread is on, by thread id.
    public var inlineRowByThread: [String: Int]
    /// The side by side row each thread is on, by thread id.
    public var sideBySideRowByThread: [String: Int]

    /// A tab is drawn as this many spaces.
    public static let tabWidth = 4

    /// Builds the document for `file`, with markers for the `threads` on it. Threads on other
    /// files are ignored, and so are threads whose line is not in the patch, such as outdated ones.
    public init(file: ChangedFile, threads: [ReviewThread] = []) {
        path = file.path
        previousPath = file.previousPath
        changeKind = file.changeKind
        additions = file.additions
        deletions = file.deletions
        rows = []
        sideBySideRows = []
        longestLineLength = 0
        inlineRowByThread = [:]
        sideBySideRowByThread = [:]

        if file.isBinary {
            body = .binary
            return
        }
        guard let text = file.patch, !text.isEmpty else {
            body = file.changeKind == .renamed ? .renamedWithoutChanges : .noPatch
            return
        }
        let patch: Patch
        do {
            patch = try PatchParser.parse(text)
        } catch {
            body = .unreadable("\(error)")
            return
        }
        if patch.isBinary {
            body = .binary
            return
        }
        guard !patch.hunks.isEmpty else {
            body = file.changeKind == .renamed ? .renamedWithoutChanges : .noPatch
            return
        }
        body = .lines

        // Threads by the line they point at: new line numbers on the right, old on the left.
        var rightThreads: [Int: [ReviewThread]] = [:]
        var leftThreads: [Int: [ReviewThread]] = [:]
        for thread in threads where thread.path == file.path {
            switch thread.side {
            case .right: rightThreads[thread.line, default: []].append(thread)
            case .left: leftThreads[thread.line, default: []].append(thread)
            }
        }
        func marker(_ found: [ReviewThread]?) -> DiffThreadMarker? {
            guard let found, let first = found.first else { return nil }
            return DiffThreadMarker(threadIDs: found.map(\.id), firstCommenter: first.startedBy?.displayName ?? "Unknown")
        }

        var rows: [DiffRow] = []
        rows.reserveCapacity(patch.hunks.reduce(0) { $0 + $1.lines.count + 1 })
        var side: [SideBySideRow] = []
        side.reserveCapacity(rows.capacity)
        var longest = 0
        var inlineByThread: [String: Int] = [:]
        var sideByThread: [String: Int] = [:]

        for hunk in patch.hunks {
            let summary = HunkSummary(oldStart: hunk.oldStart, oldCount: hunk.oldCount,
                                      newStart: hunk.newStart, newCount: hunk.newCount, section: hunk.section)
            rows.append(DiffRow(id: rows.count, kind: .hunkHeader, text: summary.header))
            side.append(SideBySideRow(id: side.count, hunk: summary))

            // Removed lines waiting for the added lines that replace them, for side by side.
            var pendingRemoved: [DiffRow] = []
            var pendingAdded: [DiffRow] = []
            func flushPairs() {
                for index in 0..<max(pendingRemoved.count, pendingAdded.count) {
                    let left = index < pendingRemoved.count ? pendingRemoved[index] : nil
                    let right = index < pendingAdded.count ? pendingAdded[index] : nil
                    for id in (left?.threads?.threadIDs ?? []) + (right?.threads?.threadIDs ?? []) {
                        sideByThread[id] = side.count
                    }
                    side.append(SideBySideRow(id: side.count, left: left, right: right))
                }
                pendingRemoved.removeAll(keepingCapacity: true)
                pendingAdded.removeAll(keepingCapacity: true)
            }

            for line in hunk.lines {
                let text = Self.expandingTabs(line.text)
                longest = max(longest, text.count)
                let kind: DiffRow.Kind
                let threadMarker: DiffThreadMarker?
                switch line.kind {
                case .context:
                    kind = .context
                    // A thread on a context line can name it from either side.
                    threadMarker = marker((line.newLineNumber.flatMap { rightThreads[$0] } ?? [])
                                          + (line.oldLineNumber.flatMap { leftThreads[$0] } ?? []))
                case .added:
                    kind = .added
                    threadMarker = marker(line.newLineNumber.flatMap { rightThreads[$0] })
                case .removed:
                    kind = .removed
                    threadMarker = marker(line.oldLineNumber.flatMap { leftThreads[$0] })
                }
                let row = DiffRow(id: rows.count, kind: kind, oldLineNumber: line.oldLineNumber,
                                  newLineNumber: line.newLineNumber, text: text,
                                  hasNoNewlineAtEnd: line.hasNoNewlineAtEnd, threads: threadMarker)
                for id in threadMarker?.threadIDs ?? [] where inlineByThread[id] == nil {
                    inlineByThread[id] = row.id
                }
                rows.append(row)

                switch kind {
                case .removed:
                    // An added line before this removed one ends the previous change.
                    if !pendingAdded.isEmpty { flushPairs() }
                    pendingRemoved.append(row)
                case .added:
                    pendingAdded.append(row)
                case .context, .hunkHeader:
                    flushPairs()
                    for id in threadMarker?.threadIDs ?? [] { sideByThread[id] = side.count }
                    side.append(SideBySideRow(id: side.count, left: row, right: row))
                }
            }
            flushPairs()
        }

        self.rows = rows
        sideBySideRows = side
        longestLineLength = longest
        inlineRowByThread = inlineByThread
        sideBySideRowByThread = sideByThread
    }

    /// The row a thread is on in a mode, or nil when its line is not in the patch.
    public func row(forThread id: String, mode: DiffMode) -> Int? {
        switch mode {
        case .inline: inlineRowByThread[id]
        case .sideBySide: sideBySideRowByThread[id]
        }
    }

    /// How many rows a mode has.
    public func rowCount(_ mode: DiffMode) -> Int {
        mode == .inline ? rows.count : sideBySideRows.count
    }

    static func expandingTabs(_ text: String) -> String {
        guard text.contains("\t") else { return text }
        var result = ""
        result.reserveCapacity(text.count + 8)
        var column = 0
        for character in text {
            if character == "\t" {
                let spaces = tabWidth - column % tabWidth
                result.append(String(repeating: " ", count: spaces))
                column += spaces
            } else {
                result.append(character)
                column += 1
            }
        }
        return result
    }
}
