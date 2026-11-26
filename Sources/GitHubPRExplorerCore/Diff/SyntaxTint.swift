import Foundation

/// Best-effort coloring for one line of code: strings, comments, keywords and numbers.
///
/// It reads one line at a time with no memory of the lines before, so a comment or string that
/// spans lines is only colored where its opening is on the same line. That keeps it cheap enough
/// to run on each row as it scrolls into view, and wrong only in harmless ways: an unknown file
/// type, or anything it does not understand, stays plain text.
public enum SyntaxTint {
    public enum Language: Sendable, Hashable {
        /// TypeScript, JavaScript, Swift, Go and similar: `//` and `/* */` comments, three quotes.
        case cLike
        /// YAML, Terraform, shell, Python, Ruby: `#` comments.
        case hashComments
        /// No coloring.
        case plain

        public init(path: String) {
            let name = path.lowercased()
            let ext = name.split(separator: ".").last.map(String.init) ?? ""
            switch ext {
            case "ts", "tsx", "js", "jsx", "mjs", "cjs", "swift", "go", "java", "kt", "c", "h", "cc", "cpp",
                 "m", "rs", "cs", "css", "scss", "json":
                self = .cLike
            case "yaml", "yml", "tf", "sh", "bash", "zsh", "py", "rb", "toml":
                self = .hashComments
            default:
                self = .plain
            }
        }
    }

    public enum Kind: Sendable, Hashable {
        case keyword
        case string
        case comment
        case number
    }

    /// A run of the line. Runs cover the whole line in order, and `kind` is nil for plain text.
    public struct Run: Sendable, Hashable {
        public var text: String
        public var kind: Kind?

        public init(_ text: String, _ kind: Kind? = nil) {
            self.text = text
            self.kind = kind
        }
    }

    static let keywords: Set<String> = [
        "abstract", "as", "async", "await", "break", "case", "catch", "class", "const", "continue",
        "default", "delete", "do", "else", "enum", "export", "extends", "false", "finally", "for",
        "from", "func", "function", "if", "implements", "import", "in", "instanceof", "interface",
        "let", "new", "nil", "null", "private", "protected", "public", "readonly", "return", "self",
        "static", "struct", "super", "switch", "this", "throw", "true", "try", "type", "typeof",
        "undefined", "var", "void", "while", "yield", "guard", "where", "package", "def", "end",
    ]

    /// The line split into runs. Joined, the runs' text is exactly `line`.
    public static func runs(_ line: String, language: Language) -> [Run] {
        guard language != .plain, !line.isEmpty else { return [Run(line)] }
        let characters = Array(line)
        var runs: [Run] = []
        var plain = ""
        func flushPlain() {
            if !plain.isEmpty { runs.append(Run(plain)); plain = "" }
        }
        func add(_ range: Range<Int>, _ kind: Kind) {
            flushPlain()
            runs.append(Run(String(characters[range]), kind))
        }

        var index = 0
        let count = characters.count
        while index < count {
            let character = characters[index]
            let next: Character? = index + 1 < count ? characters[index + 1] : nil

            // Comments.
            if language == .cLike && character == "/" && next == "/" {
                add(index..<count, .comment)
                index = count
                continue
            }
            if language == .hashComments && character == "#" {
                add(index..<count, .comment)
                index = count
                continue
            }
            if language == .cLike && character == "/" && next == "*" {
                var end = index + 2
                while end < count && !(characters[end] == "*" && end + 1 < count && characters[end + 1] == "/") { end += 1 }
                end = min(count, end + 2)
                add(index..<end, .comment)
                index = end
                continue
            }
            // A line inside a block comment, by its leading `*`.
            if language == .cLike && character == "*" && plain.allSatisfy(\.isWhitespace) && runs.isEmpty
                && (next == nil || next == " " || next == "/") {
                add(index..<count, .comment)
                index = count
                continue
            }

            // Strings.
            if character == "\"" || character == "'" || (character == "`" && language == .cLike) {
                var end = index + 1
                while end < count && characters[end] != character {
                    end += characters[end] == "\\" ? 2 : 1
                }
                end = min(count, end + 1)
                add(index..<end, .string)
                index = end
                continue
            }

            // Words: keywords, or plain identifiers.
            if character.isLetter || character == "_" || character == "$" {
                var end = index + 1
                while end < count && (characters[end].isLetter || characters[end].isNumber || characters[end] == "_" || characters[end] == "$") {
                    end += 1
                }
                let word = String(characters[index..<end])
                let previous: Character? = index > 0 ? characters[index - 1] : nil
                // `options.default` is a property, not the keyword.
                if keywords.contains(word) && previous != "." {
                    add(index..<end, .keyword)
                } else {
                    plain += word
                }
                index = end
                continue
            }

            // Numbers not inside a word.
            if character.isNumber {
                var end = index + 1
                while end < count && (characters[end].isNumber || characters[end] == "." || characters[end] == "_") { end += 1 }
                add(index..<end, .number)
                index = end
                continue
            }

            plain.append(character)
            index += 1
        }
        flushPlain()
        return runs
    }
}
