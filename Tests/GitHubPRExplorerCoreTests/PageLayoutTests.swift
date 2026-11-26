import Foundation
import Testing
@testable import GitHubPRExplorerCore

@Suite struct PageLayoutTests {
    func data(_ text: String) -> Data { Data(text.utf8) }

    @Test func roundTripsThroughJSON() throws {
        let layout = PageLayout(id: "mine", name: "Mine", tabs: [
            LayoutTab(name: "One", columns: [
                LayoutColumn(width: 2, blocks: [BlockPlacement(.description, .small), BlockPlacement(.files)]),
                LayoutColumn(width: 1, blocks: [BlockPlacement(.labelsAndMetadata)]),
            ]),
            LayoutTab(name: "Two", columns: []),
        ])
        let encoded = try layout.encoded()
        let decoded = try PageLayout.decode(encoded, fileName: "mine.json")
        #expect(decoded == layout)
        #expect(try decoded.encoded() == encoded)
    }

    @Test func encodingSortsKeys() throws {
        let text = String(decoding: try PageLayout.decisionFirst.encoded(), as: UTF8.self)
        let formatVersion = try #require(text.range(of: "\"formatVersion\""))
        let id = try #require(text.range(of: "\"id\""))
        let name = try #require(text.range(of: "\"name\" : \"Decision first\""))
        let tabs = try #require(text.range(of: "\"tabs\""))
        #expect(formatVersion.lowerBound < id.lowerBound && id.lowerBound < name.lowerBound && name.lowerBound < tabs.lowerBound)
    }

    @Test func bothBuiltInFilesLoad() throws {
        let library = LayoutLibrary.builtIn()
        #expect(library.problems.isEmpty, "\(library.problems)")
        #expect(library.layouts.map(\.id) == ["decision-first", "tabbed"])
        #expect(library.layouts.map(\.name) == ["Decision first", "Tabbed"])
    }

    @Test func decisionFirstFileMatchesTheCompiledFallback() throws {
        let file = try #require(LayoutLibrary.builtInFiles().first { $0.name == "decision-first.json" })
        #expect(try PageLayout.decode(file.data, fileName: file.name) == .decisionFirst)
        // The file is written the way the app writes layouts, so saving it changes nothing.
        #expect(try PageLayout.decisionFirst.encoded() == file.data.trimmingTrailingNewline)
    }

    @Test func decisionFirstIsTwoColumnsInFigmaOrder() {
        let layout = PageLayout.decisionFirst
        #expect(layout.tabs.count == 1)
        let columns = layout.tabs[0].columns
        #expect(columns.map { $0.blocks.map(\.kind) } == [
            [.description, .threads, .files],
            [.checks, .reviewers, .ownersTouched, .activity],
        ])
        #expect(columns[0].width > columns[1].width)
    }

    @Test func tabbedHasFourTabs() {
        let tabbed = LayoutLibrary.builtIn().layout(id: "tabbed")
        #expect(tabbed.tabs.map(\.name) == ["Overview", "Files", "Checks", "Threads"])
        #expect(tabbed.tabs.map { $0.placements.map(\.kind) } == [
            [.description, .reviewers, .ownersTouched, .activity],
            [.files, .commits],
            [.checks],
            [.threads],
        ])
    }

    @Test func unknownBlockKindFailsWithFileAndPlace() {
        let text = """
            {"formatVersion": 1, "id": "x", "name": "X", "tabs": [
              {"name": "Main", "columns": [{"width": 1, "blocks": [
                {"kind": "description", "size": "large"},
                {"kind": "summary", "size": "small"}
              ]}]}
            ]}
            """
        #expect {
            try PageLayout.decode(data(text), fileName: "team.json")
        } throws: { error in
            let message = String(describing: error)
            return message.contains("team.json")
                && message.contains("tabs[0].columns[0].blocks[1].kind")
                && message.contains("unknown block kind \"summary\"")
                && message.contains("ownersTouched")
        }
    }

    @Test func missingKeyAndBadJSONAreNamed() {
        #expect {
            try PageLayout.decode(data(#"{"formatVersion": 1, "id": "x", "tabs": []}"#), fileName: "a.json")
        } throws: { String(describing: $0) == "a.json, at name: \"name\" is missing" }
        #expect {
            try PageLayout.decode(data("{ not json"), fileName: "b.json")
        } throws: { String(describing: $0).hasPrefix("b.json: this is not valid JSON") }
    }

    @Test func validationRefusesZeroWidthNoTabsAndOtherVersions() {
        func decode(_ layout: PageLayout) throws -> PageLayout {
            try PageLayout.decode(try layout.encoded(), fileName: "c.json")
        }
        #expect { try decode(PageLayout(id: "x", name: "X", tabs: [])) } throws: {
            String(describing: $0).contains("at least one tab")
        }
        #expect { try decode(PageLayout(id: "x", name: "X", tabs: [LayoutTab(name: "T", columns: [LayoutColumn(width: 0, blocks: [])])])) } throws: {
            String(describing: $0).contains("tabs[0].columns[0].width")
        }
        #expect { try decode(PageLayout(formatVersion: 2, id: "x", name: "X", tabs: [LayoutTab(name: "T", columns: [])])) } throws: {
            String(describing: $0).contains("format version 2")
        }
    }

    @Test func emptyTabIsAllowed() throws {
        let layout = PageLayout(id: "x", name: "X", tabs: [
            LayoutTab(name: "Nothing yet", columns: []),
            LayoutTab(name: "Empty column", columns: [LayoutColumn(width: 1, blocks: [])]),
        ])
        #expect(try PageLayout.decode(try layout.encoded(), fileName: "x.json") == layout)
    }

    @Test func badFileFallsBackToDecisionFirst() {
        let library = LayoutLibrary(files: [
            ("decision-first.json", data("{")),
            ("tabbed.json", LayoutLibrary.builtInFiles()[1].data),
        ])
        #expect(library.problems.count == 1)
        #expect(library.problems.first?.fileName == "decision-first.json")
        #expect(library.layouts.map(\.id) == ["decision-first", "tabbed"])
        #expect(library.layout(id: "decision-first") == .decisionFirst)
        #expect(library.layout(id: "no-such-layout") == .decisionFirst)
        #expect(library.layout(id: nil) == .decisionFirst)
    }

    @Test func duplicateIDIsReported() throws {
        let file = try PageLayout.decisionFirst.encoded()
        let library = LayoutLibrary(files: [("one.json", file), ("two.json", file)])
        #expect(library.layouts.count == 1)
        #expect(library.problems.map(\.fileName) == ["two.json"])
    }
}

extension Data {
    fileprivate var trimmingTrailingNewline: Data {
        last == UInt8(ascii: "\n") ? dropLast() : self
    }
}
