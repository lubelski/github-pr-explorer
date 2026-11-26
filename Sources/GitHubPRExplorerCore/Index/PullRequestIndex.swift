import Foundation

/// What views read pull requests from. Synchronous and local: nothing here touches the network.
public protocol PullRequestIndex: Sendable {
    var viewer: Viewer { get }
    /// Most recently updated first.
    var allPullRequests: [PullRequest] { get }
    func pullRequest(id: String) -> PullRequest?
    func pullRequest(repository: Repository, number: Int) -> PullRequest?
    /// Every word of `text` must appear, ignoring case and accents, in the title, the number
    /// (`4826` or `#4826`), the author's login or name, the repository, or a changed file's
    /// path. Results keep the order of `allPullRequests`. Empty text returns everything.
    func search(_ text: String) -> [PullRequest]
}

extension PullRequestIndex {
    public func pullRequest(_ reference: PullRequestReference) -> PullRequest? {
        pullRequest(repository: reference.repository, number: reference.number)
    }
}

/// An index held in memory, for the mock world, tests and previews.
public struct InMemoryPullRequestIndex: PullRequestIndex {
    public let viewer: Viewer
    public let allPullRequests: [PullRequest]
    private let positionByID: [String: Int]
    private let positionByReference: [PullRequestReference: Int]
    private let searchText: [[String]]

    public init(pullRequests: [PullRequest], viewer: Viewer) {
        let sorted = pullRequests.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
            return lhs.reference < rhs.reference
        }
        self.viewer = viewer
        self.allPullRequests = sorted
        var byID: [String: Int] = [:]
        var byReference: [PullRequestReference: Int] = [:]
        for (position, pr) in sorted.enumerated() {
            byID[pr.id] = position
            byReference[pr.reference] = position
        }
        positionByID = byID
        positionByReference = byReference
        searchText = sorted.map(Self.searchFields)
    }

    public func pullRequest(id: String) -> PullRequest? {
        positionByID[id].map { allPullRequests[$0] }
    }

    public func pullRequest(repository: Repository, number: Int) -> PullRequest? {
        positionByReference[PullRequestReference(repository: repository, number: number)].map { allPullRequests[$0] }
    }

    public func search(_ text: String) -> [PullRequest] {
        let words = Self.fold(text).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return allPullRequests }
        return allPullRequests.indices.compactMap { position in
            let fields = searchText[position]
            let matches = words.allSatisfy { word in fields.contains { $0.contains(word) } }
            return matches ? allPullRequests[position] : nil
        }
    }

    private static func searchFields(_ pr: PullRequest) -> [String] {
        var fields = [
            pr.title,
            "#\(pr.number)",
            pr.repository.fullName,
            pr.reference.description,
            pr.author.login,
            pr.author.displayName,
        ]
        fields.append(contentsOf: pr.files.map(\.path))
        return fields.map(fold)
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}
