import GitHubPRExplorerCore
import SwiftUI

/// Who has reviewed and who is still asked, one row each. The viewer's own request says "you".
struct ReviewersBlock: View {
    let pullRequest: PullRequest
    let size: BlockSize
    let context: BlockContext

    var body: some View {
        let rows = ReviewerRow.rows(for: pullRequest, viewer: context.viewer)
        if rows.isEmpty {
            EmptyBlockText("No reviewers yet, and none requested.")
        } else if size == .small {
            let approved = rows.count { $0.state == .approved }
            HStack(spacing: 6) {
                HStack(spacing: -4) {
                    ForEach(rows.prefix(4)) { row in Initials(name: row.name) }
                }
                Text("\(approved) of \(rows.count) approved")
                if rows.contains(where: { $0.state == .requested && $0.isViewer }) {
                    Tag(text: "you", color: .orange)
                }
            }
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { row in
                    HStack(spacing: 6) {
                        Text(row.name).lineLimit(1)
                        if row.isCodeOwnerRequest {
                            Text("code owner").font(Style.secondary).foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: 8)
                        StatusMark(systemName: row.state.systemName, color: row.state.color, size: 10)
                        Text(row.stateText)
                            .fontWeight(row.isViewer && row.state == .requested ? .medium : .regular)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }
}

/// A round mark with a person's or team's initials, standing in for an avatar.
struct Initials: View {
    let name: String

    var body: some View {
        let words = name.trimmingCharacters(in: CharacterSet(charactersIn: "@")).split(whereSeparator: { $0 == " " || $0 == "/" || $0 == "-" })
        let letters = words.prefix(2).compactMap(\.first).map { String($0).uppercased() }.joined()
        Text(letters)
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 18, height: 18)
            .background(Circle().fill(Style.surface))
            .overlay(Circle().strokeBorder(Style.hairline))
    }
}

/// Which code owners' paths the change touches: pattern, owner, and how many files.
struct OwnersTouchedBlock: View {
    let pullRequest: PullRequest
    let size: BlockSize

    var body: some View {
        let matches = pullRequest.codeOwners
        if matches.isEmpty {
            EmptyBlockText("No code owners for these files.")
        } else if size == .small {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(matches.enumerated()), id: \.offset) { _, match in
                    Text("\(match.owners.joined(separator: ", ")) · \(fileCount(match.paths.count))")
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(matches.enumerated()), id: \.offset) { _, match in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(match.pattern)
                            Image(systemName: "arrow.right").font(.system(size: 10)).foregroundStyle(.secondary)
                            Text(match.owners.joined(separator: ", ")).fontWeight(.semibold)
                        }
                        Text(fileList(match.paths))
                            .font(Style.secondary)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
    }

    private func fileCount(_ count: Int) -> String { count == 1 ? "1 file" : "\(count) files" }

    private func fileList(_ paths: [String]) -> String {
        let names = paths.prefix(6).map(FileGroups.fileName(of:))
        let more = paths.count > names.count ? ", and \(paths.count - names.count) more" : ""
        return "\(fileCount(paths.count)): " + names.joined(separator: ", ") + more
    }
}
