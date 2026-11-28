import Foundation

/// What the overview of a selected title row shows: how many pull requests are in each status,
/// how many wait on the viewer, and the pull requests as cards in sections.
///
/// It is built from the title row as the list's tree has it, so it holds exactly the rows the
/// list holds under that row, within the chosen view, the search and the filters.
///
/// Sections are the title rows one level down, as the tree has them: an organization grouped
/// then by repository has one section per repository. At the last level there is nothing below
/// in the tree, so the cards are put in sections by status, in the badges' order, unless the
/// row or one above it already is a status. Then there is one section with no heading.
public struct GroupOverview: Sendable {
    /// Whose move it is: who or what the pull request waits on before it can go further.
    public enum NextMove: Sendable, Hashable {
        /// The author: to fix what blocks it, answer changes requested or threads, update the
        /// branch, finish a draft, or merge when it is ready.
        case author(Person)
        /// The reviewers asked and not yet heard from, a team as one. Empty when GitHub wants a
        /// review and nobody is asked.
        case reviewers([RequestedReviewer])
        /// Checks that run or wait to run.
        case checks
        /// The merge queue.
        case mergeQueue
        /// GitHub, working out whether the branch merges cleanly.
        case github
        /// Nobody: merged or closed.
        case nobody
    }

    public struct Card: Sendable, Identifiable {
        public var pullRequest: PullRequest
        public var status: StatusSentence
        public var nextMove: NextMove
        /// A review is asked of the viewer or one of the viewer's teams, or the viewer wrote it
        /// and it waits on them, other than as a draft.
        public var needsViewer: Bool

        public var id: PullRequest.ID { pullRequest.id }
    }

    public struct Section: Sendable, Identifiable {
        /// The title row one level down this section stands for, or `status:<badge>` for a
        /// section by status, or `all` for the one section with no heading.
        public var id: String
        /// The heading, or nil for the one section with no heading.
        public var name: DisplayName?
        /// The title row in the list this section is, so a click on its heading can select it.
        /// Nil for sections by status, which are not rows of the list.
        public var groupID: String?
        /// What the heading and the rows above already say, so a card need not repeat it.
        public var namedProperties: Set<ListGrouping.Property>
        public var cards: [Card]
        /// How many cards are in each status, in the badges' order, leaving out none.
        public var statusCounts: [StatusCount]
    }

    public struct StatusCount: Sendable, Hashable, Identifiable {
        public var badge: StatusSentence.Badge
        public var count: Int
        public var id: StatusSentence.Badge { badge }
    }

    public let group: ListGroup
    /// The kinds of title row that hold this one, outermost first.
    public let ancestorProperties: [ListGrouping.Property]
    /// Every status that has at least one pull request, in the badges' order.
    public let statusCounts: [StatusCount]
    /// How many cards need the viewer.
    public let needsViewerCount: Int
    public let sections: [Section]

    public init(group: ListGroup, in tree: ListTree, viewer: Viewer,
                status: (PullRequest) -> StatusSentence) {
        self.group = group
        let ancestors = tree.ancestorIDs(of: .group(group.id)).compactMap { tree.group(id: $0)?.property }
        self.ancestorProperties = ancestors
        let named = Set(ancestors).union([group.property])

        func card(_ pr: PullRequest) -> Card {
            let sentence = status(pr)
            let move = Self.nextMove(pr, status: sentence)
            let viewersMove = if case .author(let author) = move { viewer.isViewer(author) && !pr.isDraft } else { false }
            return Card(pullRequest: pr, status: sentence, nextMove: move,
                        needsViewer: sentence.isReviewRequestedFromViewer || viewersMove)
        }

        let cards = group.pullRequests.map(card)
        let cardByID = Dictionary(cards.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.statusCounts = Self.counts(cards)
        self.needsViewerCount = cards.count { $0.needsViewer }

        if !group.children.isEmpty {
            sections = group.children.map { child in
                let cards = child.pullRequests.compactMap { cardByID[$0.id] }
                return Section(id: child.id, name: child.name, groupID: child.id,
                               namedProperties: named.union([child.property]), cards: cards,
                               statusCounts: Self.counts(cards))
            }
        } else if !named.contains(.status) {
            let order = StatusSentence.Badge.allCases
            sections = order.compactMap { badge in
                let cards = cards.filter { $0.status.badge == badge }
                guard !cards.isEmpty else { return nil }
                return Section(id: "status:\(badge.rawValue)", name: DisplayName(badge.name), groupID: nil,
                               namedProperties: named.union([.status]), cards: cards,
                               statusCounts: Self.counts(cards))
            }
        } else {
            sections = [Section(id: "all", name: nil, groupID: nil, namedProperties: named, cards: cards,
                                statusCounts: Self.counts(cards))]
        }
    }

    /// The kinds of title row the overview's sections are, such as repositories, or nil when
    /// the sections are by status or there is only one.
    public var sectionProperty: ListGrouping.Property? { group.children.first?.property }

    /// Whose move it is, from the status sentence's state.
    public static func nextMove(_ pr: PullRequest, status: StatusSentence) -> NextMove {
        switch status.state {
        case .merged, .closed: .nobody
        case .draft, .blocked, .changesRequested, .optionalChecksFailed, .threadsUnresolved, .behindBase, .readyToMerge:
            .author(pr.author)
        case .inMergeQueue: .mergeQueue
        case .checksRunning, .checksQueued: .checks
        case .waitingOnReviewers, .needsReview: .reviewers(pr.reviewRequests.map(\.reviewer))
        case .mergeabilityUnknown: .github
        }
    }

    static func counts(_ cards: [Card]) -> [StatusCount] {
        var counts: [StatusSentence.Badge: Int] = [:]
        for card in cards { counts[card.status.badge, default: 0] += 1 }
        return StatusSentence.Badge.allCases.compactMap { badge in
            counts[badge].map { StatusCount(badge: badge, count: $0) }
        }
    }
}
