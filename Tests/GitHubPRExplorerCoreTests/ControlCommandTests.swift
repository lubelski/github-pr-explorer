import Foundation
import Testing
@testable import github_pr_explorer_ctl
@testable import GitHubPRExplorerCore

@Suite struct ControlCommandTests {
    static let workedExampleLine = "acme/api#4826\t✕ Blocked: e2e-chrome failed, 3 threads unresolved. Review requested from you.\tMove session refresh into the auth middleware"

    @Test func listShowsTheWorkedExample() {
        let result = ControlCommand.run(["pull-requests", "list", "--repo", "acme/api", "--state", "open"])
        #expect(result.exitCode == 0)
        #expect(result.errorOutput.isEmpty)
        let lines = result.output.split(separator: "\n").map(String.init)
        #expect(lines.contains(Self.workedExampleLine))
        #expect(lines.allSatisfy { $0.hasPrefix("acme/api#") })
    }

    @Test func listSearch() {
        let result = ControlCommand.run(["pull-requests", "list", "--search", "session refresh auth middleware"])
        #expect(result.output == Self.workedExampleLine + "\n")
    }

    @Test func listCountsByState() {
        func count(_ state: String) -> Int {
            ControlCommand.run(["pull-requests", "list", "--state", state]).output.split(separator: "\n").count
        }
        #expect(count("open") == 218)
        #expect(count("merged") == 60)
        #expect(count("closed") == 20)
        #expect(count("all") == 298)
    }

    @Test func showTheWorkedExample() {
        let result = ControlCommand.run(["pull-request", "show", "acme/api#4826"])
        #expect(result.exitCode == 0)
        let output = result.output
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        #expect(lines[0] == "acme/api#4826  Move session refresh into the auth middleware")
        #expect(lines[1] == "✕ Blocked: e2e-chrome failed, 3 threads unresolved. Review requested from you.")
        for expected in [
            "  Author      Sam Rivera (sam-rivera)",
            "  Branches    session-refresh-middleware → main",
            "  Changes     +212 −87 in 9 files, 12 commits",
            "Checks: 1 failed, 1 running, 12 passed",
            "  ✕ e2e-chrome (required) failed in 6m 12s: 2 tests failed",
            "  ● build-docker (required) running for 4m",
            "Reviews: review required",
            "  @acme/security (you) requested, pending, as code owner",
            "  auth/** → @acme/security: auth/session.ts, auth/middleware.ts, auth/middleware.test.ts",
            "  M auth/middleware.test.ts +71 −4",
            "Commits (12)",
            "Threads (3, 3 unresolved, 0 need you)",
            "  auth/middleware.ts:112 [unresolved]",
            "  api/routes/login.ts:27 (old) [unresolved]",
            "Timeline (31 events: 14 from people, 17 from bots)",
            "Sources",
            "  timeline    push, fetched 10 s ago",
        ] {
            #expect(lines.contains(expected), "missing: \(expected)")
        }
    }

    @Test func showAsJSONDecodesToTheSamePullRequest() throws {
        let result = ControlCommand.run(["pull-request", "show", "acme/api#4826", "--json"])
        #expect(result.exitCode == 0)
        let decoded = try GitHubPRExplorerJSON.decoder().decode(PullRequest.self, from: Data(result.output.utf8))
        #expect(decoded == MockWorld.standard.index.pullRequest(MockWorld.workedExample))
        #expect(result.output.contains("\"createdAt\" : \"2026-11-23T15:12:00Z\""))
    }

    @Test func missingPullRequestIsAnError() {
        let result = ControlCommand.run(["pull-request", "show", "acme/api#1"])
        #expect(result.exitCode == 1)
        #expect(result.output.isEmpty)
        #expect(result.errorOutput == "No pull request acme/api#1 in the index.\n")
    }

    @Test func badReferenceAndUnknownCommandsAreUsageErrors() {
        #expect(ControlCommand.run(["pull-request", "show", "4826"]).exitCode == 2)
        #expect(ControlCommand.run(["pull-requests", "list", "--state", "sideways"]).exitCode == 2)
        #expect(ControlCommand.run(["pull-requests", "list", "--repo", "acme/nope"]).exitCode == 1)
        #expect(ControlCommand.run(["frobnicate"]).exitCode == 2)
        #expect(ControlCommand.run([]).exitCode == 2)
    }

    @Test(arguments: [["--help"], ["pull-requests", "list", "--help"], ["pull-request", "show", "--help"], ["mock-data", "export", "--help"]])
    func helpForEachCommand(arguments: [String]) {
        let result = ControlCommand.run(arguments)
        #expect(result.exitCode == 0)
        #expect(result.output.contains("github-pr-explorer-ctl"))
    }

    @Test func exportWritesOneFilePerPullRequestAndAWorldFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("github-pr-explorer-export-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let result = ControlCommand.run(["mock-data", "export", directory.path])
        #expect(result.exitCode == 0, "\(result.errorOutput)")
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("pull-requests").path)
        #expect(files.count == 298)
        #expect(files.contains("acme-api-4826.json"))
        let worldData = try Data(contentsOf: directory.appendingPathComponent("world.json"))
        let world = try GitHubPRExplorerJSON.decoder().decode(ControlCommand.WorldFile.self, from: worldData)
        #expect(world.pullRequestFiles.count == 298)
        #expect(world.viewer == MockCast.viewer)

        // A second export is byte for byte the same.
        let again = directory.appendingPathComponent("again")
        _ = ControlCommand.run(["mock-data", "export", again.path])
        let first = try Data(contentsOf: directory.appendingPathComponent("pull-requests/acme-api-4826.json"))
        let second = try Data(contentsOf: again.appendingPathComponent("pull-requests/acme-api-4826.json"))
        #expect(first == second)
    }
}
