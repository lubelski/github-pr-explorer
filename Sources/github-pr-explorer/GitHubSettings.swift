import GitHubPRExplorerCore
import SwiftUI

/// Settings, GitHub: where pull requests come from, the gh login, how often to sync, and the
/// repositories watched in full. Everything here is in `settings.json`, except what the sync
/// reports, which it reads from the sync and never from the network itself.
struct GitHubSettingsView: View {
    let configuration: ConfigurationModel
    let sync: SyncModel
    @State private var newRepository = ""
    @Environment(\.isRenderingPreview) private var rendering

    static let intervals = [60, 120, 300, 600, 900, 1800, 3600]

    var body: some View {
        let settings = configuration.snapshot.settings
        Form {
            Section {
                Picker(selection: Binding(get: { settings.pullRequestSource }, set: { configuration.setPullRequestSource($0) })) {
                    ForEach(PullRequestSource.allCases, id: \.self) { source in
                        Text(source.title).tag(source)
                    }
                } label: {
                    Text("Pull requests from")
                    Text(settings.pullRequestSource == .mock
                         ? "The built-in placeholder pull requests, with no network and no sign-in."
                         : "Open pull requests on GitHub that involve you, read through the gh login. Read-only: nothing is sent back.")
                }
                .pickerStyle(.segmented)
            }

            Section("Login") {
                LabeledContent {
                    Text(sync.ghPath ?? "Not found")
                        .foregroundStyle(sync.ghPath == nil ? .orange : .secondary)
                        .textSelection(.enabled)
                } label: {
                    Text("GitHub command line tool")
                    if sync.ghPath == nil {
                        Text("Install it with `brew install gh`, then run `gh auth login` in Terminal.")
                    }
                }
                LabeledContent {
                    HStack(spacing: 10) {
                        Text(accountText)
                            .foregroundStyle(sync.status?.hasLogin == false ? .orange : .primary)
                        Button("Check Again") { sync.checkAgain() }
                            .disabled(rendering || sync.status?.isSyncing == true)
                    }
                } label: {
                    Text("Account")
                    Text("The token comes from `gh auth token` each time it is needed. It is never stored.")
                }
            }

            Section {
                Picker(selection: Binding(get: { settings.syncIntervalSeconds }, set: { configuration.setSyncInterval($0) })) {
                    ForEach(intervals(including: settings.syncIntervalSeconds), id: \.self) { seconds in
                        Text(Self.intervalName(seconds)).tag(seconds)
                    }
                } label: {
                    Text("Check for changes every")
                    Text("A light check of the list. A pull request that changed, or that you open, then has its detail fetched.")
                }
                if let status = sync.status, settings.pullRequestSource == .github {
                    LabeledContent("Last sync", value: status.lastSuccessAt.map { RelativeAge.ago($0, now: sync.now) } ?? "Never")
                    LabeledContent("Pull requests", value: "\(status.pullRequestCount), \(status.detailedCount) with full detail")
                    if let problem = status.problem {
                        LabeledContent("Problem") {
                            Text(problem.explanation)
                                .foregroundStyle(.orange)
                                .multilineTextAlignment(.trailing)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    ForEach(["graphql", "core"], id: \.self) { key in
                        if let reading = status.rateLimits[key] {
                            LabeledContent(key == "graphql" ? "GraphQL rate limit" : "REST rate limit", value: reading.summary)
                        }
                    }
                }
            } header: {
                Text("Sync")
            } footer: {
                FileFootnote(text: "The sync keeps to half of GitHub's hourly rate limits, so your other tools have the rest.")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
            }

            Section {
                if settings.watchedRepositories.isEmpty {
                    Text("None. Only pull requests that involve you are shown.")
                        .foregroundStyle(.secondary)
                }
                ForEach(settings.watchedRepositories, id: \.self) { name in
                    HStack {
                        Text(name).font(.body.monospaced())
                        Spacer()
                        Button {
                            configuration.setWatchedRepositories(settings.watchedRepositories.filter { $0 != name })
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Stop watching \(name)")
                    }
                }
                HStack {
                    TextField("owner/name", text: $newRepository)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                        .onSubmit(addRepository)
                    Button("Add", action: addRepository)
                        .disabled(!canAdd(settings))
                }
            } header: {
                Text("Watched repositories")
            } footer: {
                FileFootnote(text: "Every open pull request in these is fetched too, besides the ones that involve you: authored, review requested, assigned or mentioned.")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
            }

            Section {
                FileFootnote(text: "Saved in settings.json as pullRequestSource, syncIntervalSeconds and watchedRepositories. github-pr-explorer-ctl config set changes them too, and github-pr-explorer-ctl sync status reports the sync. Synced data is a cache in \(displayIndexFolder), never in the configuration folder.")
            }
            if let problem = configuration.snapshot.problems.first(where: { $0.file == ConfigurationSettings.fileName }) {
                Section {
                    ProblemRow(problem: problem, configuration: configuration)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            // Once per launch, ask the sync whose login it is, so this section can say before
            // the switch is turned on. It is a request to the sync, which does the work.
            if !rendering, sync.status == nil { sync.checkAgain() }
        }
    }

    private var accountText: String {
        guard let status = sync.status else { return "Not checked yet" }
        if status.hasLogin == false {
            return status.problem.map { $0 == .ghMissing ? "No gh login" : $0.shortText(now: sync.now) } ?? "No gh login"
        }
        if status.isSyncing, status.accountLogin == nil { return "Checking…" }
        return status.accountLogin.map { "Signed in as \($0)" } ?? (status.problem?.shortText(now: sync.now) ?? "Not checked yet")
    }

    private var displayIndexFolder: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = sync.indexLocation.deletingLastPathComponent().path
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    private func intervals(including current: Int) -> [Int] {
        Self.intervals.contains(current) ? Self.intervals : (Self.intervals + [current]).sorted()
    }

    static func intervalName(_ seconds: Int) -> String {
        if seconds % 3600 == 0 { return seconds == 3600 ? "1 hour" : "\(seconds / 3600) hours" }
        if seconds % 60 == 0 { return seconds == 60 ? "1 minute" : "\(seconds / 60) minutes" }
        return "\(seconds) seconds"
    }

    private func canAdd(_ settings: ConfigurationSettings) -> Bool {
        let name = newRepository.trimmingCharacters(in: .whitespaces)
        return Repository.isPlainName(name) && !settings.watchedRepositories.contains { $0.lowercased() == name.lowercased() }
    }

    private func addRepository() {
        let settings = configuration.snapshot.settings
        guard canAdd(settings) else { return }
        configuration.setWatchedRepositories(settings.watchedRepositories + [newRepository.trimmingCharacters(in: .whitespaces)])
        newRepository = ""
    }
}
