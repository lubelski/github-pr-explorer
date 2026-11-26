import Foundation

/// Writes synthetic but well-formed unified patches with an exact number of added and
/// removed lines. The lines read like the file's language so diff views look real.
enum MockPatchSynthesizer {
    enum Language {
        case typescript, tsx, markdown, terraform, yaml, json, sql, css

        init(path: String) {
            let lower = path.lowercased()
            if lower.hasSuffix(".tsx") { self = .tsx }
            else if lower.hasSuffix(".ts") || lower.hasSuffix(".js") { self = .typescript }
            else if lower.hasSuffix(".md") { self = .markdown }
            else if lower.hasSuffix(".tf") { self = .terraform }
            else if lower.hasSuffix(".yaml") || lower.hasSuffix(".yml") { self = .yaml }
            else if lower.hasSuffix(".json") { self = .json }
            else if lower.hasSuffix(".sql") { self = .sql }
            else if lower.hasSuffix(".css") { self = .css }
            else { self = .typescript }
        }
    }

    static func patch(
        path: String,
        changeKind: FileChangeKind,
        additions: Int,
        deletions: Int,
        noNewlineAtEnd: Bool,
        rng: inout SeededGenerator
    ) -> String? {
        let language = Language(path: path)
        switch changeKind {
        case .added:
            guard additions > 0 else { return nil }
            let lines = (0..<additions).map { _ in "+" + line(language, &rng) }
            return PatchWriter.write([PatchWriter.Hunk(oldStart: 0, lines: lines)], noNewlineAtEnd: noNewlineAtEnd)
        case .removed:
            guard deletions > 0 else { return nil }
            let lines = (0..<deletions).map { _ in "-" + line(language, &rng) }
            return PatchWriter.write([PatchWriter.Hunk(oldStart: 1, lines: lines)])
        case .modified, .renamed:
            guard additions + deletions > 0 else { return nil }
            return modifiedPatch(language: language, additions: additions, deletions: deletions, noNewlineAtEnd: noNewlineAtEnd, rng: &rng)
        }
    }

    private static func modifiedPatch(language: Language, additions: Int, deletions: Int, noNewlineAtEnd: Bool, rng: inout SeededGenerator) -> String {
        let total = additions + deletions
        let hunkCount = min(total, max(1, total / 28 + (total > 6 ? rng.int(0...1) : 0)))
        let addedPerHunk = split(additions, into: hunkCount, rng: &rng)
        var removedPerHunk = split(deletions, into: hunkCount, rng: &rng)
        // Every hunk needs at least one change. Move a removal into any empty hunk.
        for index in 0..<hunkCount where addedPerHunk[index] + removedPerHunk[index] == 0 {
            if let donor = (0..<hunkCount).first(where: { removedPerHunk[$0] > 1 || (removedPerHunk[$0] == 1 && addedPerHunk[$0] > 0) }) {
                removedPerHunk[donor] -= 1
                removedPerHunk[index] += 1
            }
        }
        var hunks: [PatchWriter.Hunk] = []
        var oldCursor = rng.int(1...24)
        for index in 0..<hunkCount {
            let before = min(3, oldCursor - 1)
            var lines: [String] = []
            for _ in 0..<before { lines.append(" " + line(language, &rng)) }
            let removed = removedPerHunk[index]
            let added = addedPerHunk[index]
            // Large blocks get one context line in the middle, as real diffs often do.
            if removed + added > 14 && removed > 2 && added > 2 {
                let firstRemoved = removed / 2, firstAdded = added / 2
                for _ in 0..<firstRemoved { lines.append("-" + line(language, &rng)) }
                for _ in 0..<firstAdded { lines.append("+" + line(language, &rng)) }
                lines.append(" " + line(language, &rng))
                for _ in 0..<(removed - firstRemoved) { lines.append("-" + line(language, &rng)) }
                for _ in 0..<(added - firstAdded) { lines.append("+" + line(language, &rng)) }
            } else {
                for _ in 0..<removed { lines.append("-" + line(language, &rng)) }
                for _ in 0..<added { lines.append("+" + line(language, &rng)) }
            }
            let isLast = index == hunkCount - 1
            let after = isLast && noNewlineAtEnd ? 0 : 3
            for _ in 0..<after { lines.append(" " + line(language, &rng)) }
            let oldStart = oldCursor - before
            let section = rng.chance(0.6) ? sectionHeader(language, &rng) : ""
            hunks.append(PatchWriter.Hunk(oldStart: oldStart, section: section, lines: lines))
            let oldLinesInHunk = lines.count { !$0.hasPrefix("+") }
            oldCursor = oldStart + oldLinesInHunk + rng.int(8...60)
        }
        return PatchWriter.write(hunks, noNewlineAtEnd: noNewlineAtEnd)
    }

    /// Splits `total` into `parts` whole numbers that add up to it.
    private static func split(_ total: Int, into parts: Int, rng: inout SeededGenerator) -> [Int] {
        guard parts > 1 else { return [total] }
        var result = Array(repeating: total / parts, count: parts)
        var remainder = total - result.reduce(0, +)
        while remainder > 0 {
            result[rng.int(0...(parts - 1))] += 1
            remainder -= 1
        }
        // Make the sizes uneven, keeping the sum.
        for _ in 0..<parts {
            let from = rng.int(0...(parts - 1)), to = rng.int(0...(parts - 1))
            let move = result[from] / 3
            result[from] -= move
            result[to] += move
        }
        return result
    }

    // MARK: Lines

    private static let identifiers = ["session", "token", "user", "request", "invoice", "account", "event", "retryCount", "timeoutMs",
                                      "result", "payload", "config", "entry", "rows", "options", "limit", "cursor", "delivery"]
    private static let functions = ["loadUser", "verifySignature", "fetchInvoice", "parseHeaders", "sendWebhook", "recordMetric", "readConfig",
                                    "lookupAccount", "refreshToken", "formatDate", "buildQuery", "nextCursor", "withRetry", "toResponse"]
    private static let types = ["Request", "Session", "Invoice", "Account", "WebhookEvent", "Config", "QueryResult", "Delivery"]
    private static let messages = ["request failed", "retrying delivery", "invoice exported", "cache miss", "token expired",
                                   "rate limit reached", "skipping empty batch", "account not found"]
    private static let components = ["Button", "Table", "Row", "Spinner", "EmptyState", "Banner", "Dialog", "Field", "Tooltip"]
    private static let words = ["The", "session", "lasts", "twelve", "hours", "and", "each", "request", "extends", "it", "when", "close",
                                "to", "ending", "webhooks", "retry", "five", "times", "with", "backoff", "an", "invoice", "is", "sent",
                                "once", "the", "month", "closes", "admins", "can", "change", "this", "in", "settings"]

    static func line(_ language: Language, _ rng: inout SeededGenerator) -> String {
        let indent = String(repeating: "  ", count: rng.int(0...3))
        let id = rng.pick(identifiers), id2 = rng.pick(identifiers), fn = rng.pick(functions), type = rng.pick(types)
        switch language {
        case .typescript:
            switch rng.int(0...13) {
            case 0: return indent + "const \(id) = await \(fn)(\(id2));"
            case 1: return indent + "if (!\(id)) {"
            case 2: return indent + "  return null;"
            case 3: return indent + "}"
            case 4: return indent + "logger.info('\(rng.pick(messages))', { \(id) });"
            case 5: return indent + "throw new HttpError(\(rng.pick([400, 401, 403, 404, 409, 422, 503])), '\(rng.pick(messages))');"
            case 6: return indent + "return \(fn)(\(id), \(id2));"
            case 7: return indent + "// \(sentence(&rng, words: 6))"
            case 8: return indent + "\(id).\(id2) = \(id2) ?? \(rng.int(1...500));"
            case 9: return "export async function \(fn)(\(id): \(type)): Promise<\(rng.pick(types))> {"
            case 10: return "import { \(fn) } from '../lib/\(rng.pick(["clock", "errors", "logger", "metrics", "retry"]))';"
            case 11: return indent + "expect(\(id)).toEqual(\(id2));"
            case 12: return indent + "for (const \(id) of \(id2)s) {"
            default: return ""
            }
        case .tsx:
            switch rng.int(0...9) {
            case 0: return indent + "<\(rng.pick(components)) \(id)={\(id2)} />"
            case 1: return indent + "const [\(id), set\(id.capitalizedFirst)] = useState(\(rng.pick(["null", "false", "0", "[]"])));"
            case 2: return indent + "{\(id) && <\(rng.pick(components)) />}"
            case 3: return indent + "</\(rng.pick(components))>"
            case 4: return indent + "return ("
            case 5: return indent + "const \(id) = use\(rng.pick(["Session", "Query", "Theme", "Toast"]))();"
            case 6: return indent + "className=\"\(rng.pick(["row", "cell", "header", "empty", "banner"]))-\(rng.pick(["muted", "active", "wide"]))\""
            case 7: return indent + "// \(sentence(&rng, words: 5))"
            case 8: return "export function \(rng.pick(components))\(rng.pick(["List", "Panel", "Header", "View"]))({ \(id) }: Props) {"
            default: return ""
            }
        case .markdown:
            switch rng.int(0...6) {
            case 0: return "## " + sentence(&rng, words: 3)
            case 1: return "- " + sentence(&rng, words: 7) + "."
            case 2, 3: return sentence(&rng, words: 12) + "."
            case 4: return "`\(fn)` " + sentence(&rng, words: 8) + "."
            default: return ""
            }
        case .terraform:
            switch rng.int(0...8) {
            case 0: return "resource \"aws_\(rng.pick(["db_instance", "s3_bucket", "iam_role", "security_group", "route53_record"]))\" \"\(rng.pick(["main", "replica", "logs", "auth", "preview"]))\" {"
            case 1: return indent + "\(rng.pick(["instance_class", "engine_version", "bucket", "name", "ttl"])) = \"\(rng.pick(["db.r6g.large", "16.4", "acme-logs", "auth-service", "300"]))\""
            case 2: return indent + "\(rng.pick(["max_connections", "allocated_storage", "retention_days", "min_size", "max_size"])) = \(rng.int(1...400))"
            case 3: return indent + "tags = local.tags"
            case 4: return "}"
            case 5: return indent + "# " + sentence(&rng, words: 6)
            case 6: return indent + "depends_on = [aws_\(rng.pick(["iam_role", "vpc", "subnet"])).main]"
            default: return ""
            }
        case .yaml:
            switch rng.int(0...8) {
            case 0: return indent + "\(id):"
            case 1: return indent + "  type: \(rng.pick(["string", "integer", "boolean", "array", "object"]))"
            case 2: return indent + "  description: \(sentence(&rng, words: 6))"
            case 3: return indent + "  $ref: '#/components/schemas/\(type)'"
            case 4: return indent + "  format: \(rng.pick(["date-time", "uuid", "email", "uri"]))"
            case 5: return indent + "replicas: \(rng.int(2...12))"
            case 6: return indent + "memory: \(rng.pick(["256Mi", "512Mi", "1Gi", "2Gi"]))"
            case 7: return indent + "- name: \(id)"
            default: return indent + "required: [\(id), \(id2)]"
            }
        case .json:
            switch rng.int(0...4) {
            case 0: return indent + "\"title\": \"\(sentence(&rng, words: 3))\","
            case 1: return indent + "\"expr\": \"rate(http_requests_total{status=~\\\"5..\\\"}[5m])\","
            case 2: return indent + "{"
            case 3: return indent + "},"
            default: return indent + "\"\(id)\": \(rng.int(1...100)),"
            }
        case .sql:
            switch rng.int(0...3) {
            case 0: return "ALTER TABLE \(rng.pick(["accounts", "sessions", "audit_log", "invoices"])) ADD COLUMN \(id)_at timestamptz;"
            case 1: return "CREATE INDEX CONCURRENTLY idx_\(id)_\(id2) ON \(rng.pick(["accounts", "audit_log"])) (\(id)_id);"
            case 2: return "-- " + sentence(&rng, words: 6)
            default: return ""
            }
        case .css:
            switch rng.int(0...4) {
            case 0: return ".\(rng.pick(["row", "cell", "banner", "toast"]))-\(rng.pick(["muted", "active"])) {"
            case 1: return "  color: var(--\(rng.pick(["text", "muted", "accent"])));"
            case 2: return "  padding: \(rng.int(1...6) * 4)px;"
            case 3: return "}"
            default: return ""
            }
        }
    }

    private static func sectionHeader(_ language: Language, _ rng: inout SeededGenerator) -> String {
        switch language {
        case .typescript: "export async function \(rng.pick(functions))(\(rng.pick(identifiers)): \(rng.pick(types))) {"
        case .tsx: "export function \(rng.pick(components))\(rng.pick(["List", "Panel", "Header"]))({ \(rng.pick(identifiers)) }: Props) {"
        case .markdown: "## " + sentence(&rng, words: 3)
        case .terraform: "resource \"aws_db_instance\" \"main\" {"
        case .yaml: "components:"
        case .json, .sql, .css: ""
        }
    }

    private static func sentence(_ rng: inout SeededGenerator, words count: Int) -> String {
        (0..<count).map { _ in rng.pick(words) }.joined(separator: " ").capitalizedFirst
    }
}
