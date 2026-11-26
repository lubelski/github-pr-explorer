import Testing
@testable import GitHubPRExplorerCore

@Suite struct PatchParserTests {
    @Test func addedLines() throws {
        let patch = try PatchParser.parse("@@ -0,0 +1,3 @@\n+one\n+two\n+three")
        #expect(patch.additions == 3)
        #expect(patch.deletions == 0)
        #expect(patch.lines.map(\.newLineNumber) == [1, 2, 3])
        #expect(patch.lines.allSatisfy { $0.kind == .added && $0.oldLineNumber == nil })
        #expect(patch.lines.map(\.text) == ["one", "two", "three"])
    }

    @Test func removedLines() throws {
        let patch = try PatchParser.parse("@@ -1,2 +0,0 @@\n-gone\n-also gone")
        #expect(patch.deletions == 2)
        #expect(patch.lines.map(\.oldLineNumber) == [1, 2])
        #expect(patch.lines.allSatisfy { $0.kind == .removed && $0.newLineNumber == nil })
    }

    @Test func contextAndChangesNumberBothSides() throws {
        let text = """
            @@ -10,4 +10,5 @@ function load() {
             const a = 1;
            -const b = 2;
            +const b = 3;
            +const c = 4;
             return a;
             }
            """
        let patch = try PatchParser.parse(text)
        let hunk = try #require(patch.hunks.first)
        #expect(hunk.section == "function load() {")
        #expect((hunk.oldStart, hunk.oldCount, hunk.newStart, hunk.newCount) == (10, 4, 10, 5))
        #expect(patch.lines.map(\.kind) == [.context, .removed, .added, .added, .context, .context])
        #expect(patch.lines.map(\.oldLineNumber) == [10, 11, nil, nil, 12, 13])
        #expect(patch.lines.map(\.newLineNumber) == [10, nil, 11, 12, 13, 14])
    }

    @Test func multipleHunks() throws {
        let text = """
            @@ -1,3 +1,3 @@
             a
            -b
            +B
             c
            @@ -40,2 +40,3 @@ section two
             x
            +y
             z
            """
        let patch = try PatchParser.parse(text)
        #expect(patch.hunks.count == 2)
        #expect(patch.hunks[1].section == "section two")
        #expect(patch.hunks[1].lines.map(\.newLineNumber) == [40, 41, 42])
        #expect(patch.additions == 2)
        #expect(patch.deletions == 1)
    }

    @Test func hunkHeaderWithoutCounts() throws {
        let patch = try PatchParser.parse("@@ -5 +5 @@\n-old\n+new")
        #expect(patch.hunks[0].oldCount == 1)
        #expect(patch.hunks[0].newCount == 1)
        #expect(patch.lines.map(\.text) == ["old", "new"])
    }

    @Test func removedLineThatLooksLikeAHeader() throws {
        // "--- a" inside a hunk is a removed line "-- a", not a file header.
        let patch = try PatchParser.parse("@@ -1,2 +1,1 @@\n--- a\n+++ b\n-x")
        #expect(patch.deletions == 2)
        #expect(patch.additions == 1)
        #expect(patch.lines.map(\.text) == ["-- a", "++ b", "x"])
        #expect(patch.oldPath == nil)
    }

    @Test func renameWithGitHeaders() throws {
        let text = """
            diff --git a/lib/mail/reset.ts b/mail/templates/reset.ts
            similarity index 91%
            rename from lib/mail/reset.ts
            rename to mail/templates/reset.ts
            index 3b18e51..a1c2f3d 100644
            --- a/lib/mail/reset.ts
            +++ b/mail/templates/reset.ts
            @@ -1,3 +1,3 @@
            -import { send } from './send';
            +import { send } from '../../lib/mail/send';

             export function reset() {}
            """
        let patch = try PatchParser.parse(text)
        #expect(patch.isRename)
        #expect(patch.oldPath == "lib/mail/reset.ts")
        #expect(patch.newPath == "mail/templates/reset.ts")
        #expect(patch.additions == 1)
        #expect(patch.deletions == 1)
        #expect(patch.lines[2].kind == .context)
        #expect(patch.lines[2].text == "")
    }

    @Test func pureRenameHasNoHunks() throws {
        let patch = try PatchParser.parse("diff --git a/old.ts b/new.ts\nsimilarity index 100%\nrename from old.ts\nrename to new.ts\n")
        #expect(patch.isRename)
        #expect(patch.hunks.isEmpty)
        #expect(patch.newPath == "new.ts")
    }

    @Test func newAndDeletedFileHeaders() throws {
        let added = try PatchParser.parse("diff --git a/x.ts b/x.ts\nnew file mode 100644\n--- /dev/null\n+++ b/x.ts\n@@ -0,0 +1 @@\n+hi\n")
        #expect(added.isNewFile)
        #expect(added.oldPath == nil)
        #expect(added.newPath == "x.ts")
        let removed = try PatchParser.parse("diff --git a/x.ts b/x.ts\ndeleted file mode 100644\n--- a/x.ts\n+++ /dev/null\n@@ -1 +0,0 @@\n-hi\n")
        #expect(removed.isDeletedFile)
        #expect(removed.newPath == nil)
    }

    @Test func noNewlineAtEndOfFile() throws {
        let text = "@@ -1,2 +1,2 @@\n a\n-b\n\\ No newline at end of file\n+b\n\\ No newline at end of file"
        let patch = try PatchParser.parse(text)
        #expect(patch.lines.count == 3)
        #expect(patch.lines.map(\.hasNoNewlineAtEnd) == [false, true, true])
        #expect(patch.additions == 1)
        #expect(patch.deletions == 1)
    }

    @Test func binaryFile() throws {
        let patch = try PatchParser.parse("diff --git a/logo.png b/logo.png\nindex 1..2 100644\nBinary files a/logo.png and b/logo.png differ\n")
        #expect(patch.isBinary)
        #expect(patch.hunks.isEmpty)
    }

    @Test func emptyTextIsAnEmptyPatch() throws {
        #expect(try PatchParser.parse("").hunks.isEmpty)
    }

    @Test func invalidHunkHeaderThrows() {
        #expect(throws: PatchParseError.invalidHunkHeader(lineNumber: 1)) { try PatchParser.parse("@@ nonsense @@\n+x") }
    }

    @Test func truncatedHunkThrows() {
        #expect(throws: PatchParseError.truncatedHunk(lineNumber: 2)) { try PatchParser.parse("@@ -1,3 +1,3 @@\n a") }
    }

    @Test func strayLineThrows() {
        #expect(throws: PatchParseError.unexpectedLine(lineNumber: 1)) { try PatchParser.parse("hello") }
    }

    @Test func writerComputesHeadersThatParseBack() throws {
        let text = PatchWriter.write([
            PatchWriter.Hunk(oldStart: 3, section: "f()", lines: [" a", "-b", "+c", "+d", " e"]),
            PatchWriter.Hunk(oldStart: 30, lines: [" x", "-y", " z"]),
        ])
        #expect(text.hasPrefix("@@ -3,3 +3,4 @@ f()\n"))
        #expect(text.contains("@@ -30,3 +31,2 @@\n"))
        let patch = try PatchParser.parse(text)
        #expect(patch.additions == 2)
        #expect(patch.deletions == 2)
        #expect(patch.hunks[1].newStart == 31)
    }

    @Test func writerForAddedAndRemovedFiles() {
        #expect(PatchWriter.write([PatchWriter.Hunk(oldStart: 0, lines: ["+a", "+b"])]) == "@@ -0,0 +1,2 @@\n+a\n+b")
        #expect(PatchWriter.write([PatchWriter.Hunk(oldStart: 1, lines: ["-a"])]) == "@@ -1 +0,0 @@\n-a")
    }
}
