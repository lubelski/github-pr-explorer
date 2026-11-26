import AppKit
import GitHubPRExplorerCore
import SwiftUI

// Panes that slide over each other from the right. Ported from `mac-os-agent`
// (`Sources/mac-os-agent/PaneStack.swift`), where Settings sections use it, and adapted for the
// pull request page:
//
// - The path lives in `AppModel`, because it belongs to the selected pull request.
// - The caller works out every strip's width at once (`DiffPaneLayout`), instead of one strip
//   at a time, since the diff and thread panes have widths of their own.
// - A click anywhere on a covered strip goes back to that pane. Rows in a strip do not open
//   other items, so the strip needs no anchors.
// - Each pane draws its own header, with a back button and an "esc" hint, as in Figma row 8.

/// One pane of a stack, as the caller is asked to draw it.
struct PaneLevel: Identifiable {
    /// 0 for the base.
    let depth: Int
    /// The top pane's depth.
    let topDepth: Int
    /// The pane's item, or nil for the base.
    let item: String?

    var id: String { "\(depth)|\(item ?? "")" }
    var isCovered: Bool { depth < topDepth }
}

/// What a pane's parts need from the stack, for the panes' own back buttons.
struct PaneStackActions {
    var goBack: () -> Void = {}
}

extension EnvironmentValues {
    @Entry var paneStackActions = PaneStackActions()
    /// True for a pane under another: it is dimmed and still, and should not ask for focus.
    @Entry var paneIsCovered = false
}

/// Panes that slide over each other from the right. See the top of this file.
struct PaneStackView<Pane: View>: View {
    let path: PaneStackPath
    /// Each covered pane's strip, oldest first, for the stack's whole width.
    let stripWidths: (CGFloat) -> [CGFloat]
    /// What a covered pane's strip says to VoiceOver: "Back to the pull request".
    let backLabel: (PaneLevel) -> String
    /// Changes the path, with the stack's motion.
    let change: (_ body: @escaping (inout PaneStackPath) -> Void) -> Void
    /// The view for each level, given the stack's whole width.
    @ViewBuilder let pane: (PaneLevel, CGFloat) -> Pane

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let topDepth = path.depth
        let levels = (0...topDepth).map { PaneLevel(depth: $0, topDepth: topDepth, item: path.entry(at: $0)) }
        GeometryReader { proxy in
            let widths = stripWidths(proxy.size.width)
            let edges = PaneStackLayout.leadingEdges(stripWidths: widths)
            let tops = PaneStackLayout.topEdges(stripWidths: widths)
            ZStack(alignment: .topLeading) {
                ForEach(levels) { level in
                    paneView(level, available: proxy.size.width)
                        .padding(.leading, edges.indices.contains(level.depth) ? edges[level.depth] : 0)
                        .padding(.top, tops.indices.contains(level.depth) ? tops[level.depth] : 0)
                        .transition(level.depth == 0 ? .identity : PaneMotion.transition(reduceMotion: reduceMotion))
                        .zIndex(Double(level.depth))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .clipped()
        .background {
            // Escape closes one pane. With only the base showing there is no button, so Escape
            // means what it meant before.
            if !path.isAtBase {
                Button("Back") { change { $0.goBack() } }
                    .keyboardShortcut(.cancelAction)
                    .opacity(0)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
    }

    private func paneView(_ level: PaneLevel, available: CGFloat) -> some View {
        let depth = level.depth
        return pane(level, available)
            .environment(\.paneStackActions, PaneStackActions(goBack: { change { $0.goBack(to: depth - 1) } }))
            .environment(\.paneIsCovered, level.isCovered)
            .modifier(CoveredPane(isCovered: level.isCovered, backLabel: backLabel(level),
                                  click: { change { $0.goBack(to: depth) } }))
            .modifier(PaneCard(level: depth))
    }
}

/// The stack's motion: a 0.28-second spring with no bounce, or a fade with Reduce Motion on.
enum PaneMotion {
    static func animation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.28, bounce: 0)
    }

    static func transition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: .trailing)
    }
}

/// The hairline along a card's top and leading edges, round at the top-leading corner.
struct PaneCardEdge: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.minY),
            tangent2End: CGPoint(x: rect.minX + radius, y: rect.minY), radius: radius)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

/// A sliding pane's card: the page's surface, round at the top-leading corner, square and flush
/// at the bottom and right, with a shadow to the left. The base (level 0) has no card.
struct PaneCard: ViewModifier {
    static let cornerRadius: CGFloat = 12

    let level: Int
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    func body(content: Content) -> some View {
        if level == 0 {
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            let shape = UnevenRoundedRectangle(topLeadingRadius: Self.cornerRadius, style: .continuous)
            let dark = colorScheme == .dark
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Style.surface)
                .clipShape(shape)
                .overlay {
                    PaneCardEdge(radius: Self.cornerRadius)
                        .offset(x: 0.5 / displayScale, y: 0.5 / displayScale)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1 / displayScale)
                }
                .shadow(color: .black.opacity(dark ? 0.4 : 0.12), radius: 10, x: -4, y: 0)
        }
    }
}

/// A pane under another: dimmed, still, and hidden from accessibility apart from a "Back to"
/// button. A click anywhere on its strip goes back to it.
struct CoveredPane: ViewModifier {
    let isCovered: Bool
    let backLabel: String
    let click: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .scrollDisabled(isCovered)
            .allowsHitTesting(!isCovered)
            .accessibilityHidden(isCovered)
            .overlay {
                if isCovered {
                    Rectangle()
                        .fill(Color.black.opacity(colorScheme == .dark ? 0.35 : 0.14))
                        .contentShape(.rect)
                        .onTapGesture(perform: click)
                        .transition(.opacity)
                        .accessibilityElement()
                        .accessibilityLabel(Text(backLabel))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { click() }
                        .help(backLabel)
                }
            }
    }
}

/// A pane's header: an "esc" hint, a back button naming where it goes, the title, and anything
/// the pane puts at the trailing end.
struct PaneHeader<Trailing: View>: View {
    let backTitle: String
    let title: Text
    @ViewBuilder let trailing: Trailing
    @Environment(\.paneStackActions) private var actions

    var body: some View {
        HStack(spacing: 10) {
            Text("esc")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Style.hairline, lineWidth: 1))
                .accessibilityHidden(true)
            Button(action: actions.goBack) {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
                    Text(backTitle)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.accentColor)
            .foregroundStyle(.tint)
            .help("Back to \(backTitle.lowercased()) (Escape)")
            title
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
    }
}
