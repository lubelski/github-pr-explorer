import Foundation

/// Builds a complete, self-consistent pull request from a spec: files and patches, commits,
/// checks, reviews, threads, comments, timeline, merge state and provenance. All randomness
/// comes from a generator seeded by the pull request's reference, so each one is stable.
struct MockPullRequestFactory {
    let now: Date
    let viewer: Viewer

    private static let minute = 60
    private static let hour = 3600
    private static let day = 86_400

    func make(_ spec: MockPullRequestSpec) -> PullRequest {
        let reference = PullRequestReference(repository: spec.repository, number: spec.number)
        var rng = SeededGenerator(seed: "mock pull request \(reference)")
        let profile = MockVocabulary.profile(for: spec.repository)
        let area = spec.area ?? rng.pick(profile.areas)
        let scenario = spec.scenario
        let isOpen = scenario.isOpen
        let id = "PR_mock_\(spec.repository.owner)_\(spec.repository.name)_\(spec.number)"
        let author = spec.author

        // Files
        let fileSpecs = spec.files ?? MockFileGenerator.files(area: area, profile: profile, rng: &rng)
        let files = fileSpecs.map { makeFile($0, rng: &rng) }
        let codeOwners = CodeOwners.matches(rules: MockCast.codeOwnerRules(for: spec.repository), paths: files.map(\.path))

        // Commits and pushes
        var commitCount = max(1, spec.commitMessages?.count ?? spec.commitCount ?? rng.int(1...min(9, files.count + 3)))
        var pushCount = min(commitCount, spec.pushCount ?? rng.int(1...min(4, commitCount)))

        // Times
        var created: Date
        var lastPush: Date
        let end: Date
        var fixedLastPush: Date?
        switch scenario {
        case .checksRunning(let minutes): fixedLastPush = ago(minutes * Self.minute + rng.int(20...150))
        case .checksQueued: fixedLastPush = ago(rng.int(60...300))
        default: fixedLastPush = nil
        }
        if let fixed = fixedLastPush {
            end = now
            if let given = spec.createdAt {
                created = given
                if pushCount == 1 && given < fixed.addingTimeInterval(-60) {
                    commitCount = max(commitCount, 2)
                    pushCount = 2
                }
            } else {
                created = pushCount == 1 ? fixed : fixed.addingTimeInterval(-Double(rng.int(Self.hour...(20 * Self.day))))
            }
            lastPush = pushCount == 1 ? created : fixed
        } else {
            if isOpen {
                created = spec.createdAt ?? ago(rng.int((2 * Self.hour)...(30 * Self.day - Self.hour)))
                end = now
            } else {
                created = spec.createdAt ?? ago(rng.int(Self.day...(30 * Self.day - Self.hour)))
                let natural = created.addingTimeInterval(Double(rng.int(Self.hour...(6 * Self.day))))
                end = spec.endedAt ?? min(natural, ago(rng.int((10 * Self.minute)...(2 * Self.hour))))
            }
            let latestPush = end.addingTimeInterval(-Double(25 * Self.minute))
            if pushCount == 1 || latestPush <= created.addingTimeInterval(120) {
                pushCount = 1
                lastPush = created
            } else {
                let span = Int(latestPush.timeIntervalSince(created))
                lastPush = created.addingTimeInterval(Double(rng.int((span * 3 / 10)...span)))
            }
        }
        if lastPush < created { created = lastPush }

        let pushTimes = makePushTimes(created: created, lastPush: lastPush, count: pushCount, rng: &rng)
        let commits = makeCommits(spec: spec, count: commitCount, pushTimes: pushTimes, rng: &rng)
        let commitsPerPush = commits.counts

        // Checks
        let checkDefinitions = spec.checks ?? profile.checks
        let checks = makeChecks(definitions: checkDefinitions, scenario: scenario, files: files, lastPush: lastPush, end: end, rng: &rng)

        // Reviews
        let reviewWindowStart = created.addingTimeInterval(Double(15 * Self.minute))
        let reviewWindowEnd = end.addingTimeInterval(-Double(3 * Self.minute))
        var plan = spec.reviewPlan ?? derivePlan(scenario: scenario, author: author, codeOwners: codeOwners, rng: &rng)
        if spec.reviewPlan == nil && reviewWindowEnd.timeIntervalSince(reviewWindowStart) < Double(20 * Self.minute) {
            plan.approvedBy = []; plan.changesRequestedBy = []; plan.commentedBy = []
        }
        var reviews: [Review] = []
        func reviewTime() -> Date {
            guard reviewWindowEnd > reviewWindowStart else { return reviewWindowStart }
            return reviewWindowStart.addingTimeInterval(Double(rng.int(0...Int(reviewWindowEnd.timeIntervalSince(reviewWindowStart)))))
        }
        for person in plan.commentedBy {
            reviews.append(Review(id: "", reviewer: person, state: .commented, submittedAt: reviewTime(), body: rng.pick(MockVocabulary.conversationComments)))
        }
        for person in plan.approvedBy {
            reviews.append(Review(id: "", reviewer: person, state: .approved, submittedAt: reviewTime(), body: rng.pick(MockVocabulary.reviewBodies)))
        }
        for person in plan.changesRequestedBy {
            reviews.append(Review(id: "", reviewer: person, state: .changesRequested, submittedAt: reviewTime(), body: rng.pick(MockVocabulary.changeRequestBodies)))
        }
        reviews.sort { $0.submittedAt < $1.submittedAt }
        for index in reviews.indices { reviews[index].id = "\(id)_review_\(index + 1)" }

        let ownerHandles = Set(codeOwners.flatMap(\.owners))
        let requestTime = created.addingTimeInterval(120)
        let reviewRequests = plan.pendingTeams.map {
            ReviewRequest(reviewer: .team($0), requestedAt: requestTime, isCodeOwnerRequest: ownerHandles.contains($0.handle))
        } + plan.pendingPeople.map {
            ReviewRequest(reviewer: .person($0), requestedAt: requestTime, isCodeOwnerRequest: ownerHandles.contains($0.handle))
        }
        let reviewDecision: ReviewDecision
        if !plan.changesRequestedBy.isEmpty {
            reviewDecision = .changesRequested
        } else if !plan.approvedBy.isEmpty && !reviewRequests.contains(where: \.isCodeOwnerRequest) {
            reviewDecision = .approved
        } else {
            reviewDecision = .reviewRequired
        }

        // Threads
        let threadKinds = spec.threads ?? deriveThreadKinds(scenario: scenario, author: author, rng: &rng)
        let threads = makeThreads(kinds: threadKinds, id: id, files: files, author: author, plan: plan,
                                  created: created, end: end, rng: &rng)

        // Merge state
        var mergeState = MergeState()
        switch scenario {
        case .mergeConflicts: mergeState.mergeability = .conflicting
        case .mergeabilityUnknown: mergeState.mergeability = .unknown
        case .mergeQueue(let position): mergeState.mergeQueuePosition = position
        default: break
        }
        if let behind = spec.isBehindBase {
            mergeState.isBehindBase = behind
        } else if scenario == .behindBase {
            mergeState.isBehindBase = true
        } else if isOpen, scenario != .readyToMerge, scenario != .mergeabilityUnknown, scenario != .needsReview {
            if case .mergeQueue = scenario {} else { mergeState.isBehindBase = rng.chance(0.18) }
        }

        // Labels, milestone, linked issues, assignees
        var labelNames = spec.labels ?? Array(area.labels.prefix(rng.int(1...max(1, area.labels.count))))
        if spec.labels == nil {
            if spec.title.hasPrefix("Fix") { labelNames.append("bug") }
            if author.isAgent { labelNames.append("agent") }
            if spec.baseBranch.hasPrefix("release/") { labelNames.append("backport") }
        }
        let labels = labelNames.map(MockCast.label)
        let milestoneRoll = rng.int(0...99)
        let milestone: Milestone? = switch milestoneRoll {
        case 0..<30: Milestone(title: "2026.12", dueOn: MockWorld.date("2026-12-15T00:00:00Z"))
        case 30..<42: Milestone(title: "2026.11", dueOn: MockWorld.date("2026-11-30T00:00:00Z"))
        default: nil
        }
        var linkedIssues: [LinkedIssue] = []
        if let given = spec.linkedIssue {
            linkedIssues = [given]
        } else if rng.chance(0.4) {
            linkedIssues = [LinkedIssue(repository: spec.repository, number: max(1, spec.number - rng.int(5...300)),
                                        title: rng.pick(area.problems), isClosed: scenario == .merged)]
        }
        var assignees: [Person] = []
        if rng.chance(0.6) { assignees.append(author) }

        let headBranch = spec.headBranch ?? Self.branchName(title: spec.title, author: author)
        let headCommitID = commits.list.last?.id ?? rng.hex(length: 40)

        // Timeline and conversation comments
        var builder = TimelineBuilder()
        let isDraft = scenario == .draft
        builder.add(.opened, author, created, "\(author.displayName) opened this pull request" + (isDraft ? " as a draft" : ""))
        if !isDraft && isOpen && rng.chance(0.12) && lastPush > created.addingTimeInterval(1200) {
            builder.add(.readyForReview, author, created.addingTimeInterval(Double(rng.int(300...1200))), "\(author.displayName) marked this pull request as ready for review")
        }
        if !labels.isEmpty {
            builder.add(.labelAdded, author, created.addingTimeInterval(60), "\(author.displayName) added the \(Self.list(labelNames)) \(labelNames.count == 1 ? "label" : "labels")")
        }
        if !assignees.isEmpty {
            builder.add(.assigned, author, created.addingTimeInterval(90), "\(author.displayName) self-assigned this")
        }
        let everyoneAsked = plan.pendingTeams.map(\.handle) + (plan.pendingPeople + plan.approvedBy + plan.changesRequestedBy).map(\.displayName)
        if !everyoneAsked.isEmpty {
            builder.add(.reviewRequested, author, requestTime, "\(author.displayName) requested review from \(Self.list(everyoneAsked))")
        }
        var comments: [IssueComment] = []
        func comment(_ person: Person, _ time: Date, _ body: String) {
            guard time <= end else { return }
            comments.append(IssueComment(id: "", author: person, body: body, createdAt: time))
            builder.add(.commented, person, time, "\(person.displayName) commented")
        }
        for (index, pushTime) in pushTimes.enumerated() {
            if index > 0 {
                let count = commitsPerPush[index]
                if rng.chance(0.1) {
                    builder.add(.forcePushed, author, pushTime, "\(author.displayName) force-pushed \(headBranch) from \(rng.hex(length: 7)) to \(rng.hex(length: 7))")
                } else {
                    builder.add(.pushedCommits, author, pushTime, "\(author.displayName) pushed \(count) \(count == 1 ? "commit" : "commits")")
                }
            }
            if profile.hasPreviews {
                let deployTime = pushTime.addingTimeInterval(Double(rng.int(240...540)))
                if deployTime <= end {
                    let url = "https://pr-\(spec.number).\(spec.repository.name).preview.acme.example"
                    builder.add(.deployed, MockCast.deployPreviewBot, deployTime, "deploy-preview-bot deployed a preview to \(url)")
                    if index == 0 {
                        comment(MockCast.deployPreviewBot, deployTime.addingTimeInterval(20),
                                "**Preview ready.** \(url)\n\nThe preview is rebuilt on every push and removed when the pull request closes.")
                    }
                }
            }
            if profile.hasCoverage {
                let coverageTime = pushTime.addingTimeInterval(Double(rng.int(360...720)))
                let total = Double(rng.int(780...920)) / 10
                let change = Double(rng.int(-15...12)) / 10
                let sign = change >= 0 ? "+" : ""
                comment(MockCast.coverageBot, coverageTime,
                        "Coverage is **\(total)%** (\(sign)\(change)%) on this branch.\n\n| Files changed | Lines covered |\n|---|---|\n| \(files.count) | \(rng.int(60...98))% |")
            }
            if spec.reportsChecksOnEveryPush {
                for definition in checkDefinitions.prefix(4) {
                    let time = pushTime.addingTimeInterval(Double(rng.int(60...480)))
                    if time <= end {
                        builder.add(.checkFinished, MockCast.ciBot, time, "\(definition.name) passed on \(rng.hex(length: 7))")
                    }
                }
            }
        }
        let checkbox = spec.ciBotCheckbox ?? (spec.allowsRandomCheckbox && spec.repository == MockCast.api && isOpen && rng.chance(0.25)
                                              ? (rng.chance(0.3) ? .ticked : .unticked) : nil)
        if let checkbox {
            comment(MockCast.ciBot, created.addingTimeInterval(180), MockWorld.expensiveChecksComment(ticked: checkbox == .ticked))
        }
        for check in checks where check.state == .failed {
            if let finished = check.finishedAt {
                builder.add(.checkFinished, MockCast.ciBot, finished, "\(check.name) failed: \(check.failureSummary ?? "failed")")
            }
        }
        for review in reviews {
            let words = switch review.state {
            case .approved: "approved these changes"
            case .changesRequested: "requested changes"
            case .commented: "reviewed and left comments"
            }
            builder.add(.reviewed, review.reviewer, review.submittedAt, "\(review.reviewer.displayName) \(words)")
        }
        for thread in threads {
            for threadComment in thread.comments {
                builder.add(.commented, threadComment.author, threadComment.createdAt, "\(threadComment.author.displayName) commented on \(thread.path)")
            }
        }
        let talkers = (MockCast.corePeople + [MockCast.robinQuill]).filter { $0.login != author.login }
        for _ in 0..<rng.int(0...2) where end.timeIntervalSince(created) > 3600 {
            let time = created.addingTimeInterval(Double(rng.int(600...Int(end.timeIntervalSince(created)) - 60)))
            comment(rng.pick(talkers + [author]), time, rng.pick(MockVocabulary.conversationComments))
        }
        if case .mergeQueue = scenario {
            let latestReview = reviews.map(\.submittedAt).max() ?? lastPush
            let queued = min(max(latestReview, lastPush).addingTimeInterval(Double(rng.int(60...1800))), ago(rng.int(60...600)))
            builder.add(.addedToMergeQueue, author, queued, "\(author.displayName) added this pull request to the merge queue")
        }
        var mergedAt: Date?
        var closedAt: Date?
        if scenario == .merged {
            let merger = plan.approvedBy.first.flatMap { rng.chance(0.3) ? $0 : nil } ?? author
            builder.add(.merged, merger, end, "\(merger.displayName) merged \(headBranch) into \(spec.baseBranch)")
            mergedAt = end
            closedAt = end
        } else if scenario == .closed {
            builder.add(.closed, author, end, "\(author.displayName) closed this pull request without merging")
            closedAt = end
        }

        comments.sort { $0.createdAt < $1.createdAt }
        for index in comments.indices { comments[index].id = "\(id)_comment_\(index + 1)" }
        let timeline = builder.events(idPrefix: id)
        let updatedAt = max(timeline.last?.occurredAt ?? created, lastPush)

        let state: PullRequestState = switch scenario {
        case .merged: .merged
        case .closed: .closed
        default: .open
        }

        var pr = PullRequest(
            id: id,
            repository: spec.repository,
            number: spec.number,
            title: spec.title,
            body: spec.body ?? Self.body(area: area, linkedIssues: linkedIssues, rng: &rng),
            author: author,
            state: state,
            isDraft: isDraft,
            baseBranch: spec.baseBranch,
            headBranch: headBranch,
            headCommitID: headCommitID,
            createdAt: created,
            updatedAt: updatedAt,
            mergedAt: mergedAt,
            closedAt: closedAt,
            additions: files.reduce(0) { $0 + $1.additions },
            deletions: files.reduce(0) { $0 + $1.deletions },
            labels: labels,
            milestone: milestone,
            linkedIssues: linkedIssues,
            assignees: assignees,
            mergeState: mergeState,
            reviewRequests: isOpen ? reviewRequests : [],
            reviews: reviews,
            reviewDecision: state == .merged ? .approved : reviewDecision,
            codeOwners: codeOwners,
            checks: checks,
            files: files,
            commits: commits.list,
            reviewThreads: threads,
            comments: comments,
            timeline: timeline,
            provenance: makeProvenance(isOpen: isOpen, rng: &rng)
        )
        pr.mergeState.blockedReasons = Self.blockedReasons(pr, profile: profile)
        return pr
    }

    // MARK: Pieces

    private func ago(_ seconds: Int) -> Date {
        now.addingTimeInterval(-Double(seconds))
    }

    private func makeFile(_ spec: MockFileSpec, rng: inout SeededGenerator) -> ChangedFile {
        if spec.isBinary {
            return ChangedFile(path: spec.path, previousPath: spec.previousPath, changeKind: spec.changeKind,
                               additions: 0, deletions: 0, isBinary: true, patch: nil)
        }
        let patch = spec.patch ?? MockPatchSynthesizer.patch(
            path: spec.path, changeKind: spec.changeKind, additions: spec.additions, deletions: spec.deletions,
            noNewlineAtEnd: spec.noNewlineAtEnd, rng: &rng)
        return ChangedFile(path: spec.path, previousPath: spec.previousPath, changeKind: spec.changeKind,
                           additions: spec.additions, deletions: spec.deletions, isBinary: false, patch: patch)
    }

    private func makePushTimes(created: Date, lastPush: Date, count: Int, rng: inout SeededGenerator) -> [Date] {
        guard count > 1 else { return [created] }
        let span = Int(lastPush.timeIntervalSince(created))
        var middle: [Date] = []
        if count > 2 {
            for _ in 0..<(count - 2) {
                middle.append(created.addingTimeInterval(Double(rng.int(min(span, 300)...max(min(span, 300), span - 300)))))
            }
            middle.sort()
        }
        return [created] + middle + [lastPush]
    }

    private func makeCommits(spec: MockPullRequestSpec, count: Int, pushTimes: [Date], rng: inout SeededGenerator) -> (list: [Commit], counts: [Int]) {
        var counts = Array(repeating: 1, count: pushTimes.count)
        for _ in 0..<(count - pushTimes.count) { counts[rng.int(0...(counts.count - 1))] += 1 }
        let messages = spec.commitMessages ?? ([spec.title] + (1..<max(count, 1)).map { _ in rng.pick(MockVocabulary.commitFollowUps) })
        var commits: [Commit] = []
        var messageIndex = 0
        for (pushIndex, pushTime) in pushTimes.enumerated() {
            let previous = pushIndex == 0 ? pushTime.addingTimeInterval(-Double(4 * Self.hour)) : pushTimes[pushIndex - 1]
            let inPush = counts[pushIndex]
            for position in 0..<inPush {
                let back = Double((inPush - position) * rng.int(120...900))
                let time = max(previous.addingTimeInterval(1), pushTime.addingTimeInterval(-back))
                let message = messages[min(messageIndex, messages.count - 1)]
                messageIndex += 1
                commits.append(Commit(id: rng.hex(length: 40), message: message, author: spec.author, authoredAt: time))
            }
        }
        return (commits, counts)
    }

    private func makeChecks(definitions: [MockCheckDefinition], scenario: MockScenario, files: [ChangedFile],
                            lastPush: Date, end: Date, rng: inout SeededGenerator) -> [Check] {
        guard !definitions.isEmpty else { return [] }
        var checks: [Check] = definitions.map { definition in
            var start = lastPush.addingTimeInterval(Double(rng.int(5...60)))
            var finish = start.addingTimeInterval(Double(rng.int(definition.seconds)))
            let latest = end.addingTimeInterval(-5)
            if finish > latest {
                finish = latest.addingTimeInterval(-Double(rng.int(0...60)))
                if start > finish.addingTimeInterval(-10) { start = finish.addingTimeInterval(-10) }
            }
            return Check(name: definition.name, state: .passed, isRequired: definition.isRequired, startedAt: start, finishedAt: finish)
        }
        func fail(_ index: Int) {
            checks[index].state = .failed
            checks[index].failureSummary = rng.pick(definitions[index].failures)
        }
        let slow = definitions.indices.filter { definitions[$0].isSlow }
        let required = definitions.indices.filter { definitions[$0].isRequired }
        let optional = definitions.indices.filter { !definitions[$0].isRequired }

        switch scenario {
        case .checksRunning(let minutes):
            let primaryStart = ago(minutes * Self.minute)
            let primary = (slow.filter { definitions[$0].isRequired }.last ?? slow.last) ?? (definitions.count - 1)
            for index in checks.indices {
                let start = index == primary ? primaryStart : primaryStart.addingTimeInterval(Double(rng.int(0...60)))
                let finish = start.addingTimeInterval(Double(rng.int(definitions[index].seconds)))
                checks[index].startedAt = start
                if index == primary || finish > now.addingTimeInterval(-2) {
                    checks[index].state = .running
                    checks[index].finishedAt = nil
                } else {
                    checks[index].finishedAt = finish
                }
            }
        case .checksQueued:
            for index in checks.indices {
                let start = lastPush.addingTimeInterval(Double(rng.int(5...60)))
                let finish = start.addingTimeInterval(Double(rng.int(definitions[index].seconds)))
                if finish > now.addingTimeInterval(-2) || start > now.addingTimeInterval(-2) {
                    checks[index] = Check(name: definitions[index].name, state: .queued, isRequired: definitions[index].isRequired)
                } else {
                    checks[index].startedAt = start
                    checks[index].finishedAt = finish
                }
            }
            if !checks.contains(where: { $0.state == .queued }) {
                let index = slow.last ?? (checks.count - 1)
                checks[index] = Check(name: definitions[index].name, state: .queued, isRequired: definitions[index].isRequired)
            }
        case .requiredCheckFailed:
            if let index = required.isEmpty ? nil : rng.pick(required) { fail(index) } else { fail(0) }
            if let cancel = optional.filter({ definitions[$0].isSlow }).first, rng.chance(0.35) {
                checks[cancel].state = .cancelled
            }
        case .optionalCheckFailed:
            if let index = optional.isEmpty ? nil : rng.pick(optional) { fail(index) }
        case .draft, .closed:
            if rng.chance(0.3) { fail(rng.int(0...(checks.count - 1))) }
        default:
            break
        }
        let touchesDatabase = files.contains { $0.path.hasPrefix("db/") }
        for index in checks.indices where checks[index].name == "migrations-check" && !touchesDatabase && checks[index].state == .passed {
            checks[index].state = .skipped
            checks[index].finishedAt = checks[index].startedAt
        }
        return checks
    }

    private func derivePlan(scenario: MockScenario, author: Person, codeOwners: [CodeOwnerMatch], rng: inout SeededGenerator) -> MockReviewPlan {
        var ownerHandles: [String] = []
        for match in codeOwners { for owner in match.owners where !ownerHandles.contains(owner) { ownerHandles.append(owner) } }
        let ownerTeams = ownerHandles.compactMap(MockCast.team(handle:))
        let ownerPeople = ownerHandles.compactMap { MockCast.person(login: String($0.dropFirst())) }.filter { $0.login != author.login }
        let candidates = (MockCast.corePeople + [MockCast.robinQuill]).filter { $0.login != author.login }

        func someone(excluding excluded: [Person]) -> Person? {
            var pool = candidates.filter { person in !excluded.contains { $0.login == person.login } }
            if rng.chance(0.12) { pool = MockCast.occasionalPeople.filter { person in !excluded.contains { $0.login == person.login } } }
            return pool.isEmpty ? nil : rng.pick(pool)
        }
        func approvalSet() -> [Person] {
            var approvers: [Person] = []
            for team in ownerTeams {
                let members = team.members.filter { member in member.login != author.login && !approvers.contains(member) }
                if !members.isEmpty { approvers.append(rng.pick(members)) }
            }
            for person in ownerPeople where !approvers.contains(person) { approvers.append(person) }
            if approvers.isEmpty || rng.chance(0.4), let extra = someone(excluding: approvers) { approvers.append(extra) }
            return approvers
        }
        func waitingPlan() -> MockReviewPlan {
            var plan = MockReviewPlan()
            plan.pendingTeams = ownerTeams
            plan.pendingPeople = ownerPeople
            let teamMembers = ownerTeams.flatMap(\.members)
            for _ in 0..<rng.int(0...2) {
                if let extra = someone(excluding: plan.pendingPeople + teamMembers) { plan.pendingPeople.append(extra) }
            }
            if plan.pendingTeams.isEmpty && plan.pendingPeople.isEmpty, let extra = someone(excluding: []) {
                plan.pendingPeople.append(extra)
            }
            if rng.chance(0.5), let approver = someone(excluding: plan.pendingPeople + teamMembers) {
                plan.approvedBy = [approver]
            }
            return plan
        }

        var plan = MockReviewPlan()
        switch scenario {
        case .readyToMerge, .mergeQueue, .behindBase, .mergeabilityUnknown, .optionalCheckFailed, .unresolvedThreads, .merged:
            plan.approvedBy = approvalSet()
        case .waitingOnReviewers:
            plan = waitingPlan()
        case .needsReview:
            break
        case .changesRequested:
            if let reviewer = someone(excluding: []) { plan.changesRequestedBy = [reviewer] }
            if rng.chance(0.5), let approver = someone(excluding: plan.changesRequestedBy) { plan.approvedBy = [approver] }
            let reviewed = plan.reviewers
            plan.pendingTeams = ownerTeams.filter { team in !reviewed.contains { team.hasMember(login: $0.login) } }
        case .checksRunning, .checksQueued, .requiredCheckFailed, .mergeConflicts:
            plan = rng.chance(0.5) ? MockReviewPlan(approvedBy: approvalSet()) : waitingPlan()
        case .draft:
            break
        case .closed:
            if rng.chance(0.5) { plan = waitingPlan() }
        }

        let viewerPerson = viewer.person
        let viewerInvolved = plan.reviewers.contains(viewerPerson) || plan.pendingPeople.contains(viewerPerson)
        let hasPending = !plan.pendingPeople.isEmpty || !plan.pendingTeams.isEmpty
        if author.login != viewerPerson.login, !viewerInvolved, scenario.isOpen, scenario != .draft,
           hasPending || scenario.outranksWaitingOnReviewers, rng.chance(0.25) {
            plan.pendingPeople.append(viewerPerson)
        }
        if scenario != .needsReview, rng.chance(0.25), let commenter = someone(excluding: plan.reviewers + plan.pendingPeople) {
            plan.commentedBy = [commenter]
        }
        return plan
    }

    private func deriveThreadKinds(scenario: MockScenario, author: Person, rng: inout SeededGenerator) -> [MockThreadKind] {
        var kinds: [MockThreadKind]
        switch scenario {
        case .unresolvedThreads(let count):
            kinds = Array(repeating: .unresolved, count: count) + (rng.chance(0.4) ? [.resolved] : [])
        case .changesRequested:
            kinds = Array(repeating: .unresolved, count: rng.int(1...2)) + (rng.chance(0.4) ? [.resolved] : [])
        case .requiredCheckFailed, .mergeConflicts, .checksRunning, .checksQueued, .draft, .closed:
            kinds = (0..<rng.int(0...3)).map { _ in rng.pick([.unresolved, .resolved, .outdated, .outdatedResolved]) }
        default:
            kinds = (0..<rng.int(0...2)).map { _ in rng.pick([.resolved, .outdatedResolved]) }
        }
        let authorIsViewer = viewer.isViewer(author)
        if scenario.allowsUnresolvedThreads, scenario.isOpen, rng.chance(authorIsViewer ? 0.5 : 0.12) {
            kinds.append(.needsViewer)
        }
        return kinds
    }

    private func makeThreads(kinds: [MockThreadKind], id: String, files: [ChangedFile], author: Person, plan: MockReviewPlan,
                             created: Date, end: Date, rng: inout SeededGenerator) -> [ReviewThread] {
        let patched = files.compactMap { file -> (ChangedFile, Patch)? in
            guard let patch = file.parsedPatch, !patch.lines.isEmpty else { return nil }
            return (file, patch)
        }
        guard !patched.isEmpty, !kinds.isEmpty else { return [] }
        let reviewerPool = plan.reviewers.isEmpty
            ? (MockCast.corePeople + [MockCast.robinQuill]).filter { $0.login != author.login }
            : plan.reviewers
        let windowStart = created.addingTimeInterval(Double(20 * Self.minute))
        let windowEnd = end.addingTimeInterval(-Double(10 * Self.minute))
        var threads: [ReviewThread] = []
        for (index, kind) in kinds.enumerated() {
            let (file, patch) = rng.pick(patched)
            let removed = patch.lines.filter { $0.kind == .removed }
            let kept = patch.lines.filter { $0.kind != .removed && !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            let line: PatchLine
            let side: DiffSide
            if (!removed.isEmpty && rng.chance(0.15)) || kept.isEmpty {
                line = rng.pick(removed.isEmpty ? patch.lines : removed)
                side = line.kind == .added ? .right : .left
            } else {
                line = rng.pick(kept)
                side = .right
            }
            let number = (side == .right ? line.newLineNumber : line.oldLineNumber) ?? 1

            var starter = rng.pick(reviewerPool)
            if kind == .needsViewer && !viewer.isViewer(author) { starter = viewer.person }
            if kind != .needsViewer && viewer.isViewer(starter) && reviewerPool.count > 1 {
                starter = reviewerPool.first { !viewer.isViewer($0) } ?? starter
            }
            var time = windowEnd > windowStart
                ? windowStart.addingTimeInterval(Double(rng.int(0...Int(windowEnd.timeIntervalSince(windowStart)))))
                : created.addingTimeInterval(60)
            var comments = [ReviewComment(id: "", author: starter, body: rng.pick(MockVocabulary.threadOpeners), createdAt: time)]
            func reply(_ person: Person, _ body: String) {
                time = min(time.addingTimeInterval(Double(rng.int(300...10_800))), end.addingTimeInterval(-60))
                comments.append(ReviewComment(id: "", author: person, body: body, createdAt: time))
            }
            switch kind {
            case .needsViewer:
                if !viewer.isViewer(author) { reply(author, "Do you mean the retry count or the timeout? Happy to change either.") }
            case .unresolved, .outdated:
                if rng.chance(0.5) { reply(author, rng.pick(MockVocabulary.authorReplies)) }
            case .resolved, .outdatedResolved:
                reply(author, rng.pick(MockVocabulary.authorReplies))
                if rng.chance(0.4) { reply(starter, "Thanks!") }
            }
            for commentIndex in comments.indices { comments[commentIndex].id = "\(id)_thread_\(index + 1)_comment_\(commentIndex + 1)" }
            threads.append(ReviewThread(
                id: "\(id)_thread_\(index + 1)",
                path: file.path,
                line: number,
                side: side,
                isResolved: kind == .resolved || kind == .outdatedResolved,
                isOutdated: kind == .outdated || kind == .outdatedResolved,
                quotedLine: line.text,
                comments: comments
            ))
        }
        return threads
    }

    private func makeProvenance(isOpen: Bool, rng: inout SeededGenerator) -> Provenance {
        let stale = !isOpen || rng.chance(0.1)
        func stamp(_ source: DataSource, _ seconds: ClosedRange<Int>) -> SectionProvenance {
            let age = stale ? rng.int((2 * Self.hour)...(9 * Self.hour)) : rng.int(seconds)
            return SectionProvenance(source: source, fetchedAt: ago(age))
        }
        return Provenance(
            metadata: stamp(.graphQLAPI, 20...600),
            checks: stamp(rng.chance(0.3) ? .push : .restAPI, 5...120),
            reviews: stamp(.graphQLAPI, 20...600),
            files: stamp(rng.chance(0.7) ? .localClone : .restAPI, 60...1800),
            threads: stamp(.graphQLAPI, 20...600),
            timeline: stamp(rng.chance(0.4) ? .push : .graphQLAPI, 5...600)
        )
    }

    // MARK: Text

    static func branchName(title: String, author: Person) -> String {
        let slug = title.lowercased().unicodeScalars.map { CharacterSet.alphanumerics.contains($0) && $0.isASCII ? String($0) : "-" }.joined()
        let collapsed = slug.split(separator: "-").prefix(6).joined(separator: "-")
        return author.isAgent ? "agent/\(collapsed)" : collapsed
    }

    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: ""
        case 1: items[0]
        case 2: "\(items[0]) and \(items[1])"
        default: items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
        }
    }

    static func body(area: MockArea, linkedIssues: [LinkedIssue], rng: inout SeededGenerator) -> String {
        var parts = ["\(rng.pick(MockVocabulary.motivations)) \(rng.pick(MockVocabulary.approaches))"]
        if let issue = linkedIssues.first { parts.append("Fixes \(issue.repository.fullName)#\(issue.number).") }
        if rng.chance(0.5) {
            parts.append("- [x] Tests\n- [\(rng.chance(0.5) ? "x" : " ")] Docs\n- [ ] Checked on staging")
        }
        parts.append(rng.pick(MockVocabulary.testingNotes))
        return parts.joined(separator: "\n\n")
    }

    /// What branch protection would report for this pull request.
    static func blockedReasons(_ pr: PullRequest, profile: MockRepositoryProfile) -> [BlockedReason] {
        guard pr.state == .open else { return [] }
        var reasons: [BlockedReason] = []
        if pr.isDraft { reasons.append(.draft) }
        if pr.mergeState.mergeability == .conflicting { reasons.append(.mergeConflicts) }
        let required = pr.checks.filter(\.isRequired)
        if required.contains(where: { $0.state == .failed }) { reasons.append(.requiredChecksFailing) }
        if required.contains(where: { !$0.state.isFinished }) { reasons.append(.requiredChecksPending) }
        switch pr.reviewDecision {
        case .changesRequested: reasons.append(.changesRequested)
        case .reviewRequired:
            reasons.append(pr.reviewRequests.contains(where: \.isCodeOwnerRequest) ? .codeOwnerReviewRequired : .reviewRequired)
        default: break
        }
        if profile.requiresResolvedThreads && pr.reviewThreads.contains(where: { !$0.isResolved }) { reasons.append(.unresolvedConversations) }
        if profile.requiresUpToDate && pr.mergeState.isBehindBase { reasons.append(.behindBase) }
        return reasons
    }
}

/// Collects timeline events in any order and hands them back sorted by time, keeping the
/// order they were added in for events at the same second.
struct TimelineBuilder {
    private var pending: [(Date, Int, TimelineEventKind, Person, String)] = []

    mutating func add(_ kind: TimelineEventKind, _ actor: Person, _ time: Date, _ summary: String) {
        pending.append((time, pending.count, kind, actor, summary))
    }

    func events(idPrefix: String) -> [TimelineEvent] {
        pending.sorted { ($0.0, $0.1) < ($1.0, $1.1) }.enumerated().map { index, event in
            TimelineEvent(id: "\(idPrefix)_event_\(index + 1)", kind: event.2, actor: event.3, occurredAt: event.0, summary: event.4)
        }
    }
}
