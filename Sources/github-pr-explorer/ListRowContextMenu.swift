import AppKit
import GitHubPRExplorerCore
import SwiftUI

/// Writes a shorthand to the configuration folder: the text to set, or nil to take it away.
/// The app sets it to `ConfigurationModel`, so the list and Settings both change at once.
/// Renders leave it nil, and then nothing is written.
struct ShorthandWriter {
    let write: (ShorthandKind, String, String?) -> Void
}

extension EnvironmentValues {
    @Entry var shorthandWriter: ShorthandWriter?
}

/// A Set Shorthand popover asked for on one row of the list.
struct ShorthandEditorRequest: Equatable, Identifiable {
    /// The row it opens on.
    let row: ListSelection
    let target: ShorthandTarget

    var id: String { "\(row.storedValue)|\(target.id)" }
}

/// The right-click menu of a row of the pull request list, drawn from `ListRowMenu`. The menu
/// belongs to the row under the pointer, selected or not, and the selection stays as it was.
struct ListRowContextMenu: View {
    @Bindable var model: AppModel
    let rows: Set<ListSelection>
    /// Opens the Set Shorthand popover on a row.
    let editShorthand: (ShorthandEditorRequest) -> Void

    var body: some View {
        if rows.count == 1, let row = rows.first,
           let menu = ListRowMenu(for: row, in: model.listTree, closed: model.closedGroups, shorthands: model.shorthands) {
            ForEach(Array(menu.sections.enumerated()), id: \.offset) { position, section in
                if position > 0 { Divider() }
                ForEach(section) { item in
                    Button(item.title) { perform(item.action, on: row) }
                        .disabled(!item.isEnabled)
                }
            }
        }
    }

    private func perform(_ action: ListRowMenu.Action, on row: ListSelection) {
        switch action {
        case .setShorthand(let target):
            // After the menu has closed, so the popover is not dismissed with it.
            DispatchQueue.main.async { editShorthand(ShorthandEditorRequest(row: row, target: target)) }
        case .openInBrowser(let url):
            NSWorkspace.shared.open(url)
        case .copy(let text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        case .setOpen(let ids, let open):
            withAnimation(.snappy(duration: 0.2)) {
                if open { model.closedGroups.subtract(ids) } else { model.closedGroups.formUnion(ids) }
            }
        }
    }
}

/// Puts the Set Shorthand popover on a row when it is asked for on that row.
struct ShorthandPopoverAnchor: ViewModifier {
    let row: ListSelection
    @Binding var request: ShorthandEditorRequest?
    let shorthands: Shorthands

    func body(content: Content) -> some View {
        content.popover(isPresented: Binding {
            request?.row == row
        } set: { shown in
            if !shown, request?.row == row { request = nil }
        }, arrowEdge: .bottom) {
            if let request {
                ShorthandEditor(edit: ShorthandEdit(target: request.target, shorthands: shorthands),
                                shorthands: shorthands) { self.request = nil }
                    .id(request.id)
            }
        }
    }
}

/// The Set Shorthand popover: the shorthand for one repository, person or organization, to
/// set, change or clear. Return saves and Escape cancels. It starts with the shorthand there
/// is, or a suggestion, selected so typing replaces it. A shorthand something else already has
/// is allowed, with the same warning Settings gives. Clearing the field and saving removes it,
/// as Remove does.
struct ShorthandEditor: View {
    let edit: ShorthandEdit
    let shorthands: Shorthands
    let close: () -> Void
    @Environment(\.shorthandWriter) private var writer
    @State private var text: String
    @FocusState private var focused: Bool

    /// - Parameter text: What the field starts with, for renders. The shorthand there is, or
    ///   the suggestion, by default.
    init(edit: ShorthandEdit, shorthands: Shorthands, text: String? = nil, close: @escaping () -> Void) {
        self.edit = edit
        self.shorthands = shorthands
        self.close = close
        _text = State(initialValue: text ?? edit.initialText)
    }

    static let width: CGFloat = 340

    var body: some View {
        let outcome = edit.outcome(of: text)
        VStack(alignment: .leading, spacing: 10) {
            Text("Shorthand for \(edit.target.title)")
                .font(.headline)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Shorthand", text: $text, prompt: Text(edit.target.suggestion))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(save)
                .accessibilityLabel("Shorthand for \(edit.target.title)")
            if let warning = edit.clashWarning(for: text, in: shorthands) {
                Label {
                    Text(warning).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                .font(.callout)
            }
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if edit.current != nil {
                    Button("Remove") { write(nil) }
                        .help("Take the shorthand away, so the full name shows again")
                }
                Spacer()
                Button("Cancel", action: close)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(outcome == .nothing)
            }
            .padding(.top, 4)
        }
        .padding(16)
        .frame(width: Self.width)
        .onAppear { focused = true }
    }

    private var caption: String {
        let place = switch edit.target.kind {
        case .repository: "Shown wherever the full name would be."
        case .person: "Shown wherever their name would be."
        case .organization: "Shown for the organization's title row, and as the owner of its repositories that have no shorthand."
        }
        return place + " The full name shows on hover. Settings, Shorthands lists them all."
    }

    private func save() {
        switch edit.outcome(of: text) {
        case .set(let shorthand): write(shorthand)
        case .remove: write(nil)
        case .nothing: close()
        }
    }

    private func write(_ shorthand: String?) {
        writer?.write(edit.target.kind, edit.target.identity, shorthand)
        close()
    }
}
