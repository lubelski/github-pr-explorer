import Foundation
import Testing
@testable import GitHubPRExplorerCore

@Suite struct DiffDocumentTests {
    let world = MockWorld.standard
    var example: PullRequest { world.index.pullRequest(MockWorld.workedExample)! }

    static func file(_ hunks: [PatchWriter.Hunk], path: String = "a.ts", kind: FileChangeKind = .modified) -> ChangedFile {
        let lines = hunks.flatMap(\.lines)
        return ChangedFile(path: path, changeKind: kind, additions: lines.count { $0.hasPrefix("+") },
                           deletions: lines.count { $0.hasPrefix("-") }, patch: PatchWriter.write(hunks))
    }

    @Test func inlineRowsHaveHunkHeadersNumbersAndMarkers() {
        let file = Self.file([PatchWriter.Hunk(oldStart: 10, section: "run()", lines: [" keep", "-old", "+new", "+more", " tail"])])
        let document = DiffDocument(file: file)
        #expect(document.body == .lines)
        #expect(document.rows.map(\.kind) == [.hunkHeader, .context, .removed, .added, .added, .context])
        #expect(document.rows[0].text == "@@ -10,3 +10,4 @@ run()")
        #expect(document.rows[1].oldLineNumber == 10 && document.rows[1].newLineNumber == 10)
        #expect(document.rows[2].oldLineNumber == 11 && document.rows[2].newLineNumber == nil)
        #expect(document.rows[3].oldLineNumber == nil && document.rows[3].newLineNumber == 11)
        #expect(document.rows[5].oldLineNumber == 12 && document.rows[5].newLineNumber == 13)
        #expect(document.rows.map(\.marker) == [" ", " ", "−", "+", "+", " "])
        #expect(document.rows.map(\.id) == Array(0..<6))
        #expect(document.longestLineLength == 4)
    }

    @Test func sideBySidePairsRemovedWithAddedAndFillsTheRest() {
        let file = Self.file([PatchWriter.Hunk(oldStart: 1, lines: [
            " a", "-b1", "-b2", "-b3", "+B1", " c", "+d1", "+d2", " e", "-f", "+F1", "+F2",
        ])])
        let rows = DiffDocument(file: file).sideBySideRows
        #expect(rows.first?.hunk?.oldRange == "1–7")
        #expect(rows.first?.hunk?.newRange == "1–8")
        func pair(_ row: SideBySideRow) -> String {
            "\(row.left?.text ?? "_")|\(row.right?.text ?? "_")"
        }
        #expect(rows.dropFirst().map(pair) == [
            "a|a", "b1|B1", "b2|_", "b3|_", "c|c", "_|d1", "_|d2", "e|e", "f|F1", "_|F2",
        ])
        // Each side keeps its own numbers.
        #expect(rows[2].left?.oldLineNumber == 2 && rows[2].right?.newLineNumber == 2)
        #expect(rows.map(\.id) == Array(0..<rows.count))
    }

    @Test func anAddedLineBeforeARemovedOneStartsANewPair() {
        let file = Self.file([PatchWriter.Hunk(oldStart: 1, lines: ["+x", "-y"])])
        let rows = DiffDocument(file: file).sideBySideRows.dropFirst()
        #expect(rows.map { "\($0.left?.text ?? "_")|\($0.right?.text ?? "_")" } == ["_|x", "y|_"])
    }

    @Test func threadsAreMarkedOnTheirLineOnEitherSide() throws {
        let pr = example
        let middleware = try #require(pr.files.first { $0.path == "auth/middleware.ts" })
        let document = DiffDocument(file: middleware, threads: pr.reviewThreads)
        let thread = try #require(pr.reviewThreads.first { $0.path == "auth/middleware.ts" })
        let index = try #require(document.row(forThread: thread.id, mode: .inline))
        let row = document.rows[index]
        #expect(row.newLineNumber == 112)
        #expect(row.kind == .added)
        #expect(row.threads?.label == "1 thread · Ada Park")
        let sideIndex = try #require(document.row(forThread: thread.id, mode: .sideBySide))
        #expect(document.sideBySideRows[sideIndex].right?.newLineNumber == 112)

        // Max's thread is on a removed line, by its old number.
        let login = try #require(pr.files.first { $0.path == "api/routes/login.ts" })
        let loginThread = try #require(pr.reviewThreads.first { $0.path == "api/routes/login.ts" })
        let loginDocument = DiffDocument(file: login, threads: pr.reviewThreads)
        let loginRow = try #require(loginDocument.row(forThread: loginThread.id, mode: .inline))
        #expect(loginDocument.rows[loginRow].kind == .removed)
        #expect(loginDocument.rows[loginRow].oldLineNumber == 27)
        #expect(loginDocument.rows[loginRow].text == loginThread.quotedLine)
        let loginSide = try #require(loginDocument.row(forThread: loginThread.id, mode: .sideBySide))
        #expect(loginDocument.sideBySideRows[loginSide].left?.oldLineNumber == 27)
        // Threads on other files mark nothing here.
        #expect(document.rows.compactMap(\.threads).count == 1)
    }

    @Test func twoThreadsOnOneLineShareAMarker() {
        let file = Self.file([PatchWriter.Hunk(oldStart: 1, lines: [" a", "+b"])])
        func thread(_ id: String, _ person: Person) -> ReviewThread {
            ReviewThread(id: id, path: "a.ts", line: 2, quotedLine: "b",
                         comments: [ReviewComment(id: "\(id)c", author: person, body: "?", createdAt: MockWorld.now)])
        }
        let document = DiffDocument(file: file, threads: [thread("t1", MockCast.adaPark), thread("t2", MockCast.samRivera)])
        #expect(document.rows[2].threads?.label == "2 threads · Ada Park")
        #expect(document.rows[2].threads?.threadIDs == ["t1", "t2"])
    }

    @Test func binaryRenamedAddedAndDeletedFilesEachHaveABody() throws {
        let pr = try #require(world.pullRequests.first { $0.title == "Move the email templates into their own folder" })
        func document(_ path: String) throws -> DiffDocument {
            DiffDocument(file: try #require(pr.files.first { $0.path == path }), threads: pr.reviewThreads)
        }
        #expect(try document("mail/assets/logo.png").body == .binary)
        let pureRename = try document("mail/templates/welcome.ts")
        #expect(pureRename.body == .renamedWithoutChanges)
        #expect(pureRename.previousPath == "lib/mail/welcome.ts")
        let changedRename = try document("mail/templates/password-reset.ts")
        #expect(changedRename.body == .lines)
        #expect(changedRename.changeKind == .renamed)
        let removed = try document("lib/mail/legacy-sender.ts")
        #expect(removed.changeKind == .removed)
        #expect(removed.rows.dropFirst().allSatisfy { $0.kind == .removed })
        #expect(removed.sideBySideRows.dropFirst().allSatisfy { $0.right == nil })
        let added = try document("mail/index.ts")
        #expect(added.rows.dropFirst().allSatisfy { $0.kind == .added })
        #expect(added.rows.last?.hasNoNewlineAtEnd == true)
        #expect(added.sideBySideRows.dropFirst().allSatisfy { $0.left == nil })

        let broken = ChangedFile(path: "x.ts", changeKind: .modified, additions: 1, deletions: 0, patch: "@@ nonsense")
        if case .unreadable = DiffDocument(file: broken).body {} else { Issue.record("expected unreadable") }
        #expect(DiffDocument(file: ChangedFile(path: "x.ts", changeKind: .modified, additions: 0, deletions: 0, patch: nil)).body == .noPatch)
    }

    @Test func tabsAreExpanded() {
        #expect(DiffDocument.expandingTabs("\tx") == "    x")
        #expect(DiffDocument.expandingTabs("ab\tx") == "ab  x")
        #expect(DiffDocument.expandingTabs("plain") == "plain")
    }

    /// The largest file in the mock world: about 5,000 lines in one patch. Building its rows for
    /// both modes must be quick enough to do off the main thread as the file opens.
    @Test func theFiveThousandLinePatchBuildsQuickly() throws {
        let large = try #require(world.pullRequests.first { $0.files.count >= 100 })
        let file = try #require(large.files.max { ($0.patch?.count ?? 0) < ($1.patch?.count ?? 0) })
        let patchLines = file.patch?.split(separator: "\n", omittingEmptySubsequences: false).count ?? 0
        #expect(patchLines >= 4_500)

        let clock = ContinuousClock()
        var document: DiffDocument?
        let elapsed = clock.measure { document = DiffDocument(file: file, threads: large.reviewThreads) }
        let built = try #require(document)
        #expect(built.rows.count == patchLines)
        #expect(built.sideBySideRows.count <= built.rows.count)
        print("DiffDocument for \(file.path): \(patchLines) patch lines, \(built.rows.count) inline rows, \(built.sideBySideRows.count) side by side rows, built in \(elapsed)")
        // A generous bound: a debug build on a laptop takes a small fraction of this.
        #expect(elapsed < .seconds(2))
    }
}

@Suite struct SyntaxTintTests {
    func kinds(_ line: String, _ language: SyntaxTint.Language = .cLike) -> [String] {
        SyntaxTint.runs(line, language: language).compactMap { run in run.kind.map { "\($0):\(run.text)" } }
    }

    @Test func runsCoverTheWholeLine() {
        for line in ["const a = 'x'; // note", "  return next();", "", "x = \"unterminated", "a /* b */ c", "#!/bin/sh", "  * doc"] {
            for language in [SyntaxTint.Language.cLike, .hashComments, .plain] {
                #expect(SyntaxTint.runs(line, language: language).map(\.text).joined() == line)
            }
        }
    }

    @Test func keywordsStringsCommentsAndNumbers() {
        #expect(kinds("const session = await readSession(req); // why") ==
                ["keyword:const", "keyword:await", "comment:// why"])
        #expect(kinds("nearExpiryMs: 5 * 60 * 1000,") == ["number:5", "number:60", "number:1000"])
        #expect(kinds("logger.error('auth failed', { path })") == ["string:'auth failed'"])
        #expect(kinds("const s = \"a \\\" b\" + `t`") == ["keyword:const", "string:\"a \\\" b\"", "string:`t`"])
        #expect(kinds("a /* b */ return") == ["comment:/* b */", "keyword:return"])
        #expect(kinds("   * a doc line") == ["comment:* a doc line"])
        // A property named like a keyword is not one, and a number inside a word is not a number.
        #expect(kinds("options.default + item2") == [])
    }

    @Test func otherLanguagesAndPlainText() {
        #expect(kinds("key: value # note", .hashComments) == ["comment:# note"])
        // `type:` in YAML is a key, not a keyword.
        #expect(kinds("type: object", .hashComments) == [])
        #expect(kinds("const x = 1", .plain) == [])
        #expect(SyntaxTint.Language(path: "auth/middleware.ts") == .cLike)
        #expect(SyntaxTint.Language(path: "openapi/acme-api.yaml") == .hashComments)
        #expect(SyntaxTint.Language(path: "docs/auth.md") == .plain)
        #expect(SyntaxTint.Language(path: "Makefile") == .plain)
    }
}
