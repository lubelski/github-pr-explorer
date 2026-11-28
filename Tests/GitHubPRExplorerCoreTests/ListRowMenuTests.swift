import Foundation
import Testing
@testable import github_pr_explorer_ctl
@testable import GitHubPRExplorerCore

/// The right-click menu on every row of the list, the Set Shorthand popover's rules, and
/// organizations as a third kind of shorthand.
@Suite struct ListRowMenuTests {
    let world = MockWorld.standard
    var open: [PullRequest] {
        SavedFilter.everything.evaluate(world.pullRequests, context: FilterContext(viewer: world.viewer, now: world.now)).matches
    }

    func tree(_ grouping: ListGrouping, shorthands: Shorthands = .none) -> ListTree {
        ListTree(grouping: grouping, pullRequests: open, viewer: world.viewer,
                 status: { $0.statusSentence(for: world.viewer, now: world.now) }, shorthands: shorthands)
    }

    func menu(_ row: ListSelection, _ tree: ListTree, closed: Set<String> = [], shorthands: Shorthands = .none) throws -> ListRowMenu {
        try #require(ListRowMenu(for: row, in: tree, closed: closed, shorthands: shorthands))
    }

    // MARK: Which items each kind of row offers

    @Test func anOrganizationRow() throws {
        let tree = tree(ListGrouping(.organization, then: .repository))
        let menu = try menu(.group("organization:acme"), tree)
        #expect(menu.subject == .organization("acme"))
        #expect(menu.sections.map { $0.map(\.title) } == [
            ["Set Shorthand\u{2026}"],
            ["Open on GitHub", "Copy Name"],
            ["Expand Everything Inside", "Collapse Everything Inside"],
        ])
        #expect(menu.items[0].action == .setShorthand(.organization("acme")))
        #expect(menu.items[1].action == .openInBrowser(URL(string: "https://github.com/acme")!))
        #expect(menu.items[2].action == .copy("acme"))
        // Everything is open, so only collapsing would change anything.
        #expect(menu.items.map(\.isEnabled) == [true, true, true, false, true])
        let ids = tree.groupIDs(within: "organization:acme")
        #expect(ids.first == "organization:acme")
        #expect(ids.count == 1 + (tree.group(id: "organization:acme")?.children.count ?? 0))
        #expect(menu.items[4].action == .setOpen(ids, open: false))
        // With one repository inside closed, both apply.
        let closedOne = try self.menu(.group("organization:acme"), tree, closed: [ids[1]])
        #expect(closedOne.items.map(\.isEnabled) == [true, true, true, true, true])
    }

    @Test func aRepositoryRowUnderItsOrganization() throws {
        let tree = tree(ListGrouping(.organization, then: .repository))
        let row = ListSelection.group("organization:acme|repository:acme/api")
        let menu = try menu(row, tree)
        #expect(menu.subject == .repository(Repository(owner: "acme", name: "api")))
        #expect(menu.titles == ["Set Shorthand\u{2026}", "Open on GitHub", "Copy Name", "Collapse"])
        #expect(menu.items[1].action == .openInBrowser(URL(string: "https://github.com/acme/api")!))
        #expect(menu.items[2].action == .copy("acme/api"))
        #expect(menu.items[3].action == .setOpen(["organization:acme|repository:acme/api"], open: false))
        // Closed, it offers Expand instead.
        let closed = try self.menu(row, tree, closed: ["organization:acme|repository:acme/api"])
        #expect(closed.titles.last == "Expand")
    }

    @Test func aRowWithAShorthandOffersToChangeIt() throws {
        let shorthands = Shorthands([Shorthand(kind: .repository, target: "acme/api", shorthand: "API")])
        let menu = try menu(.group("repository:acme/api"), tree(ListGrouping(.repository), shorthands: shorthands),
                            shorthands: shorthands)
        #expect(menu.titles.first == "Change Shorthand\u{2026}")
    }

    @Test func anAuthorRow() throws {
        let menu = try menu(.group("author:ada-park"), tree(ListGrouping(.author)))
        #expect(menu.subject == .author(MockCast.adaPark))
        #expect(menu.titles == ["Set Shorthand\u{2026}", "Open on GitHub", "Copy Username", "Collapse"])
        #expect(menu.items[0].action == .setShorthand(.person(MockCast.adaPark)))
        #expect(menu.items[1].action == .openInBrowser(URL(string: "https://github.com/ada-park")!))
        #expect(menu.items[2].action == .copy("ada-park"))
    }

    @Test func statusAndReviewStateRowsOnlyOpenAndClose() throws {
        let byStatus = tree(ListGrouping(.status))
        let status = try #require(byStatus.groups.first)
        #expect(try menu(.group(status.id), byStatus).titles == ["Collapse"])
        let byReview = tree(ListGrouping(.reviewState, then: .repository))
        let review = try #require(byReview.groups.first)
        let menu = try menu(.group(review.id), byReview)
        #expect(menu.subject == .grouping(.reviewState))
        #expect(menu.titles == ["Expand Everything Inside", "Collapse Everything Inside"])
    }

    @Test func aPullRequestRow() throws {
        let tree = tree(ListGrouping(.organization, then: .repository))
        let pr = try #require(open.first { $0.repository.fullName == "acme/api" && $0.author.login == "ada-park" })
        let menu = try menu(.pullRequest(pr.id), tree)
        #expect(menu.sections.map { $0.map(\.title) } == [
            ["Open on GitHub", "Copy Link", "Copy Reference"],
            ["Set Shorthand for Repository\u{2026}", "Set Shorthand for Author\u{2026}", "Set Shorthand for Organization\u{2026}"],
        ])
        let link = "https://github.com/acme/api/pull/\(pr.number)"
        #expect(menu.items[0].action == .openInBrowser(URL(string: link)!))
        #expect(menu.items[1].action == .copy(link))
        #expect(menu.items[2].action == .copy("acme/api#\(pr.number)"))
        #expect(menu.items[3].action == .setShorthand(.repository(pr.repository)))
        #expect(menu.items[4].action == .setShorthand(.person(MockCast.adaPark)))
        #expect(menu.items[5].action == .setShorthand(.organization("acme")))
        // The same in a flat list.
        #expect(try self.menu(.pullRequest(pr.id), self.tree(.none)).titles == menu.titles)
    }

    @Test func aRowNotInTheTreeHasNoMenu() {
        #expect(ListRowMenu(for: .group("organization:initech"), in: tree(ListGrouping(.organization)), closed: [], shorthands: .none) == nil)
        #expect(ListRowMenu(for: .pullRequest("nope"), in: tree(.none), closed: [], shorthands: .none) == nil)
    }

    @Test func botProfilesLiveUnderApps() {
        #expect(GitHubWebLinks.person(Person(login: "renovate[bot]", displayName: "renovate", isBot: true)).absoluteString
                == "https://github.com/apps/renovate")
        #expect(GitHubWebLinks.person(MockCast.ciBot).absoluteString == "https://github.com/ci-bot")
    }

    // MARK: The Set Shorthand popover

    @Test func thePopoverSuggestsAShorthand() {
        #expect(ShorthandTarget.repository(Repository(owner: "acme", name: "api")).suggestion == "API")
        #expect(ShorthandTarget.repository(Repository(owner: "acme", name: "web-admin")).suggestion == "Web Admin")
        #expect(ShorthandTarget.organization("globex").suggestion == "Globex")
        #expect(ShorthandTarget.person(MockCast.adaPark).suggestion == "Ada")
        #expect(ShorthandTarget.person(MockCast.adaPark).title == "Ada Park (@ada-park)")
        #expect(ShorthandTarget.person(MockCast.ciBot).title == "@ci-bot")
        #expect(ShorthandTarget.person(MockCast.ciBot).suggestion == "Ci Bot")
    }

    @Test func savingSetsChangesOrClears() {
        let api = ShorthandTarget.repository(Repository(owner: "acme", name: "api"))
        let fresh = ShorthandEdit(target: api, shorthands: .none)
        #expect(fresh.current == nil)
        #expect(fresh.initialText == "API")
        #expect(fresh.outcome(of: " API ") == .set("API"))
        #expect(fresh.outcome(of: "  ") == .nothing)

        let set = ShorthandEdit(target: api, shorthands: Shorthands([Shorthand(kind: .repository, target: "ACME/api", shorthand: "Core")]))
        #expect(set.current == "Core")
        #expect(set.initialText == "Core")
        #expect(set.outcome(of: "Core") == .nothing)
        #expect(set.outcome(of: "Service") == .set("Service"))
        #expect(set.outcome(of: "") == .remove)
    }

    @Test func thePopoverWarnsWhenTheShorthandIsTaken() {
        let shorthands = Shorthands([
            Shorthand(kind: .repository, target: "acme/web", shorthand: "Web"),
            Shorthand(kind: .organization, target: "acme", shorthand: "Acme"),
        ])
        let docs = ShorthandEdit(target: .repository(Repository(owner: "acme", name: "docs")), shorthands: shorthands)
        #expect(docs.clashWarning(for: "web ", in: shorthands)
                == "\u{201C}web\u{201D} is also the shorthand for acme/web, so the label does not tell them apart.")
        #expect(docs.clashWarning(for: "Docs", in: shorthands) == nil)
        // Its own shorthand is no clash.
        let web = ShorthandEdit(target: .repository(Repository(owner: "acme", name: "web")), shorthands: shorthands)
        #expect(web.clashWarning(for: "Web", in: shorthands) == nil)
    }

    // MARK: Organizations as a kind of shorthand

    static let withOrganization = Shorthands([
        Shorthand(kind: .organization, target: "globex", shorthand: "Gx"),
        Shorthand(kind: .repository, target: "globex/docs", shorthand: "Handbook"),
    ])

    @Test func anOrganizationsShorthandNamesItsRowAndItsRepositories() throws {
        let shorthands = Self.withOrganization
        #expect(shorthands.name(forOrganization: "globex") == DisplayName(text: "Gx", fullName: "globex", isShortened: true))
        #expect(shorthands.name(forOrganization: "GLOBEX").text == "Gx")
        #expect(shorthands.name(forOrganization: "acme") == DisplayName("acme"))
        // A repository with no shorthand of its own takes the owner's: "Gx/billing".
        let billing = shorthands.reference(MockCast.globexBilling, number: 12)
        #expect(billing.text == "Gx/billing #12")
        #expect(billing.fullName == "globex/billing #12")
        #expect(billing.accessibilityLabel == "Gx/billing #12, short for globex/billing #12")
        // A repository's own shorthand still stands alone.
        #expect(shorthands.name(for: MockCast.globexDocs).text == "Handbook")
        #expect(shorthands.name(for: Repository(owner: "acme", name: "api")) == DisplayName("acme/api"))

        // In the tree: the organization's row, and its repositories under it by their own names.
        let tree = tree(ListGrouping(.organization, then: .repository), shorthands: shorthands)
        let globex = try #require(tree.group(id: "organization:globex"))
        #expect(globex.name.text == "Gx")
        #expect(globex.name.help == "globex")
        #expect(globex.children.map(\.title) == ["billing", "Handbook"])
        #expect(try #require(tree.group(id: "organization:acme")).title == "acme")
        // Grouped by repository alone, a repository names its owner by the shorthand.
        let flat = self.tree(ListGrouping(.repository), shorthands: shorthands)
        #expect(flat.group(id: "repository:globex/billing")?.title == "Gx/billing")
        // Ordered by full name all the same.
        #expect(tree.groups.map(\.id) == ["organization:acme", "organization:globex"])
    }

    @Test func searchFindsByTheOrganizationsShorthand() {
        let found = world.index.search("Gx", shorthands: Self.withOrganization)
        #expect(!found.isEmpty)
        #expect(found.allSatisfy { $0.repository.owner == "globex" })
        #expect(world.index.search("Gx").isEmpty)
    }

    @Test func aFileWrittenBeforeOrganizationsStillLoads() throws {
        let old = """
            {
              "formatVersion" : 1,
              "shorthands" : [
                { "for" : "acme/web", "kind" : "repository", "shorthand" : "Web" },
                { "for" : "ada-park", "kind" : "person", "shorthand" : "Ada" }
              ]
            }
            """
        let file = try ShorthandsFile.decode(Data(old.utf8))
        #expect(file.lookup.shorthand(.repository, for: "acme/web") == "Web")
        #expect(file.lookup.shorthand(.person, for: "ada-park") == "Ada")
        let config = TemporaryConfiguration()
        try config.write(old, to: "shorthands.json")
        config.store.reload()
        #expect(config.store.problems.isEmpty)
        #expect(config.store.snapshot.shorthands.entries.count == 2)
    }

    @Test func anOrganizationInTheFileIsCheckedLikeTheOthers() throws {
        let schema = MiniSchemaValidator(root: try SchemaTests.schema("shorthands.schema.json"))
        let good = #"{"formatVersion": 1, "shorthands": [{"kind": "organization", "for": "globex", "shorthand": "Gx"}]}"#
        #expect(try ShorthandsFile.decode(Data(good.utf8)).lookup.shorthand(.organization, for: "globex") == "Gx")
        #expect(schema.validate(try SchemaTests.json(Data(good.utf8))).isEmpty)
        for bad in ["globex/billing", "-globex", "glo bex"] {
            let text = #"{"formatVersion": 1, "shorthands": [{"kind": "organization", "for": "\#(bad)", "shorthand": "G"}]}"#
            #expect(throws: LayoutFileError.self, "the app accepted \(bad)") { try ShorthandsFile.decode(Data(text.utf8)) }
        }
        // An organization and a repository may share a shorthand, with the usual warning.
        let both = Shorthands([Shorthand(kind: .organization, target: "acme", shorthand: "A"),
                               Shorthand(kind: .repository, target: "acme/api", shorthand: "a")])
        #expect(both.clashes.count == 1)
    }

    @Test func theIndexOffersItsOrganizations() {
        let candidates = ShorthandCandidates(index: world.index)
        #expect(candidates.organizations == ["acme", "globex"])
        let unset = candidates.unset(.organization, in: Self.withOrganization)
        #expect(unset.map(\.identity) == ["acme"])
    }

    @Test func theStoreCtlAndMCPSetOrganizations() throws {
        let config = TemporaryConfiguration()
        let store = config.store
        #expect(try store.setShorthand(.organization, for: "@globex", to: "Gx", author: .mainWindow) == "Set the shorthand for globex to Gx")
        #expect(store.snapshot.shorthands.shorthand(.organization, for: "globex") == "Gx")
        #expect(try store.versions().first?.author == "main window")
        #expect(throws: ConfigurationError.self) { try store.setShorthand(.organization, for: "globex/billing", to: "G", author: .commandLine) }

        func run(_ arguments: String...) -> ControlCommandResult {
            ControlCommand.run(arguments + ["--config", config.folder.path])
        }
        #expect(run("shorthands", "set", "organization", "acme", "Acme").output == "Set the shorthand for acme to Acme.\n")
        #expect(run("shorthands", "list").output.contains("organization\tacme\tAcme\n"))
        #expect(run("shorthands", "remove", "organization", "acme").output == "Removed the shorthand Acme for acme.\n")

        let server = MCPServer(folder: config.folder) { .success(ControlCommand.IndexChoice(world: .standard)) }
        guard case .success(let set)? = server.callShorthandTool("shorthand_set", ["kind": "organization", "for": "acme", "shorthand": "Gx"]) else {
            Issue.record("shorthand_set failed"); return
        }
        #expect(set.hasPrefix("Set the shorthand for acme to Gx."))
        #expect(set.contains("Warning: \u{201C}Gx\u{201D} is also the shorthand for globex"))
        #expect(try store.versions().first?.author == "MCP")
        guard case .success(let list)? = server.callShorthandTool("shorthands_list", [:]) else {
            Issue.record("shorthands_list failed"); return
        }
        #expect(list.contains("\"kind\" : \"organization\""))
        guard case .success(let removed)? = server.callShorthandTool("shorthand_remove", ["kind": "organization", "for": "acme"]) else {
            Issue.record("shorthand_remove failed"); return
        }
        #expect(removed == "Removed the shorthand Gx for acme.")
        guard case .failure? = server.callShorthandTool("shorthand_set", ["kind": "team", "for": "x", "shorthand": "y"]) else {
            Issue.record("a kind that does not exist was accepted"); return
        }
        #expect(server.callShorthandTool("saved_filters_list", [:]) == nil)
    }
}
