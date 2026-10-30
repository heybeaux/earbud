import AppKit
import SwiftUI

/// Line glyphs from `design/mockups/kit.js` that have no SF Symbol equivalent.
/// Paths are drawn on the kit's 24 × 24 grid, y pointing down.
enum GlyphPaths {
    /// The EarBud speech bud outline (icon concept A, menu-bar glyph).
    static func budOutline() -> CGPath {
        let p = CGMutablePath()
        let center = CGPoint(x: 12, y: 11.5)
        let radius: CGFloat = 8.3
        p.move(to: CGPoint(x: 12, y: 3.2))
        // Clockwise (y down) from the top round to the lower left, where the tail starts.
        p.addRelativeArc(center: center, radius: radius, startAngle: -.pi / 2, delta: radians(123.7 + 90))
        p.addLine(to: CGPoint(x: 3.6, y: 20.2))
        p.addLine(to: CGPoint(x: 4.9, y: 16.3))
        p.addRelativeArc(center: center, radius: radius, startAngle: radians(146), delta: radians(270 - 146))
        p.closeSubpath()
        return p
    }

    /// Three bars inside the bud: "Ready".
    static func budBars() -> CGPath {
        let p = CGMutablePath()
        p.addLines(between: [CGPoint(x: 9, y: 10), CGPoint(x: 9, y: 14)])
        p.addLines(between: [CGPoint(x: 12, y: 8.3), CGPoint(x: 12, y: 15.7)])
        p.addLines(between: [CGPoint(x: 15, y: 10), CGPoint(x: 15, y: 14)])
        return p
    }

    /// Two arrows inside the bud: "Syncing".
    static func budSyncArrows() -> CGPath {
        let p = CGMutablePath()
        let c = CGPoint(x: 12, y: 12)
        p.addRelativeArc(center: c, radius: 3.6, startAngle: radians(-25), delta: radians(-150))
        p.addRelativeArc(center: c, radius: 3.6, startAngle: radians(155), delta: radians(-150))
        p.addLines(between: [CGPoint(x: 15.6, y: 8.4), CGPoint(x: 15.6, y: 10.4), CGPoint(x: 13.6, y: 10.4)])
        p.addLines(between: [CGPoint(x: 8.4, y: 15.6), CGPoint(x: 8.4, y: 13.6), CGPoint(x: 10.4, y: 13.6)])
        return p
    }

    /// The wristband pod used for "My Fieldy".
    static func podOutline() -> CGPath {
        let p = CGMutablePath()
        p.addRoundedRect(in: CGRect(x: 7, y: 6, width: 10, height: 12), cornerWidth: 3.2, cornerHeight: 3.2)
        for y: CGFloat in [9.5, 14.5] {
            p.addLines(between: [CGPoint(x: 2.5, y: y), CGPoint(x: 7, y: y)])
            p.addLines(between: [CGPoint(x: 17, y: y), CGPoint(x: 21.5, y: y)])
        }
        return p
    }

    private static func radians(_ degrees: CGFloat) -> CGFloat { degrees * .pi / 180 }
}

/// A kit glyph scaled into any frame, stroked like an SF Symbol.
struct StrokedGlyph: Shape {
    enum Kind: Sendable { case pod, bud }
    let kind: Kind

    func path(in rect: CGRect) -> Path {
        let source = switch kind {
        case .pod: GlyphPaths.podOutline()
        case .bud: GlyphPaths.budOutline()
        }
        let scale = min(rect.width, rect.height) / 24
        var t = CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: scale, y: scale)
        return Path(source.copy(using: &t) ?? source)
    }
}

/// The pod glyph: outline plus a filled centre button.
struct PodGlyph: View {
    var size: CGFloat = 16
    var lineWidth: CGFloat = 1.7

    var body: some View {
        ZStack {
            StrokedGlyph(kind: .pod)
                .stroke(style: StrokeStyle(lineWidth: lineWidth * size / 24, lineCap: .round, lineJoin: .round))
            Circle()
                .frame(width: 3.2 * size / 24, height: 3.2 * size / 24)
        }
        .frame(width: size, height: size)
    }
}

/// Menu-bar icon states, as in the legend on mockup 18.
enum MenuBarGlyphState: Equatable {
    case ready, syncing, recording, notNearby
}

enum MenuBarGlyph {
    /// An 18 pt image for `MenuBarExtra`. Drawn at display time, so colours follow the menu bar.
    @MainActor
    static func image(for state: MenuBarGlyphState) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let scale = rect.width / 24
            ctx.scaleBy(x: scale, y: scale)
            let ink = NSColor.labelColor.withAlphaComponent(state == .notNearby ? 0.45 : 1)
            ctx.setStrokeColor(ink.cgColor)
            ctx.setLineWidth(1.8)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.addPath(GlyphPaths.budOutline())
            ctx.addPath(state == .syncing ? GlyphPaths.budSyncArrows() : GlyphPaths.budBars())
            ctx.strokePath()
            if state == .recording {
                ctx.setFillColor(NSColor(srgbRed: 0xE5 / 255, green: 0x48 / 255, blue: 0x3C / 255, alpha: 1).cgColor)
                ctx.fillEllipse(in: CGRect(x: 17.5, y: 1.5, width: 6, height: 6))
            }
            return true
        }
        // Template images let macOS tint the glyph; the recording dot must stay red.
        image.isTemplate = state != .recording
        image.accessibilityDescription = "EarBud"
        return image
    }
}
