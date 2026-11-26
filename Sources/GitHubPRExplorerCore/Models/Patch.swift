import Foundation

public enum PatchLineKind: String, Codable, Sendable, Hashable, CaseIterable {
    case context
    case added
    case removed
}

/// One line of a hunk, without its leading ` `, `+` or `-`.
public struct PatchLine: Codable, Sendable, Hashable {
    public var kind: PatchLineKind
    public var text: String
    /// The line's number in the old file. Nil for an added line.
    public var oldLineNumber: Int?
    /// The line's number in the new file. Nil for a removed line.
    public var newLineNumber: Int?
    /// The patch said `\ No newline at end of file` after this line.
    public var hasNoNewlineAtEnd: Bool

    public init(kind: PatchLineKind, text: String, oldLineNumber: Int?, newLineNumber: Int?, hasNoNewlineAtEnd: Bool = false) {
        self.kind = kind
        self.text = text
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
        self.hasNoNewlineAtEnd = hasNoNewlineAtEnd
    }
}

public struct PatchHunk: Codable, Sendable, Hashable {
    public var oldStart: Int
    public var oldCount: Int
    public var newStart: Int
    public var newCount: Int
    /// The text after the second `@@`, usually the enclosing function. Can be empty.
    public var section: String
    public var lines: [PatchLine]

    public init(oldStart: Int, oldCount: Int, newStart: Int, newCount: Int, section: String, lines: [PatchLine]) {
        self.oldStart = oldStart
        self.oldCount = oldCount
        self.newStart = newStart
        self.newCount = newCount
        self.section = section
        self.lines = lines
    }
}

/// A unified patch for one file, parsed into hunks and lines.
public struct Patch: Codable, Sendable, Hashable {
    /// From a `diff --git` or `---` header, when the text had one. Nil for `/dev/null`.
    public var oldPath: String?
    public var newPath: String?
    public var isRename: Bool
    public var isNewFile: Bool
    public var isDeletedFile: Bool
    public var isBinary: Bool
    public var hunks: [PatchHunk]

    public init(
        oldPath: String? = nil,
        newPath: String? = nil,
        isRename: Bool = false,
        isNewFile: Bool = false,
        isDeletedFile: Bool = false,
        isBinary: Bool = false,
        hunks: [PatchHunk] = []
    ) {
        self.oldPath = oldPath
        self.newPath = newPath
        self.isRename = isRename
        self.isNewFile = isNewFile
        self.isDeletedFile = isDeletedFile
        self.isBinary = isBinary
        self.hunks = hunks
    }

    public var lines: [PatchLine] { hunks.flatMap(\.lines) }
    public var additions: Int { hunks.reduce(0) { $0 + $1.lines.count { $0.kind == .added } } }
    public var deletions: Int { hunks.reduce(0) { $0 + $1.lines.count { $0.kind == .removed } } }

    /// The line a review thread points at: by new line number on the right, old on the left.
    public func line(number: Int, side: DiffSide) -> PatchLine? {
        lines.first { line in
            switch side {
            case .right: line.kind != .removed && line.newLineNumber == number
            case .left: line.kind != .added && line.oldLineNumber == number
            }
        }
    }
}

public enum PatchParseError: Error, Equatable, Sendable {
    /// A line starting with `@@` that is not a valid hunk header. Lines count from 1.
    case invalidHunkHeader(lineNumber: Int)
    /// A line that is neither part of a hunk nor a header this parser knows.
    case unexpectedLine(lineNumber: Int)
    /// The text ended before the last hunk had as many lines as its header said.
    case truncatedHunk(lineNumber: Int)
}

/// Parses unified diff text for one file.
///
/// It reads GitHub's per-file `patch` field (hunks only) and the fuller `git diff` form with
/// `diff --git`, `rename from`, `---`, `+++` and `Binary files` headers. Hunk lengths come
/// from the hunk header, so a removed line that starts with `--` is not mistaken for a header.
public enum PatchParser {
    public static func parse(_ text: String) throws(PatchParseError) -> Patch {
        var patch = Patch()
        var rawLines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if rawLines.last == "" { rawLines.removeLast() }

        var hunk: PatchHunk?
        var oldRemaining = 0
        var newRemaining = 0
        var oldLine = 0
        var newLine = 0

        func finishHunk() {
            if let finished = hunk { patch.hunks.append(finished) }
            hunk = nil
        }

        for (offset, rawLine) in rawLines.enumerated() {
            let lineNumber = offset + 1
            let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine

            if line.hasPrefix("\\") {
                // "\ No newline at end of file" belongs to the line just before it.
                if var current = hunk, !current.lines.isEmpty {
                    current.lines[current.lines.count - 1].hasNoNewlineAtEnd = true
                    hunk = current
                } else if var last = patch.hunks.last, !last.lines.isEmpty {
                    last.lines[last.lines.count - 1].hasNoNewlineAtEnd = true
                    patch.hunks[patch.hunks.count - 1] = last
                }
                continue
            }

            if hunk != nil, oldRemaining > 0 || newRemaining > 0 {
                let marker = line.first
                let body = line.isEmpty ? "" : String(line.dropFirst())
                switch marker {
                case " ", nil:
                    hunk!.lines.append(PatchLine(kind: .context, text: body, oldLineNumber: oldLine, newLineNumber: newLine))
                    oldLine += 1; newLine += 1
                    oldRemaining -= 1; newRemaining -= 1
                case "+":
                    hunk!.lines.append(PatchLine(kind: .added, text: body, oldLineNumber: nil, newLineNumber: newLine))
                    newLine += 1
                    newRemaining -= 1
                case "-":
                    hunk!.lines.append(PatchLine(kind: .removed, text: body, oldLineNumber: oldLine, newLineNumber: nil))
                    oldLine += 1
                    oldRemaining -= 1
                default:
                    throw .unexpectedLine(lineNumber: lineNumber)
                }
                if oldRemaining < 0 || newRemaining < 0 { throw .unexpectedLine(lineNumber: lineNumber) }
                continue
            }

            if line.hasPrefix("@@") {
                finishHunk()
                guard let header = parseHunkHeader(line) else { throw .invalidHunkHeader(lineNumber: lineNumber) }
                hunk = PatchHunk(
                    oldStart: header.oldStart, oldCount: header.oldCount,
                    newStart: header.newStart, newCount: header.newCount,
                    section: header.section, lines: []
                )
                oldRemaining = header.oldCount
                newRemaining = header.newCount
                oldLine = header.oldStart
                newLine = header.newStart
                continue
            }

            finishHunk()
            if line.hasPrefix("diff --git ") {
                let paths = line.dropFirst("diff --git ".count).split(separator: " ", maxSplits: 1).map(String.init)
                if paths.count == 2 {
                    patch.oldPath = stripPrefix(paths[0])
                    patch.newPath = stripPrefix(paths[1])
                }
            } else if line.hasPrefix("--- ") {
                patch.oldPath = headerPath(line.dropFirst(4))
            } else if line.hasPrefix("+++ ") {
                patch.newPath = headerPath(line.dropFirst(4))
            } else if line.hasPrefix("rename from ") {
                patch.isRename = true
                patch.oldPath = String(line.dropFirst("rename from ".count))
            } else if line.hasPrefix("rename to ") {
                patch.isRename = true
                patch.newPath = String(line.dropFirst("rename to ".count))
            } else if line.hasPrefix("new file mode") {
                patch.isNewFile = true
            } else if line.hasPrefix("deleted file mode") {
                patch.isDeletedFile = true
            } else if line.hasPrefix("Binary files ") || line == "GIT binary patch" {
                patch.isBinary = true
            } else if line.hasPrefix("index ") || line.hasPrefix("similarity index")
                        || line.hasPrefix("dissimilarity index") || line.hasPrefix("old mode")
                        || line.hasPrefix("new mode") || line.hasPrefix("copy from") || line.hasPrefix("copy to")
                        || line.isEmpty {
                continue
            } else if patch.isBinary {
                // The body of a `GIT binary patch` block. Nothing in it is shown as lines.
                continue
            } else {
                throw .unexpectedLine(lineNumber: lineNumber)
            }
        }

        if hunk != nil, oldRemaining > 0 || newRemaining > 0 {
            throw .truncatedHunk(lineNumber: rawLines.count)
        }
        finishHunk()
        return patch
    }

    private struct HunkHeader {
        var oldStart: Int, oldCount: Int, newStart: Int, newCount: Int, section: String
    }

    /// `@@ -oldStart[,oldCount] +newStart[,newCount] @@[ section]`
    private static func parseHunkHeader(_ line: String) -> HunkHeader? {
        guard line.hasPrefix("@@ ") else { return nil }
        let rest = line.dropFirst(3)
        guard let close = rest.range(of: " @@") else { return nil }
        let ranges = rest[..<close.lowerBound].split(separator: " ")
        guard ranges.count == 2, ranges[0].first == "-", ranges[1].first == "+",
              let old = parseRange(ranges[0].dropFirst()),
              let new = parseRange(ranges[1].dropFirst())
        else { return nil }
        var section = String(rest[close.upperBound...])
        if section.hasPrefix(" ") { section.removeFirst() }
        return HunkHeader(oldStart: old.start, oldCount: old.count, newStart: new.start, newCount: new.count, section: section)
    }

    private static func parseRange(_ text: Substring) -> (start: Int, count: Int)? {
        let parts = text.split(separator: ",", omittingEmptySubsequences: false)
        guard let start = Int(parts[0]), start >= 0 else { return nil }
        if parts.count == 1 { return (start, 1) }
        guard parts.count == 2, let count = Int(parts[1]), count >= 0 else { return nil }
        return (start, count)
    }

    private static func stripPrefix(_ path: String) -> String {
        if path.hasPrefix("a/") || path.hasPrefix("b/") { return String(path.dropFirst(2)) }
        return path
    }

    private static func headerPath(_ text: Substring) -> String? {
        let path = String(text.split(separator: "\t", maxSplits: 1).first ?? "")
        if path == "/dev/null" { return nil }
        return stripPrefix(path)
    }
}

/// Writes unified patch text from hunk bodies, working out each header's counts and the new
/// side's start line. Mock data and tests use it so every hunk header is right.
public enum PatchWriter {
    public struct Hunk: Sendable {
        /// The first old line the hunk shows, or for a hunk with no old lines, the line it follows.
        public var oldStart: Int
        public var section: String
        /// Each line with its ` `, `+` or `-` marker. An empty line counts as an empty context line.
        public var lines: [String]

        public init(oldStart: Int, section: String = "", lines: [String]) {
            self.oldStart = oldStart
            self.section = section
            self.lines = lines
        }

        /// Takes the lines from text, one per line. A trailing newline is ignored.
        public init(oldStart: Int, section: String = "", text: String) {
            var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            if lines.last == "" { lines.removeLast() }
            self.init(oldStart: oldStart, section: section, lines: lines)
        }
    }

    /// The hunks must be in file order and must not overlap.
    public static func write(_ hunks: [Hunk], noNewlineAtEnd: Bool = false) -> String {
        var output: [String] = []
        var offset = 0
        for hunk in hunks {
            let lines = hunk.lines.map { $0.isEmpty ? " " : $0 }
            let added = lines.count { $0.hasPrefix("+") }
            let removed = lines.count { $0.hasPrefix("-") }
            let context = lines.count - added - removed
            let oldCount = context + removed
            let newCount = context + added
            var newStart = hunk.oldStart + offset
            if oldCount == 0 { newStart += 1 }
            if newCount == 0 { newStart -= 1 }
            if oldCount == 0 && newCount == 0 { newStart = hunk.oldStart + offset }
            var header = "@@ -\(range(hunk.oldStart, oldCount)) +\(range(newStart, newCount)) @@"
            if !hunk.section.isEmpty { header += " \(hunk.section)" }
            output.append(header)
            output.append(contentsOf: lines)
            offset += added - removed
        }
        if noNewlineAtEnd { output.append("\\ No newline at end of file") }
        return output.joined(separator: "\n")
    }

    private static func range(_ start: Int, _ count: Int) -> String {
        count == 1 ? "\(start)" : "\(start),\(count)"
    }
}
