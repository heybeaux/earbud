import AppKit
import SwiftUI

/// Colour tokens from `design/mockups/mockups.css` (`:root` for light, `.dark` for dark).
/// Every token resolves per appearance, so views never branch on the colour scheme.
enum Palette {
    // Accent: Pine.
    static let accent = dynamic(light: rgb(0x2C7A6B), dark: rgb(0x3FA592))
    static let accentHi = dynamic(light: rgb(0x34907E), dark: rgb(0x49B19D))
    static let accentTint = dynamic(light: rgb(0x2C7A6B, 0.13), dark: rgb(0x3FA592, 0.20))
    static let accentTintStrong = dynamic(light: rgb(0x2C7A6B, 0.22), dark: rgb(0x3FA592, 0.32))

    // Labels.
    static let label = dynamic(light: white(0, 0.86), dark: white(1, 0.88))
    static let label2 = dynamic(light: white(0, 0.55), dark: white(1, 0.55))
    static let label3 = dynamic(light: white(0, 0.32), dark: white(1, 0.30))

    // Lines and fills.
    static let separator = dynamic(light: white(0, 0.09), dark: white(1, 0.08))
    static let separatorStrong = dynamic(light: white(0, 0.14), dark: white(0, 0.60))
    static let fill = dynamic(light: white(0, 0.05), dark: white(1, 0.07))
    static let fill2 = dynamic(light: white(0, 0.08), dark: white(1, 0.10))

    // Surfaces.
    static let content = dynamic(light: rgb(0xFFFFFF), dark: rgb(0x1F1F1F))
    static let content2 = dynamic(light: rgb(0xFAF9F7), dark: rgb(0x262626))
    static let group = dynamic(light: white(0, 0.028), dark: white(1, 0.04))
    static let groupBorder = dynamic(light: white(0, 0.07), dark: white(1, 0.07))
    static let control = dynamic(light: rgb(0xFFFFFF), dark: rgb(0x5A5A5C))
    static let controlOn = dynamic(light: rgb(0xFFFFFF), dark: rgb(0x636366))
    static let controlBorder = dynamic(light: white(0, 0.13), dark: white(0, 0.20))
    static let settingsBackground = dynamic(light: rgb(0xF6F5F3), dark: rgb(0x262626))
    static let deviceCard = dynamic(light: white(1, 0.55), dark: white(1, 0.06))
    static let deviceCardBorder = dynamic(light: white(0, 0.07), dark: white(1, 0.06))

    // Status.
    static let red = rgbStatic(0xE5483C)
    static let green = dynamic(light: rgb(0x2FA84F), dark: rgb(0x32C25A))
    static let orange = rgbStatic(0xE8912D)
    static let neutralDot = rgbStatic(0xA6A29C)
    static let neutralIcon = rgbStatic(0x8A8580)

    // Search highlight.
    static let highlight = dynamic(light: rgb(0xFFCC00, 0.42), dark: rgb(0xFFCC00, 0.35))
    static let highlightCurrent = rgbStatic(0xFFCC1F)
    static let highlightOnAccent = Color(red: 1, green: 224 / 255, blue: 102 / 255).opacity(0.95)

    // Places where the dark mockup (22) tunes a colour beyond the shared tokens.
    static let selectedRow = dynamic(light: rgb(0x2C7A6B), dark: rgb(0x2E7E70))
    static let currentSegment = dynamic(light: rgb(0x2C7A6B, 0.13), dark: rgb(0x3FA592, 0.16))
    static let sidebarIcon = dynamic(light: rgb(0x2C7A6B), dark: rgb(0x5DBFAB))
    static let podIcon = dynamic(light: rgb(0x2C7A6B), dark: rgb(0x6CC9B6))
    static let waveIdle = dynamic(light: white(0, 0.16), dark: white(1, 0.20))

    // Pills.
    static let pillDoneText = dynamic(light: rgb(0x23803C), dark: rgb(0x5BCB7A))
    static let pillDoneBackground = dynamic(light: rgb(0x2FA84F, 0.13), dark: rgb(0x2FA84F, 0.20))
    static let pillFailText = rgbStatic(0xC2392E)
    static let pillFailBackground = rgbStatic(0xE5483C, 0.12)
    static let pillIncompleteText = rgbStatic(0xA8641A)
    static let pillIncompleteBackground = rgbStatic(0xE8912D, 0.15)

    // Record card.
    static let recordCard = rgbStatic(0xE5483C, 0.07)
    static let recordCardBorder = rgbStatic(0xE5483C, 0.25)
    static let recordDotHalo = rgbStatic(0xE5483C, 0.14)

    // MARK: Helpers

    /// RGBA components, stored as plain values so the dynamic provider stays `Sendable`.
    struct RGBA: Sendable {
        var r: Double, g: Double, b: Double, a: Double
    }

    static func rgb(_ hex: UInt32, _ alpha: Double = 1) -> RGBA {
        RGBA(r: Double((hex >> 16) & 0xFF) / 255, g: Double((hex >> 8) & 0xFF) / 255, b: Double(hex & 0xFF) / 255, a: alpha)
    }

    static func white(_ level: Double, _ alpha: Double) -> RGBA {
        RGBA(r: level, g: level, b: level, a: alpha)
    }

    static func rgbStatic(_ hex: UInt32, _ alpha: Double = 1) -> Color {
        let c = rgb(hex, alpha)
        return Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: c.a)
    }

    static func dynamic(light: RGBA, dark: RGBA) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let c = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: c.a)
        })
    }
}
