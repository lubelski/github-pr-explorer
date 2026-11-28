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
        /// A selection drawn in the Description, to show it crossing blocks.
        var markdownSelection = MarkdownPreviewSelection.none
        /// An update the title bar shows as waiting. Renders have no feed, so by default none.
        var pendingUpdate: AppUpdates.Pending?
        let model: () -> AppModel
    }

    static func run(arguments: [String]) -> Int32 {
        guard let index = arguments.firstIndex(of: argument) else { return 2 }
        if arguments.contains("--list") {
            for state in drawables() { print(state.name) }
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
        let chosen = drawables().filter { named.isEmpty || named.contains($0.name) }
        // The Settings states fill temporary configuration folders, removed when done.
        defer { SettingsPreviews.removeFolders() }
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
                guard let image = draw(state.view(), size: state.size, appearance: appearance),
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

    private static func updater(for state: State) -> AppUpdater {
        state.pendingUpdate.map { AppUpdater.preview(pending: $0) } ?? .unavailable()
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

    /// Every state the renderer can draw: the main window's, then the Settings window's.
    static func drawables() -> [SettingsPreviews.State] {
        let world = MockWorld.standard
        let window = states().map { state in
            SettingsPreviews.State(name: state.name, size: state.size) {
                AnyView(MainWindowView(model: state.model(), updater: updater(for: state))
                    .environment(\.previewExpandsBlocks, state.expandsBlocks)
                    .environment(\.previewMarkdownSelection, state.markdownSelection))
            }
        }
        let configured = SettingsPreviews.mainWindowStates { snapshot in
            AppModel(index: world.index, now: world.now, library: snapshot.library, selection: MockWorld.workedExample, build: .preview)
        }
        return window + configured + SettingsPreviews.states()
    }

    // MARK: States

    static func states() -> [State] {
        let world = MockWorld.standard
        let index = world.index
        let open = world.pullRequests.filter { $0.state == .open }
        func model(_ reference: PullRequestReference?, layout: String = LayoutLibrary.fallbackID, tab: Int = 0,
                   library: LayoutLibrary = .builtIn(), index: any PullRequestIndex = index) -> AppModel {
            let model = AppModel(index: index, now: world.now, library: library, selection: reference, build: .preview)
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
            // A selection from a paragraph, across the table, the lists and the code, into a
            // numbered list, and Select All. Each prints what Copy gives (MAC-72).
            State(name: "page-rich-body-selection-spanning", markdownSelection: .spanning) {
                model(first { $0.body.contains("<details>") })
            },
            State(name: "page-rich-body-select-all", markdownSelection: .all) { model(first { $0.body.contains("<details>") }) },
            State(name: "page-no-checks-no-reviewers") {
                model(first { $0.checks.isEmpty && $0.reviewRequests.isEmpty && $0.reviews.isEmpty })
            },
            State(name: "list-search") {
                let model = model(example)
                model.searchText = "session refresh"
                return model
            },
            State(name: "list-view-mine") {
                let model = model(first { $0.state == .open && world.viewer.isViewer($0.author) })
                model.listView = .mine
                return model
            },
            State(name: "list-view-everything-open") {
                let model = model(example)
                model.listView = .everythingOpen
                return model
            },
            State(name: "list-view-empty-search") {
                let model = model(example)
                model.listView = .mine
                model.searchText = "no such words anywhere"
                return model
            },
            // The list's filters (MAC-69): two facets on, one that leaves nothing, drafts only,
            // and filters at the narrowest list. The menus themselves cannot be drawn offscreen.
            State(name: "list-filter-repository-and-status") {
                let model = model(example)
                model.listView = .everythingOpen
                model.listFilter = ListFilter(repositories: [MockCast.api], statuses: [.blocked, .running])
                return model
            },
            State(name: "list-filter-no-matches") {
                let model = model(example)
                model.listView = .mine
                model.listFilter = ListFilter(authors: [MockCast.adaPark.login])
                return model
            },
            State(name: "list-filter-drafts-only") {
                let model = model(example)
                model.listView = .everythingOpen
                model.listFilter = ListFilter(drafts: .only)
                return model
            },
            State(name: "list-filter-narrowest") {
                let model = model(example)
                model.listWidth = AppModel.listWidthRange.lowerBound
                model.listFilter = ListFilter(repositories: [MockCast.api, MockCast.web], authors: [MockCast.adaPark.login],
                                              reviewStates: [.reviewRequired])
                return model
            },
            // The list in sections: by repository in "Mine", short enough to show several
            // sections, over everything open, and by status within a filter.
            State(name: "list-group-repository") {
                let model = model(first { $0.state == .open && world.viewer.isViewer($0.author) })
                model.listView = .mine
                model.listGrouping = .repository
                return model
            },
            State(name: "list-group-repository-everything-open") {
                let model = model(example)
                model.listView = .everythingOpen
                model.listGrouping = .repository
                return model
            },
            State(name: "list-group-status-filtered") {
                let model = model(example)
                model.listView = .everythingOpen
                model.listFilter = ListFilter(repositories: [MockCast.api])
                model.listGrouping = .status
                return model
            },
            // A repository name far longer than the mock world's, made up here and marked as
            // mock data, to show it gives way before the number does.
            State(name: "list-long-repository-name") {
                let long = longRepositoryPullRequests(from: index, now: world.now)
                let longIndex = InMemoryPullRequestIndex(pullRequests: long + world.pullRequests, viewer: world.viewer)
                let model = model(long.first?.reference, index: longIndex)
                model.listView = .everythingOpen
                return model
            },
            State(name: "list-narrowest") {
                let model = model(example)
                model.listWidth = AppModel.listWidthRange.lowerBound
                return model
            },
            State(name: "list-widest") {
                let model = model(example)
                model.listWidth = AppModel.listWidthRange.upperBound
                return model
            },
            // The smallest window the app allows, to check the title bar's status does not run
            // into the centered name and the page header fits beside the widest list.
            State(name: "window-smallest-list-widest", size: CGSize(width: 900, height: 560)) {
                let model = model(example)
                model.listWidth = AppModel.listWidthRange.upperBound
                return model
            },
            State(name: "window-smallest", size: CGSize(width: 900, height: 560)) { model(example) },
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

        // The title bar while an update waits (MAC-47): found, then downloaded. Nothing else in
        // the window changes. A narrow window shows the indicator's symbol only, and the two
        // window states check the status still clears the centered name.
        let available = AppUpdates.Pending(stage: .available, version: "0.2.0")
        let ready = AppUpdates.Pending(stage: .readyToInstall, version: "0.2.0")
        states += [
            State(name: "titlebar-update-available", pendingUpdate: available) { model(example) },
            State(name: "titlebar-update-ready", pendingUpdate: ready) { model(example) },
            State(name: "window-smallest-update-ready", size: CGSize(width: 900, height: 560),
                  pendingUpdate: ready) { model(example) },
            // Just wider than MainWindowView.compactTitleBarWidth, where the full label returns.
            State(name: "window-narrow-update-ready", size: CGSize(width: 1240, height: 760),
                  pendingUpdate: ready) { model(example) },
        ]

        // The title bar in GitHub mode (MAC-59). The data is the mock world: a render never
        // uses the network or real pull requests. Only the sync's status is made up.
        func synced(_ configure: (inout GitHubSyncStatus) -> Void, selection: PullRequestReference? = example,
                    size: CGSize? = nil) -> AppModel {
            var status = GitHubSyncStatus()
            status.accountLogin = world.viewer.person.login
            status.hasLogin = true
            status.lastSuccessAt = world.now.addingTimeInterval(-4 * 60)
            status.pullRequestCount = 218
            status.detailedCount = 218
            status.rateLimits["graphql"] = RateLimitReading(resource: "graphql", limit: 5000, remaining: 4870,
                                                            resetAt: world.now.addingTimeInterval(40 * 60), readAt: world.now)
            configure(&status)
            let model = model(selection)
            model.syncSummary = SyncStatusSummary(status: status, now: world.now)
            return model
        }
        let hour = world.now.addingTimeInterval(38 * 60)
        states += [
            State(name: "titlebar-github-synced") { synced { _ in } },
            State(name: "titlebar-github-synced-nothing-open") { synced({ _ in }, selection: nil) },
            State(name: "titlebar-github-syncing") { synced { $0.phase = .listing } },
            State(name: "titlebar-github-not-synced-yet") {
                synced({ $0.lastSuccessAt = nil; $0.phase = .checkingLogin }, selection: nil)
            },
            State(name: "titlebar-github-gh-missing") { synced { $0.problem = .ghMissing; $0.hasLogin = false } },
            State(name: "titlebar-github-signed-out") { synced { $0.problem = .signedOut; $0.hasLogin = false } },
            State(name: "titlebar-github-offline") { synced { $0.problem = .offline } },
            State(name: "titlebar-github-rate-limited") { synced { $0.problem = .rateLimited(until: hour) } },
            State(name: "titlebar-github-budget-paused") { synced { $0.problem = .budgetPaused(until: hour) } },
            State(name: "window-smallest-github-offline", size: CGSize(width: 900, height: 560)) { synced { $0.problem = .offline } },
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

    /// Copies of two open pull requests in a repository with a very long name, one written by
    /// the viewer. Their provenance says `mock`: they are made up for this preview.
    private static func longRepositoryPullRequests(from index: any PullRequestIndex, now: Date) -> [PullRequest] {
        let open = index.allPullRequests.filter { $0.state == .open && !$0.isDraft }
        let picks = [open.first, open.first { index.viewer.isViewer($0.author) }].compactMap { $0 }
        return picks.enumerated().map { offset, pr in
            var copy = pr
            copy.id = "PR_preview_long_repository_\(offset)"
            copy.repository = Repository(owner: "acme", name: "payments-platform-reconciliation-service")
            copy.number = 10_482 + offset
            copy.updatedAt = now.addingTimeInterval(Double(-offset))
            copy.provenance = .uniform(.mock, fetchedAt: now)
            return copy
        }
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
