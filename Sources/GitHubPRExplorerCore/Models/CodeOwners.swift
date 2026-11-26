import Foundation

/// One line of a CODEOWNERS file: a path pattern and who owns what it matches.
public struct CodeOwnerRule: Codable, Sendable, Hashable {
    public var pattern: String
    /// `@login` or `@org/team`.
    public var owners: [String]

    public init(pattern: String, owners: [String]) {
        self.pattern = pattern
        self.owners = owners
    }
}

/// Which changed paths a CODEOWNERS pattern matched in this pull request, and its owners.
public struct CodeOwnerMatch: Codable, Sendable, Hashable {
    public var pattern: String
    public var owners: [String]
    public var paths: [String]

    public init(pattern: String, owners: [String], paths: [String]) {
        self.pattern = pattern
        self.owners = owners
        self.paths = paths
    }
}

public enum CodeOwners {
    /// Applies CODEOWNERS rules to changed paths. As on GitHub, the last rule that matches a
    /// path wins. Matches come back in rule order, each with its paths in the order given.
    public static func matches(rules: [CodeOwnerRule], paths: [String]) -> [CodeOwnerMatch] {
        var pathsByRule = Array(repeating: [String](), count: rules.count)
        for path in paths {
            if let index = rules.lastIndex(where: { pattern($0.pattern, matches: path) }) {
                pathsByRule[index].append(path)
            }
        }
        return rules.indices.compactMap { index in
            let matched = pathsByRule[index]
            guard !matched.isEmpty, !rules[index].owners.isEmpty else { return nil }
            return CodeOwnerMatch(pattern: rules[index].pattern, owners: rules[index].owners, paths: matched)
        }
    }

    /// CODEOWNERS pattern matching, for the forms the mock data and most real files use.
    ///
    /// - `*` matches within one path segment, `**` across segments, `?` one character.
    /// - A pattern with no `/` except a trailing one matches at any depth, such as `*.md`.
    /// - A pattern ending in `/` matches everything under that folder.
    /// - A leading `/` anchors the pattern to the repository root.
    public static func pattern(_ pattern: String, matches path: String) -> Bool {
        var pattern = pattern
        let anchored = pattern.hasPrefix("/")
        if anchored { pattern.removeFirst() }
        let hasInnerSlash = (pattern.hasSuffix("/") ? pattern.dropLast() : Substring(pattern)).contains("/")
        if pattern.hasSuffix("/") { pattern += "**" }
        if !anchored && !hasInnerSlash {
            pattern = "**/" + pattern
        }
        return glob(Array(pattern), Array(path))
    }

    private static func glob(_ pattern: [Character], _ text: [Character]) -> Bool {
        // memo[p][t]: does pattern[p...] match text[t...]
        var memo = [[Bool?]](repeating: [Bool?](repeating: nil, count: text.count + 1), count: pattern.count + 1)
        func match(_ p: Int, _ t: Int) -> Bool {
            if let known = memo[p][t] { return known }
            let result: Bool
            if p == pattern.count {
                result = t == text.count
            } else if pattern[p] == "*" && p + 1 < pattern.count && pattern[p + 1] == "*" {
                // `**/` may match nothing, so `**/x` also matches `x`.
                var next = p + 2
                if next < pattern.count && pattern[next] == "/" {
                    next += 1
                    if match(next, t) { memo[p][t] = true; return true }
                }
                var found = false
                var index = t
                while index <= text.count {
                    if match(p + 2, index) { found = true; break }
                    index += 1
                }
                result = found
            } else if pattern[p] == "*" {
                var found = false
                var index = t
                while index <= text.count {
                    if match(p + 1, index) { found = true; break }
                    if index < text.count && text[index] == "/" { break }
                    index += 1
                }
                result = found
            } else if t < text.count && (pattern[p] == "?" ? text[t] != "/" : pattern[p] == text[t]) {
                result = match(p + 1, t + 1)
            } else {
                result = false
            }
            memo[p][t] = result
            return result
        }
        return match(0, 0)
    }
}
