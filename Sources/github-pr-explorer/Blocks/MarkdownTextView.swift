import AppKit
import GitHubPRExplorerCore
import SwiftUI

/// A Markdown body drawn as one native text view, so a drag can select from any block into any
/// other, Command-A selects the whole body, and Copy gives `MarkdownDocument.plainText`.
///
/// SwiftUI's `.textSelection(.enabled)` makes each `Text` selectable on its own, so a body
/// drawn as a stack of `Text` views could only be selected one block at a time. SwiftUI has no
/// read-only text that spans blocks and also draws code backgrounds, quote bars and tables, so
/// this uses AppKit's `NSTextView` over one attributed string. The view sizes itself to its
/// text at the width it is offered and never scrolls on its own.
struct MarkdownTextView: NSViewRepresentable {
    let document: MarkdownDocument
    @Environment(\.previewMarkdownSelection) private var previewSelection

    func makeNSView(context: Context) -> MarkdownNSTextView {
        let view = MarkdownNSTextView(usingTextLayoutManager: false)
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = true
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = false
        // Links look as they did in a SwiftUI `Text`: the accent color, no underline.
        view.linkTextAttributes = [.foregroundColor: NSColor.controlAccentColor, .cursor: NSCursor.pointingHand]
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setAccessibilityLabel("Description")
        return view
    }

    func updateNSView(_ view: MarkdownNSTextView, context: Context) {
        view.show(document, width: view.builtWidth ?? max(view.bounds.width, 1))
        if previewSelection != .none { view.applyPreviewSelection(previewSelection) }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: MarkdownNSTextView, context: Context) -> CGSize? {
        guard let proposed = proposal.width, proposed.isFinite, proposed > 0 else { return nil }
        let width = floor(proposed)
        view.show(document, width: width)
        guard let container = view.textContainer, let layout = view.layoutManager else { return nil }
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        return CGSize(width: width, height: ceil(layout.usedRect(for: container).height))
    }
}

/// The text view behind `MarkdownTextView`. Copy and drags write the plain text with markers
/// and tabs as `MarkdownDocument` defines it, instead of the drawn pictures and line breaks.
final class MarkdownNSTextView: NSTextView {
    private var document: MarkdownDocument?
    private(set) var builtWidth: CGFloat?
    private var appliedPreview = false

    /// Builds the text again when the body changes, or when the width changes and a table's
    /// column widths depend on it. A selection is kept as far as the new text allows.
    func show(_ document: MarkdownDocument, width: CGFloat) {
        let hasTable = document.paragraphs.contains { if case .tableCell = $0.role { true } else { false } }
        if document == self.document, builtWidth == width || !hasTable { return }
        let text = MarkdownTextBuilder(width: width).build(document)
        let selection = selectedRange()
        textStorage?.setAttributedString(text)
        let start = min(selection.location, text.length)
        setSelectedRange(NSRange(location: start, length: min(selection.length, text.length - start)))
        self.document = document
        builtWidth = width
    }

    /// Rich text and plain text. Not RTFD, which would carry the marker pictures as images.
    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] {
        [.rtf, .string]
    }

    /// Writes the selection with the copy substitutions applied, as rich text and as plain
    /// text. Copy and drags both come through here.
    override func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        let copied = selectedCopy
        let wantsRTF = types.contains { $0 == .rtf || $0.rawValue == "NeXT Rich Text Format v1.0 pasteboard type" }
        let wantsPlain = types.contains { $0 == .string || $0.rawValue == "NSStringPboardType" }
        guard wantsRTF || wantsPlain else { return super.writeSelection(to: pboard, types: types) }
        pboard.declareTypes((wantsRTF ? [.rtf] : []) + (wantsPlain ? [.string] : []), owner: nil)
        if wantsRTF, let data = copied.rtf(from: NSRange(location: 0, length: copied.length), documentAttributes: [:]) {
            pboard.setData(data, forType: .rtf)
        }
        if wantsPlain { pboard.setString(copied.string, forType: .string) }
        return true
    }

    /// The selection as Copy writes it.
    private var selectedCopy: NSAttributedString {
        let out = NSMutableAttributedString()
        guard let storage = textStorage else { return out }
        for (index, range) in selectedRanges.map(\.rangeValue).enumerated() {
            if index > 0 { out.append(NSAttributedString(string: "\n")) }
            out.append(MarkdownTextBuilder.copy(storage, range: range))
        }
        return out
    }

    /// For renders only: selects part or all of the text, and prints what Copy would give,
    /// written to a private pasteboard, never the one the person uses.
    func applyPreviewSelection(_ selection: MarkdownPreviewSelection) {
        guard !appliedPreview, let document else { return }
        appliedPreview = true
        let string = self.string as NSString
        switch selection {
        case .none: return
        case .all: selectAll(nil)
        case .spanning:
            let start = string.range(of: "column menu moved").location
            let end = NSMaxRange(string.range(of: "Scroll the table"))
            guard start != NSNotFound, end != NSNotFound, end > start else { return }
            setSelectedRange(NSRange(location: start, length: end - start))
        }
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("github-pr-explorer.render-copy-check"))
        pasteboard.clearContents()
        // The types Copy writes.
        _ = writeSelection(to: pasteboard, types: writablePasteboardTypes)
        let rich = pasteboard.data(forType: .rtf).flatMap { NSAttributedString(rtf: $0, documentAttributes: nil) }
        let copied = pasteboard.string(forType: .string) ?? ""
        pasteboard.releaseGlobally()
        if selection == .all {
            print("description copy check: Select All then Copy \(copied == document.plainText ? "matches" : "DOES NOT MATCH") MarkdownDocument.plainText")
        }
        print("description copy check, \(selection): rich text \(rich?.string == copied ? "has the same text" : "DIFFERS")")
        print("description copy check, \(selection):\n\(copied)\n-- end of copied text")
    }
}

/// A selection a render draws in the Description, to show it spanning blocks.
enum MarkdownPreviewSelection: String, Sendable {
    case none, spanning, all
}

extension EnvironmentValues {
    @Entry var previewMarkdownSelection = MarkdownPreviewSelection.none
}

/// Turns a `MarkdownDocument` into the attributed string the text view draws. It matches the
/// look of the stack of SwiftUI views it replaces: 13 point text, 8 points between blocks,
/// hanging list markers, rounded code backgrounds, a bar beside quotes, and tables as wide as
/// their content inside a rounded border.
@MainActor
struct MarkdownTextBuilder {
    /// Marks text drawn one way and copied another: a checkbox picture copies as `[x] `, the
    /// line break that ends a table cell copies as a tab.
    static let copyTextKey = NSAttributedString.Key("githubPRExplorer.copyText")

    let width: CGFloat
    let body = NSFont.systemFont(ofSize: 13)
    let blockSpacing: CGFloat = 8
    let lineSpacing: CGFloat = 2
    let listIndent: CGFloat = 16
    let markerGap: CGFloat = 6

    /// The text in `range` with copy substitutions applied: pictures become their text, and
    /// the line break after a table cell becomes a tab. Other attributes are kept for rich text,
    /// without the text blocks that draw code backgrounds and tables.
    static func copy(_ text: NSAttributedString, range: NSRange) -> NSAttributedString {
        let out = NSMutableAttributedString()
        text.enumerateAttributes(in: range) { attributes, run, _ in
            var kept = attributes
            kept[.attachment] = nil
            kept[copyTextKey] = nil
            kept[.kern] = nil
            if let style = attributes[.paragraphStyle] as? NSParagraphStyle, !style.textBlocks.isEmpty,
               let plain = style.mutableCopy() as? NSMutableParagraphStyle {
                plain.textBlocks = []
                kept[.paragraphStyle] = plain
            }
            if let value = attributes[copyTextKey] as? String {
                // Each substituted character stands for its own copy, even when two in a row
                // carry the same one, such as the tabs after two empty cells.
                out.append(NSAttributedString(string: String(repeating: value, count: run.length), attributes: kept))
            } else {
                out.append(NSAttributedString(string: (text.string as NSString).substring(with: run), attributes: kept))
            }
        }
        return out
    }

    func build(_ document: MarkdownDocument) -> NSAttributedString {
        let out = NSMutableAttributedString()
        var tables: [Int: TableParts] = [:]
        let paragraphs = document.paragraphs
        for (index, paragraph) in paragraphs.enumerated() {
            let isLast = index == paragraphs.count - 1
            // TextKit adds the line spacing after a paragraph's last line too, which a SwiftUI
            // stack did not, so the space between blocks takes it off.
            let after: CGFloat = paragraph.endsBlock && !isLast ? blockSpacing - lineSpacing : 0
            // A code block takes the line spacing off its padding instead, and a rule has none.
            let fullAfter: CGFloat = paragraph.endsBlock && !isLast ? blockSpacing : 0
            let style = NSMutableParagraphStyle()
            style.lineSpacing = lineSpacing
            let start = out.length
            // A margin below a table's border is not kept, so the block after a table puts the
            // space above itself instead.
            if index > 0, case .tableCell = paragraphs[index - 1].role, paragraphs[index - 1].endsBlock {
                style.paragraphSpacingBefore = blockSpacing
            }
            var line = NSMutableAttributedString()

            switch paragraph.role {
            case .heading(let level):
                let font = NSFont.systemFont(ofSize: level <= 2 ? 14 : 13, weight: .semibold)
                line = styled(paragraph.text, font: font, weight: .semibold, color: .labelColor)
                style.paragraphSpacingBefore = max(style.paragraphSpacingBefore, 2)
                style.paragraphSpacing = after
            case .paragraph:
                line = styled(paragraph.text, font: body, color: .labelColor)
                style.paragraphSpacing = after
            case .listItem(let depth):
                line = listItem(paragraph, depth: depth, style: style)
                style.paragraphSpacing = after
            case .code:
                let block = CodeBlock()
                block.setValue(100, type: .percentageValueType, for: .width)
                block.setWidth(8, type: .absoluteValueType, for: .padding)
                block.setWidth(8 - lineSpacing, type: .absoluteValueType, for: .padding, edge: .maxY)
                block.setWidth(fullAfter, type: .absoluteValueType, for: .margin, edge: .maxY)
                style.textBlocks = [block]
                line = NSMutableAttributedString(string: String(paragraph.text.characters), attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), .foregroundColor: NSColor.labelColor,
                ])
            case .quote:
                let block = QuoteBlock()
                block.setValue(100, type: .percentageValueType, for: .width)
                block.setWidth(QuoteBlock.barWidth + 8, type: .absoluteValueType, for: .padding, edge: .minX)
                block.setWidth(after, type: .absoluteValueType, for: .margin, edge: .maxY)
                style.textBlocks = [block]
                line = styled(paragraph.text, font: body, color: .secondaryLabelColor)
            case .tableCell(let row, let column, let rows, let columns):
                let parts = tables[paragraph.block] ?? tableParts(for: paragraph.block, in: paragraphs)
                tables[paragraph.block] = parts
                let cell = NSTextTableBlock(table: parts.table, startingRow: row, rowSpan: 1, startingColumn: column, columnSpan: 1)
                if let widths = parts.contentWidths {
                    cell.setValue(widths[column], type: .absoluteValueType, for: .width)
                }
                if column < columns - 1 { cell.setWidth(16, type: .absoluteValueType, for: .padding, edge: .maxX) }
                if row == 0, rows > 1 {
                    // The line under the header, with 4 points on each side, as the Grid's Divider had.
                    cell.setWidth(4 - lineSpacing, type: .absoluteValueType, for: .padding, edge: .maxY)
                    cell.setWidth(1, type: .absoluteValueType, for: .border, edge: .maxY)
                    cell.setBorderColor(.separatorColor, for: .maxY)
                }
                if row > 0 { cell.setWidth(row == 1 ? 4 : 4 - lineSpacing, type: .absoluteValueType, for: .padding, edge: .minY) }
                style.textBlocks = [parts.frame, cell]
                line = styled(paragraph.text, font: row == 0 ? semibold : body, weight: row == 0 ? .semibold : .regular,
                              color: .labelColor)
            case .image:
                line = pictured(paragraph, symbol: "photo", pointSize: 13, weight: .regular, gap: 8,
                                symbolColor: .secondaryLabelColor, font: body, textColor: .secondaryLabelColor)
                style.paragraphSpacing = after
            case .summary:
                line = pictured(paragraph, symbol: "chevron.down", pointSize: 9, weight: .bold, gap: 4,
                                symbolColor: .secondaryLabelColor, font: NSFont.systemFont(ofSize: 13, weight: .medium),
                                textColor: .labelColor)
                style.paragraphSpacing = after
            case .rule:
                // A rule draws as a line. Its text is one zero-width space, so it can be
                // selected and copied as `---`.
                let block = RuleBlock()
                block.setValue(100, type: .percentageValueType, for: .width)
                block.setWidth(fullAfter, type: .absoluteValueType, for: .margin, edge: .maxY)
                style.textBlocks = [block]
                style.lineSpacing = 0
                style.minimumLineHeight = 1
                style.maximumLineHeight = 1
                line = NSMutableAttributedString(string: "\u{200B}", attributes: [
                    .font: NSFont.systemFont(ofSize: 1), Self.copyTextKey: paragraph.textCopyText,
                ])
            }

            out.append(line)
            if !isLast {
                var attributes: [NSAttributedString.Key: Any] = [.font: line.length > 0 ? line.attribute(.font, at: line.length - 1, effectiveRange: nil) ?? body : body]
                if paragraph.separator != "\n" { attributes[Self.copyTextKey] = paragraph.separator }
                out.append(NSAttributedString(string: "\n", attributes: attributes))
            }
            out.addAttribute(.paragraphStyle, value: style, range: NSRange(location: start, length: out.length - start))
        }
        return out
    }

    private var semibold: NSFont { NSFont.systemFont(ofSize: 13, weight: .semibold) }

    // MARK: Inline text

    /// Inline marks as a SwiftUI `Text` draws them: bold, italic, struck through, code in the
    /// monospaced face at the same size, and links.
    private func styled(_ text: AttributedString, font: NSFont, weight: NSFont.Weight = .regular,
                        color: NSColor) -> NSMutableAttributedString {
        let out = NSMutableAttributedString()
        for run in text.runs {
            let intent = run.inlinePresentationIntent ?? []
            var runFont = intent.contains(.code) ? NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: weight) : font
            if intent.contains(.stronglyEmphasized) { runFont = NSFontManager.shared.convert(runFont, toHaveTrait: .boldFontMask) }
            if intent.contains(.emphasized) { runFont = NSFontManager.shared.convert(runFont, toHaveTrait: .italicFontMask) }
            var attributes: [NSAttributedString.Key: Any] = [.font: runFont, .foregroundColor: color]
            if intent.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if let link = run.link { attributes[.link] = link }
            out.append(NSAttributedString(string: String(text[run.range].characters), attributes: attributes))
        }
        return out
    }

    // MARK: Lists

    /// A list item with a hanging marker: the marker sits at the item's indent, and every line
    /// of its text starts `markerGap` after the marker, as the HStack did.
    private func listItem(_ paragraph: MarkdownDocument.Paragraph, depth: Int, style: NSMutableParagraphStyle) -> NSMutableAttributedString {
        let out = NSMutableAttributedString()
        let indent = paragraph.indent
        let indentWidth = (indent as NSString).size(withAttributes: [.font: body]).width
        out.append(NSAttributedString(string: indent, attributes: [.font: body]))
        let left = CGFloat(depth) * listIndent
        var markerWidth: CGFloat = 0
        switch paragraph.marker {
        case .task(let checked):
            let attachment = symbol(checked ? "checkmark.square.fill" : "square", pointSize: 13, weight: .regular,
                                    color: checked ? .controlAccentColor : .secondaryLabelColor, font: body,
                                    label: checked ? "Done" : "Not done")
            markerWidth = attachment.bounds.width
            out.append(NSAttributedString(attachment: attachment, attributes: [
                .font: body, Self.copyTextKey: paragraph.marker?.copyText ?? "",
            ]))
            out.append(gap(markerGap, copiedAs: nil))
        default:
            let marker = paragraph.marker?.copyText ?? "•"
            let font = paragraph.marker == .bullet ? body : NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
            markerWidth = (marker as NSString).size(withAttributes: attributes).width
            out.append(NSAttributedString(string: marker, attributes: attributes))
            out.append(gap(markerGap, copiedAs: nil))
        }
        out.append(styled(paragraph.text, font: body, color: .labelColor))
        style.firstLineHeadIndent = max(0, left - indentWidth)
        style.headIndent = left + markerWidth + markerGap
        return out
    }

    /// A space stretched or narrowed to `width`, the gap between a marker and its text. It
    /// copies as a space unless `copiedAs` says otherwise.
    private func gap(_ width: CGFloat, copiedAs copy: String?) -> NSAttributedString {
        let space = (" " as NSString).size(withAttributes: [.font: body]).width
        var attributes: [NSAttributedString.Key: Any] = [.font: body, .kern: width - space]
        if let copy { attributes[Self.copyTextKey] = copy }
        return NSAttributedString(string: " ", attributes: attributes)
    }

    /// A symbol, a gap, and text, as a SwiftUI `Label` draws it.
    private func pictured(_ paragraph: MarkdownDocument.Paragraph, symbol name: String, pointSize: CGFloat,
                          weight: NSFont.Weight, gap: CGFloat, symbolColor: NSColor, font: NSFont,
                          textColor: NSColor) -> NSMutableAttributedString {
        let out = NSMutableAttributedString()
        let attachment = symbol(name, pointSize: pointSize, weight: weight, color: symbolColor, font: font, label: nil)
        out.append(NSAttributedString(attachment: attachment, attributes: [
            Self.copyTextKey: paragraph.markerCopyText, .font: font,
        ]))
        out.append(self.gap(gap, copiedAs: ""))
        out.append(NSAttributedString(string: String(paragraph.text.characters), attributes: [
            .font: font, .foregroundColor: textColor,
        ]))
        return out
    }

    /// An SF Symbol as a text attachment, tinted at draw time so it follows light and dark.
    private func symbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight, color: NSColor,
                        font: NSFont, label: String?) -> NSTextAttachment {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        let base = NSImage(systemSymbolName: name, accessibilityDescription: label)?.withSymbolConfiguration(configuration)
        let size = base?.size ?? NSSize(width: pointSize, height: pointSize)
        let image = NSImage(size: size, flipped: false) { rect in
            // The color, cut to the symbol's shape, so a translucent color stays translucent.
            color.set()
            rect.fill()
            base?.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1)
            return true
        }
        image.cacheMode = .never
        image.accessibilityDescription = label
        let attachment = NSTextAttachment()
        attachment.image = image
        // Centered on the capital letters, as a symbol beside text is.
        attachment.bounds = CGRect(x: 0, y: ((font.capHeight - size.height) / 2).rounded(), width: size.width, height: size.height)
        return attachment
    }

    // MARK: Tables

    private struct TableParts {
        let frame: TableFrameBlock
        let table: NSTextTable
        /// Each column's text width when the table fits at its natural width. Nil when it does
        /// not fit, and the table shares out the width instead.
        let contentWidths: [CGFloat]?
    }

    /// The table and its rounded border. A table is as wide as its content, as the Grid was,
    /// unless that is wider than the view.
    private func tableParts(for block: Int, in paragraphs: [MarkdownDocument.Paragraph]) -> TableParts {
        let cells = paragraphs.filter { $0.block == block }
        var widths: [CGFloat] = []
        for cell in cells {
            guard case .tableCell(let row, let column, _, let columns) = cell.role else { continue }
            if widths.isEmpty { widths = Array(repeating: 0, count: columns) }
            let text = styled(cell.text, font: row == 0 ? semibold : body, weight: row == 0 ? .semibold : .regular, color: .labelColor)
            widths[column] = max(widths[column], ceil(text.size().width))
        }
        let spacing = CGFloat(max(widths.count - 1, 0)) * 16
        // The border is drawn inside the padding, as SwiftUI's strokeBorder was, so it takes no room.
        let framePadding: CGFloat = 8
        let natural = widths.reduce(0, +) + spacing
        let fits = natural + 2 * framePadding <= width

        let frame = TableFrameBlock()
        frame.setWidth(framePadding, type: .absoluteValueType, for: .padding)
        frame.setWidth(framePadding - lineSpacing, type: .absoluteValueType, for: .padding, edge: .maxY)
        let table = NSTextTable()
        table.numberOfColumns = widths.count
        table.hidesEmptyCells = false
        if fits {
            frame.setValue(natural, type: .absoluteValueType, for: .width)
            table.layoutAlgorithm = .fixedLayoutAlgorithm
            table.setValue(natural, type: .absoluteValueType, for: .width)
        } else {
            frame.setValue(100, type: .percentageValueType, for: .width)
            table.layoutAlgorithm = .automaticLayoutAlgorithm
            table.setValue(100, type: .percentageValueType, for: .width)
        }
        return TableParts(frame: frame, table: table, contentWidths: fits ? widths : nil)
    }
}

// MARK: Block decorations

/// The rectangle a block draws in: its frame without its margins.
private func drawingRect(_ block: NSTextBlock, _ frame: NSRect) -> NSRect {
    var rect = frame
    rect.origin.x += block.width(for: .margin, edge: .minX)
    rect.origin.y += block.width(for: .margin, edge: .minY)
    rect.size.width -= block.width(for: .margin, edge: .minX) + block.width(for: .margin, edge: .maxX)
    rect.size.height -= block.width(for: .margin, edge: .minY) + block.width(for: .margin, edge: .maxY)
    return rect
}

/// A code block's rounded background.
private final class CodeBlock: NSTextBlock {
    override func drawBackground(withFrame frameRect: NSRect, in controlView: NSView?, characterRange: NSRange,
                                 layoutManager: NSLayoutManager) {
        let rect = drawingRect(self, frameRect)
        let base = NSColor.quaternaryLabelColor
        base.withAlphaComponent(base.alphaComponent * 0.6).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
    }
}

/// The bar beside a quote.
private final class QuoteBlock: NSTextBlock {
    static let barWidth: CGFloat = 3

    override func drawBackground(withFrame frameRect: NSRect, in controlView: NSView?, characterRange: NSRange,
                                 layoutManager: NSLayoutManager) {
        let rect = drawingRect(self, frameRect)
        NSColor.tertiaryLabelColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: rect.minX, y: rect.minY, width: Self.barWidth, height: rect.height),
                     xRadius: 1, yRadius: 1).fill()
    }
}

/// A rule: one line across the width.
private final class RuleBlock: NSTextBlock {
    override func drawBackground(withFrame frameRect: NSRect, in controlView: NSView?, characterRange: NSRange,
                                 layoutManager: NSLayoutManager) {
        let rect = drawingRect(self, frameRect)
        NSColor.separatorColor.setFill()
        NSRect(x: rect.minX, y: rect.midY.rounded(.down), width: rect.width, height: 1).fill()
    }
}

/// The rounded border around a table.
private final class TableFrameBlock: NSTextBlock {
    override func drawBackground(withFrame frameRect: NSRect, in controlView: NSView?, characterRange: NSRange,
                                 layoutManager: NSLayoutManager) {
        let rect = drawingRect(self, frameRect).insetBy(dx: 0.5, dy: 0.5)
        NSColor.separatorColor.setStroke()
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        path.lineWidth = 1
        path.stroke()
    }
}
