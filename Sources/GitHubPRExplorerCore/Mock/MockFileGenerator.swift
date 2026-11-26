import Foundation

/// Picks the files a generated pull request changes, with their change kinds and sizes.
enum MockFileGenerator {
    enum Size { case small, medium, large }

    static func files(area: MockArea, profile: MockRepositoryProfile, rng: inout SeededGenerator) -> [MockFileSpec] {
        let size: Size = rng.pick(weighted: [(.small, 40), (.medium, 45), (.large, 15)])
        return files(area: area, profile: profile, size: size, rng: &rng)
    }

    static func files(area: MockArea, profile: MockRepositoryProfile, size: Size, rng: inout SeededGenerator) -> [MockFileSpec] {
        let count = switch size {
        case .small: rng.int(1...2)
        case .medium: rng.int(2...5)
        case .large: rng.int(5...10)
        }
        var paths = rng.pick(area.files, count: count)
        if rng.chance(0.2), let other = profile.areas.first(where: { $0.name != area.name }) {
            let extra = rng.pick(other.files)
            if !paths.contains(extra) { paths.append(extra) }
        }
        var used = Set(paths)
        var specs: [MockFileSpec] = []
        for path in paths {
            let (additions, deletions) = counts(size: size, rng: &rng)
            let roll = rng.int(0...99)
            if roll < 10 {
                // A new file next to this one.
                let newPath = newFilePath(near: path, profile: profile, rng: &rng)
                if !used.contains(newPath) {
                    used.insert(newPath)
                    specs.append(MockFileSpec(path: newPath, changeKind: .added, additions: max(1, additions), noNewlineAtEnd: rng.chance(0.15)))
                    continue
                }
            } else if roll < 14 && paths.count > 1 {
                specs.append(MockFileSpec(path: path, changeKind: .removed, deletions: rng.int(8...90)))
                continue
            } else if roll < 18 {
                let newPath = newFilePath(near: path, profile: profile, rng: &rng)
                if !used.contains(newPath) {
                    used.insert(newPath)
                    let pure = rng.chance(0.5)
                    specs.append(MockFileSpec(path: newPath, changeKind: .renamed, additions: pure ? 0 : rng.int(1...6),
                                              deletions: pure ? 0 : rng.int(1...6), previousPath: path))
                    continue
                }
            }
            specs.append(MockFileSpec(path: path, additions: additions, deletions: deletions, noNewlineAtEnd: rng.chance(0.04)))
        }
        if profile.repository == MockCast.web && rng.chance(0.06) {
            specs.append(MockFileSpec(path: "public/images/\(rng.pick(["empty-state", "hero", "invoice", "avatar-placeholder"])).png",
                                      changeKind: rng.chance(0.5) ? .added : .modified, isBinary: true))
        }
        if profile.repository == MockCast.docs && rng.chance(0.08) {
            specs.append(MockFileSpec(path: "docs/images/\(rng.pick(["settings", "webhooks", "sso"]))-screenshot.png",
                                      changeKind: .modified, isBinary: true))
        }
        return specs
    }

    static func counts(size: Size, rng: inout SeededGenerator) -> (Int, Int) {
        switch size {
        case .small: (rng.int(1...12), rng.int(0...6))
        case .medium: (rng.int(4...60), rng.int(0...40))
        case .large: (rng.int(30...220), rng.int(10...150))
        }
    }

    private static func newFilePath(near path: String, profile: MockRepositoryProfile, rng: inout SeededGenerator) -> String {
        let folder = path.split(separator: "/").dropLast().joined(separator: "/")
        let fileExtension = path.split(separator: ".").last.map(String.init) ?? profile.fileExtension
        let stem = rng.pick(profile.newFileStems)
        return folder.isEmpty ? "\(stem).\(fileExtension)" : "\(folder)/\(stem).\(fileExtension)"
    }
}
