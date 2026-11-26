import Foundation

/// The generated part of the mock world: the awkward cases views must handle, then enough
/// ordinary pull requests to reach 218 open, 60 merged and 20 closed.
enum MockGenerated {
    static let openTarget = 218
    static let mergedTarget = 60
    static let closedTarget = 20

    /// `handWrittenOpen` is how many open pull requests the hand-written ones supply.
    static func specs(now: Date, reserved: Set<PullRequestReference>, handWrittenOpen: Int) -> [MockPullRequestSpec] {
        var rng = SeededGenerator(seed: "mock world generated pull requests")
        var usedTitles = Set<String>()
        var drafts: [MockPullRequestSpec] = special(rng: &rng)
        for spec in drafts { usedTitles.insert(spec.title) }

        let openNeeded = openTarget - handWrittenOpen - drafts.count { $0.scenario.isOpen }
        let authors = rng.shuffled(
            MockCast.corePeople + MockCast.corePeople + MockCast.corePeople
                + [MockCast.robinQuill, MockCast.robinQuill] + MockCast.occasionalPeople.prefix(10)
        )
        let repositories: [(Repository, Int)] = [(MockCast.api, 40), (MockCast.web, 30), (MockCast.infra, 16), (MockCast.docs, 14)]

        // Each open scenario once in every repository first, so every status shows up everywhere.
        let everyScenario: [MockScenario] = [
            .readyToMerge, .waitingOnReviewers, .checksRunning(minutes: 1), .checksQueued, .requiredCheckFailed,
            .optionalCheckFailed, .changesRequested, .unresolvedThreads(count: 1), .draft, .mergeConflicts,
            .behindBase, .mergeabilityUnknown, .needsReview,
        ]
        var openScenarios = everyScenario.flatMap { Array(repeating: $0, count: repositories.count) }
        while openScenarios.count < openNeeded {
            openScenarios.append(rng.pick(weighted: [
                (.readyToMerge, 11), (.waitingOnReviewers, 18), (.checksRunning(minutes: 0), 12), (.checksQueued, 4),
                (.requiredCheckFailed, 10), (.optionalCheckFailed, 3), (.changesRequested, 8), (.unresolvedThreads(count: 0), 8),
                (.draft, 10), (.mergeConflicts, 5), (.behindBase, 5), (.mergeabilityUnknown, 2), (.needsReview, 3),
            ]))
        }
        openScenarios = Array(openScenarios.prefix(max(0, openNeeded)))

        var index = 0
        func ordinary(_ scenario: MockScenario, repository: Repository? = nil) -> MockPullRequestSpec {
            defer { index += 1 }
            let repository = repository ?? (index < everyScenario.count * repositories.count
                ? repositories[index % repositories.count].0
                : rng.pick(weighted: repositories))
            let profile = MockVocabulary.profile(for: repository)
            let area = rng.pick(profile.areas)
            var scenario = scenario
            switch scenario {
            case .checksRunning: scenario = .checksRunning(minutes: rng.int(1...45))
            case .unresolvedThreads: scenario = .unresolvedThreads(count: rng.int(1...4))
            default: break
            }
            let author = authors[index % authors.count]
            let title = makeTitle(profile: profile, area: area, rng: &rng, used: &usedTitles)
            return MockPullRequestSpec(
                repository: repository, number: 0, title: title, author: author, scenario: scenario,
                createdAt: createdAt(scenario: scenario, now: now, rng: &rng), area: area
            )
        }

        for scenario in openScenarios { drafts.append(ordinary(scenario)) }
        for _ in 0..<mergedTarget { drafts.append(ordinary(.merged)) }
        for _ in 0..<closedTarget { drafts.append(ordinary(.closed)) }

        return assignNumbers(drafts, reserved: reserved)
    }

    // MARK: Special cases

    private static func special(rng: inout SeededGenerator) -> [MockPullRequestSpec] {
        let api = MockCast.api, web = MockCast.web, infra = MockCast.infra, docs = MockCast.docs
        let now = MockWorld.now
        func daysAgo(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }
        var specs: [MockPullRequestSpec] = []

        // One very large pull request: about 120 files, one with a patch of about 5,000 lines.
        let modelNames = ["Account", "Invoice", "Session", "Webhook", "User", "Team", "Plan", "Payment", "Refund", "Coupon",
                          "AuditEvent", "ApiKey", "Delivery", "Report", "Export", "Address", "TaxRate", "Seat", "Role", "Token"]
        let modelSuffixes = ["", "List", "Request", "Response", "Event", "Status"]
        var largeFiles = [
            MockFileSpec(path: "openapi/acme-api.yaml", additions: 3020, deletions: 1980),
            MockFileSpec(path: "clients/typescript/src/index.ts", additions: 118, deletions: 40),
        ]
        for name in modelNames {
            for suffix in modelSuffixes where largeFiles.count < 120 {
                let path = "clients/typescript/src/models/\(name)\(suffix).ts"
                if rng.chance(0.3) {
                    largeFiles.append(MockFileSpec(path: path, changeKind: .added, additions: rng.int(20...60)))
                } else {
                    largeFiles.append(MockFileSpec(path: path, additions: rng.int(3...30), deletions: rng.int(1...15)))
                }
            }
        }
        specs.append(MockPullRequestSpec(
            repository: api, number: 0, title: "Regenerate the TypeScript client from the OpenAPI spec", author: MockCast.tomasReyes,
            scenario: .waitingOnReviewers,
            body: "Regenerated with the new generator version. The spec file was reformatted by the upgrade, which is most of the diff.\n\nNo hand edits. Review `clients/typescript/src/index.ts` and skim the rest.",
            createdAt: daysAgo(2.3), files: largeFiles, commitCount: 3, labels: ["generated", "dependencies"]
        ))

        // A timeline of about 300 events, most of them from bots.
        specs.append(MockPullRequestSpec(
            repository: api, number: 0, title: "Upgrade the ORM to version 7", author: MockCast.maxChen,
            scenario: .checksRunning(minutes: 9),
            body: "Version 7 changes how transactions nest, so this moves every caller to the new API one module at a time. Each push is one module, which is why the timeline is long.\n\n- [x] accounts\n- [x] billing\n- [x] webhooks\n- [ ] audit log",
            createdAt: daysAgo(21), area: MockVocabulary.api.areas[4], commitCount: 44, pushCount: 40, labels: ["dependencies", "refactor"],
            reportsChecksOnEveryPush: true
        ))

        // ci-bot's comment with a checkbox that starts expensive CI.
        specs.append(MockPullRequestSpec(
            repository: api, number: 0, title: "Shard the integration tests across four runners", author: MockCast.joLindqvist,
            scenario: .waitingOnReviewers,
            body: "Integration tests take 14 minutes on one runner. Four shards bring it to about 4.\n\nThe full end-to-end suite is not part of this. Start it from ci-bot's comment if you want it.",
            createdAt: daysAgo(1.2), area: MockVocabulary.api.areas[5], ciBotCheckbox: .unticked
        ))
        specs.append(MockPullRequestSpec(
            repository: api, number: 0, title: "Batch audit log writes", author: MockCast.kaiDuarte,
            scenario: .checksRunning(minutes: 31),
            createdAt: daysAgo(0.8), area: MockVocabulary.api.areas[4], ciBotCheckbox: .ticked
        ))

        // An empty body.
        specs.append(MockPullRequestSpec(
            repository: web, number: 0, title: "Bump the icon set to 3.2", author: MockCast.miraHolm, scenario: .readyToMerge,
            body: "", createdAt: daysAgo(3.5), files: [MockFileSpec(path: "package.json", additions: 1, deletions: 1),
                                                     MockFileSpec(path: "package-lock.json", additions: 9, deletions: 9)]
        ))

        // A body with a table, an image, a task list, a collapsed section and a code block.
        specs.append(MockPullRequestSpec(
            repository: web, number: 0, title: "Make the reports table header sticky", author: MockCast.samRivera,
            scenario: .waitingOnReviewers, body: richBody, createdAt: daysAgo(4.1), area: MockVocabulary.web.areas[2]
        ))

        // A very long title.
        specs.append(MockPullRequestSpec(
            repository: api, number: 0,
            title: "Make the invoice export job resumable after a worker restart by writing a checkpoint every thousand rows, and skip rows that were already sent so customers never get duplicate lines in their export files",
            author: MockCast.lenaOkafor, scenario: .checksRunning(minutes: 21), createdAt: daysAgo(6), area: MockVocabulary.api.areas[2]
        ))

        // Non-ASCII characters in the title and the body.
        specs.append(MockPullRequestSpec(
            repository: api, number: 0, title: "Render ü, é, ñ, 日本語 and emoji ✅ in invoice PDFs", author: MockCast.kaiDuarte,
            scenario: .requiredCheckFailed,
            body: "Invoices for names such as “Zoë Ångström” or “東京オフィス” came out with empty boxes, because the PDF font has no glyphs past Latin-1. This embeds a fallback font and adds a test with ü, é, ñ, ß, 日本語, 한국어, العربية and emoji 🚀✅.\n\nThe font adds 1.8 MB to the worker image — worth it, I think.",
            createdAt: daysAgo(2.8), area: MockVocabulary.api.areas[2], labels: ["billing", "bug"]
        ))

        // Thirty reviewers requested.
        let author = MockCast.maxChen
        let manyPeople = (MockCast.corePeople + [MockCast.robinQuill] + MockCast.occasionalPeople).filter { $0.login != author.login }
        specs.append(MockPullRequestSpec(
            repository: web, number: 0, title: "Move every page to the new layout grid", author: author,
            scenario: .waitingOnReviewers,
            body: "Every page moves to the 12-column grid. Each team owns some of these pages, so everyone is asked. Look at your own pages and approve when they look right.",
            createdAt: daysAgo(5), area: MockVocabulary.web.areas[4], labels: ["ui"],
            reviewPlan: MockReviewPlan(pendingPeople: Array(manyPeople.prefix(28)), pendingTeams: MockCast.teams)
        ))

        // No reviewers at all.
        specs.append(MockPullRequestSpec(
            repository: infra, number: 0, title: "Rename the staging log bucket", author: MockCast.tomasReyes,
            scenario: .needsReview, createdAt: daysAgo(0.4),
            files: [MockFileSpec(path: "modules/logging/main.tf", additions: 4, deletions: 4)],
            reviewPlan: MockReviewPlan(), threads: []
        ))

        // Forty checks.
        var matrix: [MockCheckDefinition] = []
        for shard in 1...16 { matrix.append(MockCheckDefinition(name: "unit-tests (node \(shard <= 8 ? 20 : 22), shard \((shard - 1) % 8 + 1)/8)", isRequired: true, seconds: 90...200, failures: ["1 test failed"])) }
        for shard in 1...8 { matrix.append(MockCheckDefinition(name: "e2e-chrome (shard \(shard)/8)", isRequired: true, seconds: 200...330, failures: ["1 test failed"])) }
        for shard in 1...8 { matrix.append(MockCheckDefinition(name: "e2e-firefox (shard \(shard)/8)", isRequired: false, seconds: 200...340, failures: ["1 test failed"])) }
        matrix.append(contentsOf: MockVocabulary.api.checks.filter { ["lint", "typecheck", "build-docker", "codeql", "coverage", "license-scan", "secret-scan", "openapi-diff"].contains($0.name) })
        specs.append(MockPullRequestSpec(
            repository: api, number: 0, title: "Run the unit tests on Node 22 as well as Node 20", author: MockCast.samRivera,
            scenario: .readyToMerge, createdAt: daysAgo(7),
            files: [MockFileSpec(path: ".github/workflows/test.yaml", additions: 14, deletions: 3)], checks: matrix
        ))

        // No checks.
        specs.append(MockPullRequestSpec(
            repository: docs, number: 0, title: "Fix broken links in the changelog", author: MockCast.joLindqvist,
            scenario: .readyToMerge, createdAt: daysAgo(1.5),
            files: [MockFileSpec(path: "docs/changelog.md", additions: 6, deletions: 6)], checks: []
        ))

        // Base branch release/2026.11.
        specs.append(MockPullRequestSpec(
            repository: api, number: 0, title: "Backport: Retry token refresh on 503", author: MockCast.adaPark,
            scenario: .waitingOnReviewers,
            body: "Backport of the 503 retry to the November release, for the customers still on it.",
            createdAt: daysAgo(0.9), baseBranch: "release/2026.11", headBranch: "backport-retry-refresh-503-2026.11",
            files: [MockFileSpec(path: "auth/refresh-client.ts", additions: 31, deletions: 6)]
        ))
        specs.append(MockPullRequestSpec(
            repository: web, number: 0, title: "Backport: Fix flicker on sign-in redirect", author: MockCast.miraHolm,
            scenario: .readyToMerge, createdAt: daysAgo(0.5), baseBranch: "release/2026.11",
            headBranch: "backport-sign-in-flicker-2026.11",
            files: [MockFileSpec(path: "src/pages/sign-in/SignInRedirect.tsx", additions: 19, deletions: 11)]
        ))

        // Small pull requests written by agents, all under 50 changed lines.
        let agentWork: [(Repository, String, String, Int, Int, MockScenario)] = [
            (api, "Add a missing await in the audit log writer", "db/audit-log.ts", 1, 1, .readyToMerge),
            (api, "Remove an unused import from the billing export", "billing/export.ts", 0, 1, .waitingOnReviewers),
            (api, "Fix the typo in the rate limit error message", "lib/rate-limit.ts", 1, 1, .checksRunning(minutes: 2)),
            (api, "Add a test for empty webhook payloads", "webhooks/sender.test.ts", 24, 0, .requiredCheckFailed),
            (web, "Add alt text to the billing page illustration", "src/pages/billing/BillingPage.tsx", 2, 1, .readyToMerge),
            (web, "Drop the stale TODO in the session hook", "src/hooks/useSession.ts", 0, 3, .draft),
            (infra, "Correct the port in the staging API deployment", "k8s/staging/api-deployment.yaml", 2, 2, .waitingOnReviewers),
            (docs, "Fix a typo in the webhook guide", "docs/guides/webhooks.md", 1, 1, .readyToMerge),
        ]
        for (offset, work) in agentWork.enumerated() {
            specs.append(MockPullRequestSpec(
                repository: work.0, number: 0, title: work.1, author: MockCast.agents[offset % 2], scenario: work.5,
                body: "Small fix found while working on something else.\n\nOpened by an agent. A person reviews before merging.",
                createdAt: daysAgo(0.3 + Double(offset) * 1.7),
                files: [MockFileSpec(path: work.2, additions: work.3, deletions: work.4)], commitCount: 1
            ))
        }

        // Renamed, removed, added and binary files.
        specs.append(MockPullRequestSpec(
            repository: api, number: 0, title: "Move the email templates into their own folder", author: MockCast.miraHolm,
            scenario: .readyToMerge,
            body: "Email templates were spread over `lib/mail`. They now live in `mail/templates`, the legacy sender is gone, and the logo is checked in instead of fetched at send time.",
            createdAt: daysAgo(9),
            files: [
                MockFileSpec(path: "mail/templates/welcome.ts", changeKind: .renamed, previousPath: "lib/mail/welcome.ts"),
                MockFileSpec(path: "mail/templates/password-reset.ts", changeKind: .renamed, additions: 3, deletions: 2, previousPath: "lib/mail/password-reset.ts"),
                MockFileSpec(path: "lib/mail/legacy-sender.ts", changeKind: .removed, deletions: 64),
                MockFileSpec(path: "mail/index.ts", changeKind: .added, additions: 22, noNewlineAtEnd: true),
                MockFileSpec(path: "mail/assets/logo.png", changeKind: .added, isBinary: true),
                MockFileSpec(path: "lib/mail/index.ts", additions: 2, deletions: 9),
            ],
            commitCount: 4, threads: [.resolved, .outdatedResolved]
        ))

        // Outdated and resolved threads beside unresolved ones.
        specs.append(MockPullRequestSpec(
            repository: api, number: 0, title: "Cache account lookups in the users endpoint", author: MockCast.joLindqvist,
            scenario: .requiredCheckFailed, createdAt: daysAgo(3), area: MockVocabulary.api.areas[1],
            threads: [.unresolved, .outdated, .outdatedResolved, .resolved]
        ))

        // The viewer's own pull requests, with threads waiting on the viewer.
        specs.append(MockPullRequestSpec(
            repository: api, number: 0, title: "Add audit events for session revocation", author: MockCast.robinQuill,
            scenario: .unresolvedThreads(count: 1), createdAt: daysAgo(2), area: MockVocabulary.api.areas[0],
            threads: [.needsViewer, .unresolved, .resolved]
        ))
        specs.append(MockPullRequestSpec(
            repository: infra, number: 0, title: "Tighten access to the deploy role", author: MockCast.robinQuill,
            scenario: .changesRequested, createdAt: daysAgo(4), area: MockVocabulary.infra.areas[4],
            threads: [.needsViewer, .resolved]
        ))
        // A thread the viewer started, where the author has answered.
        specs.append(MockPullRequestSpec(
            repository: web, number: 0, title: "Retry failed CSV exports on the reports page", author: MockCast.samRivera,
            scenario: .changesRequested, createdAt: daysAgo(3.4), area: MockVocabulary.web.areas[2],
            reviewPlan: MockReviewPlan(changesRequestedBy: [MockCast.robinQuill]),
            threads: [.needsViewer, .unresolved]
        ))

        // The merge queue, at several positions.
        let queued: [(Repository, String, Person, Int)] = [
            (api, "Return 404 instead of 500 for unknown webhook ids", MockCast.adaPark, 1),
            (api, "Index audit log rows by account", MockCast.maxChen, 2),
            (api, "Add a timeout to the invoice worker", MockCast.lenaOkafor, 3),
            (api, "Log request ids in the search endpoint", MockCast.samRivera, 4),
            (web, "Fix dark mode colors in the nav bar", MockCast.miraHolm, 1),
            (web, "Add a loading state to the invoice list", MockCast.joLindqvist, 2),
        ]
        for (offset, entry) in queued.enumerated() {
            specs.append(MockPullRequestSpec(
                repository: entry.0, number: 0, title: entry.1, author: entry.2, scenario: .mergeQueue(position: entry.3),
                createdAt: daysAgo(1 + Double(offset) * 0.6)
            ))
        }

        return specs
    }

    static let richBody = """
        ## What changed

        The reports table header now sticks to the top while scrolling, and the column menu moved into the header.

        | Column | Before | After |
        |---|---|---|
        | Date | Fixed width | Fits content |
        | Amount | Left aligned | Right aligned |
        | Status | Text | Badge |

        ![The reports table with the sticky header](https://assets.acme.example/pull-requests/reports-header.png)

        - [x] Sticky header
        - [x] Column menu in the header
        - [ ] Check with a screen reader

        <details>
        <summary>Why not a CSS-only fix</summary>

        `position: sticky` does not work inside the scroll container the table uses today, so the header is drawn by `ReportsTableHeader` instead.

        </details>

        ```tsx
        <ReportsTable columns={columns} rows={rows} stickyHeader />
        ```
        """

    // MARK: Helpers

    private static func makeTitle(profile: MockRepositoryProfile, area: MockArea, rng: inout SeededGenerator, used: inout Set<String>) -> String {
        for _ in 0..<40 {
            let title = "\(rng.pick(profile.actions)) \(rng.pick(area.subjects))"
            if !used.contains(title) {
                used.insert(title)
                return title
            }
        }
        var number = 2
        let base = "\(rng.pick(profile.actions)) \(rng.pick(area.subjects))"
        while used.contains("\(base), part \(number)") { number += 1 }
        let title = "\(base), part \(number)"
        used.insert(title)
        return title
    }

    private static func createdAt(scenario: MockScenario, now: Date, rng: inout SeededGenerator) -> Date {
        let hour = 3600, day = 86_400
        switch scenario {
        case .merged, .closed: return now.addingTimeInterval(-Double(rng.int(day...(30 * day - hour))))
        default: return now.addingTimeInterval(-Double(rng.int((2 * hour)...(30 * day - hour))))
        }
    }

    /// Numbers go up with creation time within each repository, skipping hand-written ones.
    private static func assignNumbers(_ specs: [MockPullRequestSpec], reserved: Set<PullRequestReference>) -> [MockPullRequestSpec] {
        var rng = SeededGenerator(seed: "mock world numbers")
        var result = specs
        for repository in MockCast.repositories {
            let indices = result.indices
                .filter { result[$0].repository == repository }
                .sorted { (result[$0].createdAt ?? .distantPast, $0) < (result[$1].createdAt ?? .distantPast, $1) }
            var number = MockVocabulary.profile(for: repository).firstNumber
            for index in indices {
                number += rng.int(1...2)
                while reserved.contains(PullRequestReference(repository: repository, number: number)) { number += 1 }
                result[index].number = number
            }
        }
        return result
    }
}
