import GitHubPRExplorerCore
import SwiftUI

/// What changed, by file: grouped by folder, with added and removed counts and a small bar.
/// Folders with one code owner are marked. Large shows the first five files and a row for the
/// rest, which opens to all of them.
struct FilesBlock: View {
    static let collapsedLimit = 5

    let pullRequest: PullRequest
    let size: BlockSize
    @State private var showsAll = false
    @State private var closedFolders: Set<String> = []
    @Environment(\.pageActions) private var actions
    @Environment(\.previewExpandsBlocks) private var previewExpands

    var body: some View {
        if pullRequest.files.isEmpty {
            EmptyBlockText("No files changed.")
        } else if size == .small {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(pullRequest.files.count == 1 ? "1 file" : "\(pullRequest.files.count) files")
                    Text(verbatim: "+\(pullRequest.additions)").foregroundStyle(Style.added).monospacedDigit()
                    Text(verbatim: "−\(pullRequest.deletions)").foregroundStyle(Style.removed).monospacedDigit()
                }
                ChangeBar(additions: pullRequest.additions, deletions: pullRequest.deletions)
                    .frame(height: 4)
            }
        } else {
            large.onAppear { if previewExpands { showsAll = true } }
        }
    }

    private var large: some View {
        let groups = FileGroups(files: pullRequest.files, codeOwners: pullRequest.codeOwners,
                                limit: showsAll ? nil : Self.collapsedLimit)
        return LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(groups.groups) { group in
                folderRow(group)
                if !closedFolders.contains(group.folder) {
                    ForEach(group.files, id: \.path) { file in
                        fileRow(file, indented: true)
                    }
                }
            }
            if groups.hiddenFileCount > 0 {
                Button { showsAll = true } label: {
                    countsRow(
                        title: Text(groups.hiddenFileCount == 1 ? "1 more file" : "\(groups.hiddenFileCount) more files").foregroundStyle(.secondary),
                        additions: groups.hiddenAdditions, deletions: groups.hiddenDeletions, isBinary: false)
                }
                .buttonStyle(.plain)
                .help("Show every file")
            } else if showsAll && pullRequest.files.count > Self.collapsedLimit {
                LinkButton(title: "Show fewer") { showsAll = false }
                    .padding(.top, 4)
            }
        }
    }

    private func folderRow(_ group: FileGroups.Group) -> some View {
        let isClosed = closedFolders.contains(group.folder)
        return Button {
            if isClosed { closedFolders.remove(group.folder) } else { closedFolders.insert(group.folder) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isClosed ? -90 : 0))
                    .frame(width: 10)
                Text(group.folder.isEmpty ? "/" : group.folder).fontWeight(.semibold)
                if !group.owners.isEmpty {
                    Tag(text: "owned by \(group.owners.joined(separator: ", "))", color: .orange)
                        .padding(.leading, 12)
                }
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
    }

    private func fileRow(_ file: ChangedFile, indented: Bool) -> some View {
        let selected = actions.openFilePath == file.path
        let kind: String = switch file.changeKind {
        case .added: "  added"
        case .removed: "  removed"
        case .renamed: "  renamed"
        case .modified: ""
        }
        let name = Text("\(FileGroups.fileName(of: file.path))\(Text(kind).font(Style.secondary).foregroundStyle(.secondary))")
        return countsRow(title: name, additions: file.additions, deletions: file.deletions, isBinary: file.isBinary)
            .padding(.leading, indented ? 20 : 0)
            .background(RoundedRectangle(cornerRadius: 4).fill(selected ? Color.accentColor.opacity(0.16) : .clear).padding(.horizontal, -4))
            .contentShape(Rectangle())
            .onTapGesture { actions.openFile?(file.path) }
            .help(file.previousPath.map { "\(file.path), renamed from \($0)" } ?? file.path)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func countsRow(title: Text, additions: Int, deletions: Int, isBinary: Bool) -> some View {
        HStack(spacing: 8) {
            title.lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            if isBinary {
                Text("binary").font(Style.secondary).foregroundStyle(.secondary)
                    .frame(width: 96, alignment: .trailing)
            } else {
                Text(verbatim: "+\(additions)").foregroundStyle(Style.added)
                    .frame(width: 44, alignment: .trailing)
                Text(verbatim: "−\(deletions)").foregroundStyle(Style.removed)
                    .frame(width: 44, alignment: .leading)
            }
            ChangeBar(additions: additions, deletions: deletions)
                .frame(width: 100, height: 6)
        }
        .font(.system(size: 12).monospacedDigit())
        .padding(.vertical, 2.5)
    }
}

/// A bar split into added and removed shares. Gray when nothing changed line by line.
struct ChangeBar: View {
    let additions: Int
    let deletions: Int

    var body: some View {
        GeometryReader { proxy in
            let total = additions + deletions
            let share = total == 0 ? 0 : CGFloat(additions) / CGFloat(total)
            HStack(spacing: 1) {
                if total == 0 {
                    Capsule().fill(.quaternary)
                } else {
                    if additions > 0 { Capsule().fill(Style.added).frame(width: max(2, proxy.size.width * share - 0.5)) }
                    if deletions > 0 { Capsule().fill(Style.removed) }
                }
            }
        }
        .accessibilityHidden(true)
    }
}
