import AppKit
import GitHubPRExplorerCore
import SwiftUI

/// `--render-previews <folder> [state ...]`: draws named states of the main window to PNG files
/// and quits, without ever putting a window on screen. No Dock icon, no menu bar, no focus,
/// and no Screen Recording permission, so an agent can run it without asking the owner.
/// `scripts/render-previews.sh` runs it.
///
/// Each state is the real window, built the way the app builds it, with the mock world's index
/// and a model set to that state. Every state is drawn in light and in dark.
@MainActor
enum PreviewRenderer {
    static let argument = "--render-previews"

    struct State {
        let name: String
        var size = CGSize(width: 1560, height: 940)
        var expandsBlocks = false
        let model: () -> AppModel
    }

    static func run(arguments: [String]) -> Int32 {
        guard let index = arguments.firstIndex(of: argument) else { return 2 }
        if arguments.contains("--list") {
            for state in states() { print(state.name) }
            return 0
        }
        guard index + 1 < arguments.count else {
            FileHandle.standardError.write(Data("\(argument) needs an output folder.\n".utf8))
            return 2
        }
        let folder = URL(filePath: (arguments[index + 1] as NSString).expandingTildeInPath, directoryHint: .isDirectory)
        var appearances: [(String, NSAppearance.Name)] = [("light", .aqua), ("dark", .darkAqua)]
        if let flag = arguments.firstIndex(of: "--appearances"), flag + 1 < arguments.count {
            let wanted = arguments[flag + 1].split(separator: ",").map(String.init)
            appearances = appearances.filter { wanted.contains($0.0) }
        }
        let named = Set(arguments.dropFirst(index + 2).filter { !$0.hasPrefix("--") && !$0.contains(",") && $0 != "light" && $0 != "dark" })
        let chosen = states().filter { named.isEmpty || named.contains($0.name) }
        let unknown = named.subtracting(chosen.map(\.name))
        if !unknown.isEmpty {
            FileHandle.standardError.write(Data("Unknown states: \(unknown.sorted().joined(separator: ", ")). --list lists them.\n".utf8))
            return 2
        }

        NSApplication.shared.setActivationPolicy(.prohibited)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            FileHandle.standardError.write(Data("Could not create \(folder.path): \(error.localizedDescription)\n".utf8))
            return 1
        }
        var failed = false
        for state in chosen {
            for (look, appearance) in appearances {
                let url = folder.appending(path: "\(state.name)-\(look).png")
                let started = Date()
                guard let image = draw(MainWindowView(model: state.model()).environment(\.previewExpandsBlocks, state.expandsBlocks),
                                        size: state.size, appearance: appearance),
                      let png = image.representation(using: .png, properties: [:])
                else {
                    FileHandle.standardError.write(Data("Could not render \(state.name) in \(look)\n".utf8))
                    failed = true
                    continue
                }
                do {
                    try png.write(to: url)
                    print("rendered \(url.path) in \(Int(Date().timeIntervalSince(started) * 1000)) ms")
                } catch {
                    FileHandle.standardError.write(Data("Could not write \(url.path): \(error.localizedDescription)\n".utf8))
                    failed = true
                }
            }
        }
        return failed ? 1 : 0
    }

    /// Draws a view in a titled window that is never ordered in, title bar included.
    private static func draw(_ view: some View, size: CGSize, appearance: NSAppearance.Name) -> NSBitmapImageRep? {
        let root = view
            .environment(\.isRenderingPreview, true)
            .frame(width: size.width, height: size.height)
        let hosting = NSHostingView(rootView: root)
        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -20000, y: -20000), size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        // Give SwiftUI a moment to lay out, apply the title bar, and fill the lazy stacks.
        for _ in 0..<6 {
            hosting.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.08))
        }
        // The frame view holds the title bar and the content, so the image is the whole window.
        guard let frame = hosting.superview else { return nil }
        frame.layoutSubtreeIfNeeded()
        frame.displayIfNeeded()
        let bounds = frame.bounds
        guard bounds.width > 0, let rep = frame.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        frame.cacheDisplay(in: bounds, to: rep)
        window.contentView = nil
        return rep
    }

    // MARK: States

    static func states() -> [State] {
        let world = MockWorld.standard
        let index = world.index
        let open = world.pullRequests.filter { $0.state == .open }
        func model(_ reference: PullRequestReference?, layout: String = LayoutLibrary.fallbackID, tab: Int = 0,
                   library: LayoutLibrary = .builtIn(), index: any PullRequestIndex = index) -> AppModel {
            let model = AppModel(index: index, now: world.now, library: library, selection: reference)
            model.layoutID = layout
            model.selectedTab = tab
            return model
        }
        func first(_ test: (PullRequest) -> Bool) -> PullRequestReference? {
            (open.first(where: test) ?? world.pullRequests.first(where: test))?.reference
        }
        let example = MockWorld.workedExample

        var states: [State] = [
            State(name: "page-4826-decision-first") { model(example) },
            State(name: "page-4826-tabbed-overview") { model(example, layout: "tabbed", tab: 0) },
            State(name: "page-4826-tabbed-files") { model(example, layout: "tabbed", tab: 1) },
            State(name: "page-4826-tabbed-checks") { model(example, layout: "tabbed", tab: 2) },
            State(name: "page-4826-tabbed-threads") { model(example, layout: "tabbed", tab: 3) },
            State(name: "page-120-files") { model(first { $0.files.count >= 100 }) },
            State(name: "page-120-files-tabbed-files") { model(first { $0.files.count >= 100 }, layout: "tabbed", tab: 1) },
            State(name: "page-120-files-expanded", expandsBlocks: true) {
                model(first { $0.files.count >= 100 }, layout: "tabbed", tab: 1)
            },
            State(name: "page-empty-body") { model(first { $0.body.isEmpty }) },
            State(name: "page-40-checks") { model(first { $0.checks.count == 40 }) },
            State(name: "page-40-checks-tabbed-checks", expandsBlocks: true) {
                model(first { $0.checks.count == 40 }, layout: "tabbed", tab: 2)
            },
            State(name: "page-draft") { model(PullRequestReference(parsing: "acme/api#4774")) },
            State(name: "page-merge-queue") { model(first { $0.mergeState.mergeQueuePosition != nil }) },
            State(name: "page-long-title") { model(first { $0.title.count >= 150 }) },
            State(name: "page-long-timeline") { model(first { $0.timeline.count >= 250 }) },
            State(name: "page-long-timeline-expanded", expandsBlocks: true) {
                model(first { $0.timeline.count >= 250 }, layout: "tabbed", tab: 0)
            },
            State(name: "page-rich-body") { model(first { $0.body.contains("<details>") }) },
            State(name: "page-no-checks-no-reviewers") {
                model(first { $0.checks.isEmpty && $0.reviewRequests.isEmpty && $0.reviews.isEmpty })
            },
            State(name: "list-search") {
                let model = model(example)
                model.searchText = "session refresh"
                return model
            },
            State(name: "list-hidden") {
                let model = model(example)
                model.showsList = false
                return model
            },
            State(name: "layout-file-error") {
                // A layout file with a block kind the app does not know. The app reports it and
                // falls back to Decision first.
                let bad = Data(#"{"formatVersion": 1, "id": "decision-first", "name": "Decision first", "tabs": [{"name": "Main", "columns": [{"width": 1, "blocks": [{"kind": "summary", "size": "large"}]}]}]}"#.utf8)
                let library = LayoutLibrary(files: [("decision-first.json", bad), LayoutLibrary.builtInFiles()[1]])
                for problem in library.problems { print("layout-file-error: \(problem)") }
                return model(example, library: library)
            },
        ]

        // The diff pane over the page (MAC-53, Figma row 8).
        func diff(_ reference: PullRequestReference?, file: String, mode: DiffMode = .inline, thread: String? = nil,
                  layout: String = LayoutLibrary.fallbackID, tab: Int = 0) -> AppModel {
            let model = model(reference, layout: layout, tab: tab)
            model.diffMode = mode
            if let pr = model.selectedPullRequest {
                if let thread, let path = pr.paneStack(showingThread: thread) {
                    model.panePath = path
                } else {
                    model.openFile(file)
                }
                model.buildDocumentNow(for: pr, path: file)
            }
            return model
        }
        let examplePR = index.pullRequest(example)!
        let middlewareThread = examplePR.reviewThreads.first { $0.path == "auth/middleware.ts" }!.id
        let large = first { $0.files.count >= 100 }
        let largeFile = large.flatMap(index.pullRequest)?.files.max { ($0.patch?.count ?? 0) < ($1.patch?.count ?? 0) }?.path ?? ""
        let mail = first { $0.title == "Move the email templates into their own folder" }
        states += [
            State(name: "diff-4826-inline") { diff(example, file: "auth/middleware.ts") },
            State(name: "diff-4826-side-by-side") { diff(example, file: "auth/middleware.ts", mode: .sideBySide) },
            State(name: "diff-4826-thread") { diff(example, file: "auth/middleware.ts", thread: middlewareThread) },
            State(name: "diff-4826-tabbed") { diff(example, file: "auth/session.ts", layout: "tabbed", tab: 1) },
            State(name: "diff-4826-narrow", size: CGSize(width: 1240, height: 860)) { diff(example, file: "auth/middleware.ts") },
            State(name: "diff-5000-lines") { diff(large, file: largeFile) },
            State(name: "diff-5000-lines-side-by-side") { diff(large, file: largeFile, mode: .sideBySide) },
            State(name: "diff-renamed") { diff(mail, file: "mail/templates/password-reset.ts") },
            State(name: "diff-renamed-without-changes") { diff(mail, file: "mail/templates/welcome.ts") },
            State(name: "diff-binary") { diff(mail, file: "mail/assets/logo.png") },
            State(name: "diff-deleted") { diff(mail, file: "lib/mail/legacy-sender.ts") },
            State(name: "diff-added-side-by-side") { diff(mail, file: "mail/index.ts", mode: .sideBySide) },
        ]

        // Every block, small on the left and large on the right, through the same decoding a
        // layout file uses.
        let catalogue = PageLayout(id: "catalogue", name: "Block catalogue (preview only)", tabs: [
            LayoutTab(name: "Catalogue", columns: [
                LayoutColumn(width: 1, blocks: BlockKind.allCases.map { BlockPlacement($0, .small) }),
                LayoutColumn(width: 2, blocks: BlockKind.allCases.map { BlockPlacement($0, .large) }),
            ]),
        ])
        let catalogueFiles = LayoutLibrary.builtInFiles() + [("catalogue.json", (try? catalogue.encoded()) ?? Data())]
        let catalogueLibrary = LayoutLibrary(files: catalogueFiles)
        states.append(State(name: "catalogue-4826", size: CGSize(width: 1560, height: 2300)) {
            model(example, layout: "catalogue", library: catalogueLibrary)
        })

        // The same, for a pull request with nothing in any block, made up here for the preview
        // and marked as mock data, to show every empty state.
        states.append(State(name: "catalogue-empty", size: CGSize(width: 1560, height: 1500)) {
            let empty = emptyPullRequest(like: index.pullRequest(example)!, now: world.now)
            let emptyIndex = InMemoryPullRequestIndex(pullRequests: [empty] + world.pullRequests, viewer: world.viewer)
            return model(empty.reference, layout: "catalogue", library: catalogueLibrary, index: emptyIndex)
        })
        return states
    }

    /// A pull request with an empty body, no checks, reviewers, files, threads, commits or
    /// events. Its provenance says `mock`: it is made up for this preview, never from GitHub.
    private static func emptyPullRequest(like pr: PullRequest, now: Date) -> PullRequest {
        var empty = pr
        empty.id = "PR_preview_empty"
        empty.number = 1
        empty.title = "A pull request with nothing in it yet"
        empty.body = ""
        empty.labels = []
        empty.milestone = nil
        empty.linkedIssues = []
        empty.assignees = []
        empty.reviewRequests = []
        empty.reviews = []
        empty.reviewDecision = nil
        empty.codeOwners = []
        empty.checks = []
        empty.files = []
        empty.commits = []
        empty.additions = 0
        empty.deletions = 0
        empty.reviewThreads = []
        empty.comments = []
        empty.timeline = []
        empty.mergeState = MergeState()
        empty.provenance = .uniform(.mock, fetchedAt: now)
        return empty
    }
}
