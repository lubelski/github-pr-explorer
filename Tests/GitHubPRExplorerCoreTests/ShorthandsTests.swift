import Foundation
import Testing
@testable import github_pr_explorer_ctl
@testable import GitHubPRExplorerCore

/// Shorthands (MAC-73): the file, the labels, the search, clashes, the store, and `ctl`.
@Suite struct ShorthandsTests {
    static let sample = Shorthands([
        Shorthand(kind: .repository, target: "acme/web", shorthand: "Web"),
        Shorthand(kind: .person, target: "ada-park", shorthand: "Ada"),
        Shorthand(kind: .person, target: "ci-bot", shorthand: "CI"),
    ])

    // MARK: Labels

    @Test func withNoShorthandsEveryLabelIsAsBefore() {
        let none = Shorthands.none
        let web = Repository(owner: "acme", name: "web")
        #expect(none.name(for: web) == DisplayName("acme/web"))
        #expect(none.reference(web, number: 95).text == "acme/web #95")
        #expect(!none.reference(web, number: 95).isShortened)
        #expect(none.name(for: MockCast.adaPark).text == "Ada Park")
        #expect(none.name(forHandle: "@ada-park").text == "@ada-park")
        #expect(none.name(for: MockCast.adaPark).help == nil)
    }

    @Test func aRepositoryShowsItsShorthandAlone() {
        let web = Repository(owner: "acme", name: "web")
        let reference = Self.sample.reference(web, number: 95)
        #expect(reference.text == "Web #95")
        #expect(reference.fullName == "acme/web #95")
        #expect(reference.help == "acme/web #95")
        #expect(reference.accessibilityLabel == "Web #95, short for acme/web #95")
        // Matching ignores case, as GitHub does, and is otherwise exact.
        #expect(Self.sample.name(for: Repository(owner: "ACME", name: "Web")).text == "Web")
        #expect(Self.sample.name(for: Repository(owner: "acme", name: "web-admin")).text == "acme/web-admin")
        #expect(Self.sample.name(for: Repository(owner: "other", name: "web")).text == "other/web")
    }

    @Test func aPersonShowsTheirShorthandWithTheFullNameOnHover() {
        let ada = Self.sample.name(for: MockCast.adaPark)
        #expect(ada.text == "Ada")
        #expect(ada.help == "Ada Park, @ada-park")
        #expect(Self.sample.name(for: MockCast.samRivera).text == "Sam Rivera")
        #expect(Self.sample.name(for: MockCast.ciBot).help == "@ci-bot")
        #expect(Self.sample.name(forHandle: "@ada-park").text == "Ada")
        #expect(Self.sample.name(forHandle: "@acme/security").text == "@acme/security")
        #expect(Self.sample.name(for: RequestedReviewer.person(MockCast.adaPark)).text == "Ada")
        #expect(Self.sample.name(forLogin: "ci-bot").text == "CI")
    }

    @Test func anActivityLineKeepsItsWordsAndShortensOnlyTheActor() {
        let event = TimelineEvent(id: "e", kind: .reviewed, actor: MockCast.adaPark, occurredAt: MockWorld.now,
                                  summary: "Ada Park approved these changes")
        let line = Self.sample.activityLine(event)
        #expect(line.actor?.text == "Ada")
        #expect(line.rest == " approved these changes")
        let before = Shorthands.none.activityLine(event)
        #expect(before.actor?.text == "Ada Park")
        #expect(before.rest == " approved these changes")
    }

    @Test func reviewerRowsAndThreadMarkersTakeShorthands() throws {
        let pr = try #require(MockWorld.standard.index.pullRequest(MockWorld.workedExample))
        let rows = ReviewerRow.rows(for: pr, viewer: MockWorld.standard.viewer, shorthands: Self.sample)
        let ada = try #require(rows.first { $0.id == "@ada-park" })
        #expect(ada.label.text == "Ada")
        #expect(ada.name == "Ada Park")
        let plain = ReviewerRow.rows(for: pr, viewer: MockWorld.standard.viewer)
        #expect(plain.map(\.label.text) == plain.map(\.name))

        let marker = DiffThreadMarker(threadIDs: ["t"], firstCommenter: "Ada Park", startedBy: MockCast.adaPark)
        #expect(marker.label == "1 thread · Ada Park")
        #expect(marker.label(using: Self.sample) == "1 thread · Ada")
    }

    // MARK: Search

    @Test func searchFindsByTheFullNameAndByTheShorthand() {
        let index = MockWorld.standard.index
        let shorthands = Shorthands([Shorthand(kind: .repository, target: "acme/infra", shorthand: "Platform"),
                                     Shorthand(kind: .person, target: "sam-rivera", shorthand: "Zed")])
        let byShorthand = index.search("Platform", shorthands: shorthands)
        #expect(!byShorthand.isEmpty)
        #expect(byShorthand.allSatisfy { $0.repository.fullName == "acme/infra" || $0.title.localizedCaseInsensitiveContains("platform") })
        #expect(index.search("acme/infra", shorthands: shorthands).count == index.search("acme/infra").count)
        #expect(index.search("Zed", shorthands: shorthands).allSatisfy { $0.author.login == "sam-rivera" })
        #expect(!index.search("Zed", shorthands: shorthands).isEmpty)
        #expect(index.search("Zed").isEmpty, "without shorthands the search is as before")
    }

    // MARK: Clashes

    @Test func twoThingsSharingAShorthandAreAWarningNotAnError() throws {
        let shorthands = Shorthands([
            Shorthand(kind: .repository, target: "acme/web", shorthand: "Web"),
            Shorthand(kind: .repository, target: "acme/docs", shorthand: "web "),
            Shorthand(kind: .person, target: "ada-park", shorthand: "Ada"),
        ])
        #expect(shorthands.clashes.count == 1)
        let clash = try #require(shorthands.clashes.first)
        #expect(clash.entries.map(\.target) == ["acme/web", "acme/docs"])
        #expect(clash.warning(for: clash.entries[0]) == "\u{201C}Web\u{201D} is also the shorthand for acme/docs, so the label does not tell them apart.")
        #expect(shorthands.clash(for: shorthands.entries[2]) == nil)
    }

    // MARK: The file

    static let badFiles = [
        #"{"shorthands": []}"#,
        #"{"formatVersion": 2, "shorthands": []}"#,
        #"{"formatVersion": 1}"#,
        #"{"formatVersion": 1, "shorthands": [{"kind": "label", "for": "bug", "shorthand": "B"}]}"#,
        #"{"formatVersion": 1, "shorthands": [{"kind": "repository", "for": "acme/api/extra", "shorthand": "A"}]}"#,
        #"{"formatVersion": 1, "shorthands": [{"kind": "person", "for": "@ada park", "shorthand": "A"}]}"#,
        #"{"formatVersion": 1, "shorthands": [{"kind": "person", "for": "ada-park", "shorthand": ""}]}"#,
        #"{"formatVersion": 1, "shorthands": [{"kind": "person", "for": "ada-park", "shorthand": "  "}]}"#,
        #"{"formatVersion": 1, "shorthands": [{"kind": "person", "for": "ada-park"}]}"#,
        #"{"formatVersion": 1, "shorthands": [{"kind": "person", "for": "ada-park", "shorthand": "A", "colour": "red"}]}"#,
    ]

    @Test func filesTheAppRefusesTheSchemaRefuses() throws {
        let schema = MiniSchemaValidator(root: try SchemaTests.schema("shorthands.schema.json"))
        for text in Self.badFiles {
            #expect(throws: LayoutFileError.self, "the app accepted \(text)") { try ShorthandsFile.decode(Data(text.utf8)) }
            #expect(!schema.validate(try SchemaTests.json(Data(text.utf8))).isEmpty, "the schema accepted \(text)")
        }
        let good = ShorthandsFile(shorthands: Self.sample.entries)
        #expect(schema.validate(try SchemaTests.json(good.encoded())).isEmpty)
        #expect(try ShorthandsFile.decode(good.encoded()) == good)
        // Two shorthands for one thing: the app refuses it. The schema cannot say so.
        let twice = #"{"formatVersion": 1, "shorthands": [{"kind": "person", "for": "ada-park", "shorthand": "A"}, {"kind": "person", "for": "Ada-Park", "shorthand": "B"}]}"#
        #expect(throws: LayoutFileError.self) { try ShorthandsFile.decode(Data(twice.utf8)) }
        // A login where a repository belongs: the app refuses it. The schema's one pattern
        // takes either form.
        let login = #"{"formatVersion": 1, "shorthands": [{"kind": "repository", "for": "acme", "shorthand": "A"}]}"#
        #expect(throws: LayoutFileError.self) { try ShorthandsFile.decode(Data(login.utf8)) }
    }

    @Test func schemaNamesMatchTheType() throws {
        let schema = try SchemaTests.schema("shorthands.schema.json")
        let properties = try #require(schema["properties"] as? [String: [String: Any]])
        #expect(Set(properties.keys) == Set(ShorthandsFile.keys + ["$schema"]))
        let entry = try #require((schema["$defs"] as? [String: [String: Any]])?["shorthand"]?["properties"] as? [String: [String: Any]])
        #expect(Set(entry.keys) == Set(ShorthandsFile.entryKeys))
        #expect(entry["kind"]?["enum"] as? [String] == ShorthandKind.allCases.map(\.rawValue))
        guard case .object(let top) = JSONKeyCheck.shorthandsShape, case .array(.object(let item)) = top["shorthands"] else {
            Issue.record("unexpected shape"); return
        }
        #expect(Set(top.keys) == Set(ShorthandsFile.keys))
        #expect(Set(item.keys) == Set(ShorthandsFile.entryKeys))
        for (name, property) in properties.merging(entry, uniquingKeysWith: { a, _ in a }) {
            #expect((property["description"] as? String)?.isEmpty == false, "\(name) has no description")
        }
    }

    // MARK: The store

    @Test func theStoreSetsReplacesAndRemovesAndKeepsHistory() throws {
        let config = TemporaryConfiguration()
        let store = config.store
        try store.prepare(author: .app)
        #expect(store.snapshot.shorthands.isEmpty, "empty by default")
        #expect(!FileManager.default.fileExists(atPath: store.shorthandsURL.path), "no file until one is set")

        #expect(try store.setShorthand(.repository, for: "acme/web", to: " Web ", author: .settingsWindow) == "Set the shorthand for acme/web to Web")
        try store.setShorthand(.person, for: "@ada-park", to: "Ada", author: .commandLine)
        try store.setShorthand(.repository, for: "ACME/web", to: "Site", author: .settingsWindow)
        #expect(store.snapshot.shorthands.entries.map(\.shorthand) == ["Site", "Ada"])
        #expect(store.snapshot.shorthands.shorthand(.person, for: "ada-park") == "Ada")

        #expect(throws: ConfigurationError.self) { try store.setShorthand(.repository, for: "acme", to: "A", author: .commandLine) }
        #expect(throws: ConfigurationError.self) { try store.setShorthand(.person, for: "ada-park", to: " ", author: .commandLine) }
        #expect(throws: ConfigurationError.self) { try store.removeShorthand(.person, for: "sam-rivera", author: .commandLine) }

        try store.removeShorthand(.person, for: "ada-park", author: .settingsWindow)
        #expect(store.snapshot.shorthands.entries.map(\.target) == ["acme/web"])
        let summaries = try store.versions().map(\.summary)
        #expect(summaries.prefix(4) == ["Removed the shorthand Ada for ada-park", "Set the shorthand for acme/web to Site",
                                        "Set the shorthand for ada-park to Ada", "Set the shorthand for acme/web to Web"])
    }

    @Test func aBrokenFileKeepsTheLastGoodOneAndIsNotOverwritten() throws {
        let config = TemporaryConfiguration()
        let store = config.store
        try store.setShorthand(.repository, for: "acme/web", to: "Web", author: .settingsWindow)
        try config.write(#"{"formatVersion": 1, "shorthands": [{"kind": "repo", "for": "acme/web", "shorthand": "W"}]}"#, to: "shorthands.json")
        store.reload(committingAs: .editedOnDisk)
        let problem = try #require(store.problems.first { $0.file == "shorthands.json" })
        #expect(problem.lastGoodInUse)
        #expect(store.snapshot.shorthands.shorthand(.repository, for: "acme/web") == "Web")
        #expect(throws: ConfigurationError.self) { try store.setShorthand(.person, for: "ada-park", to: "Ada", author: .settingsWindow) }
    }

    // MARK: ctl

    @Test func ctlListsSetsAndRemoves() throws {
        let config = TemporaryConfiguration()
        func run(_ arguments: String...) -> ControlCommandResult {
            ControlCommand.run(arguments + ["--config", config.folder.path])
        }
        #expect(run("shorthands", "list").output == "No shorthands. Full names are shown everywhere.\n")
        #expect(run("shorthands", "set", "repository", "acme/web", "Web").output == "Set the shorthand for acme/web to Web.\n")
        var result = run("shorthands", "set", "repository", "acme/docs", "Web")
        #expect(result.output.contains("warning\t\u{201C}Web\u{201D} is also the shorthand for acme/web"))
        #expect(run("shorthands", "set", "person", "sam-rivera", "Sam").exitCode == 0)
        result = run("shorthands", "list")
        #expect(result.output == """
            repository\tacme/web\tWeb
            repository\tacme/docs\tWeb
            person\tsam-rivera\tSam
            warning\t\u{201C}Web\u{201D} is the shorthand for acme/web and acme/docs, so the label does not tell them apart.

            """)
        result = run("shorthands", "list", "--json")
        #expect(result.output.contains("\"for\" : \"sam-rivera\""))
        // A clash is a warning: validate still passes.
        result = run("config", "validate")
        #expect(result.exitCode == 0)
        #expect(result.output.contains("ok\tshorthands.json\n"))
        #expect(run("config", "show").output.contains("Shorthands (shorthands.json)\n  repository\tacme/web\tWeb\n"))
        // The search finds by the shorthand. The output keeps full names.
        result = run("pull-requests", "list", "--search", "Sam", "--source", "mock")
        #expect(!result.output.isEmpty)
        // Sam's pull requests are in both placeholder organizations, acme and globex.
        let fullNames = MockCast.allRepositories.map(\.fullName)
        #expect(result.output.split(separator: "\n").allSatisfy { line in fullNames.contains { line.hasPrefix($0 + "#") } })

        #expect(run("shorthands", "remove", "person", "@sam-rivera").output == "Removed the shorthand Sam for sam-rivera.\n")
        #expect(run("shorthands", "remove", "person", "sam-rivera").exitCode == 1)
        #expect(run("shorthands", "set", "team", "x", "y").exitCode == 2)
        #expect(run("shorthands").exitCode == 2)
    }
}
