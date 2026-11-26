import Foundation

/// The only part of the app that uses the network. It reads pull requests from GitHub through
/// the `gh` login and writes them into the index, which views read and redraw from.
///
/// It fetches in tiers (see `GitHubQueries`): a light list pass on a timer, then computed
/// fields in small batches and full detail, with per-file patches from REST, for pull requests
/// that are new, have changed, or were asked for. A view never calls it to fetch: it may ask
/// for a pull request sooner with `requestSooner`, and the sync decides when.
///
/// It keeps to half of GitHub's hourly limits, reads the limit from every answer, waits when
/// GitHub asks it to, and uses ETags for REST so an unchanged answer costs nothing.
///
/// Requests are sent one at a time, as GitHub asks of clients.
public actor GitHubSync {
    public enum RunKind: Sendable, Hashable {
        /// The list pass, then whatever changed or was asked for.
        case full
        /// Only the pull requests asked for, with no list pass.
        case focused
        /// Only whether the `gh` login works and whose it is.
        case loginCheck
    }

    /// What the window redraws from after a change.
    public struct Update: Sendable {
        public var index: InMemoryPullRequestIndex
        public var status: GitHubSyncStatus
        /// Counts up with every update, so a receiver that hops threads can drop a late one.
        public var sequence: Int
    }

    // Tiers and budget. Small batches for computed fields, after the research.
    static let computedBatchSize = 5
    static let detailBatchSize = 5
    static let searchPageLimit = 4
    static let repositoryPageLimit = 10
    static let filePageLimit = 10
    static let detailLimitPerRun = 60
    /// Computed fields are fetched again after this, since a check finishing does not move
    /// a pull request's `updatedAt`.
    static let computedMaxAge: TimeInterval = 15 * 60
    /// A pull request asked for again within this is not fetched again.
    static let requestedMaxAge: TimeInterval = 60
    static let viewerMaxAge: TimeInterval = 6 * 3600
    static let codeOwnersMaxAge: TimeInterval = 6 * 3600
    /// The share of each hourly limit the sync may spend.
    static let budgetShare = 0.5
    /// Stop when this share or less is left, whoever spent it, to leave room for other tools.
    static let reserveShare = 0.1

    private let client: GitHubAPIClient
    private let tokenProvider: any GitHubTokenProvider
    private let storage: any GitHubIndexStorage
    private let now: @Sendable () -> Date
    private var onUpdate: @Sendable (Update) -> Void

    private var snapshot: GitHubIndexSnapshot
    private var watchedRepositories: [Repository] = []
    private var interval: TimeInterval = 300
    private var requested: [String] = []
    private var isRunning = false
    private var nextFullRunAt: Date?
    private var runCounts = GitHubRequestCounts()
    private var sequence = 0
    /// Points spent by this sync in each limit's current window, by resource.
    private var spent: [String: (resetAt: Date, points: Int)] = [:]

    public init(transport: any GitHubTransport = URLSessionGitHubTransport(),
                tokenProvider: any GitHubTokenProvider = GitHubCLITokenProvider(),
                storage: any GitHubIndexStorage = JSONFileIndexStorage(),
                now: @escaping @Sendable () -> Date = { Date() },
                onUpdate: @escaping @Sendable (Update) -> Void = { _ in }) {
        self.client = GitHubAPIClient(transport: transport, now: now)
        self.tokenProvider = tokenProvider
        self.storage = storage
        self.now = now
        self.onUpdate = onUpdate
        self.snapshot = GitHubIndexSnapshot(savedAt: now())
    }

    /// Who hears about every change to the index and the status.
    public func setUpdateHandler(_ handler: @escaping @Sendable (Update) -> Void) {
        onUpdate = handler
    }

    // MARK: Reading what is known

    public var status: GitHubSyncStatus { snapshot.status }
    public var index: InMemoryPullRequestIndex { snapshot.index }
    public var savedSnapshot: GitHubIndexSnapshot { snapshot }

    /// Reads the last snapshot from storage, so the window shows it before the first fetch
    /// returns. Returns the problem when the file is there and cannot be read.
    @discardableResult
    public func loadSaved() -> String? {
        do {
            if var saved = try storage.load() {
                // A run that was cut off is not running any more.
                saved.status.phase = .idle
                saved.status.session = GitHubRequestCounts()
                snapshot = saved
            }
            publish()
            return nil
        } catch {
            publish()
            return "The saved index at \(storage.location.path) could not be read, so it will be built again: \(GitHubAPIClient.describe(error))"
        }
    }

    /// Which repositories to watch in full, and how often to run the list pass.
    public func configure(watchedRepositories: [Repository], interval: TimeInterval) {
        let changed = watchedRepositories != self.watchedRepositories
        self.watchedRepositories = watchedRepositories
        self.interval = max(60, interval)
        if changed { nextFullRunAt = nil }
    }

    /// Asks for one pull request to be fetched sooner, as when it is opened. The sync fetches
    /// it at its next chance unless it was fetched in the last minute.
    public func requestSooner(_ id: String) {
        if !requested.contains(id) { requested.append(id) }
    }

    // MARK: The timer

    /// Runs the list pass every interval, and fetches pull requests asked for in between,
    /// until the task is cancelled.
    public func runUntilCancelled() async {
        while !Task.isCancelled {
            let current = now()
            if nextFullRunAt == nil || current >= nextFullRunAt! {
                await run(.full)
                var next = now().addingTimeInterval(interval)
                if let until = snapshot.status.problem?.waitsUntil, until > next { next = until }
                nextFullRunAt = next
            } else if !requested.isEmpty, snapshot.status.problem?.waitsUntil.map({ $0 <= current }) ?? true {
                await run(.focused)
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    /// Makes the next tick run the list pass, as Check Again does.
    public func runSoon() { nextFullRunAt = nil }

    // MARK: One run

    /// One sync run. Returns the status after it. Problems are in the status, never thrown.
    @discardableResult
    public func run(_ kind: RunKind) async -> GitHubSyncStatus {
        guard !isRunning else { return snapshot.status }
        isRunning = true
        defer { isRunning = false }
        let started = now()
        runCounts = GitHubRequestCounts()
        snapshot.status.lastAttemptAt = started
        if let until = snapshot.status.problem?.waitsUntil, until > started {
            publish()
            return snapshot.status
        }
        snapshot.status.problem = nil
        snapshot.status.warnings = []
        snapshot.status.phase = .checkingLogin
        snapshot.status.tokenSource = tokenProvider.sourceDescription
        publish()

        let token: String
        do {
            token = try await tokenProvider.token()
            snapshot.status.hasLogin = true
        } catch {
            snapshot.status.hasLogin = false
            snapshot.status.problem = switch error {
            case .ghMissing: .ghMissing
            case .signedOut: .signedOut
            case .failed(let message): .loginFailed(message)
            }
            finish(started: started, kind: kind)
            return snapshot.status
        }

        do throws(GitHubRequestError) {
            try await refreshViewer(token: token, force: kind == .loginCheck)
            if kind == .full {
                snapshot.status.phase = .listing
                publish()
                try await listPass(token: token)
                save()
                publish()
            }
            if kind != .loginCheck {
                snapshot.status.phase = .fetchingDetail
                publish()
                try await fetchTiers(token: token, kind: kind)
            }
        } catch {
            snapshot.status.problem = error.problem
        }
        finish(started: started, kind: kind)
        return snapshot.status
    }

    private func finish(started: Date, kind: RunKind) {
        let finished = now()
        snapshot.status.phase = .idle
        snapshot.status.lastRun = runCounts
        snapshot.status.lastRunSeconds = finished.timeIntervalSince(started)
        snapshot.status.session = snapshot.status.session + runCounts
        if snapshot.status.problem == nil, kind == .full { snapshot.status.lastSuccessAt = finished }
        countPullRequests()
        save()
        publish()
    }

    private func countPullRequests() {
        snapshot.status.pullRequestCount = snapshot.pullRequests.count
        snapshot.status.detailedCount = snapshot.pullRequests.count { snapshot.records[$0.id]?.detailFetchedAt != nil }
    }

    private func publish() {
        countPullRequests()
        sequence += 1
        onUpdate(Update(index: snapshot.index, status: snapshot.status, sequence: sequence))
    }

    private func save() {
        snapshot.savedAt = now()
        do {
            try storage.save(snapshot)
        } catch {
            let warning = "The index could not be saved to \(storage.location.path): \(error.localizedDescription)"
            if !snapshot.status.warnings.contains(warning) { snapshot.status.warnings.append(warning) }
        }
    }

    private func warn(_ text: String) {
        if !snapshot.status.warnings.contains(text) { snapshot.status.warnings.append(text) }
    }

    // MARK: Budget

    private func checkBudget(_ resource: String) throws(GitHubRequestError) {
        guard let reading = snapshot.status.rateLimits[resource] else { return }
        let current = now()
        guard reading.resetAt > current else { return }
        if Double(reading.remaining) <= Double(reading.limit) * Self.reserveShare {
            throw .budget(until: reading.resetAt)
        }
        if let window = spent[resource], window.resetAt == reading.resetAt,
           Double(window.points) >= Double(reading.limit) * Self.budgetShare {
            throw .budget(until: reading.resetAt)
        }
    }

    private func record(_ reading: RateLimitReading?, resource: String, points: Int) {
        if let reading {
            snapshot.status.rateLimits[reading.resource] = reading
        }
        let resetAt = reading?.resetAt ?? snapshot.status.rateLimits[resource]?.resetAt ?? .distantFuture
        if let window = spent[resource], window.resetAt == resetAt {
            spent[resource] = (resetAt, window.points + points)
        } else {
            spent[resource] = (resetAt, points)
        }
    }

    private func graphQL<Payload: Decodable & Sendable>(_ query: String, _ variables: [String: GraphQLValue] = [:], token: String,
                                                         as type: Payload.Type) async throws(GitHubRequestError) -> GraphQLAnswer<Payload> {
        try checkBudget("graphql")
        runCounts.graphQLRequests += 1
        do {
            let answer = try await client.graphQL(query, variables: variables, token: token, as: type)
            runCounts.graphQLPoints += answer.cost
            record(answer.rateLimit, resource: "graphql", points: answer.cost)
            return answer
        } catch {
            // A timed-out query still costs points. GitHub does not say how many, so count one.
            runCounts.graphQLPoints += 1
            record(nil, resource: "graphql", points: 1)
            throw error
        }
    }

    private func rest(_ path: String, etag: String?, token: String) async throws(GitHubRequestError) -> RESTAnswer {
        try checkBudget("core")
        runCounts.restRequests += 1
        let (answer, reading) = try await client.rest(path, etag: etag, token: token)
        if case .notModified = answer {
            runCounts.restNotModified += 1
            record(reading, resource: "core", points: 0)
        } else {
            record(reading, resource: "core", points: 1)
        }
        return answer
    }

    // MARK: The viewer

    private func refreshViewer(token: String, force: Bool) async throws(GitHubRequestError) {
        let current = now()
        if !force, snapshot.viewer != nil, let fetched = snapshot.viewerFetchedAt, current.timeIntervalSince(fetched) < Self.viewerMaxAge {
            snapshot.status.accountLogin = snapshot.viewer?.person.login
            return
        }
        let answer = try await graphQL(GitHubQueries.viewer, token: token, as: ViewerPayload.self)
        let person = GitHubMapping.person(answer.data.viewer)
        if snapshot.viewer?.person.login != person.login, snapshot.viewer != nil {
            // Someone else signed in to gh. What was synced for the last account is not theirs.
            snapshot.pullRequests = []
            snapshot.records = [:]
        }
        var teams: [Team] = []
        do throws(GitHubRequestError) {
            let teamAnswer = try await graphQL(GitHubQueries.viewerTeams, ["login": .string(person.login)], token: token, as: ViewerTeamsPayload.self)
            for organization in teamAnswer.data.viewer.organizations.items {
                for team in organization.teams?.items ?? [] {
                    teams.append(Team(organization: organization.login, slug: team.slug, members: [person]))
                }
            }
        } catch {
            if case .rateLimited = error { throw error }
            warn("Your teams could not be read, so reviews asked of a team are not counted as yours.")
        }
        snapshot.viewer = Viewer(person: person, teams: teams)
        snapshot.viewerFetchedAt = current
        snapshot.status.accountLogin = person.login
    }

    // MARK: Tier 1: the list pass

    private func listPass(token: String) async throws(GitHubRequestError) {
        let fetchedAt = now()
        var found: [String: GHListPullRequest] = [:]
        for query in GitHubQueries.involvementSearches {
            var after: String?
            for _ in 0..<Self.searchPageLimit {
                let answer = try await graphQL(GitHubQueries.search, ["query": .string(query), "after": after.map(GraphQLValue.string) ?? .null],
                                               token: token, as: SearchPayload.self)
                for node in answer.data.search.items { if let pr = node.pullRequest { found[pr.id] = pr } }
                guard let page = answer.data.search.pageInfo, page.hasNextPage, let cursor = page.endCursor else { break }
                after = cursor
            }
        }
        for repository in watchedRepositories {
            var after: String?
            for _ in 0..<Self.repositoryPageLimit {
                let answer = try await graphQL(GitHubQueries.repositoryPullRequests,
                                               ["owner": .string(repository.owner), "name": .string(repository.name), "after": after.map(GraphQLValue.string) ?? .null],
                                               token: token, as: RepositoryPullRequestsPayload.self)
                guard let connection = answer.data.repository?.pullRequests else {
                    warn("The watched repository \(repository.fullName) was not found, or this gh login cannot read it.")
                    break
                }
                for pr in connection.items { found[pr.id] = pr }
                guard let page = connection.pageInfo, page.hasNextPage, let cursor = page.endCursor else { break }
                after = cursor
            }
        }

        // Every list came back whole, so a pull request missing from all of them has closed,
        // merged, or no longer involves the viewer. It leaves the index.
        let existing = Dictionary(snapshot.pullRequests.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var pullRequests: [PullRequest] = []
        var records: [String: PullRequestSyncRecord] = [:]
        for (id, node) in found {
            pullRequests.append(GitHubMapping.pullRequest(node, existing: existing[id], fetchedAt: fetchedAt))
            var record = snapshot.records[id] ?? PullRequestSyncRecord(listUpdatedAt: node.updatedAt, listHeadCommitID: node.headRefOid)
            record.listUpdatedAt = node.updatedAt
            record.listHeadCommitID = node.headRefOid
            records[id] = record
        }
        snapshot.pullRequests = InMemoryPullRequestIndex(pullRequests: pullRequests, viewer: snapshot.viewer ?? GitHubIndexSnapshot.unknownViewer).allPullRequests
        snapshot.records = records
        snapshot.status.lastListAt = fetchedAt
    }

    // MARK: Tiers 2 and 3

    /// Which pull requests need which tier now. Ones asked for come first.
    private func targets(kind: RunKind) -> (computed: [String], detail: [String], files: [String]) {
        let current = now()
        let byID = Set(snapshot.pullRequests.map(\.id))
        var asked: [String] = []
        for id in requested where byID.contains(id) {
            let record = snapshot.records[id]
            let fresh = record?.detailFetchedAt.map { current.timeIntervalSince($0) < Self.requestedMaxAge } ?? false
            if !fresh { asked.append(id) }
        }
        requested.removeAll()
        if kind == .focused { return (asked, asked, asked) }

        var changed: [String] = []
        var stale: [String] = []
        for pr in snapshot.pullRequests {
            guard let record = snapshot.records[pr.id] else { continue }
            if record.detailFetchedAt == nil || record.detailForUpdatedAt != record.listUpdatedAt
                || record.filesForHeadCommitID != record.listHeadCommitID {
                changed.append(pr.id)
            } else if record.computedFetchedAt.map({ current.timeIntervalSince($0) >= Self.computedMaxAge }) ?? true
                        || pr.checks.contains(where: { !$0.state.isFinished }) || pr.mergeState.mergeability == .unknown {
                stale.append(pr.id)
            }
        }
        func ordered(_ ids: [String]) -> [String] {
            var seen: Set<String> = []
            return ids.filter { seen.insert($0).inserted }
        }
        let detail = Array(ordered(asked + changed).prefix(Self.detailLimitPerRun))
        return (ordered(detail + stale), detail, detail)
    }

    private func fetchTiers(token: String, kind: RunKind) async throws(GitHubRequestError) {
        let (computedIDs, detailIDs, fileIDs) = targets(kind: kind)
        guard !(computedIDs.isEmpty && detailIDs.isEmpty && fileIDs.isEmpty) else { return }
        // Detail first: the blocked reasons worked out with the computed fields lean on the
        // threads that detail brings.
        for batch in detailIDs.chunked(Self.detailBatchSize) {
            try await fetchDetail(batch, token: token)
            publish()
        }
        for batch in computedIDs.chunked(Self.computedBatchSize) {
            try await fetchComputed(batch, token: token)
            publish()
        }
        for id in fileIDs {
            try await fetchFiles(id, token: token)
            publish()
        }
    }

    private func position(of id: String) -> Int? { snapshot.pullRequests.firstIndex { $0.id == id } }

    /// Computed fields for a few pull requests. A batch GitHub cannot finish in time is split
    /// in half and tried again, down to one pull request.
    private func fetchComputed(_ ids: [String], token: String) async throws(GitHubRequestError) {
        let query = GitHubQueries.computed(ids: ids)
        let answer: GraphQLAnswer<ComputedPayload>
        do {
            answer = try await graphQL(query, token: token, as: ComputedPayload.self)
        } catch {
            if case .tooExpensive = error, ids.count > 1 {
                let half = ids.count / 2
                try await fetchComputed(Array(ids[..<half]), token: token)
                try await fetchComputed(Array(ids[half...]), token: token)
                return
            }
            if case .tooExpensive = error {
                warn("GitHub could not work out the checks and merge state of one pull request in time.")
                return
            }
            throw error
        }
        let fetchedAt = now()
        for node in answer.data.nodes {
            guard let position = position(of: node.id) else { continue }
            GitHubMapping.apply(node, to: &snapshot.pullRequests[position], fetchedAt: fetchedAt)
            snapshot.records[node.id]?.computedFetchedAt = fetchedAt
        }
    }

    private func fetchDetail(_ ids: [String], token: String) async throws(GitHubRequestError) {
        let answer: GraphQLAnswer<DetailPayload>
        do {
            answer = try await graphQL(GitHubQueries.detail, ["ids": .strings(ids)], token: token, as: DetailPayload.self)
        } catch {
            if case .tooExpensive = error, ids.count > 1 {
                let half = ids.count / 2
                try await fetchDetail(Array(ids[..<half]), token: token)
                try await fetchDetail(Array(ids[half...]), token: token)
                return
            }
            if case .tooExpensive = error {
                warn("GitHub could not send the detail of one pull request in time.")
                return
            }
            throw error
        }
        let fetchedAt = now()
        for case let node? in answer.data.nodes {
            guard let position = position(of: node.id) else { continue }
            GitHubMapping.apply(node, to: &snapshot.pullRequests[position], fetchedAt: fetchedAt)
            if var record = snapshot.records[node.id] {
                record.detailFetchedAt = fetchedAt
                record.detailForUpdatedAt = record.listUpdatedAt
                snapshot.records[node.id] = record
            }
        }
    }

    private func fetchFiles(_ id: String, token: String) async throws(GitHubRequestError) {
        guard let position = position(of: id), let record = snapshot.records[id] else { return }
        let pr = snapshot.pullRequests[position]
        guard Repository.isPlainName(pr.repository.fullName) else { return }
        let base = "/repos/\(pr.repository.owner)/\(pr.repository.name)/pulls/\(pr.number)/files?per_page=100"
        var files: [ChangedFile] = []
        var etag: String?
        var page = 1
        while page <= Self.filePageLimit {
            // Only the first page is asked conditionally. A new push changes it, and the others
            // are read only when it changed.
            let answer = try await rest("\(base)&page=\(page)", etag: page == 1 && pr.provenance.files.isFetched ? record.filesETag : nil, token: token)
            switch answer {
            case .notModified:
                snapshot.records[id]?.filesFetchedAt = now()
                snapshot.records[id]?.filesForHeadCommitID = record.listHeadCommitID
                snapshot.pullRequests[position].provenance.files = SectionProvenance(source: .restAPI, fetchedAt: now())
                return
            case .ok(let data, let tag, let hasNextPage):
                if page == 1 { etag = tag }
                do {
                    files += try GitHubJSON.decoder.decode([RESTFile].self, from: data).map(GitHubMapping.file)
                } catch {
                    throw .decoding(GitHubAPIClient.describe(error))
                }
                if !hasNextPage { page = Self.filePageLimit + 1 } else { page += 1 }
            }
        }
        if files.count >= Self.filePageLimit * 100 {
            warn("A pull request has more than \(Self.filePageLimit * 100) changed files. Only the first \(Self.filePageLimit * 100) were fetched.")
        }
        let fetchedAt = now()
        snapshot.pullRequests[position].files = files
        snapshot.pullRequests[position].provenance.files = SectionProvenance(source: .restAPI, fetchedAt: fetchedAt)
        snapshot.records[id]?.filesETag = etag
        snapshot.records[id]?.filesFetchedAt = fetchedAt
        snapshot.records[id]?.filesForHeadCommitID = record.listHeadCommitID
        try await applyCodeOwners(at: position, token: token)
    }

    private func applyCodeOwners(at position: Int, token: String) async throws(GitHubRequestError) {
        let repository = snapshot.pullRequests[position].repository
        let key = repository.fullName
        let current = now()
        if snapshot.codeOwners[key].map({ current.timeIntervalSince($0.fetchedAt) >= Self.codeOwnersMaxAge }) ?? true {
            do throws(GitHubRequestError) {
                let answer = try await graphQL(GitHubQueries.codeOwners, ["owner": .string(repository.owner), "name": .string(repository.name)],
                                               token: token, as: CodeOwnersPayload.self)
                let repo = answer.data.repository
                let text = repo?.github?.text ?? repo?.root?.text ?? repo?.docs?.text ?? ""
                snapshot.codeOwners[key] = CodeOwnersRecord(rules: GitHubMapping.codeOwnerRules(text), fetchedAt: current)
            } catch {
                if case .rateLimited = error { throw error }
                if case .budget = error { throw error }
                snapshot.codeOwners[key] = CodeOwnersRecord(rules: [], fetchedAt: current)
            }
        }
        let rules = snapshot.codeOwners[key]?.rules ?? []
        let paths = snapshot.pullRequests[position].files.map(\.path)
        snapshot.pullRequests[position].codeOwners = CodeOwners.matches(rules: rules, paths: paths)
    }
}

extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
