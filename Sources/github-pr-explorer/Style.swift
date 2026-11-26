import AppKit
import GitHubPRExplorerCore
import SwiftUI

/// Sizes, colors and symbols the page shares. Colors are the system's, so light and dark both
/// work, except for added and removed lines, which have fixed colors of their own.
enum Style {
    static let cornerRadius: CGFloat = 8
    static let blockSpacing: CGFloat = 16
    static let blockTitle = Font.system(size: 13, weight: .semibold)
    static let body = Font.system(size: 13)
    static let secondary = Font.system(size: 11)
    static let rowSpacing: CGFloat = 6

    /// The page behind the blocks: the surface tinted a step toward the text color, so cards
    /// stand off it in light and in dark. The system's window colors draw the same as the
    /// surface on this macOS, so the tint is drawn here.
    static var pageBackground: some View {
        ZStack {
            surface
            Color.primary.opacity(0.045)
        }
    }
    /// A block's card, the header and the list.
    static let surface = Color(nsColor: .textBackgroundColor)
    static let hairline = Color(nsColor: .separatorColor)

    static let added = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.36, green: 0.78, blue: 0.53, alpha: 1)
            : NSColor(srgbRed: 0.16, green: 0.60, blue: 0.38, alpha: 1)
    })
    static let removed = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.98, green: 0.42, blue: 0.42, alpha: 1)
            : NSColor(srgbRed: 0.88, green: 0.24, blue: 0.26, alpha: 1)
    })
}

/// A status as a symbol and a color. The symbol always carries the meaning, so color is never
/// the only sign.
struct StatusMark: View {
    let systemName: String
    let color: Color
    var size: CGFloat = 11

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size + 3)
            .accessibilityHidden(true)
    }
}

extension StatusSentence.Symbol {
    var systemName: String {
        switch self {
        case .cross: "xmark"
        case .filledCircle: "circle.fill"
        case .halfCircle: "circle.lefthalf.filled"
        case .emptyCircle: "circle.dashed"
        case .check: "checkmark"
        case .slashedCircle: "nosign"
        }
    }

    var color: Color {
        switch self {
        case .cross: .red
        case .filledCircle, .halfCircle: .orange
        case .emptyCircle, .slashedCircle: .secondary
        case .check: .green
        }
    }
}

extension CheckState {
    var systemName: String {
        switch self {
        case .failed: "xmark"
        case .running: "circle.fill"
        case .queued: "clock"
        case .passed: "checkmark"
        case .skipped: "arrow.turn.down.right"
        case .cancelled: "slash.circle"
        }
    }

    var color: Color {
        switch self {
        case .failed: .red
        case .running: .orange
        case .passed: .green
        case .queued, .skipped, .cancelled: .secondary
        }
    }
}

extension ReviewerRow.State {
    var systemName: String {
        switch self {
        case .approved: "checkmark"
        case .changesRequested: "xmark"
        case .commented: "text.bubble"
        case .requested: "circle"
        }
    }

    var color: Color {
        switch self {
        case .approved: .green
        case .changesRequested: .red
        case .commented: .secondary
        case .requested: .orange
        }
    }
}

/// Inline markdown, such as `code` and **bold**, for one line or paragraph.
func inlineMarkdown(_ text: String) -> AttributedString {
    (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
        ?? AttributedString(text)
}

/// A small rounded tag, such as "needs you" or "owned by @acme/security".
struct Tag: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(color == .secondary ? Color.secondary : color)
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.14)))
    }
}

/// A text button that reads as a link, such as "Show".
struct LinkButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
    }
}

/// Whether views are being drawn to a file. Offscreen, a list's selection does not draw, so
/// views draw it themselves.
extension EnvironmentValues {
    @Entry var isRenderingPreview = false
    /// A render opens every "N more" row, to show long blocks in full.
    @Entry var previewExpandsBlocks = false
}
