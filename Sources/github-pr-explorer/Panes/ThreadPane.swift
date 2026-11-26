import GitHubPRExplorerCore
import SwiftUI

/// One review thread, as a pane over the diff: where it is, the line it quotes, each comment,
/// and a reply field with Resolve and Reply. Nothing is sent yet, so those are disabled.
struct ThreadPane: View {
    let model: AppModel
    let pullRequest: PullRequest
    let thread: ReviewThread
    let now: Date


    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(backTitle: "Files", title: Text("Thread · line \(Text(verbatim: "\(thread.line)"))")) {
                EmptyView()
            }
            Divider()
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {
                    location
                    quotedLine
                    ForEach(Array(thread.comments.enumerated()), id: \.element.id) { index, comment in
                        if index > 0 { Divider().padding(.leading, 32) }
                        commentView(comment)
                    }
                    reply
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var location: some View {
        HStack(spacing: 6) {
            Text(verbatim: "\(thread.path) · \(thread.side == .left ? "old " : "")line \(thread.line)")
                .font(Style.secondary)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
                .textSelection(.enabled)
            if pullRequest.threadsNeedingAttention(from: model.index.viewer).contains(where: { $0.id == thread.id }) {
                Tag(text: "needs you", color: .accentColor)
            }
            if thread.isOutdated { Tag(text: "outdated") }
            if thread.isResolved { Tag(text: "resolved") }
        }
    }

    /// The line as the diff shows it, with its number and marker.
    private var quotedLine: some View {
        let kind = lineKind
        let marker = kind == .added ? "+" : kind == .removed ? "−" : " "
        return HStack(spacing: 6) {
            Text(verbatim: "\(thread.line)").foregroundStyle(.tertiary)
            Text(verbatim: marker).foregroundStyle(DiffColors.marker(kind))
            DiffColors.code(thread.quotedLine.trimmingCharacters(in: .whitespaces), language: SyntaxTint.Language(path: thread.path))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .font(DiffLinesView.font)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 4).fill(kind == .context ? Color.primary.opacity(0.05) : DiffColors.background(kind)))
        .help(thread.quotedLine)
    }

    /// Added, removed or context, from the diff when it is built, or from the patch.
    private var lineKind: DiffRow.Kind {
        if let document = model.cachedDocument(for: pullRequest, path: thread.path),
           let index = document.row(forThread: thread.id, mode: .inline) {
            return document.rows[index].kind
        }
        let line = pullRequest.files.first { $0.path == thread.path }?.parsedPatch?.line(number: thread.line, side: thread.side)
        switch line?.kind {
        case .added: return .added
        case .removed: return .removed
        default: return .context
        }
    }

    private func commentView(_ comment: ReviewComment) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Avatar(person: comment.author)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(comment.author.displayName).font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 8)
                    Text(RelativeAge.ago(comment.createdAt, now: now))
                        .font(Style.secondary)
                        .foregroundStyle(.secondary)
                }
                Text(inlineMarkdown(comment.body))
                    .font(Style.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var reply: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Reply…", text: .constant(""), axis: .vertical)
                .lineLimit(4, reservesSpace: true)
                .textFieldStyle(.plain)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).strokeBorder(Style.hairline, lineWidth: 1))
                .disabled(true)
                .help(ReadOnlyNote.help)
            HStack {
                Button("Resolve") {}
                    .help(ReadOnlyNote.help)
                Spacer()
                Button("Reply") {}
                    .buttonStyle(.borderedProminent)
                    .help(ReadOnlyNote.help)
            }
            .controlSize(.large)
            .disabled(true)
        }
        .padding(.top, 8)
    }
}

/// A placeholder avatar: the person's initials in a circle. No image is fetched.
struct Avatar: View {
    let person: Person

    var body: some View {
        let initials = person.displayName.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        Text(initials)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
            .background(Circle().fill(Color.primary.opacity(0.08)))
            .accessibilityHidden(true)
    }
}
