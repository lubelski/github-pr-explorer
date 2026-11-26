import Foundation

/// The pull requests the designs' lists show by name, besides #4826. Their facts are chosen
/// by hand; patches, times and the rest come from the factory.
enum MockHandWritten {
    static func specs() -> [MockPullRequestSpec] {
        let api = MockCast.api, web = MockCast.web, infra = MockCast.infra, docs = MockCast.docs
        let ada = MockCast.adaPark, sam = MockCast.samRivera, jo = MockCast.joLindqvist, max = MockCast.maxChen
        let lena = MockCast.lenaOkafor, tomas = MockCast.tomasReyes, mira = MockCast.miraHolm, kai = MockCast.kaiDuarte
        let viewer = MockCast.robinQuill
        let security = MockCast.securityTeam
        func at(_ text: String) -> Date { MockWorld.date(text) }
        func modified(_ path: String, _ additions: Int, _ deletions: Int) -> MockFileSpec {
            MockFileSpec(path: path, additions: additions, deletions: deletions)
        }
        func added(_ path: String, _ additions: Int) -> MockFileSpec {
            MockFileSpec(path: path, changeKind: .added, additions: additions)
        }

        return [
            MockPullRequestSpec(
                repository: api, number: 4831, title: "Rotate signing keys for session tokens", author: ada,
                scenario: .checksRunning(minutes: 6),
                body: """
                    Session tokens are signed with one key that has not changed since launch. This adds a key ring: new tokens are signed with the newest key, and tokens signed with the previous key still verify for 24 hours.

                    - [x] Key ring with a 24 hour overlap
                    - [x] Tests for old, current and unknown keys
                    - [ ] Runbook entry for rotating by hand
                    """,
                createdAt: at("2026-11-25T10:05:00Z"),
                files: [modified("auth/tokens.ts", 48, 12), added("auth/keys.ts", 36), modified("auth/tokens.test.ts", 40, 2), added("config/keys.example.json", 6)],
                commitCount: 4, pushCount: 2, labels: ["auth", "security"],
                reviewPlan: MockReviewPlan(pendingTeams: [security]), threads: []
            ),
            MockPullRequestSpec(
                repository: api, number: 4819, title: "Log failed refresh attempts with request id", author: jo,
                scenario: .readyToMerge,
                body: "When a session refresh fails we log only the session id, so failures cannot be matched to the request that caused them. This adds the request id to the log line and counts failures by reason.\n\nTested locally by expiring a session by hand.",
                createdAt: at("2026-11-24T13:40:00Z"),
                files: [modified("auth/session.ts", 14, 3), modified("lib/logger.ts", 6, 1), modified("auth/session.test.ts", 22, 0)],
                commitCount: 2, labels: ["auth"],
                reviewPlan: MockReviewPlan(approvedBy: [lena, ada]), threads: [.resolved]
            ),
            MockPullRequestSpec(
                repository: api, number: 4790, title: "Retry token refresh on 503", author: ada,
                scenario: .waitingOnReviewers,
                body: "The identity provider answers 503 for a few seconds during its deploys, and each one signs people out. This retries the refresh up to three times with backoff before giving up.\n\n- [x] Backoff of 200, 400 and 800 ms\n- [x] Tests for retry and give-up",
                createdAt: at("2026-11-21T09:30:00Z"),
                files: [modified("auth/refresh-client.ts", 31, 6), added("auth/refresh-client.test.ts", 44)],
                commitCount: 3, labels: ["auth", "bug"],
                reviewPlan: MockReviewPlan(approvedBy: [sam], pendingTeams: [security]), threads: [.resolved]
            ),
            MockPullRequestSpec(
                repository: api, number: 4774, title: "Remove the legacy cookie fallback", author: max,
                scenario: .draft,
                body: "The legacy `acme_sid` cookie was replaced a year ago, but sign-in still reads it as a fallback. This removes the fallback and its tests.\n\nDraft until the web app stops writing the old cookie.",
                createdAt: at("2026-11-19T15:00:00Z"),
                files: [modified("auth/cookies.ts", 4, 58), modified("auth/cookies.test.ts", 2, 31), modified("docs/auth.md", 1, 6)],
                commitCount: 2, labels: ["auth", "refactor"],
                reviewPlan: MockReviewPlan(changesRequestedBy: [ada], pendingTeams: [security]), threads: [.unresolved]
            ),
            MockPullRequestSpec(
                repository: api, number: 4768, title: "Add a rate limit to the login route", author: sam,
                scenario: .waitingOnReviewers,
                body: "Login has no rate limit of its own, only the global one. This adds 10 attempts a minute per account and per address, and answers 429 with a `Retry-After` header.\n\nTested with the load test script against the preview.",
                createdAt: at("2026-11-18T11:20:00Z"),
                files: [modified("api/routes/login.ts", 18, 2), modified("lib/rate-limit.ts", 27, 4), added("api/routes/login.test.ts", 39)],
                commitCount: 3, labels: ["security", "feature"],
                reviewPlan: MockReviewPlan(pendingPeople: [viewer]), threads: []
            ),
            MockPullRequestSpec(
                repository: api, number: 4835, title: "Rotate the signing key for session cookies", author: lena,
                scenario: .checksRunning(minutes: 3),
                body: "Cookie signatures still use the key from the original launch. This reads the cookie key from the key ring added for tokens, so both rotate together.",
                createdAt: at("2026-11-25T16:40:00Z"),
                files: [modified("auth/cookies.ts", 22, 9), modified("config/production.ts", 3, 1)],
                commitCount: 2, pushCount: 2, labels: ["auth", "security"],
                reviewPlan: MockReviewPlan(pendingTeams: [security]), threads: []
            ),
            MockPullRequestSpec(
                repository: web, number: 1301, title: "Fix flicker on sign-in redirect", author: mira,
                scenario: .checksRunning(minutes: 7),
                body: "After signing in, the account page drew once with the signed-out layout before the session loaded. This waits for the session before the first render.",
                createdAt: at("2026-11-25T08:15:00Z"),
                files: [modified("src/pages/sign-in/SignInRedirect.tsx", 19, 11), modified("src/hooks/useSession.ts", 7, 3)],
                commitCount: 3, pushCount: 2, labels: ["auth", "ui", "bug"],
                reviewPlan: MockReviewPlan(approvedBy: [max]), threads: [.resolved]
            ),
            MockPullRequestSpec(
                repository: web, number: 1290, title: "Add token expiry banner to the account page", author: sam,
                scenario: .changesRequested,
                body: "Shows a banner five minutes before the session ends, with a button to stay signed in.\n\n- [x] Banner and button\n- [ ] Copy reviewed",
                createdAt: at("2026-11-22T10:00:00Z"),
                files: [added("src/pages/account/SessionBanner.tsx", 54), modified("src/pages/account/AccountPage.tsx", 8, 2), added("src/pages/account/SessionBanner.test.tsx", 41)],
                commitCount: 4, labels: ["ui", "feature"],
                reviewPlan: MockReviewPlan(changesRequestedBy: [mira]), threads: [.unresolved, .unresolved, .resolved]
            ),
            MockPullRequestSpec(
                repository: web, number: 1172, title: "Add an empty state to the billing page", author: lena,
                scenario: .readyToMerge,
                body: "New accounts see an empty table on the billing page. This shows an illustration and a link to add a payment method instead.",
                createdAt: at("2026-11-12T14:00:00Z"),
                files: [modified("src/pages/billing/BillingPage.tsx", 21, 4), added("src/pages/billing/EmptyBilling.tsx", 33),
                        MockFileSpec(path: "public/images/empty-billing.png", changeKind: .added, isBinary: true)],
                commitCount: 2, labels: ["billing", "ui"],
                reviewPlan: MockReviewPlan(approvedBy: [mira]), threads: []
            ),
            MockPullRequestSpec(
                repository: web, number: 1180, title: "Replace the date picker on the reports page", author: kai,
                scenario: .unresolvedThreads(count: 2),
                body: "The old date picker ignores the week start setting and cannot be used with a keyboard. This swaps in the shared one from the design system.",
                createdAt: at("2026-11-14T09:00:00Z"),
                files: [modified("src/components/DatePicker.tsx", 88, 120), modified("src/pages/reports/ReportsPage.tsx", 6, 9), modified("package.json", 1, 1)],
                commitCount: 5, labels: ["ui", "accessibility"],
                reviewPlan: MockReviewPlan(approvedBy: [max]), threads: [.unresolved, .unresolved, .resolved]
            ),
            MockPullRequestSpec(
                repository: infra, number: 318, title: "Raise the database connection pool limit", author: tomas,
                scenario: .checksRunning(minutes: 12),
                body: "The API runs out of database connections at the Monday peak. This raises `max_connections` from 200 to 400 and the pool size to match.",
                createdAt: at("2026-11-25T11:00:00Z"),
                files: [modified("modules/database/main.tf", 3, 3), modified("modules/database/variables.tf", 5, 1)],
                commitCount: 2, pushCount: 2, labels: ["infra", "performance"],
                reviewPlan: MockReviewPlan(approvedBy: [kai]), threads: []
            ),
            MockPullRequestSpec(
                repository: infra, number: 612, title: "Tighten IAM policy for the auth service", author: kai,
                scenario: .waitingOnReviewers,
                body: "The auth service role can read every bucket. This limits it to the session and key buckets it uses.\n\nPlan output shows no other changes.",
                createdAt: at("2026-11-24T16:30:00Z"),
                files: [modified("iam/auth-service.tf", 24, 31)],
                commitCount: 2, labels: ["security", "infra"],
                reviewPlan: MockReviewPlan(pendingTeams: [security]), threads: []
            ),
            MockPullRequestSpec(
                repository: docs, number: 92, title: "Document the webhook retry schedule", author: jo,
                scenario: .readyToMerge,
                body: "Customers keep asking when a failed webhook is retried. This adds the schedule, with an example of the headers on a retry.",
                createdAt: at("2026-11-20T12:00:00Z"),
                files: [modified("docs/guides/webhooks.md", 38, 4)],
                commitCount: 1, labels: ["docs", "webhooks"],
                reviewPlan: MockReviewPlan(approvedBy: [max]), threads: []
            ),
            MockPullRequestSpec(
                repository: docs, number: 233, title: "Document the session lifetime settings", author: sam,
                scenario: .waitingOnReviewers,
                body: "Explains how long a session lasts, when it is extended, and which settings an admin can change.",
                createdAt: at("2026-11-24T10:00:00Z"),
                files: [added("docs/admin/sessions.md", 46), modified("docs/admin/index.md", 1, 0)],
                commitCount: 2, labels: ["docs"],
                reviewPlan: MockReviewPlan(pendingPeople: [max]), threads: []
            ),
        ]
    }
}
