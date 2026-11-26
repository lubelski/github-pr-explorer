import Foundation
@testable import GitHubPRExplorerCore
import Testing

/// The Description as one text: what each block becomes, and what Copy gives.
struct MarkdownDocumentTests {
    @Test func richBodyCopiesAsReadableText() {
        let document = MarkdownDocument(markdown: MockGenerated.richBody)
        #expect(document.plainText == """
            What changed
            The reports table header now sticks to the top while scrolling, and the column menu moved into the header.
            Column\tBefore\tAfter
            Date\tFixed width\tFits content
            Amount\tLeft aligned\tRight aligned
            Status\tText\tBadge
            The reports table with the sticky header
            [x] Sticky header
            [x] Column menu in the header
            [ ] Check with a screen reader
            Why not a CSS-only fix
            position: sticky does not work inside the scroll container the table uses today, so the header is drawn by ReportsTableHeader instead.
            <ReportsTable columns={columns} rows={rows} stickyHeader />
            How to check it
            1. Open Reports on staging and pick a range with more than one page of rows.
            2. Scroll the table and watch the header.
              • It should stay put, with the column menu still reachable.
              • The shadow under it should appear once the first row scrolls away.
            3. Read the notes in the design review.
            Ada Park asked for the shadow in the design review. It is the same one the invoice table uses, so the two tables match.
            ---
            The totals row is a follow-up.
            """)
    }

    @Test func everyBlockKindBecomesAParagraph() {
        let document = MarkdownDocument(markdown: MockGenerated.richBody)
        let roles = document.paragraphs.map(\.role)
        #expect(roles.first == .heading(level: 2))
        #expect(roles.contains(.heading(level: 3)))
        #expect(roles.contains(.paragraph))
        #expect(roles.contains(.listItem(depth: 0)))
        #expect(roles.contains(.listItem(depth: 1)))
        #expect(roles.contains(.code(language: "tsx")))
        #expect(roles.contains(.quote))
        #expect(roles.contains(.tableCell(row: 0, column: 0, rows: 4, columns: 3)))
        #expect(roles.contains(.image(url: "https://assets.acme.example/pull-requests/reports-header.png")))
        #expect(roles.contains(.summary))
        #expect(roles.contains(.rule))
        // A table is one block, so its cells share the block index.
        let cells = document.paragraphs.filter { if case .tableCell = $0.role { true } else { false } }
        #expect(cells.count == 12)
        #expect(Set(cells.map(\.block)).count == 1)
        #expect(cells.filter(\.endsBlock).count == 1)
    }

    @Test func inlineMarksAndLinksSurvive() {
        let document = MarkdownDocument(markdown: "Read **this** and [the notes](https://docs.acme.example/notes) with `code`.")
        let text = document.paragraphs[0].text
        #expect(String(text.characters) == "Read this and the notes with code.")
        #expect(text.runs.contains { $0.link == URL(string: "https://docs.acme.example/notes") })
        #expect(text.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
        #expect(text.runs.contains { $0.inlinePresentationIntent?.contains(.code) == true })
    }

    @Test func markersCopyAsText() {
        let document = MarkdownDocument(markdown: "- one\n  - two\n9. nine\n- [ ] open\n- [x] done\n![](https://assets.acme.example/a.png)")
        #expect(document.paragraphs.map(\.marker) == [.bullet, .bullet, .number(9), .task(checked: false), .task(checked: true), .image])
        #expect(document.plainText == "• one\n  • two\n9. nine\n[ ] open\n[x] done\nImage")
    }

    @Test func shortTableRowsArePaddedAndCodeKeepsItsLines() {
        let document = MarkdownDocument(markdown: "| A | B |\n|---|---|\n| 1 |\n\n```\nlet a = 1\nlet b = 2\n```")
        #expect(document.plainText == "A\tB\n1\t\nlet a = 1\nlet b = 2")
        #expect(document.paragraphs.last?.endsBlock == true)
    }

    @Test func emptyBodyIsEmpty() {
        #expect(MarkdownDocument(markdown: "").paragraphs.isEmpty)
        #expect(MarkdownDocument(markdown: "").plainText == "")
    }
}
