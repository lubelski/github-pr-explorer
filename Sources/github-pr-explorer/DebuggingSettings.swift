import AppKit
import GitHubPRExplorerCore
import SwiftUI

/// Settings, Debugging: read-only facts for finding out why something went wrong. It shows
/// counts, paths and problems, never pull request content.
struct DebuggingSettingsView: View {
    let configuration: ConfigurationModel
    let context: SettingsContext
    @State private var copied = false

    var body: some View {
        let report = DiagnosticsReport(configuration: configuration, context: context)
        Form {
            Section {
                HStack {
                    Text("For finding out why something went wrong. Copy Diagnostics puts all of this on the clipboard as plain text.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(copied ? "Copied" : "Copy Diagnostics") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(report.plainText, forType: .string)
                        copied = true
                    }
                }
            }
            ForEach(report.groups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.rows, id: \.label) { row in
                        LabeledContent(row.label) {
                            Text(row.value)
                                .textSelection(.enabled)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }
            Section("Problems since launch") {
                if configuration.problemLog.isEmpty {
                    Text("None.").foregroundStyle(.secondary)
                } else {
                    ForEach(configuration.problemLog.reversed()) { problem in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(problem.text)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                            Text(problem.date.formatted(date: .abbreviated, time: .standard))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// What Debugging shows, as groups of rows and as plain text for Copy Diagnostics.
@MainActor
struct DiagnosticsReport {
    struct Row { var label: String; var value: String }
    struct Group { var title: String; var rows: [Row] }

    var groups: [Group]
    var problems: [ConfigurationModel.LoggedProblem]

    init(configuration: ConfigurationModel, context: SettingsContext) {
        let build = context.build
        let world = context.world
        let snapshot = configuration.snapshot
        func count(_ state: PullRequestState) -> Int { world.pullRequests.count { $0.state == state } }
        let builtIn = snapshot.layouts.count { $0.source == .builtIn }
        let fromFiles = snapshot.layouts.count - builtIn
        let history: String = if let problem = configuration.historyProblem {
            "Not working: \(problem)"
        } else {
            "Working, \(configuration.versions.count) \(configuration.versions.count == 1 ? "version" : "versions")"
        }
        groups = [
            Group(title: "Build", rows: [
                Row(label: "Version", value: build.version),
                Row(label: "Build", value: build.build),
                Row(label: "Commit", value: build.commit),
            ]),
            Group(title: "Mock world", rows: [
                Row(label: "Pull requests", value: "\(world.pullRequests.count): \(count(.open)) open, \(count(.merged)) merged, \(count(.closed)) closed"),
                Row(label: "Repositories", value: "\(world.repositories.count)"),
                Row(label: "People", value: "\(world.people.count)"),
                Row(label: "Teams", value: "\(world.teams.count)"),
                Row(label: "Seen from", value: world.now.formatted(.iso8601)),
            ]),
            Self.syncGroup(context.sync),
            Group(title: "Configuration", rows: [
                Row(label: "Folder", value: configuration.displayPath),
                Row(label: "Watching for changes", value: configuration.isWatching ? "Yes" : "No"),
                Row(label: "History", value: history),
                Row(label: "Layouts", value: "\(builtIn) built in, \(fromFiles) from files"),
                Row(label: "Default layout", value: snapshot.defaultLayout.id),
                Row(label: "Files with problems", value: snapshot.problems.isEmpty ? "None" : snapshot.problems.map(\.file).joined(separator: ", ")),
            ]),
        ]
        problems = configuration.problemLog
    }

    /// Counts and times only, never pull request content or the token.
    static func syncGroup(_ sync: SyncModel) -> Group {
        let status = sync.status
        let now = sync.now
        var rows = [
            Row(label: "Source", value: sync.source.title),
            Row(label: "gh", value: sync.ghPath ?? "Not found"),
            Row(label: "Account", value: status?.accountLogin ?? (status?.hasLogin == false ? "No gh login" : "Not checked yet")),
        ]
        if let status {
            let run = status.lastRun
            rows += [
                Row(label: "Pull requests", value: "\(status.pullRequestCount), \(status.detailedCount) with full detail"),
                Row(label: "Last sync", value: status.lastSuccessAt.map { "\($0.formatted(.iso8601)), \(RelativeAge.ago($0, now: now))" } ?? "Never"),
                Row(label: "Last run", value: "\(run.totalRequests) requests, GraphQL \(run.graphQLPoints) points, REST \(run.restPoints) (\(run.restNotModified) not modified), \(String(format: "%.1f", status.lastRunSeconds ?? 0)) s"),
                Row(label: "Since launch", value: "\(status.session.totalRequests) requests, GraphQL \(status.session.graphQLPoints) points, REST \(status.session.restPoints)"),
                Row(label: "Problem", value: status.problem.map { $0.shortText(now: now) } ?? "None"),
            ]
            for (key, label) in [("graphql", "GraphQL limit"), ("core", "REST limit")] {
                if let reading = status.rateLimits[key] { rows.append(Row(label: label, value: reading.summary)) }
            }
        }
        rows.append(Row(label: "Index", value: (sync.indexLocation.path as NSString).abbreviatingWithTildeInPath))
        return Group(title: "Sync", rows: rows)
    }

    var plainText: String {
        var text = "github-pr-explorer diagnostics\n"
        for group in groups {
            text += "\n\(group.title)\n"
            for row in group.rows { text += "  \(row.label): \(row.value)\n" }
        }
        text += "\nProblems since launch\n"
        if problems.isEmpty { text += "  None\n" }
        for problem in problems { text += "  \(problem.date.formatted(.iso8601)) \(problem.text)\n" }
        return text
    }
}
