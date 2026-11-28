import Foundation

/// A check a repository runs, with how long it takes and how it fails.
struct MockCheckDefinition {
    var name: String
    var isRequired: Bool
    var seconds: ClosedRange<Int>
    var failures: [String]
    /// Slow checks are the ones left running or queued.
    var isSlow: Bool { seconds.upperBound >= 240 }
}

/// A part of a repository: the files it holds and the phrases titles use for it.
struct MockArea {
    var name: String
    var subjects: [String]
    var files: [String]
    var directory: String
    var labels: [String]
    var problems: [String]
}

/// What the generator knows about one repository.
struct MockRepositoryProfile {
    var repository: Repository
    var areas: [MockArea]
    var actions: [String]
    var checks: [MockCheckDefinition]
    var hasPreviews: Bool
    var hasCoverage: Bool
    var newFileStems: [String]
    var fileExtension: String
    var firstNumber: Int
    /// Branch protection asks for resolved conversations before merging.
    var requiresResolvedThreads: Bool
    /// Branch protection asks the branch to be up to date with its base.
    var requiresUpToDate: Bool
}

enum MockVocabulary {
    static func profile(for repository: Repository) -> MockRepositoryProfile {
        switch repository {
        case MockCast.api: api
        case MockCast.web: web
        case MockCast.infra: infra
        case MockCast.globexBilling: globexBilling
        default: docs
        }
    }

    static let api = MockRepositoryProfile(
        repository: MockCast.api,
        areas: [
            MockArea(name: "auth", subjects: ["the token signer", "the session store", "the sign-in flow", "the password reset flow"],
                     files: ["auth/session.ts", "auth/tokens.ts", "auth/sign-in.ts", "auth/password-reset.ts", "auth/types.ts", "auth/session.test.ts"],
                     directory: "auth", labels: ["auth", "security"],
                     problems: ["Sessions end while a user is active", "Password reset links expire too early", "Token signing is slow under load"]),
            MockArea(name: "routes", subjects: ["the search endpoint", "the user settings route", "the account route", "the users endpoint"],
                     files: ["api/routes/search.ts", "api/routes/users.ts", "api/routes/account.ts", "api/routes/settings.ts", "api/routes/search.test.ts"],
                     directory: "api/routes", labels: ["feature"],
                     problems: ["Search returns stale results", "The settings route returns 500 on empty input", "Users endpoint is slow for large teams"]),
            MockArea(name: "billing", subjects: ["the invoice worker", "the billing export", "the tax calculation", "invoice PDFs"],
                     files: ["billing/invoices.ts", "billing/export.ts", "billing/pdf.ts", "billing/tax.ts", "billing/invoices.test.ts"],
                     directory: "billing", labels: ["billing"],
                     problems: ["Invoice export stops halfway", "Tax is rounded twice on credit notes", "Invoice PDFs drop accented names"]),
            MockArea(name: "webhooks", subjects: ["the webhook sender", "webhook signatures", "the delivery queue"],
                     files: ["webhooks/sender.ts", "webhooks/retry.ts", "webhooks/signature.ts", "webhooks/sender.test.ts"],
                     directory: "webhooks", labels: ["webhooks"],
                     problems: ["Webhook deliveries are sent twice", "Signature checks fail after key rotation", "The delivery queue backs up on Mondays"]),
            MockArea(name: "database", subjects: ["the accounts table", "the connection pool", "the audit log", "slow queries"],
                     files: ["db/index.ts", "db/accounts.ts", "db/audit-log.ts", "db/migrations/2026_11_add_audit_index.sql"],
                     directory: "db", labels: ["performance"],
                     problems: ["Audit log queries time out", "Connection pool runs dry at peak", "Accounts table scan on every sign-in"]),
            MockArea(name: "platform", subjects: ["the rate limiter", "the logger", "the metrics client", "error handling"],
                     files: ["lib/rate-limit.ts", "lib/logger.ts", "lib/metrics.ts", "lib/errors.ts", "lib/clock.ts"],
                     directory: "lib", labels: ["refactor"],
                     problems: ["Logs are missing request ids", "Rate limiter counts retries", "Metrics client drops tags"]),
        ],
        actions: ["Add a timeout to", "Log request ids in", "Remove dead code from", "Add tests for", "Split up", "Tidy error handling in",
                  "Cache lookups in", "Speed up", "Add metrics to", "Handle empty results in", "Validate input in", "Fix a race in",
                  "Retry transient errors in", "Type the responses of", "Move config out of", "Document"],
        checks: [
            MockCheckDefinition(name: "lint", isRequired: true, seconds: 40...95, failures: ["3 problems in api/routes/search.ts", "Unused import in billing/export.ts"]),
            MockCheckDefinition(name: "typecheck", isRequired: true, seconds: 60...140, failures: ["TS2345 in webhooks/sender.ts", "TS2322 in auth/tokens.ts"]),
            MockCheckDefinition(name: "unit-tests", isRequired: true, seconds: 150...260, failures: ["1 test failed", "4 tests failed"]),
            MockCheckDefinition(name: "integration-tests", isRequired: true, seconds: 300...420, failures: ["Timed out after 15 min", "2 tests failed"]),
            MockCheckDefinition(name: "e2e-chrome", isRequired: true, seconds: 330...420, failures: ["2 tests failed", "Sign-in spec failed"]),
            MockCheckDefinition(name: "e2e-firefox", isRequired: false, seconds: 330...440, failures: ["1 test failed"]),
            MockCheckDefinition(name: "build-docker", isRequired: true, seconds: 250...380, failures: ["COPY failed: file not found"]),
            MockCheckDefinition(name: "migrations-check", isRequired: false, seconds: 30...70, failures: ["Migration is not reversible"]),
            MockCheckDefinition(name: "coverage", isRequired: false, seconds: 20...45, failures: ["Coverage fell by 1.2%"]),
            MockCheckDefinition(name: "codeql", isRequired: false, seconds: 200...300, failures: ["1 new alert"]),
            MockCheckDefinition(name: "license-scan", isRequired: false, seconds: 20...40, failures: ["Unknown license in a new package"]),
            MockCheckDefinition(name: "secret-scan", isRequired: false, seconds: 15...30, failures: ["Possible key in a fixture"]),
            MockCheckDefinition(name: "openapi-diff", isRequired: false, seconds: 20...40, failures: ["Breaking change to GET /users"]),
            MockCheckDefinition(name: "deploy-preview", isRequired: false, seconds: 240...360, failures: ["Preview failed to start"]),
        ],
        hasPreviews: true, hasCoverage: true,
        newFileStems: ["limits", "backoff", "format", "schema", "errors", "types", "constants", "cache", "queue"],
        fileExtension: "ts", firstNumber: 4560, requiresResolvedThreads: true, requiresUpToDate: true
    )

    static let web = MockRepositoryProfile(
        repository: MockCast.web,
        areas: [
            MockArea(name: "account", subjects: ["the account page", "the session banner", "the profile form"],
                     files: ["src/pages/account/AccountPage.tsx", "src/pages/account/ProfileForm.tsx", "src/pages/account/SessionBanner.tsx"],
                     directory: "src/pages/account", labels: ["ui"],
                     problems: ["Account page jumps while loading", "Profile form loses input on error"]),
            MockArea(name: "billing", subjects: ["the billing page", "the invoice list", "the plan picker"],
                     files: ["src/pages/billing/BillingPage.tsx", "src/pages/billing/InvoiceList.tsx", "src/pages/billing/PlanPicker.tsx"],
                     directory: "src/pages/billing", labels: ["billing", "ui"],
                     problems: ["Invoice list is empty for new accounts", "Plan picker hides the annual price"]),
            MockArea(name: "reports", subjects: ["the reports table", "the reports page", "the date picker", "CSV export"],
                     files: ["src/pages/reports/ReportsPage.tsx", "src/pages/reports/ReportsTable.tsx", "src/components/DatePicker.tsx", "src/pages/reports/exportCsv.ts"],
                     directory: "src/pages/reports", labels: ["ui"],
                     problems: ["Reports table is slow with 5,000 rows", "Date picker ignores the week start setting"]),
            MockArea(name: "sign-in", subjects: ["the sign-in form", "the session hook", "the sign-in redirect"],
                     files: ["src/pages/sign-in/SignInForm.tsx", "src/pages/sign-in/SignInRedirect.tsx", "src/hooks/useSession.ts"],
                     directory: "src/pages/sign-in", labels: ["auth", "ui"],
                     problems: ["Sign-in redirect flickers", "Session hook refetches on every render"]),
            MockArea(name: "components", subjects: ["the toast queue", "the nav bar", "the dialog component", "the button styles"],
                     files: ["src/components/Toast.tsx", "src/components/NavBar.tsx", "src/components/Dialog.tsx", "src/components/Button.tsx", "src/styles/tokens.css"],
                     directory: "src/components", labels: ["ui", "accessibility"],
                     problems: ["Toasts stack off screen", "Dialog traps focus after closing"]),
            MockArea(name: "settings", subjects: ["the settings dialog", "notification settings", "the API keys page"],
                     files: ["src/pages/settings/SettingsDialog.tsx", "src/pages/settings/NotificationSettings.tsx", "src/pages/settings/ApiKeys.tsx"],
                     directory: "src/pages/settings", labels: ["ui"],
                     problems: ["Notification settings do not save", "API keys page shows revoked keys"]),
        ],
        actions: ["Fix layout shift in", "Add a loading state to", "Add an empty state to", "Make keyboard focus visible in", "Fix flicker in",
                  "Add tests for", "Split up", "Memoize rows in", "Fix dark mode colors in", "Add aria labels to", "Remove the old styles from",
                  "Lazy-load", "Add error messages to", "Tidy up"],
        checks: [
            MockCheckDefinition(name: "lint", isRequired: true, seconds: 30...80, failures: ["2 problems in src/components/Dialog.tsx"]),
            MockCheckDefinition(name: "typecheck", isRequired: true, seconds: 50...120, failures: ["TS2339 in src/hooks/useSession.ts"]),
            MockCheckDefinition(name: "unit-tests", isRequired: true, seconds: 120...240, failures: ["3 tests failed", "Snapshot mismatch in NavBar"]),
            MockCheckDefinition(name: "e2e-chrome", isRequired: true, seconds: 300...420, failures: ["2 tests failed", "Checkout spec timed out"]),
            MockCheckDefinition(name: "e2e-safari", isRequired: false, seconds: 330...450, failures: ["1 test failed"]),
            MockCheckDefinition(name: "visual-regression", isRequired: false, seconds: 240...330, failures: ["12 screenshots changed"]),
            MockCheckDefinition(name: "bundle-size", isRequired: false, seconds: 40...90, failures: ["Main bundle grew by 38 KB"]),
            MockCheckDefinition(name: "build", isRequired: true, seconds: 120...200, failures: ["Module not found: ./EmptyState"]),
            MockCheckDefinition(name: "deploy-preview", isRequired: false, seconds: 200...300, failures: ["Preview failed to start"]),
            MockCheckDefinition(name: "codeql", isRequired: false, seconds: 180...260, failures: ["1 new alert"]),
            MockCheckDefinition(name: "license-scan", isRequired: false, seconds: 20...40, failures: ["Unknown license in a new package"]),
        ],
        hasPreviews: true, hasCoverage: true,
        newFileStems: ["EmptyState", "LoadingRow", "useDebounce", "formatMoney", "ErrorBanner", "Skeleton"],
        fileExtension: "tsx", firstNumber: 1100, requiresResolvedThreads: true, requiresUpToDate: false
    )

    static let infra = MockRepositoryProfile(
        repository: MockCast.infra,
        areas: [
            MockArea(name: "database", subjects: ["the database module", "the read replicas", "the connection pool"],
                     files: ["modules/database/main.tf", "modules/database/variables.tf", "modules/database/outputs.tf"],
                     directory: "modules/database", labels: ["infra"],
                     problems: ["Database runs out of connections at peak", "Read replica lags by minutes"]),
            MockArea(name: "cluster", subjects: ["the staging cluster", "the API deployment", "the worker deployment"],
                     files: ["k8s/staging/api-deployment.yaml", "k8s/production/api-deployment.yaml", "k8s/production/worker-deployment.yaml"],
                     directory: "k8s", labels: ["infra"],
                     problems: ["API pods restart under load", "Workers are not spread across zones"]),
            MockArea(name: "ci", subjects: ["the CI runners", "the runner autoscaler"],
                     files: ["modules/ci-runners/main.tf", "modules/ci-runners/variables.tf"],
                     directory: "modules/ci-runners", labels: ["infra", "performance"],
                     problems: ["CI runners queue for 20 minutes in the morning"]),
            MockArea(name: "dns", subjects: ["the DNS module", "preview domains"],
                     files: ["modules/dns/main.tf", "modules/dns/records.tf"],
                     directory: "modules/dns", labels: ["infra"],
                     problems: ["Preview domains are not cleaned up"]),
            MockArea(name: "iam", subjects: ["the auth service role", "the deploy role"],
                     files: ["iam/auth-service.tf", "iam/deploy.tf", "iam/policies.tf"],
                     directory: "iam", labels: ["security"],
                     problems: ["The auth service can read every bucket"]),
            MockArea(name: "monitoring", subjects: ["the alerting rules", "the API dashboard", "the backup job"],
                     files: ["monitoring/alerts.yaml", "monitoring/dashboards/api.json", "modules/backups/main.tf"],
                     directory: "monitoring", labels: ["infra"],
                     problems: ["Nobody is paged when backups fail", "The API dashboard hides 5xx spikes"]),
        ],
        actions: ["Raise memory limits for", "Pin provider versions in", "Add alerts for", "Tag resources in", "Move secrets out of",
                  "Add a dashboard for", "Tighten access to", "Enable encryption for", "Lower log retention for", "Add autoscaling to"],
        checks: [
            MockCheckDefinition(name: "terraform-fmt", isRequired: true, seconds: 10...25, failures: ["modules/database/main.tf is not formatted"]),
            MockCheckDefinition(name: "terraform-validate", isRequired: true, seconds: 30...70, failures: ["Unsupported argument \"max_connections\""]),
            MockCheckDefinition(name: "plan-staging", isRequired: true, seconds: 180...300, failures: ["Plan would destroy 2 resources"]),
            MockCheckDefinition(name: "plan-production", isRequired: false, seconds: 240...360, failures: ["Plan would replace aws_db_instance.main"]),
            MockCheckDefinition(name: "tflint", isRequired: false, seconds: 20...45, failures: ["3 warnings in modules/dns"]),
            MockCheckDefinition(name: "checkov", isRequired: false, seconds: 40...90, failures: ["CKV_AWS_18: bucket logging is off"]),
            MockCheckDefinition(name: "kubeconform", isRequired: false, seconds: 10...30, failures: ["Unknown field \"replica\""]),
        ],
        hasPreviews: false, hasCoverage: false,
        newFileStems: ["locals", "alarms", "outputs", "versions"],
        fileExtension: "tf", firstNumber: 250, requiresResolvedThreads: false, requiresUpToDate: true
    )

    static let docs = MockRepositoryProfile(
        repository: MockCast.docs,
        areas: [
            MockArea(name: "reference", subjects: ["the sessions API reference", "the webhooks API reference", "the invoices API reference"],
                     files: ["docs/api/sessions.md", "docs/api/webhooks.md", "docs/api/invoices.md"],
                     directory: "docs/api", labels: ["docs"],
                     problems: ["The sessions reference lists a removed field"]),
            MockArea(name: "guides", subjects: ["the quickstart guide", "the webhook guide", "the sign-in guide"],
                     files: ["docs/guides/quickstart.md", "docs/guides/webhooks.md", "docs/guides/sign-in.md"],
                     directory: "docs/guides", labels: ["docs"],
                     problems: ["Quickstart uses an old API key format"]),
            MockArea(name: "admin", subjects: ["the single sign-on page", "the audit log page", "the admin overview"],
                     files: ["docs/admin/sso.md", "docs/admin/audit-log.md", "docs/admin/index.md"],
                     directory: "docs/admin", labels: ["docs"],
                     problems: ["Single sign-on setup skips the callback URL"]),
            MockArea(name: "changelog", subjects: ["the changelog", "the release notes"],
                     files: ["docs/changelog.md", "docs/releases/2026-11.md"],
                     directory: "docs", labels: ["docs"],
                     problems: ["Release notes miss the November changes"]),
        ],
        actions: ["Fix typos in", "Add examples to", "Update screenshots in", "Clarify", "Add a troubleshooting section to",
                  "Fix broken links in", "Reword", "Shorten"],
        checks: [
            MockCheckDefinition(name: "markdown-lint", isRequired: true, seconds: 10...30, failures: ["MD013 line length in docs/guides/webhooks.md"]),
            MockCheckDefinition(name: "link-check", isRequired: false, seconds: 40...120, failures: ["2 broken links"]),
            MockCheckDefinition(name: "build-site", isRequired: true, seconds: 60...150, failures: ["Unknown shortcode in docs/api/sessions.md"]),
            MockCheckDefinition(name: "spell-check", isRequired: false, seconds: 10...25, failures: ["\"recieve\" in docs/guides/quickstart.md"]),
        ],
        hasPreviews: false, hasCoverage: false,
        newFileStems: ["troubleshooting", "faq", "limits", "migration"],
        fileExtension: "md", firstNumber: 40, requiresResolvedThreads: false, requiresUpToDate: false
    )

    /// The second organization's billing service (MAC-111).
    static let globexBilling = MockRepositoryProfile(
        repository: MockCast.globexBilling,
        areas: [
            MockArea(name: "invoices", subjects: ["invoice totals", "the invoice renderer", "credit notes"],
                     files: ["src/invoices/totals.go", "src/invoices/render.go", "src/invoices/totals_test.go"],
                     directory: "src/invoices", labels: ["billing"],
                     problems: ["Invoice totals are off by a cent on long invoices"]),
            MockArea(name: "payments", subjects: ["the card charger", "the dunning schedule", "failed payment emails"],
                     files: ["src/payments/charger.go", "src/payments/dunning.go", "src/payments/charger_test.go"],
                     directory: "src/payments", labels: ["billing"],
                     problems: ["Cards are charged twice after a timeout"]),
            MockArea(name: "ledger", subjects: ["the ledger", "ledger exports"],
                     files: ["src/ledger/entry.go", "src/ledger/export.go", "src/ledger/entry_test.go"],
                     directory: "src/ledger", labels: ["billing"],
                     problems: ["Ledger exports lose the currency"]),
        ],
        actions: ["Simplify", "Add tests for", "Speed up", "Fix rounding in"],
        checks: [
            MockCheckDefinition(name: "go-test", isRequired: true, seconds: 60...180, failures: ["TestChargeRetries timed out"]),
            MockCheckDefinition(name: "golangci-lint", isRequired: true, seconds: 20...60, failures: ["errcheck in src/payments/charger.go"]),
        ],
        hasPreviews: false, hasCoverage: false,
        newFileStems: ["currency", "budget"],
        fileExtension: "go", firstNumber: 200, requiresResolvedThreads: false, requiresUpToDate: false
    )

    // MARK: Words for bodies, comments and commits

    static let motivations = [
        "This came up twice in on-call this month.",
        "Support asked about this on three tickets last week.",
        "It was flagged in the last incident review.",
        "The current behavior surprises new people on the team.",
        "This is the follow-up promised in the last release.",
        "Profiling showed it on the hot path.",
        "A customer on the enterprise plan reported it.",
    ]

    static let approaches = [
        "The change is small and keeps the public interface the same.",
        "Each step is its own commit, so it reads best commit by commit.",
        "Most of the diff is tests. The fix itself is a few lines.",
        "It adds a flag so it can be turned off without a deploy.",
        "Nothing changes for callers that do not opt in.",
        "The old path stays for one release, behind a warning.",
    ]

    static let testingNotes = [
        "Tested locally and on the preview.",
        "Covered by new unit tests.",
        "Ran the affected end-to-end specs twice.",
        "Checked by hand with a large account.",
    ]

    static let commitFollowUps = [
        "Add tests", "Address review comments", "Fix lint", "Rename the helper", "Handle the empty case",
        "Update snapshots", "Tidy up", "Fix typecheck after rebase", "Split into smaller functions",
        "Add a log line for failures", "Remove debug output", "Use the shared clock", "Simplify the error path",
    ]

    static let threadOpeners = [
        "Can this be null here?",
        "Nit: this name could be clearer.",
        "Should this have a test?",
        "Is this safe to run twice?",
        "This allocates on every call. Can it move out of the loop?",
        "Do we need the log line at info level?",
        "What happens when the list is empty?",
        "Could this use the shared helper instead?",
        "This changes the error code callers see. Is that intended?",
        "Worth a comment on why this is needed.",
    ]

    static let authorReplies = [
        "Good catch, fixed in the next push.",
        "I'd rather leave this for a follow-up.",
        "Yes, it is covered by the test below.",
        "Renamed.",
        "It can't be null here, the caller checks first.",
        "Done, and added a test.",
    ]

    static let conversationComments = [
        "Thanks for picking this up.",
        "Is this needed for the release, or can it wait a week?",
        "I tried the preview and it looks right to me.",
        "Can we split the refactor from the fix?",
        "Holding off on approving until the flaky test is sorted.",
        "Linking the incident doc for context.",
    ]

    static let reviewBodies = [
        "Looks good.",
        "A couple of nits, nothing blocking.",
        "Thanks, this reads much better.",
        "",
        "",
    ]

    static let changeRequestBodies = [
        "This needs a test for the failure path before it goes in.",
        "The new error code breaks the web app. Please keep the old one.",
        "Please split the migration into its own pull request.",
    ]
}
