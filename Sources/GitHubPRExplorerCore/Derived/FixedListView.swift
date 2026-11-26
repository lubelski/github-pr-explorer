import Foundation

/// The three views the pull request list offers above its rows: a fixed choice of which open
/// pull requests to list. The search narrows the list further within the chosen view.
///
/// These are fixed for now, written as plain predicates. They are not the filter language and
/// not saved views. When the filter language arrives, each becomes a built-in filter written in
/// it, and this type goes away rather than becoming a second way to write a condition.
public enum FixedListView: String, Codable, Sendable, Hashable, CaseIterable, Identifiable {
    /// Open pull requests where a review is asked of the viewer or one of the viewer's teams.
    case needsMyReview
    /// Open pull requests the viewer wrote.
    case mine
    /// Every open pull request.
    case everythingOpen

    public var id: String { rawValue }

    /// The view the list starts in when nothing was chosen before.
    public static let standard: FixedListView = .needsMyReview

    public var name: String {
        switch self {
        case .needsMyReview: "Needs my review"
        case .mine: "Mine"
        case .everythingOpen: "Everything open"
        }
    }

    /// A shorter name for when the list is too narrow for the full ones.
    public var shortName: String {
        switch self {
        case .needsMyReview: "Review"
        case .mine: "Mine"
        case .everythingOpen: "All open"
        }
    }

    public func includes(_ pr: PullRequest, viewer: Viewer) -> Bool {
        guard pr.state == .open else { return false }
        switch self {
        case .needsMyReview: return pr.isReviewRequested(from: viewer)
        case .mine: return viewer.isViewer(pr.author)
        case .everythingOpen: return true
        }
    }

    /// The pull requests in this view, in the order given.
    public func pullRequests(in pullRequests: [PullRequest], viewer: Viewer) -> [PullRequest] {
        pullRequests.filter { includes($0, viewer: viewer) }
    }
}
