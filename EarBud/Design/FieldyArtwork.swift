import SwiftUI

/// The generic wristband recorder drawing from `kit.js` (`.fieldy-art`). Not Field Labs artwork.
struct FieldyArtwork: View {
    var width: CGFloat = 220
    /// LED colour; `nil` draws the light off.
    var led: Color? = nil
    /// Draws the three "searching" rings behind the device.
    var radar = false

    var body: some View {
        Canvas { context, size in
            let s = size.width / 220
            func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
                CGRect(x: x * s, y: y * s, width: w * s, height: h * s)
            }
            func circle(_ cx: CGFloat, _ cy: CGFloat, _ radius: CGFloat) -> Path {
                Path(ellipseIn: r(cx - radius, cy - radius, radius * 2, radius * 2))
            }
            let pine = Color(red: 0x2C / 255, green: 0x7A / 255, blue: 0x6B / 255)

            if radar {
                for (radius, opacity) in [(68.0, 0.24), (84.0, 0.14), (100.0, 0.07)] {
                    context.stroke(circle(110, 80, radius), with: .color(pine.opacity(opacity)), lineWidth: 1.5 * s)
                }
            }

            // Band.
            let band = Color(red: 0xCF / 255, green: 0xC6 / 255, blue: 0xBA / 255)
            context.fill(
                Path(roundedRect: r(0, 58, 220, 44), cornerRadius: 10 * s),
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: band.opacity(0), location: 0),
                        .init(color: band, location: 0.22),
                        .init(color: band, location: 0.78),
                        .init(color: band.opacity(0), location: 1),
                    ]),
                    startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: size.width, y: 0)))
            var stitches = Path()
            for (x0, x1) in [(22.0, 62.0), (158.0, 198.0)] {
                for y in [66.0, 94.0] {
                    stitches.move(to: CGPoint(x: x0 * s, y: y * s))
                    stitches.addLine(to: CGPoint(x: x1 * s, y: y * s))
                }
            }
            context.stroke(stitches, with: .color(Color(red: 0xB8 / 255, green: 0xAE / 255, blue: 0xA1 / 255).opacity(0.5)), lineWidth: s)

            // Pod with a soft drop shadow.
            let pod = Path(roundedRect: r(62, 32, 96, 96), cornerRadius: 30 * s, style: .continuous)
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: Color(red: 0x2A / 255, green: 0x1A / 255, blue: 0x0A / 255).opacity(0.28), radius: 7 * s, x: 0, y: 6 * s))
                layer.fill(pod, with: .linearGradient(
                    Gradient(colors: [Color(red: 0x4A / 255, green: 0x4B / 255, blue: 0x4F / 255), Color(red: 0x23 / 255, green: 0x24 / 255, blue: 0x27 / 255)]),
                    startPoint: CGPoint(x: 0, y: 32 * s), endPoint: CGPoint(x: 0, y: 128 * s)))
            }
            context.stroke(Path(roundedRect: r(63, 33, 94, 94), cornerRadius: 29 * s, style: .continuous), with: .color(.white.opacity(0.1)), lineWidth: s)

            // Button.
            context.fill(circle(110, 84, 19), with: .color(Color(red: 0x2B / 255, green: 0x2C / 255, blue: 0x2F / 255)))
            context.stroke(circle(110, 84, 19), with: .color(.white.opacity(0.12)), lineWidth: 1.5 * s)
            context.stroke(circle(110, 84, 13), with: .color(.black.opacity(0.25)), lineWidth: s)

            // Light.
            if let led {
                context.fill(circle(110, 50, 12), with: .radialGradient(
                    Gradient(colors: [led.opacity(0.9), led.opacity(0)]),
                    center: CGPoint(x: 110 * s, y: 50 * s), startRadius: 0, endRadius: 12 * s))
                context.fill(circle(110, 50, 3.6), with: .color(led))
            } else {
                context.fill(circle(110, 50, 3.2), with: .color(Color(red: 0x55 / 255, green: 0x56 / 255, blue: 0x5A / 255)))
            }
        }
        .frame(width: width, height: width * 160 / 220)
        .accessibilityHidden(true)
    }
}
