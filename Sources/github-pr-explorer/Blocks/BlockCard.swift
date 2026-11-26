import GitHubPRExplorerCore
import SwiftUI

/// What every block needs besides the pull request.
struct BlockContext {
    let viewer: Viewer
    /// The clock ages are measured from.
    let now: Date
}

/// A block as the page draws it: a rounded card with a title, an optional count, and the
/// block's own view for its size.
struct BlockView: View {
    let placement: BlockPlacement
    let pullRequest: PullRequest
    let context: BlockContext

    var body: some View {
        BlockCard(title: placement.kind.title,
                  count: placement.kind.count(for: pullRequest)) {
            content
        }
    }

    @ViewBuilder private var content: some View {
        let pr = pullRequest, size = placement.size
        switch placement.kind {
        case .description: DescriptionBlock(pullRequest: pr, size: size)
        case .checks: ChecksBlock(pullRequest: pr, size: size, context: context)
        case .reviewers: ReviewersBlock(pullRequest: pr, size: size, context: context)
        case .ownersTouched: OwnersTouchedBlock(pullRequest: pr, size: size)
        case .files: FilesBlock(pullRequest: pr, size: size)
        case .threads: ThreadsBlock(pullRequest: pr, size: size, context: context)
        case .activity: ActivityBlock(pullRequest: pr, size: size, context: context)
        case .commits: CommitsBlock(pullRequest: pr, size: size, context: context)
        case .labelsAndMetadata: LabelsAndMetadataBlock(pullRequest: pr, size: size)
        }
    }
}

struct BlockCard<Content: View>: View {
    let title: String
    let count: Int?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text(title).font(Style.blockTitle)
                if let count {
                    Text("· \(count)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            content
                .font(Style.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .background(RoundedRectangle(cornerRadius: Style.cornerRadius).fill(Style.surface))
        .overlay(RoundedRectangle(cornerRadius: Style.cornerRadius).strokeBorder(Style.hairline, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

/// The line a block shows when it has nothing to show.
struct EmptyBlockText: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension BlockKind {
    /// The number beside the title, or nil for blocks that show none.
    func count(for pr: PullRequest) -> Int? {
        switch self {
        case .checks: pr.checks.isEmpty ? nil : pr.checks.count
        case .files: pr.files.isEmpty ? nil : pr.files.count
        case .threads: pr.unresolvedThreads.isEmpty ? nil : pr.unresolvedThreads.count
        case .commits: pr.commits.isEmpty ? nil : pr.commits.count
        case .description, .reviewers, .ownersTouched, .activity, .labelsAndMetadata: nil
        }
    }
}

extension EnvironmentValues {
    /// The short names drawn for repositories and people on the page, from `shorthands.json`.
    /// Every name a block or pane draws comes through it. None by default.
    @Entry var shorthands = Shorthands.none
}

/// A repository's or a person's name as a label draws it. A shortened name shows its full name
/// on hover, and VoiceOver reads both. A name with no shorthand is plain text, as it was.
struct ShortenedName: View {
    let name: DisplayName

    init(_ name: DisplayName) { self.name = name }

    var body: some View {
        if name.isShortened {
            Text(verbatim: name.text)
                .help(name.fullName)
                .accessibilityLabel(name.accessibilityLabel)
        } else {
            Text(verbatim: name.text)
        }
    }
}

extension View {
    /// A tooltip only when there is text for one, so a label with nothing shortened keeps
    /// whatever tooltip the view around it has.
    @ViewBuilder func optionalHelp(_ text: String?) -> some View {
        if let text { help(text) } else { self }
    }
}
