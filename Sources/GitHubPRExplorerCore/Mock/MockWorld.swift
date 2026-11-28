import Foundation

/// A fixed, placeholder GitHub world to build and test every view against, with no network
/// and no sign-in.
///
/// Everything in it comes from fixed data and a seeded generator, and `now` is fixed, so two
/// builds encode to byte-identical JSON on any Mac. The org is `acme`, and no person,
/// repository or pull request in it is real.
public struct MockWorld: Codable, Sendable {
    /// The moment the mock world is seen from: 2026-11-25T18:00:00Z.
    public static let now = date("2026-11-25T18:00:00Z")

    /// The standard world: 218 open pull requests, 60 merged and 20 closed, including
    /// `acme/api #4826`, the worked example the designs show.
    public static let standard = MockWorld.build()

    /// The worked example's reference, `acme/api#4826`.
    public static let workedExample = MockWorkedExample.reference

    public var now: Date
    public var viewer: Viewer
    public var people: [Person]
    public var teams: [Team]
    public var repositories: [Repository]
    public var codeOwners: [RepositoryCodeOwners]
    /// In the order of `InMemoryPullRequestIndex.allPullRequests`: most recently updated first.
    public var pullRequests: [PullRequest]

    public struct RepositoryCodeOwners: Codable, Sendable, Hashable {
        public var repository: Repository
        public var rules: [CodeOwnerRule]
    }

    /// Builds the standard world from scratch. `standard` holds the same value.
    public static func build() -> MockWorld {
        let now = Self.now
        let viewer = MockCast.viewer
        let factory = MockPullRequestFactory(now: now, viewer: viewer)
        let handWritten = MockHandWritten.specs()
        var reserved: Set<PullRequestReference> = [MockWorkedExample.reference]
        for spec in handWritten { reserved.insert(PullRequestReference(repository: spec.repository, number: spec.number)) }
        let generated = MockGenerated.specs(now: now, reserved: reserved, handWrittenOpen: 1 + handWritten.count { $0.scenario.isOpen })

        var pullRequests = [MockWorkedExample.make(now: now)]
        pullRequests.append(contentsOf: handWritten.map(factory.make))
        pullRequests.append(contentsOf: generated.map(factory.make))
        let index = InMemoryPullRequestIndex(pullRequests: pullRequests, viewer: viewer)

        return MockWorld(
            now: now,
            viewer: viewer,
            people: MockCast.everyone,
            teams: MockCast.teams,
            repositories: MockCast.allRepositories,
            codeOwners: MockCast.allRepositories.map { RepositoryCodeOwners(repository: $0, rules: MockCast.codeOwnerRules(for: $0)) },
            pullRequests: index.allPullRequests
        )
    }

    /// An index over this world's pull requests, seen by its viewer.
    public var index: InMemoryPullRequestIndex {
        InMemoryPullRequestIndex(pullRequests: pullRequests, viewer: viewer)
    }

    /// Reads an ISO 8601 date such as `2026-11-25T18:00:00Z`. For fixed dates in mock data.
    public static func date(_ text: String) -> Date {
        guard let date = try? Date(text, strategy: .iso8601) else {
            preconditionFailure("Not an ISO 8601 date: \(text)")
        }
        return date
    }

    /// The text that marks ci-bot's comment for starting the full end-to-end suite.
    public static let expensiveEndToEndCheckbox = "Run the full end-to-end suite (about 40 minutes)"

    /// ci-bot's comment offering expensive checks. Ticking a box starts that check, the way
    /// the owner's company starts expensive CI.
    static func expensiveChecksComment(ticked: Bool) -> String {
        """
        ### Expensive checks

        These checks do not run on every push. Tick a box to start one.

        - [\(ticked ? "x" : " ")] \(expensiveEndToEndCheckbox)
        - [ ] Run the load test against staging (about 25 minutes)
        """
    }
}
