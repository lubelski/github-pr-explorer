import GitHubPRExplorerCore
import SwiftUI

/// The pull request's body, drawn natively from its markdown. Small shows the first lines.
struct DescriptionBlock: View {
    let pullRequest: PullRequest
    let size: BlockSize

    var body: some View {
        let blocks = MarkdownBlock.parse(pullRequest.body)
        if blocks.isEmpty {
            EmptyBlockText("No description provided.")
        } else if size == .small {
            Text(inlineMarkdown(MarkdownBlock.firstText(blocks) ?? pullRequest.body))
                .lineLimit(3)
                .lineSpacing(2)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    MarkdownBlockView(block: block)
                }
            }
            .lineSpacing(2)
            .textSelection(.enabled)
        }
    }
}

struct MarkdownBlockView: View {
    let block: MarkdownBlock

    var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(inlineMarkdown(text))
                .font(.system(size: level <= 2 ? 14 : 13, weight: .semibold))
                .padding(.top, 2)
        case .paragraph(let text):
            Text(inlineMarkdown(text))
                .fixedSize(horizontal: false, vertical: true)
        case .listItem(let text, let checked, let ordinal, let depth):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let checked {
                    Image(systemName: checked ? "checkmark.square.fill" : "square")
                        .foregroundStyle(checked ? Color.accentColor : Color.secondary)
                        .accessibilityLabel(checked ? "Done" : "Not done")
                } else if let ordinal {
                    Text("\(ordinal).").foregroundStyle(.secondary).monospacedDigit()
                } else {
                    Text("•").foregroundStyle(.secondary)
                }
                Text(inlineMarkdown(text))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(depth) * 16)
        case .code(_, let text):
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.6)))
        case .quote(let text):
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1).fill(.tertiary).frame(width: 3)
                Text(inlineMarkdown(text)).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .table(let rows):
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(inlineMarkdown(cell)).fontWeight(index == 0 ? .semibold : .regular)
                        }
                    }
                    if index == 0 { Divider().gridCellUnsizedAxes(.horizontal) }
                }
            }
            .padding(8)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Style.hairline))
        case .image(let alt, _):
            Label(alt.isEmpty ? "Image" : alt, systemImage: "photo")
                .foregroundStyle(.secondary)
                .help("Images are not loaded yet")
        case .summary(let text):
            Label(text, systemImage: "chevron.down")
                .labelStyle(SummaryLabelStyle())
        case .rule:
            Divider()
        }
    }
}

private struct SummaryLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
            configuration.title.fontWeight(.medium)
        }
    }
}
