import CoreGraphics
import Foundation

/// Draws the app icon's artwork: white shapes on a clear background, one image per layer of
/// the Icon Composer file. `scripts/render-icon.sh` turns them into `Resources/AppIcon.icon`,
/// and the system adds the background, the rounded shape, and the glass.
///
/// There are four designs, kept from when the icon was chosen. `shipped` is the one in the app.
/// It is compiled on its own by `scripts/render-icon.sh`, so it uses CoreGraphics only.
public enum AppIconDrawing {
    /// The side of the square canvas, in pixels. Icon Composer's canvas for a Mac icon.
    public static let canvas: CGFloat = 1024

    /// The design in `Resources/AppIcon.icon`.
    public static let shipped = Design.branchEndingInLens

    public enum Design: Int, CaseIterable, Sendable {
        /// A magnifier with a pull request mark inside its lens: finding pull requests.
        case lensOverBranch = 1
        /// A stack of cards, the front one with a pull request mark cut out: the list.
        case cardStack = 2
        /// The pull request mark alone, large.
        case branch = 3
        /// The pull request mark whose head is a magnifier's lens: a pull request, explored. The
        /// shipped design. Its strokes are heavy so the branch and the lens still read at 32 px.
        case branchEndingInLens = 4

        public var title: String {
            switch self {
            case .lensOverBranch: "Lens over a pull request"
            case .cardStack: "Stack of pull requests"
            case .branch: "Pull request mark"
            case .branchEndingInLens: "Branch ending in a lens"
            }
        }

        /// The background gradient, top color first, as sRGB components. A deep indigo, apart
        /// from the green of github-pr-watch-menubar and the teal of mac-os-agent.
        public var gradient: (top: [CGFloat], bottom: [CGFloat]) {
            ([0.40, 0.42, 0.96], [0.15, 0.12, 0.50])
        }

        /// The layers, front first, as Icon Composer lists them.
        public var layers: [Layer] {
            switch self {
            case .lensOverBranch:
                [Layer(name: "mark", draw: { AppIconDrawing.pullRequestMark(in: $0, center: AppIconDrawing.lensCenter, size: 250, weight: 1.5) }),
                 Layer(name: "lens", draw: AppIconDrawing.lens)]
            case .cardStack:
                [Layer(name: "front", draw: AppIconDrawing.frontCard),
                 Layer(name: "behind", draw: AppIconDrawing.cardsBehind)]
            case .branch:
                [Layer(name: "mark", draw: { AppIconDrawing.pullRequestMark(in: $0, center: CGPoint(x: 512, y: 512), size: 600, weight: 1) })]
            case .branchEndingInLens:
                [Layer(name: "lens", draw: AppIconDrawing.headLens),
                 Layer(name: "branch", draw: AppIconDrawing.branchToLens)]
            }
        }
    }

    /// One layer of the icon: a name for its image, and a routine that draws it in white on a
    /// clear, canvas-sized context with y pointing up.
    public struct Layer: Sendable {
        public let name: String
        public let draw: @Sendable (CGContext) -> Void
    }

    static let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)

    // MARK: The pull request mark

    /// The pull request mark, drawn in a square `size` wide around `center`: the base branch
    /// as a line between two dots on the left, and on the right the head's dot with a line
    /// that rises and turns left into an arrow, toward the base. `weight` thickens the lines
    /// and dots for small sizes.
    static func pullRequestMark(in context: CGContext, center: CGPoint, size: CGFloat, weight: CGFloat) {
        let u = size / 512
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: center.x + (x - 256) * u, y: center.y + (y - 256) * u)
        }
        let line = 46 * u * weight
        let dot = 58 * u * weight
        context.setFillColor(white)
        context.setStrokeColor(white)
        context.setLineWidth(line)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        // The base branch.
        context.move(to: p(112, 70))
        context.addLine(to: p(112, 442))
        // The head: up from its dot, around the corner, and left to the arrow.
        context.move(to: p(400, 70))
        context.addLine(to: p(400, 330))
        context.addQuadCurve(to: p(300, 430), control: p(400, 430))
        context.addLine(to: p(240, 430))
        // The arrowhead.
        let head = 62 * u * max(1, weight * 0.85)
        context.move(to: CGPoint(x: p(240, 430).x + head, y: p(240, 430).y + head))
        context.addLine(to: p(240, 430))
        context.addLine(to: CGPoint(x: p(240, 430).x + head, y: p(240, 430).y - head))
        context.strokePath()
        for c in [p(112, 70), p(112, 442), p(400, 70)] {
            context.fillEllipse(in: CGRect(x: c.x - dot, y: c.y - dot, width: dot * 2, height: dot * 2))
        }
    }

    // MARK: Design 1, the lens

    static let lensCenter = CGPoint(x: 452, y: 572)
    static let lensRadius: CGFloat = 228

    @Sendable static func lens(_ context: CGContext) {
        context.setStrokeColor(white)
        context.setLineWidth(60)
        context.strokeEllipse(in: CGRect(x: lensCenter.x - lensRadius, y: lensCenter.y - lensRadius,
                                         width: lensRadius * 2, height: lensRadius * 2))
        // The handle, down and to the right.
        let angle = -CGFloat.pi / 4
        let from = CGPoint(x: lensCenter.x + (lensRadius + 40) * cos(angle), y: lensCenter.y + (lensRadius + 40) * sin(angle))
        context.setLineWidth(104)
        context.setLineCap(.round)
        context.move(to: from)
        context.addLine(to: CGPoint(x: 800, y: 224))
        context.strokePath()
    }

    // MARK: Design 2, the cards

    static let cardSize = CGSize(width: 560, height: 380)

    static func card(at origin: CGPoint) -> CGPath {
        CGPath(roundedRect: CGRect(origin: origin, size: cardSize), cornerWidth: 64, cornerHeight: 64, transform: nil)
    }

    @Sendable static func frontCard(_ context: CGContext) {
        let origin = CGPoint(x: 200, y: 190)
        context.setFillColor(white)
        context.addPath(card(at: origin))
        context.fillPath()
        // The mark, cut out of the card.
        context.setBlendMode(.clear)
        pullRequestMark(in: context, center: CGPoint(x: origin.x + cardSize.width / 2, y: origin.y + cardSize.height / 2),
                        size: 270, weight: 1.3)
        context.setBlendMode(.normal)
    }

    @Sendable static func cardsBehind(_ context: CGContext) {
        // Only the strips that show above the front card, so the glass does not stack.
        context.setFillColor(white.copy(alpha: 0.72)!)
        for (index, origin) in [CGPoint(x: 232, y: 290), CGPoint(x: 264, y: 390)].enumerated() {
            context.saveGState()
            let below = index == 0 ? CGFloat(190) : 290
            context.clip(to: CGRect(x: 0, y: below + cardSize.height + 14, width: canvas, height: canvas))
            context.addPath(card(at: origin))
            context.fillPath()
            context.restoreGState()
        }
    }

    // MARK: Design 4, a branch that ends in a lens

    static let headLensCenter = CGPoint(x: 650, y: 410)
    static let headLensRadius: CGFloat = 118

    @Sendable static func headLens(_ context: CGContext) {
        let c = headLensCenter, r = headLensRadius
        context.setStrokeColor(white)
        context.setLineWidth(68)
        context.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        // The handle, down and to the right.
        context.setLineWidth(96)
        context.setLineCap(.round)
        let a = -CGFloat.pi / 4
        context.move(to: CGPoint(x: c.x + (r + 34) * cos(a), y: c.y + (r + 34) * sin(a)))
        context.addLine(to: CGPoint(x: 812, y: 236))
        context.strokePath()
    }

    @Sendable static func branchToLens(_ context: CGContext) {
        context.setFillColor(white)
        context.setStrokeColor(white)
        context.setLineWidth(84)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        // The base branch: a line between two dots.
        let x: CGFloat = 300, bottom: CGFloat = 262, top: CGFloat = 762
        context.move(to: CGPoint(x: x, y: bottom))
        context.addLine(to: CGPoint(x: x, y: top))
        // The head: from the lens, up and around to the left, into an arrow at the base.
        let c = headLensCenter
        context.move(to: CGPoint(x: c.x, y: c.y + headLensRadius + 34))
        context.addLine(to: CGPoint(x: c.x, y: 662))
        context.addQuadCurve(to: CGPoint(x: 550, y: top), control: CGPoint(x: c.x, y: top))
        context.addLine(to: CGPoint(x: 476, y: top))
        context.move(to: CGPoint(x: 536, y: top + 56))
        context.addLine(to: CGPoint(x: 476, y: top))
        context.addLine(to: CGPoint(x: 536, y: top - 56))
        context.strokePath()
        for y in [bottom, top] {
            context.fillEllipse(in: CGRect(x: x - 84, y: y - 84, width: 168, height: 168))
        }
    }

    // MARK: Output

    /// Draws one layer on a clear canvas.
    public static func image(of layer: Layer) -> CGImage? {
        let size = Int(canvas)
        guard let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        layer.draw(context)
        return context.makeImage()
    }

    /// The Icon Composer file's `icon.json` for a design, naming each layer's image as
    /// `<name>.png`.
    public static func iconJSON(for design: Design) -> String {
        func color(_ c: [CGFloat]) -> String {
            "srgb:" + (c + [1]).map { String(format: "%.5f", Double($0)) }.joined(separator: ",")
        }
        let layers = design.layers.map {
            """
                    {
                      "image-name" : "\($0.name).png",
                      "name" : "\($0.name)"
                    }
            """
        }.joined(separator: ",\n")
        return """
        {
          "fill" : {
            "linear-gradient" : [
              "\(color(design.gradient.top))",
              "\(color(design.gradient.bottom))"
            ]
          },
          "groups" : [
            {
              "layers" : [
        \(layers)
              ],
              "shadow" : {
                "kind" : "neutral",
                "opacity" : 0.5
              },
              "translucency" : {
                "enabled" : false,
                "value" : 0.5
              }
            }
          ],
          "supported-platforms" : {
            "squares" : [
              "macOS"
            ]
          }
        }

        """
    }
}
