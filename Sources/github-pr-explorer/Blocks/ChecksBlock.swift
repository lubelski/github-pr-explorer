import GitHubPRExplorerCore
import SwiftUI

/// CI results: failed first, then running and queued, then passed and skipped collapsed into one
/// row each, which opens to list them.
struct ChecksBlock: View {
    let pullRequest: PullRequest
    let size: BlockSize
    let context: BlockContext
    @State private var expanded: Set<CheckState> = []
    @Environment(\.previewExpandsBlocks) private var previewExpands

    var body: some View {
        if pullRequest.checks.isEmpty {
            EmptyBlockText("No checks ran on this commit.")
        } else if size == .small {
            small
        } else {
            large.onAppear { if previewExpands { expanded = Set(CheckState.allCases) } }
        }
    }

    private var small: some View {
        let summary = pullRequest.checkSummary
        return HStack(spacing: 10) {
            ForEach(summary.entries, id: \.state) { entry in
                HStack(spacing: 3) {
                    StatusMark(systemName: entry.state.systemName, color: entry.state.color, size: 10)
                    Text("\(entry.count) \(entry.state.rawValue)")
                }
            }
        }
    }

    private var large: some View {
        let groups = CheckGroups(checks: pullRequest.checks)
        return LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(groups.attention.enumerated()), id: \.offset) { index, check in
                if index > 0 { Divider() }
                checkRow(check, bold: true)
            }
            ForEach(groups.collapsed) { group in
                if !groups.attention.isEmpty || group.state != groups.collapsed.first?.state { Divider() }
                collapsedRow(group)
                if expanded.contains(group.state) {
                    ForEach(Array(group.checks.enumerated()), id: \.offset) { _, check in
                        checkRow(check, bold: false)
                            .padding(.leading, 17)
                    }
                }
            }
        }
    }

    private func checkRow(_ check: Check, bold: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            StatusMark(systemName: check.state.systemName, color: check.state.color)
            Text(check.name).fontWeight(bold ? .semibold : .regular)
            Text(CheckGroups.detail(for: check, now: context.now))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if check.isRequired {
                Text("required").font(Style.secondary).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, Style.rowSpacing)
    }

    private func collapsedRow(_ group: CheckGroups.Collapsed) -> some View {
        let isOpen = expanded.contains(group.state)
        return Button {
            if isOpen { expanded.remove(group.state) } else { expanded.insert(group.state) }
        } label: {
            HStack(spacing: 6) {
                StatusMark(systemName: group.state.systemName, color: group.state.color)
                Text(group.title).fontWeight(.semibold)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, Style.rowSpacing)
        .accessibilityLabel(isOpen ? "Hide \(group.title)" : "Show \(group.title)")
    }
}
