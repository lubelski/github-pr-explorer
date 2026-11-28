import GitHubPRExplorerCore
import SwiftUI

/// Settings, Shorthands: short names the app draws in place of repositories, people and
/// organizations, one list per kind, with a way to add, change and remove each. Everything here is
/// `shorthands.json`. Two things that share a shorthand are allowed, with a warning beside each.
struct ShorthandsSettingsView: View {
    let configuration: ConfigurationModel
    /// The repositories and people the index knows, offered when adding one.
    let candidates: ShorthandCandidates

    var body: some View {
        let shorthands = configuration.snapshot.shorthands
        Form {
            Section {
                Text("A shorthand is a short name drawn in place of a repository, a person or an organization, such as Web for acme/web, so a list is quicker to scan. Hover over a shortened name to see the full one. Search finds both. Right-click a row of the pull request list to set one from there.")
                    .fixedSize(horizontal: false, vertical: true)
                Text("Only the labels the app draws change. Titles, descriptions, comments, links, and anything sent to GitHub stay as written.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let problem = configuration.snapshot.problems.first(where: { $0.file == ShorthandsFile.fileName }) {
                Section {
                    ProblemRow(problem: problem, configuration: configuration)
                }
            }
            ForEach(ShorthandKind.allCases) { kind in
                Section {
                    let entries = shorthands.entries(of: kind).sorted { $0.target.lowercased() < $1.target.lowercased() }
                    if entries.isEmpty {
                        Text("None yet.").foregroundStyle(.secondary)
                    }
                    ForEach(entries) { entry in
                        ShorthandRow(entry: entry, clash: shorthands.clash(for: entry), configuration: configuration)
                    }
                    NewShorthandRow(kind: kind, suggestions: candidates.unset(kind, in: shorthands), configuration: configuration)
                } header: {
                    Text(kind.pluralTitle)
                }
            }
            Section {
                FileFootnote(text: "Saved in shorthands.json in the configuration folder. Editing that file, or `github-pr-explorer-ctl shorthands set`, changes these too.")
            }
        }
        .formStyle(.grouped)
    }
}

/// One shorthand: what it is for, the shorthand to edit, and Remove. A clash shows under it.
struct ShorthandRow: View {
    let entry: Shorthand
    let clash: ShorthandClash?
    let configuration: ConfigurationModel
    @State private var text: String

    init(entry: Shorthand, clash: ShorthandClash?, configuration: ConfigurationModel) {
        self.entry = entry
        self.clash = clash
        self.configuration = configuration
        _text = State(initialValue: entry.shorthand)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(verbatim: entry.target)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Shorthand", text: $text, prompt: Text("Shorthand"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                    .onSubmit(save)
                    .accessibilityLabel("Shorthand for \(entry.target)")
                Button {
                    configuration.removeShorthand(entry.kind, for: entry.target)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Remove the shorthand for \(entry.target)")
            }
            if let clash {
                Label {
                    Text(clash.warning(for: entry))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                .font(.callout)
            }
        }
        .onChange(of: entry.shorthand) { _, new in text = new }
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { text = entry.shorthand; return }
        guard trimmed != entry.shorthand else { return }
        configuration.setShorthand(entry.kind, for: entry.target, to: trimmed)
    }
}

/// The row that adds a shorthand: what it is for, typed or picked from what the index knows,
/// and the shorthand.
struct NewShorthandRow: View {
    let kind: ShorthandKind
    let suggestions: [(identity: String, title: String)]
    let configuration: ConfigurationModel
    @State private var target = ""
    @State private var shorthand = ""

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                TextField(kind.identityPlaceholder, text: $target, prompt: Text(kind.identityPlaceholder))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .onSubmit(add)
                if !suggestions.isEmpty {
                    Menu {
                        ForEach(suggestions.prefix(60), id: \.identity) { suggestion in
                            Button(suggestion.title) { target = suggestion.identity }
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.borderless)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help(pickHelp)
                }
            }
            .frame(maxWidth: .infinity)
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Shorthand", text: $shorthand, prompt: Text("Shorthand"))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                .onSubmit(add)
            Button("Add", action: add)
                .disabled(!canAdd)
        }
    }

    private var pickHelp: String {
        switch kind {
        case .repository: "Pick a repository the app knows"
        case .person: "Pick a person the app knows"
        case .organization: "Pick an organization the app knows"
        }
    }

    private var canAdd: Bool {
        kind.isValidIdentity(kind.normalizedIdentity(target)) && !shorthand.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func add() {
        guard canAdd else { return }
        configuration.setShorthand(kind, for: target, to: shorthand)
        target = ""
        shorthand = ""
    }
}
