import Foundation

/// A pull request body split into the blocks a native view draws, one after another.
///
/// `AttributedString(markdown:)` handles inline marks (bold, code, links) but a SwiftUI `Text`
/// drops block structure: list bullets, checkboxes, headings and code blocks run together. So
/// this splits the body into blocks and leaves each block's inline text as markdown for
/// `AttributedString`. It covers what GitHub bodies use most. HTML is not drawn: a
/// `<details>` block shows its summary and contents, and other tags are dropped.
public enum MarkdownBlock: Sendable, Hashable {
    case heading(level: Int, text: String)
    case paragraph(String)
    /// `checked` is nil for a plain bullet, true or false for a task list item. `ordinal` is set
    /// for a numbered item.
    case listItem(text: String, checked: Bool?, ordinal: Int?, depth: Int)
    case code(language: String, text: String)
    case quote(String)
    /// A table, kept as rows of cells. The separator row is left out.
    case table(rows: [[String]])
    /// An image, shown as its alt text and address. Images are not loaded.
    case image(alt: String, url: String)
    /// The title line of a `<details>` block.
    case summary(String)
    case rule

    public static func parse(_ body: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var lines = body.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")[...]

        func flushParagraph() {
            let text = paragraph.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { blocks.append(.paragraph(text)) }
            paragraph = []
        }

        while let raw = lines.popFirst() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let indent = raw.prefix { $0 == " " }.count

            if line.isEmpty {
                flushParagraph()
                continue
            }
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                flushParagraph()
                let fence = String(line.prefix(3))
                let language = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                while let next = lines.popFirst() {
                    if next.trimmingCharacters(in: .whitespaces).hasPrefix(fence) { break }
                    code.append(next)
                }
                blocks.append(.code(language: language, text: code.joined(separator: "\n")))
                continue
            }
            if let heading = headingLevel(line) {
                flushParagraph()
                blocks.append(.heading(level: heading, text: line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)))
                continue
            }
            if line == "---" || line == "***" || line == "___" {
                flushParagraph()
                blocks.append(.rule)
                continue
            }
            if line.hasPrefix("|") {
                flushParagraph()
                var rows = [cells(line)]
                while let next = lines.first, next.trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    lines.removeFirst()
                    let row = next.trimmingCharacters(in: .whitespaces)
                    if row.allSatisfy({ "|-: ".contains($0) }) { continue }
                    rows.append(cells(row))
                }
                blocks.append(.table(rows: rows))
                continue
            }
            if line.hasPrefix("!["), let image = image(line) {
                flushParagraph()
                blocks.append(image)
                continue
            }
            if line.hasPrefix(">") {
                flushParagraph()
                var quoted = [line.dropFirst().trimmingCharacters(in: .whitespaces)]
                while let next = lines.first, next.trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    lines.removeFirst()
                    quoted.append(next.trimmingCharacters(in: .whitespaces).dropFirst().trimmingCharacters(in: .whitespaces))
                }
                blocks.append(.quote(quoted.joined(separator: " ")))
                continue
            }
            if line.hasPrefix("<") {
                flushParagraph()
                if let summary = tagContents(line, tag: "summary") {
                    blocks.append(.summary(summary))
                }
                // Other HTML lines, such as <details> and </details>, are dropped.
                continue
            }
            if let item = listItem(line, depth: indent / 2) {
                flushParagraph()
                blocks.append(item)
                continue
            }
            paragraph.append(line)
        }
        flushParagraph()
        return blocks
    }

    /// The first paragraph's text, or the first block's text, for a small Description.
    public static func firstText(_ blocks: [MarkdownBlock]) -> String? {
        for block in blocks {
            switch block {
            case .paragraph(let text), .quote(let text): return text
            case .heading, .rule, .summary, .image, .table, .code, .listItem: continue
            }
        }
        return nil
    }

    private static func headingLevel(_ line: String) -> Int? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return hashes
    }

    private static func cells(_ row: String) -> [String] {
        var parts = row.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.first == "" { parts.removeFirst() }
        if parts.last == "" { parts.removeLast() }
        return parts
    }

    private static func image(_ line: String) -> MarkdownBlock? {
        guard let altEnd = line.range(of: "]("), line.hasSuffix(")") else { return nil }
        let alt = String(line[line.index(line.startIndex, offsetBy: 2)..<altEnd.lowerBound])
        let url = String(line[altEnd.upperBound..<line.index(before: line.endIndex)])
        return .image(alt: alt, url: url)
    }

    private static func tagContents(_ line: String, tag: String) -> String? {
        guard let open = line.range(of: "<\(tag)>"), let close = line.range(of: "</\(tag)>"), open.upperBound <= close.lowerBound else { return nil }
        return String(line[open.upperBound..<close.lowerBound]).trimmingCharacters(in: .whitespaces)
    }

    private static func listItem(_ line: String, depth: Int) -> MarkdownBlock? {
        var rest = Substring(line)
        var ordinal: Int?
        if let first = rest.first, first == "-" || first == "*" || first == "+", rest.dropFirst().first == " " {
            rest = rest.dropFirst(2)
        } else {
            let digits = rest.prefix { $0.isNumber }
            guard !digits.isEmpty, let number = Int(digits) else { return nil }
            let after = rest.dropFirst(digits.count)
            guard after.first == "." || after.first == ")", after.dropFirst().first == " " else { return nil }
            ordinal = number
            rest = after.dropFirst(2)
        }
        var checked: Bool?
        if rest.hasPrefix("[ ] ") { checked = false; rest = rest.dropFirst(4) }
        else if rest.hasPrefix("[x] ") || rest.hasPrefix("[X] ") { checked = true; rest = rest.dropFirst(4) }
        return .listItem(text: String(rest), checked: checked, ordinal: ordinal, depth: depth)
    }
}
