import AppKit
import GitHubPRExplorerCore
import SwiftUI

/// The diff, as a pane over the page: a header with the way back and the mode switch, the file
/// tree on the left, and the open file's diff on the right.
struct DiffPane: View {
    @Bindable var model: AppModel
    let pullRequest: PullRequest
    let path: String
    let treeIsRail: Bool
    let change: (_ body: @escaping () -> Void) -> Void

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(backTitle: "Pull request",
                       title: Text("Files · \(Text("\(pullRequest.files.count)"))")) {
                Picker("Diff mode", selection: Binding(
                    get: { model.diffMode },
                    set: { mode in change { model.diffMode = mode } })) {
                    ForEach(DiffMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Show the diff inline, or the old and new files side by side")
            }
            Divider()
            HStack(spacing: 0) {
                DiffFileTree(pullRequest: pullRequest, selectedPath: path, isRail: treeIsRail) { newPath in
                    model.openFile(newPath)
                }
                .frame(width: treeIsRail ? DiffPaneLayout.railWidth : DiffPaneLayout.treeWidth)
                Divider()
                fileDiff
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder private var fileDiff: some View {
        // Renders build the document before drawing (`PreviewRenderer`), so they never wait here.
        if let document = model.cachedDocument(for: pullRequest, path: path) {
            DiffFileView(document: document, mode: model.diffMode, openThreadID: model.panePath.openThreadID,
                         openThread: { id in change { model.openThread(id) } })
                .id(path)
        } else {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task(id: path) { await model.loadDocument(for: pullRequest, path: path) }
        }
    }
}

// MARK: - The file tree

/// Every file the pull request changes, grouped by folder with its counts, the open one marked.
/// As a rail it shows one mark per file, with the full path in its tooltip. Up and down move
/// through the files while it has the keyboard.
struct DiffFileTree: View {
    let pullRequest: PullRequest
    let selectedPath: String
    let isRail: Bool
    let select: (String) -> Void

    @FocusState private var focused: Bool
    @Environment(\.paneIsCovered) private var covered
    @Environment(\.isRenderingPreview) private var rendering

    var body: some View {
        let groups = FileGroups(files: pullRequest.files, codeOwners: pullRequest.codeOwners)
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(groups.groups.enumerated()), id: \.element.id) { index, group in
                        if isRail {
                            if index > 0 { Divider().padding(.horizontal, 8).padding(.vertical, 3) }
                        } else {
                            folderRow(group)
                        }
                        ForEach(group.files, id: \.path) { file in
                            Group {
                                if isRail { railRow(file) } else { fileRow(file) }
                            }
                            .id(file.path)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .onAppear { proxy.scrollTo(selectedPath, anchor: .center) }
            .onChange(of: selectedPath) { _, path in proxy.scrollTo(path) }
        }
        .background(Color.primary.opacity(0.025))
        .focusable(!covered)
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.downArrow) { move(groups, 1) }
        .onKeyPress(.upArrow) { move(groups, -1) }
        .onAppear { if !covered && !rendering { focused = true } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Changed files")
    }

    private func move(_ groups: FileGroups, _ offset: Int) -> KeyPress.Result {
        if let next = groups.path(movingFrom: selectedPath, by: offset), next != selectedPath { select(next) }
        return .handled
    }

    private func pick(_ path: String) {
        focused = true
        if path != selectedPath { select(path) }
    }

    private func folderRow(_ group: FileGroups.Group) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.secondary)
            Text(group.folder.isEmpty ? "/" : group.folder)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.head)
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 3)
        .help(group.folder)
    }

    private func fileRow(_ file: ChangedFile) -> some View {
        let selected = file.path == selectedPath
        return HStack(spacing: 6) {
            Text(FileGroups.fileName(of: file.path))
                .fontWeight(selected ? .semibold : .regular)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            FileCounts(file: file)
        }
        .font(.system(size: 12))
        .padding(.leading, 22)
        .padding(.trailing, 10)
        .frame(height: 24)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 5).fill(Color.accentColor.opacity(0.18)).padding(.horizontal, 5)
            }
        }
        .contentShape(.rect)
        .onTapGesture { pick(file.path) }
        .help(file.treeTooltip)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func railRow(_ file: ChangedFile) -> some View {
        let selected = file.path == selectedPath
        let mark = FileMark(file: file)
        return Image(systemName: mark.systemName)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(selected ? Color.white : mark.color)
            .frame(width: 26, height: 22)
            .background(RoundedRectangle(cornerRadius: 5).fill(selected ? Color.accentColor : Color.primary.opacity(0.06)))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
            .contentShape(.rect)
            .onTapGesture { pick(file.path) }
            .help(file.treeTooltip)
            .accessibilityElement()
            .accessibilityLabel(file.treeTooltip)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// "+48 −12", or "binary".
struct FileCounts: View {
    let file: ChangedFile

    var body: some View {
        if file.isBinary {
            Text("binary").foregroundStyle(.secondary)
        } else {
            HStack(spacing: 4) {
                Text(verbatim: "+\(file.additions)").foregroundStyle(Style.added)
                Text(verbatim: "−\(file.deletions)").foregroundStyle(Style.removed)
            }
            .monospacedDigit()
        }
    }
}

/// A file's mark on the rail: what kind of change it is, as a symbol and a color. The symbol
/// carries the meaning; the color only repeats it.
struct FileMark {
    let systemName: String
    let color: Color

    init(file: ChangedFile) {
        if file.isBinary {
            systemName = "photo"
            color = .secondary
            return
        }
        switch file.changeKind {
        case .added: systemName = "plus"; color = Style.added
        case .removed: systemName = "minus"; color = Style.removed
        case .renamed: systemName = "arrow.right"; color = .blue
        case .modified: systemName = "pencil"; color = .secondary
        }
    }
}

extension ChangedFile {
    /// The full path, what happened to it, and its counts, for a tooltip.
    var treeTooltip: String {
        let kind: String = switch changeKind {
        case .added: "added"
        case .removed: "deleted"
        case .renamed: "renamed from \(previousPath ?? "another path")"
        case .modified: "modified"
        }
        let counts = isBinary ? "binary" : "+\(additions) −\(deletions)"
        return "\(path)\n\(kind), \(counts)"
    }
}

// MARK: - One file's diff

/// The open file: a header with its path and counts, then its diff in the chosen mode, or a
/// line saying why there is none.
struct DiffFileView: View {
    let document: DiffDocument
    let mode: DiffMode
    let openThreadID: String?
    let openThread: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            switch document.body {
            case .lines:
                DiffLinesView(document: document, mode: mode, openThreadID: openThreadID, openThread: openThread)
            case .binary:
                note("Binary file, not shown", systemName: "photo")
            case .renamedWithoutChanges:
                note("Renamed from \(document.previousPath ?? "another path") without changes", systemName: "arrow.right")
            case .noPatch:
                note("No changes to show", systemName: "doc")
            case .unreadable(let problem):
                note("The patch for this file could not be read: \(problem)", systemName: "exclamationmark.triangle")
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Group {
                if let previous = document.previousPath, document.changeKind == .renamed {
                    Text("\(Text(previous).foregroundStyle(.secondary)) → \(Text(document.path))")
                } else {
                    Text(document.path)
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
            .truncationMode(.head)
            .textSelection(.enabled)
            switch document.changeKind {
            case .added: Tag(text: "added", color: Style.added)
            case .removed: Tag(text: "deleted", color: Style.removed)
            case .renamed: Tag(text: "renamed", color: .blue)
            case .modified: EmptyView()
            }
            Spacer(minLength: 8)
            if document.body != .binary {
                HStack(spacing: 4) {
                    Text(verbatim: "+\(document.additions)").foregroundStyle(Style.added)
                    Text(verbatim: "−\(document.deletions)").foregroundStyle(Style.removed)
                }
                .font(.system(size: 12).monospacedDigit())
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
    }

    private func note(_ text: String, systemName: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemName).font(.system(size: 22)).foregroundStyle(.tertiary)
            Text(text).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The diff's lines, in a lazy list. Every row is the same height and the same width, worked out
/// once from the longest line, so nothing is measured per row and a 5,000-line file scrolls as
/// a short one does.
///
/// Long lines scroll sideways and never wrap. The rows stay pinned to the visible width: line
/// numbers, markers and thread markers stay put, and only the code moves, by the scroll view's
/// horizontal offset. In side by side mode that keeps both halves on screen, scrolling together.
struct DiffLinesView: View {
    let document: DiffDocument
    let mode: DiffMode
    let openThreadID: String?
    let openThread: (String) -> Void

    @State private var shift: CGFloat = 0

    static let font = Font.system(size: 12, design: .monospaced)
    static let rowHeight: CGFloat = 19
    static let numberWidth: CGFloat = 40
    static let markerWidth: CGFloat = 16
    /// One character of the monospaced font, for the longest line's width.
    static let characterWidth: CGFloat = {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        return ("0" as NSString).size(withAttributes: [.font: font]).width
    }()
    /// Room at the end of a line for a thread marker.
    static let markerRoom: CGFloat = 170
    /// The gutter before the code: line numbers and the marker.
    static let inlineGutter: CGFloat = numberWidth * 2 + markerWidth + 6
    static let sideGutter: CGFloat = numberWidth + markerWidth + 4

    var body: some View {
        GeometryReader { proxy in
            let viewport = proxy.size.width
            let language = SyntaxTint.Language(path: document.path)
            let hasMarkers = !document.inlineRowByThread.isEmpty
            let code = CGFloat(document.longestLineLength) * Self.characterWidth + 24 + (hasMarkers ? Self.markerRoom : 0)
            // How far the code can scroll: the most any one code column overflows.
            let overflow: CGFloat = switch mode {
            case .inline: max(0, Self.inlineGutter + code - viewport)
            case .sideBySide: max(0, Self.sideGutter + code - (viewport - 1) / 2)
            }
            let rowWidth = viewport + overflow
            let pinned = min(max(0, shift), overflow)
            ScrollViewReader { scroller in
                ScrollView([.vertical, .horizontal]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        switch mode {
                        case .inline:
                            ForEach(document.rows) { row in
                                InlineDiffRow(row: row, language: language, shift: pinned, openThreadID: openThreadID, openThread: openThread)
                                    .frame(width: viewport, height: Self.rowHeight, alignment: .leading)
                                    .offset(x: pinned)
                                    .frame(width: rowWidth, alignment: .leading)
                                    .id(row.id)
                            }
                        case .sideBySide:
                            ForEach(document.sideBySideRows) { row in
                                SideBySideDiffRow(row: row, half: (viewport - 1) / 2, language: language, shift: pinned,
                                                  openThreadID: openThreadID, openThread: openThread)
                                    .frame(width: viewport, height: Self.rowHeight, alignment: .leading)
                                    .offset(x: pinned)
                                    .frame(width: rowWidth, alignment: .leading)
                                    .id(row.id)
                            }
                        }
                    }
                    .frame(width: rowWidth, alignment: .leading)
                }
                .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.x }) { _, offset in shift = offset }
                .onAppear { scrollToOpenThread(scroller) }
                .onChange(of: openThreadID) { _, _ in scrollToOpenThread(scroller) }
                .onChange(of: mode) { _, _ in scrollToOpenThread(scroller) }
            }
        }
        .font(Self.font)
    }

    private func scrollToOpenThread(_ scroller: ScrollViewProxy) {
        guard let id = openThreadID, let row = document.row(forThread: id, mode: mode) else { return }
        scroller.scrollTo(row, anchor: UnitPoint(x: 0, y: 0.35))
    }
}

/// A line's code, moved left by the horizontal scroll and clipped to its column.
struct ScrolledCode: View {
    let text: String
    let language: SyntaxTint.Language
    let shift: CGFloat

    var body: some View {
        // The code is an overlay, so a line longer than its column never widens the row.
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .leading) {
                DiffColors.code(text, language: language)
                    .lineLimit(1)
                    .fixedSize()
                    .offset(x: -shift)
            }
            .clipped()
    }
}

/// A thin bar at the start of the line whose thread is open in the pane beside it.
struct OpenThreadBar: View {
    var body: some View {
        Rectangle().fill(Color.accentColor).frame(width: 3)
    }
}

/// The colors a diff line is drawn in. A removed or added line is always marked with its symbol
/// too, so the color is never the only sign.
enum DiffColors {
    static func background(_ kind: DiffRow.Kind) -> Color {
        switch kind {
        case .added: Style.added.opacity(0.13)
        case .removed: Style.removed.opacity(0.12)
        case .hunkHeader: Color.primary.opacity(0.045)
        case .context: .clear
        }
    }

    static func gutter(_ kind: DiffRow.Kind) -> Color {
        switch kind {
        case .added: Style.added.opacity(0.08)
        case .removed: Style.removed.opacity(0.08)
        case .hunkHeader, .context: .clear
        }
    }

    static func marker(_ kind: DiffRow.Kind) -> Color {
        switch kind {
        case .added: Style.added
        case .removed: Style.removed
        case .hunkHeader, .context: .secondary
        }
    }

    static let keyword = Color(nsColor: .systemPurple)
    static let string = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.98, green: 0.62, blue: 0.38, alpha: 1)
            : NSColor(srgbRed: 0.70, green: 0.30, blue: 0.05, alpha: 1)
    })
    static let number = Color(nsColor: .systemBlue)
    static let comment = Color.secondary

    /// A line of code with best-effort tinting.
    static func code(_ text: String, language: SyntaxTint.Language) -> Text {
        guard language != .plain else { return Text(verbatim: text) }
        var attributed = AttributedString()
        for run in SyntaxTint.runs(text, language: language) {
            var part = AttributedString(run.text)
            switch run.kind {
            case .keyword: part.foregroundColor = keyword
            case .string: part.foregroundColor = string
            case .number: part.foregroundColor = number
            case .comment: part.foregroundColor = comment
            case nil: break
            }
            attributed.append(part)
        }
        return Text(attributed)
    }
}

/// The small "1 thread · Ada Park" marker at the end of a line. It opens the line's first thread.
struct ThreadMarkerButton: View {
    let marker: DiffThreadMarker
    let isOpen: Bool
    let open: (String) -> Void
    @Environment(\.shorthands) private var shorthands

    var body: some View {
        Button { if let first = marker.threadIDs.first { open(first) } } label: {
            Text(marker.label(using: shorthands))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isOpen ? Color.white : Color.accentColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 1.5)
                .background(Capsule().fill(isOpen ? Color.accentColor : Color.accentColor.opacity(0.13)))
                // Opaque underneath, so a long line running under the marker does not show through.
                .background(Capsule().fill(Style.surface))
        }
        .buttonStyle(.plain)
        .help("Open the thread on this line")
        .padding(.trailing, 10)
    }
}

struct InlineDiffRow: View {
    let row: DiffRow
    let language: SyntaxTint.Language
    let shift: CGFloat
    let openThreadID: String?
    let openThread: (String) -> Void

    var body: some View {
        if row.kind == .hunkHeader {
            Text(verbatim: row.text)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.leading, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .background(DiffColors.background(.hunkHeader))
        } else {
            let isOpen = row.threads.map { marker in openThreadID.map(marker.threadIDs.contains) ?? false } ?? false
            HStack(spacing: 0) {
                number(row.oldLineNumber)
                number(row.newLineNumber)
                Text(verbatim: row.marker)
                    .foregroundStyle(DiffColors.marker(row.kind))
                    .frame(width: DiffLinesView.markerWidth)
                    .padding(.leading, 6)
                ScrolledCode(text: row.text + (row.hasNoNewlineAtEnd ? "  ⊘ no newline at end of file" : ""),
                             language: language, shift: shift)
            }
            .frame(maxHeight: .infinity)
            .background(DiffColors.background(row.kind))
            .overlay(alignment: .leading) { if isOpen { OpenThreadBar() } }
            .overlay(alignment: .trailing) {
                if let marker = row.threads {
                    ThreadMarkerButton(marker: marker, isOpen: isOpen, open: openThread)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func number(_ value: Int?) -> some View {
        Text(value.map(String.init) ?? "")
            .foregroundStyle(.tertiary)
            .frame(width: DiffLinesView.numberWidth, alignment: .trailing)
            .frame(maxHeight: .infinity)
            .background(DiffColors.gutter(row.kind))
    }
}

struct SideBySideDiffRow: View {
    let row: SideBySideRow
    let half: CGFloat
    let language: SyntaxTint.Language
    let shift: CGFloat
    let openThreadID: String?
    let openThread: (String) -> Void

    var body: some View {
        if let hunk = row.hunk {
            HStack(spacing: 0) {
                Text("Old · \(hunk.oldRange)")
                    .padding(.leading, 14)
                    .frame(width: half, alignment: .leading)
                Divider()
                Text("New · \(hunk.newRange)\(hunk.section.isEmpty ? "" : "  \(hunk.section)")")
                    .padding(.leading, 14)
                    .frame(width: half, alignment: .leading)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxHeight: .infinity)
            .background(DiffColors.background(.hunkHeader))
        } else {
            HStack(spacing: 0) {
                side(row.left, number: row.left?.oldLineNumber, isOld: true)
                Divider()
                side(row.right, number: row.right?.newLineNumber, isOld: false)
            }
        }
    }

    @ViewBuilder private func side(_ line: DiffRow?, number: Int?, isOld: Bool) -> some View {
        if let line {
            // A context line's thread shows once, on the new side.
            let marker = isOld && line.kind == .context ? nil : line.threads
            let isOpen = marker.map { marker in openThreadID.map(marker.threadIDs.contains) ?? false } ?? false
            HStack(spacing: 0) {
                Text(number.map(String.init) ?? "")
                    .foregroundStyle(.tertiary)
                    .frame(width: DiffLinesView.numberWidth, alignment: .trailing)
                Text(verbatim: line.marker)
                    .foregroundStyle(DiffColors.marker(line.kind))
                    .frame(width: DiffLinesView.markerWidth)
                    .padding(.leading, 4)
                ScrolledCode(text: line.text, language: language, shift: shift)
            }
            .frame(width: half)
            .frame(maxHeight: .infinity)
            .background(DiffColors.background(line.kind))
            .overlay(alignment: .leading) { if isOpen { OpenThreadBar() } }
            .overlay(alignment: .trailing) {
                if let marker {
                    ThreadMarkerButton(marker: marker, isOpen: isOpen, open: openThread)
                }
            }
        } else {
            // Filler where this side has no line.
            Color.primary.opacity(0.035)
                .frame(width: half)
                .frame(maxHeight: .infinity)
        }
    }
}
