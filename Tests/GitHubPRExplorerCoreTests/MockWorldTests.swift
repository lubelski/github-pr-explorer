import Foundation
import Testing
@testable import GitHubPRExplorerCore

@Suite struct MockWorldTests {
    let world = MockWorld.standard
    var open: [PullRequest] { world.pullRequests.filter { $0.state == .open } }

    func status(_ pr: PullRequest) -> StatusSentence {
        pr.statusSentence(for: world.viewer, now: world.now)
    }

    // MARK: Size and shape

    @Test func nowIsFixed() {
        #expect(world.now == MockWorld.date("2026-11-25T18:00:00Z"))
    }

    @Test func exactly218Open() {
        #expect(open.count == 218)
    }

    @Test func about60MergedAnd20Closed() {
        #expect(world.pullRequests.count { $0.state == .merged } == 60)
        #expect(world.pullRequests.count { $0.state == .closed } == 20)
    }

    @Test func everyRepositoryHasOpenPullRequests() {
        for repository in MockCast.repositories {
            #expect(open.count { $0.repository == repository } >= 20, "\(repository)")
        }
    }

    @Test func idsAndReferencesAreUnique() {
        #expect(Set(world.pullRequests.map(\.id)).count == world.pullRequests.count)
        #expect(Set(world.pullRequests.map(\.reference)).count == world.pullRequests.count)
    }

    @Test func titlesAreUnique() {
        #expect(Set(world.pullRequests.map(\.title)).count == world.pullRequests.count)
    }

    @Test func handWrittenPullRequestsAreThere() {
        let expected: [(Repository, Int, String)] = [
            (MockCast.api, 4831, "Rotate signing keys for session tokens"),
            (MockCast.api, 4819, "Log failed refresh attempts with request id"),
            (MockCast.api, 4790, "Retry token refresh on 503"),
            (MockCast.api, 4774, "Remove the legacy cookie fallback"),
            (MockCast.api, 4768, "Add a rate limit to the login route"),
            (MockCast.api, 4835, "Rotate the signing key for session cookies"),
            (MockCast.web, 1301, "Fix flicker on sign-in redirect"),
            (MockCast.web, 1290, "Add token expiry banner to the account page"),
            (MockCast.web, 1172, "Add an empty state to the billing page"),
            (MockCast.web, 1180, "Replace the date picker on the reports page"),
            (MockCast.infra, 318, "Raise the database connection pool limit"),
            (MockCast.infra, 612, "Tighten IAM policy for the auth service"),
            (MockCast.docs, 92, "Document the webhook retry schedule"),
            (MockCast.docs, 233, "Document the session lifetime settings"),
        ]
        for (repository, number, title) in expected {
            #expect(world.index.pullRequest(repository: repository, number: number)?.title == title, "\(repository)#\(number)")
        }
    }

    @Test(arguments: [
        ("acme/api#4831", "● CI running 6 min. Review requested from you."),
        ("acme/api#4819", "✓ Ready to merge"),
        ("acme/api#4790", "◐ Waiting on 1 reviewer. Review requested from you."),
        ("acme/api#4774", "○ Draft"),
        ("acme/api#4768", "◐ Waiting on 1 reviewer. Review requested from you."),
        ("acme/api#4835", "● CI running 3 min. Review requested from you."),
        ("acme/web#1301", "● CI running 7 min"),
        ("acme/web#1290", "✕ Changes requested"),
        ("acme/web#1172", "✓ Ready to merge"),
        ("acme/web#1180", "◐ 2 threads unresolved"),
        ("acme/infra#318", "● CI running 12 min"),
        ("acme/docs#92", "✓ Ready to merge"),
    ])
    func handWrittenStatus(reference: String, expected: String) throws {
        let parsed = try #require(PullRequestReference(parsing: reference))
        let pr = try #require(world.index.pullRequest(parsed))
        #expect(status(pr).text == expected)
    }

    @Test func handWrittenDetails() throws {
        let index = world.index
        let ref1301 = try #require(index.pullRequest(repository: MockCast.web, number: 1301))
        #expect(ref1301.reviewDecision == .approved)
        let docs92 = try #require(index.pullRequest(repository: MockCast.docs, number: 92))
        #expect(docs92.reviews.contains { $0.reviewer == MockCast.maxChen && $0.state == .approved })
        let api4831 = try #require(index.pullRequest(repository: MockCast.api, number: 4831))
        #expect(api4831.reviewRequests.map(\.reviewer) == [.team(MockCast.securityTeam)])
        let api4774 = try #require(index.pullRequest(repository: MockCast.api, number: 4774))
        #expect(api4774.reviewDecision == .changesRequested)
        let api4768 = try #require(index.pullRequest(repository: MockCast.api, number: 4768))
        #expect(api4768.reviewRequests.map(\.reviewer) == [.person(MockCast.robinQuill)])
        #expect(api4768.checks.allSatisfy { $0.state == .passed || $0.state == .skipped })
    }

    // MARK: Determinism and placeholders

    @Test func twoBuildsEncodeToIdenticalJSON() throws {
        let encoder = GitHubPRExplorerJSON.encoder()
        let first = try encoder.encode(MockWorld.build())
        let second = try encoder.encode(MockWorld.build())
        #expect(first == second)
        #expect(first == (try encoder.encode(MockWorld.standard)))
    }

    @Test func jsonRoundTrips() throws {
        let data = try GitHubPRExplorerJSON.encoder().encode(world)
        let decoded = try GitHubPRExplorerJSON.decoder().decode(MockWorld.self, from: data)
        #expect(decoded.pullRequests == world.pullRequests)
    }

    @Test func everyRepositoryOwnerIsAcme() {
        #expect(world.repositories.allSatisfy { $0.owner == "acme" })
        #expect(world.pullRequests.allSatisfy { $0.repository.owner == "acme" })
        #expect(world.pullRequests.allSatisfy { pr in pr.linkedIssues.allSatisfy { $0.repository.owner == "acme" } })
        #expect(world.teams.allSatisfy { $0.organization == "acme" })
    }

    @Test func everyAccountIsFromTheCast() {
        let known = Set(MockCast.everyone.map(\.login))
        for pr in world.pullRequests {
            var accounts = [pr.author] + pr.assignees + pr.reviews.map(\.reviewer) + pr.commits.map(\.author)
            accounts += pr.timeline.map(\.actor) + pr.comments.map(\.author) + pr.reviewThreads.flatMap { $0.comments.map(\.author) }
            for account in accounts {
                #expect(known.contains(account.login), "\(account.login) in \(pr.reference)")
            }
        }
    }

    @Test func linksPointAtPlaceholderDomains() {
        for pr in world.pullRequests {
            let text = pr.body + pr.comments.map(\.body).joined() + pr.timeline.map(\.summary).joined()
            for word in text.split(whereSeparator: { $0.isWhitespace || $0 == "(" || $0 == ")" }) where word.contains("https://") {
                #expect(word.contains(".acme.example"), "\(word) in \(pr.reference)")
            }
        }
    }

    // MARK: Consistency

    @Test func everyPatchParsesAndMatchesItsCounts() throws {
        for pr in world.pullRequests {
            for file in pr.files {
                guard let text = file.patch else {
                    #expect(file.isBinary || (file.changeKind == .renamed && file.additions == 0 && file.deletions == 0),
                            "\(pr.reference) \(file.path) has no patch")
                    continue
                }
                let patch = try PatchParser.parse(text)
                #expect(patch.additions == file.additions, "\(pr.reference) \(file.path)")
                #expect(patch.deletions == file.deletions, "\(pr.reference) \(file.path)")
            }
            #expect(pr.additions == pr.files.reduce(0) { $0 + $1.additions }, "\(pr.reference)")
            #expect(pr.deletions == pr.files.reduce(0) { $0 + $1.deletions }, "\(pr.reference)")
        }
    }

    @Test func currentThreadsQuoteTheLineTheyPointAt() throws {
        for pr in world.pullRequests {
            for thread in pr.reviewThreads where !thread.isOutdated {
                let file = try #require(pr.files.first { $0.path == thread.path }, "\(pr.reference) \(thread.path)")
                let line = file.parsedPatch?.line(number: thread.line, side: thread.side)
                #expect(line?.text == thread.quotedLine, "\(pr.reference) \(thread.path):\(thread.line)")
            }
        }
    }

    @Test func timesAreInOrderAndWithinThirtyDays() {
        let earliest = world.now.addingTimeInterval(-30 * 86_400 - 4 * 3600)
        for pr in world.pullRequests {
            #expect(pr.createdAt >= earliest, "\(pr.reference)")
            #expect(pr.createdAt <= pr.updatedAt, "\(pr.reference)")
            #expect(pr.updatedAt <= world.now, "\(pr.reference)")
            let times = pr.timeline.map(\.occurredAt)
            #expect(times == times.sorted(), "\(pr.reference)")
            #expect(times.allSatisfy { $0 <= world.now }, "\(pr.reference)")
            #expect(pr.commits.allSatisfy { $0.authoredAt <= world.now }, "\(pr.reference)")
            for check in pr.checks {
                if let started = check.startedAt, let finished = check.finishedAt { #expect(started <= finished, "\(pr.reference) \(check.name)") }
                #expect((check.finishedAt ?? world.now) <= world.now, "\(pr.reference) \(check.name)")
            }
            if pr.state == .merged { #expect(pr.mergedAt != nil) }
        }
    }

    @Test func headCommitIsTheLastCommit() {
        for pr in world.pullRequests {
            #expect(pr.headCommitID == pr.commits.last?.id, "\(pr.reference)")
            #expect(pr.headCommitID.count == 40)
        }
    }

    @Test func mergeQueuePositionsAreUniquePerRepository() {
        for repository in MockCast.repositories {
            let positions = open.filter { $0.repository == repository }.compactMap(\.mergeState.mergeQueuePosition)
            #expect(Set(positions).count == positions.count, "\(repository)")
        }
    }

    @Test func everySectionHasProvenance() {
        let sources = Set(world.pullRequests.flatMap { pr in PullRequestSection.allCases.map { pr.provenance[$0].source } })
        #expect(sources.isSuperset(of: [.graphQLAPI, .restAPI, .localClone, .push]))
        #expect(world.pullRequests.allSatisfy { pr in PullRequestSection.allCases.allSatisfy { pr.provenance[$0].fetchedAt <= world.now } })
    }

    // MARK: Every status

    @Test(arguments: StatusSentence.State.allCases)
    func everyStatusStateAppears(state: StatusSentence.State) {
        #expect(world.pullRequests.contains { status($0).state == state })
    }

    @Test func blockedByConflictsAndByARequiredCheckBothAppear() {
        #expect(open.contains { status($0).state == .blocked && $0.mergeState.mergeability == .conflicting })
        #expect(open.contains { status($0).state == .blocked && $0.mergeState.mergeability != .conflicting })
    }

    @Test func approvedAndAllChecksPassedAppear() {
        #expect(open.contains { $0.reviewDecision == .approved })
        #expect(open.contains { !$0.checks.isEmpty && $0.checks.allSatisfy { $0.state == .passed } })
    }

    @Test func mergeQueueAtSeveralPositions() {
        #expect(Set(open.compactMap(\.mergeState.mergeQueuePosition)).count >= 3)
    }

    @Test func reviewRequestedFromTheViewerAppearsOften() {
        #expect(open.count { status($0).isReviewRequestedFromViewer } >= 20)
    }

    // MARK: Awkward cases, each found by a property

    @Test func smallAgentWrittenPullRequests() {
        let agentWork = world.pullRequests.filter { $0.author.isAgent && $0.changedLineCount < 50 }
        #expect(agentWork.count >= 2)
    }

    @Test func docsOnlyPullRequestInDocs() {
        #expect(world.pullRequests.contains { pr in
            pr.repository == MockCast.docs && !pr.files.isEmpty && pr.files.allSatisfy { $0.path.hasSuffix(".md") }
        })
    }

    @Test func releaseBranchBase() {
        #expect(open.contains { $0.baseBranch == "release/2026.11" })
    }

    @Test func veryLargePullRequest() throws {
        let large = try #require(world.pullRequests.first { $0.files.count >= 100 })
        #expect((110...130).contains(large.files.count))
        let longest = large.files.compactMap { $0.patch?.split(separator: "\n", omittingEmptySubsequences: false).count }.max() ?? 0
        #expect((4500...6000).contains(longest))
    }

    @Test func longTimelineMostlyFromBots() throws {
        let long = try #require(world.pullRequests.first { $0.timeline.count >= 250 })
        #expect(long.timeline.count <= 350)
        #expect(long.botTimelineEvents.count * 2 > long.timeline.count)
    }

    @Test func ciBotCommentWithACheckbox() {
        let line = "- [ ] Run the full end-to-end suite (about 40 minutes)"
        #expect(world.pullRequests.contains { pr in pr.comments.contains { $0.author == MockCast.ciBot && $0.body.contains(line) } })
        #expect(MockWorld.expensiveEndToEndCheckbox == "Run the full end-to-end suite (about 40 minutes)")
    }

    @Test func emptyBody() {
        #expect(world.pullRequests.contains { $0.body.isEmpty })
    }

    @Test func richBody() {
        #expect(world.pullRequests.contains { pr in
            let body = pr.body
            return body.contains("|---") && body.contains("![") && body.contains("- [ ]")
                && body.contains("<details>") && body.contains("```")
        })
    }

    @Test func veryLongTitle() {
        #expect(world.pullRequests.contains { $0.title.count >= 150 })
    }

    @Test func nonASCIITitleAndBody() {
        #expect(world.pullRequests.contains { pr in
            pr.title.unicodeScalars.contains { !$0.isASCII } && pr.body.unicodeScalars.contains { !$0.isASCII }
        })
    }

    @Test func thirtyReviewersRequested() {
        #expect(open.contains { $0.reviewRequests.count == 30 })
    }

    @Test func noReviewers() {
        #expect(open.contains { $0.reviewRequests.isEmpty && $0.reviews.isEmpty })
    }

    @Test func fortyChecksAndNone() {
        #expect(world.pullRequests.contains { $0.checks.count == 40 })
        #expect(world.pullRequests.contains { $0.checks.isEmpty })
    }

    @Test(arguments: FileChangeKind.allCases)
    func everyFileChangeKindAppears(kind: FileChangeKind) {
        #expect(world.pullRequests.contains { pr in pr.files.contains { $0.changeKind == kind } })
    }

    @Test func binaryAndPureRenameFiles() {
        let files = world.pullRequests.flatMap(\.files)
        #expect(files.contains { $0.isBinary && $0.patch == nil })
        #expect(files.contains { $0.changeKind == .renamed && $0.previousPath != nil && $0.patch == nil })
        #expect(files.contains { $0.changeKind == .renamed && $0.patch != nil })
    }

    @Test func noNewlineAtEndOfFileAppears() {
        #expect(world.pullRequests.contains { pr in pr.files.contains { $0.patch?.contains("\\ No newline at end of file") == true } })
    }

    @Test func outdatedResolvedAndUnresolvedThreads() {
        let threads = world.pullRequests.flatMap(\.reviewThreads)
        #expect(threads.contains { $0.isOutdated && !$0.isResolved })
        #expect(threads.contains { $0.isOutdated && $0.isResolved })
        #expect(threads.contains { !$0.isOutdated && $0.isResolved })
        #expect(threads.contains { !$0.isOutdated && !$0.isResolved })
    }

    @Test func threadsNeedingTheViewer() {
        let needing = open.filter { !$0.threadsNeedingAttention(from: world.viewer).isEmpty }
        #expect(needing.contains { world.viewer.isViewer($0.author) })
        #expect(needing.contains { !world.viewer.isViewer($0.author) })
    }

    @Test func checkStatesAllAppear() {
        let states = Set(world.pullRequests.flatMap { $0.checks.map(\.state) })
        #expect(states == Set(CheckState.allCases))
    }

    @Test func viewerAuthorsSomePullRequests() {
        #expect(world.pullRequests.count { world.viewer.isViewer($0.author) } >= 3)
    }

    @Test func authorsAreSpreadOverPeople() {
        let authors = Set(world.pullRequests.map(\.author.login))
        for person in MockCast.corePeople + [MockCast.robinQuill] + MockCast.agents {
            #expect(authors.contains(person.login), "\(person.login)")
        }
    }
}
