import Foundation

/// A pull request body as one run of paragraphs, for a view that draws the whole body as a
/// single text, so a selection can start in one block and end in another.
///
/// Each `MarkdownBlock` becomes one or more paragraphs: a table becomes one paragraph per cell,
/// and every other block becomes one. A paragraph knows what it was (its role), the marker drawn
/// before it, and its inline text. `plainText` is what Copy gives for the whole body: blocks on
/// their own lines, list markers kept, nested items indented, and table cells separated by tabs.
/// The view draws markers and rules its own way, and maps them back to this text when copying.
public struct MarkdownDocument: Sendable, Equatable {
    /// What is drawn before a paragraph's text.
    public enum Marker: Sendable, Hashable {
        case bullet
        case number(Int)
        case task(checked: Bool)
        /// The photo symbol before an image's alt text.
        case image
        /// The disclosure chevron before a collapsed section's title.
        case summary

        /// What Copy gives for the marker. Empty when the marker is only a picture.
        public var copyText: String {
            switch self {
            case .bullet: "•"
            case .number(let number): "\(number)."
            case .task(let checked): checked ? "[x]" : "[ ]"
            case .image, .summary: ""
            }
        }
    }

    public enum Role: Sendable, Hashable {
        case heading(level: Int)
        case paragraph
        case listItem(depth: Int)
        case code(language: String)
        case quote
        /// One cell of a table. Row 0 is the header. Every row has `columns` cells: a short row
        /// is padded with empty cells.
        case tableCell(row: Int, column: Int, rows: Int, columns: Int)
        case image(url: String)
        case summary
        case rule
    }

    public struct Paragraph: Sendable, Equatable {
        public var role: Role
        public var marker: Marker?
        /// The text after the marker, with inline marks (bold, code, links) as markdown gives
        /// them. Code is kept as written, with its line breaks. A rule has no text.
        public var text: AttributedString
        /// The index of the `MarkdownBlock` it came from. Paragraphs of one table share it.
        public var block: Int

        /// Two spaces for each level a list item is nested, so a copied list keeps its shape.
        public var indent: String {
            if case .listItem(let depth) = role { return String(repeating: "  ", count: depth) }
            return ""
        }

        /// What Copy gives for the marker and the space after it.
        public var markerCopyText: String {
            guard let copy = marker?.copyText, !copy.isEmpty else { return "" }
            return copy + " "
        }

        /// What Copy gives for the text. A rule, which draws as a line, copies as `---`.
        public var textCopyText: String {
            if role == .rule { return "---" }
            return String(text.characters)
        }

        /// What separates this paragraph from the next one when copied: a tab between the
        /// cells of a row, and a line break everywhere else.
        public var separator: String {
            if case .tableCell(_, let column, _, let columns) = role, column < columns - 1 { return "\t" }
            return "\n"
        }

        /// Whether this paragraph ends its block, so the space between blocks follows it.
        public var endsBlock: Bool {
            if case .tableCell(let row, let column, let rows, let columns) = role {
                return row == rows - 1 && column == columns - 1
            }
            return true
        }
    }

    public let paragraphs: [Paragraph]

    public init(blocks: [MarkdownBlock]) {
        var paragraphs: [Paragraph] = []
        for (index, block) in blocks.enumerated() {
            func add(_ role: Role, _ text: AttributedString, marker: Marker? = nil) {
                paragraphs.append(Paragraph(role: role, marker: marker, text: text, block: index))
            }
            switch block {
            case .heading(let level, let text):
                add(.heading(level: level), Self.inline(text))
            case .paragraph(let text):
                add(.paragraph, Self.inline(text))
            case .listItem(let text, let checked, let ordinal, let depth):
                let marker: Marker = if let checked { .task(checked: checked) } else if let ordinal { .number(ordinal) } else { .bullet }
                add(.listItem(depth: depth), Self.inline(text), marker: marker)
            case .code(let language, let text):
                add(.code(language: language), AttributedString(text))
            case .quote(let text):
                add(.quote, Self.inline(text))
            case .table(let rows):
                let columns = rows.map(\.count).max() ?? 0
                guard columns > 0 else { continue }
                for (row, cells) in rows.enumerated() {
                    for column in 0..<columns {
                        let cell = column < cells.count ? cells[column] : ""
                        add(.tableCell(row: row, column: column, rows: rows.count, columns: columns), Self.inline(cell))
                    }
                }
            case .image(let alt, let url):
                add(.image(url: url), AttributedString(alt.isEmpty ? "Image" : alt), marker: .image)
            case .summary(let text):
                add(.summary, AttributedString(text), marker: .summary)
            case .rule:
                add(.rule, AttributedString())
            }
        }
        self.paragraphs = paragraphs
    }

    public init(markdown: String) {
        self.init(blocks: MarkdownBlock.parse(markdown))
    }

    /// The whole body as Copy gives it after Select All.
    public var plainText: String {
        var text = ""
        for (index, paragraph) in paragraphs.enumerated() {
            text += paragraph.indent + paragraph.markerCopyText + paragraph.textCopyText
            if index < paragraphs.count - 1 { text += paragraph.separator }
        }
        return text
    }

    /// Inline markdown, such as `code`, **bold** and links, for one paragraph.
    public static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}
