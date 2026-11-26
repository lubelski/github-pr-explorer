import Foundation

/// The layouts the app can show, and the problems found reading them.
///
/// Today it holds the built-in layouts only. A later task adds a configuration folder, whose
/// files go through the same `PageLayout.decode(_:fileName:)`.
public struct LayoutLibrary: Sendable, Hashable {
    /// The id of the layout every page falls back to.
    public static let fallbackID = "decision-first"

    /// In the order a menu lists them. Always holds "Decision first".
    public var layouts: [PageLayout]
    /// One per file that could not be used. The app shows these and keeps going.
    public var problems: [LayoutFileError]

    /// Reads layout files. A file that does not decode is left out and reported. When no file
    /// gives "Decision first", the copy compiled into the app is used, so a page always has a
    /// layout.
    public init(files: [(name: String, data: Data)]) {
        var layouts: [PageLayout] = []
        var problems: [LayoutFileError] = []
        for file in files {
            do {
                let layout = try PageLayout.decode(file.data, fileName: file.name)
                if layouts.contains(where: { $0.id == layout.id }) {
                    problems.append(LayoutFileError(fileName: file.name, path: "id",
                                                    problem: "another layout already has the id \"\(layout.id)\""))
                } else {
                    layouts.append(layout)
                }
            } catch {
                problems.append(error)
            }
        }
        if !layouts.contains(where: { $0.id == Self.fallbackID }) {
            layouts.insert(.decisionFirst, at: 0)
        }
        self.layouts = layouts
        self.problems = problems
    }

    /// The layouts that ship with the app, read from the JSON files in the package.
    public static func builtIn() -> LayoutLibrary {
        LayoutLibrary(files: builtInFiles())
    }

    /// The built-in layout files, in menu order: "Decision first", then "Tabbed".
    public static func builtInFiles() -> [(name: String, data: Data)] {
        builtInFileNames.map { name in
            guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "BuiltInLayouts") else {
                return (name, Data())
            }
            return (name, (try? Data(contentsOf: url)) ?? Data())
        }
    }

    public static let builtInFileNames = ["decision-first.json", "tabbed.json"]

    /// The layout with this id, or "Decision first" when there is none.
    public func layout(id: String?) -> PageLayout {
        if let id, let found = layouts.first(where: { $0.id == id }) { return found }
        return layouts.first { $0.id == Self.fallbackID } ?? .decisionFirst
    }
}

extension PageLayout {
    /// "Decision first", compiled in. The app falls back to it when its file cannot be read.
    /// A test checks it equals `decision-first.json`.
    public static let decisionFirst = PageLayout(
        id: "decision-first",
        name: "Decision first",
        tabs: [
            LayoutTab(name: "Pull request", columns: [
                LayoutColumn(width: 1.85, blocks: [
                    BlockPlacement(.description), BlockPlacement(.threads), BlockPlacement(.files),
                ]),
                LayoutColumn(width: 1, blocks: [
                    BlockPlacement(.checks), BlockPlacement(.reviewers), BlockPlacement(.ownersTouched), BlockPlacement(.activity),
                ]),
            ]),
        ]
    )
}
