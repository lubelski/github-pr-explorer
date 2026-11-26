import GitHubPRExplorerCore
import SwiftUI

/// The pull request's body, drawn natively from its markdown. Small shows the first lines, and
/// large draws the whole body as one selectable text with `MarkdownTextView`.
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
            // One text for the whole body, so a selection can cross blocks (MAC-72).
            MarkdownTextView(document: MarkdownDocument(blocks: blocks))
                // TextKit leaves out the space above the first paragraph, which a heading had.
                .padding(.top, startsWithHeading(blocks) ? 2 : 0)
        }
    }

    private func startsWithHeading(_ blocks: [MarkdownBlock]) -> Bool {
        if case .heading = blocks.first { return true }
        return false
    }
}
