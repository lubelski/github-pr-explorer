import Foundation
import Testing
@testable import github_pr_explorer_ctl
@testable import GitHubPRExplorerCore

/// `config` and `layouts`, always with `--config` and a temporary folder.
@Suite struct ConfigurationCommandTests {
    let config = TemporaryConfiguration()

    func run(_ arguments: String...) -> ControlCommandResult {
        ControlCommand.run(arguments + ["--config", config.folder.path])
    }

    @Test func pathPrintsTheFolderWithoutMakingIt() {
        let result = run("config", "path")
        #expect(result.exitCode == 0)
        #expect(result.output == config.folder.standardizedFileURL.path + "\n")
        #expect(!config.store.exists)
        // The default, with no --config, is the app's folder. Only printed, never touched.
        #expect(ControlCommand.run(["config", "path"]).output.hasSuffix("/Library/Application Support/github-pr-explorer/config\n"))
    }

    @Test func validateBeforeAndAfter() throws {
        var result = run("config", "validate")
        #expect(result.exitCode == 0)
        #expect(result.output.contains("No configuration folder"))
        #expect(!config.store.exists, "looking never creates the folder")

        try config.store.prepare(author: .app)
        result = run("config", "validate")
        #expect(result.exitCode == 0)
        #expect(result.output == "ok\tsettings.json\nok\tsaved-filters.json\n")

        try config.write(myLayout, to: "layouts/mine.json")
        try config.write(#"{"formatVersion": 1, "id": "broken", "name": "B", "tabs": []}"#, to: "layouts/broken.json")
        result = run("config", "validate")
        #expect(result.exitCode == 1)
        #expect(result.output == """
            ok\tsettings.json
            ok\tsaved-filters.json
            invalid\tlayouts/broken.json, at tabs: a layout needs at least one tab. It is not in use.
            ok\tlayouts/mine.json

            """)
        #expect(result.errorOutput == "1 problem found.\n")
        #expect(try config.versions().count == 1, "validate records nothing")
    }

    @Test func setShowAndHistory() throws {
        var result = run("config", "set", "defaultLayout", "tabbed")
        #expect(result.exitCode == 0, "\(result.errorOutput)")
        #expect(result.output == "Set the default layout to Tabbed.\n")
        result = run("config", "set", "appearance", "dark")
        #expect(result.output == "Set appearance to Dark.\n")
        result = run("config", "set", "appearance", "purple")
        #expect(result.exitCode == 1)
        #expect(result.errorOutput.contains("system, light, dark"))
        #expect(run("config", "set", "appearance").exitCode == 2)

        result = run("config", "show")
        #expect(result.output.contains("  appearance                dark\n"))
        #expect(result.output.contains("  tabbed\tTabbed\tbuilt in\tdefault\n"))

        result = run("config", "show", "--json")
        let report = try GitHubPRExplorerJSON.decoder().decode(ControlCommand.ConfigurationReport.self, from: Data(result.output.utf8))
        #expect(report.settings.defaultLayout == "tabbed")
        #expect(report.layouts.first { $0.isDefault }?.id == "tabbed")

        result = run("config", "history")
        let lines = result.output.split(separator: "\n").map { $0.split(separator: "\t").map(String.init) }
        #expect(lines.count == 3)
        #expect(lines.map { $0[2] } == ["ctl", "ctl", "ctl"])
        #expect(lines.map { $0[3] } == ["Set appearance to Dark", "Set the default layout to Tabbed", "Created the configuration folder"])
        #expect(lines.allSatisfy { $0[0].count == 7 && $0[1].hasSuffix(" UTC") })
        #expect(run("config", "history", "--limit", "1").output.split(separator: "\n").count == 1)
        #expect(run("config", "history", "--limit", "zero").exitCode == 2)
        let versions = try GitHubPRExplorerJSON.decoder().decode([ConfigurationVersion].self, from: Data(run("config", "history", "--json").output.utf8))
        #expect(versions.count == 3)
    }

    @Test func diffAndRestore() throws {
        _ = run("config", "set", "appearance", "light")
        _ = run("config", "set", "appearance", "dark")
        let lines = run("config", "history").output.split(separator: "\n").map { $0.split(separator: "\t").map(String.init) }
        let lightVersion = lines[1][0]

        let diff = run("config", "diff", lightVersion)
        #expect(diff.exitCode == 0)
        #expect(diff.output.contains("+  \"appearance\" : \"light\","))
        #expect(run("config", "diff", "nope").exitCode == 1)

        let restore = run("config", "restore", lightVersion, "settings.json")
        #expect(restore.exitCode == 0, "\(restore.errorOutput)")
        #expect(restore.output.hasPrefix("Restored settings.json to version \(lightVersion)"))
        #expect(restore.output.contains("The versions after it are kept."))
        #expect(try config.read("settings.json").contains("\"light\""))
        #expect(run("config", "history").output.split(separator: "\n").count == 4)
    }

    @Test func layoutsListShowAndDuplicate() throws {
        var result = run("layouts", "list")
        #expect(result.output == "decision-first\tDecision first\tbuilt in\tdefault\ntabbed\tTabbed\tbuilt in\n")
        #expect(!config.store.exists)

        result = run("layouts", "show", "tabbed")
        #expect(result.output.contains("Tab \"Files\"\n  Column 1, width 1: files (large), commits (large)\n"))
        result = run("layouts", "show", "tabbed", "--json")
        #expect(try PageLayout.decode(Data(result.output.utf8), fileName: "tabbed.json") == LayoutLibrary.builtIn().layout(id: "tabbed"))
        #expect(run("layouts", "show", "nope").exitCode == 1)

        result = run("layouts", "duplicate", "tabbed", "review", "--name", "Review")
        #expect(result.exitCode == 0, "\(result.errorOutput)")
        #expect(config.exists("layouts/review.json"))
        result = run("layouts", "list")
        #expect(result.output.contains("review\tReview\tlayouts/review.json\n"))
        #expect(run("layouts", "duplicate", "tabbed", "review").exitCode == 1)
        #expect(run("layouts", "duplicate", "tabbed").exitCode == 2)
        let latest = try #require(try config.versions().first)
        #expect(latest.author == "ctl")
        #expect(latest.summary == "Duplicated Tabbed to layouts/review.json")
    }

    @Test(arguments: [["config", "--help"], ["layouts", "--help"], ["config", "set", "--help"]])
    func help(arguments: [String]) {
        let result = ControlCommand.run(arguments)
        #expect(result.exitCode == 0)
        #expect(result.output.contains("--config <folder>"))
    }

    @Test func unknownCommandsAreUsageErrors() {
        #expect(run("config", "frobnicate").exitCode == 2)
        #expect(run("layouts", "frobnicate").exitCode == 2)
        #expect(run("config").exitCode == 2)
        #expect(ControlCommand.run(["config", "path", "--config"]).exitCode == 2)
    }
}
