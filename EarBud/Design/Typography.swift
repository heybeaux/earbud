import SwiftUI

/// Type scale from `mockups.css`. Sizes are in points; the mockups use SF Pro at 13 pt body.
enum Typography {
    static let body = Font.system(size: 13)
    static let bodyMedium = Font.system(size: 13, weight: .medium)
    static let bodySemibold = Font.system(size: 13, weight: .semibold)
    static let small = Font.system(size: 11)
    static let smallMedium = Font.system(size: 11, weight: .medium)
    static let caption = Font.system(size: 11.5)
    static let captionSemibold = Font.system(size: 11.5, weight: .semibold)
    static let footnote = Font.system(size: 12)
    static let callout = Font.system(size: 12.5)

    // Toolbar and sidebar.
    static let toolbarTitle = Font.system(size: 15, weight: .bold)
    static let sidebarHeader = Font.system(size: 11, weight: .semibold)

    // Recording list.
    static let dayHeader = Font.system(size: 12, weight: .bold)
    static let dayCount = Font.system(size: 12, weight: .medium)
    static let rowTitle = Font.system(size: 13, weight: .semibold)
    static let rowTitleUntitled = Font.system(size: 13, weight: .medium)
    static let rowMeta = Font.system(size: 11.5)
    static let rowPreview = Font.system(size: 12.5)
    static let pill = Font.system(size: 11, weight: .semibold)

    // Detail.
    static let detailTitle = Font.system(size: 22, weight: .bold)
    static let detailSubtitle = Font.system(size: 12.5)
    static let transcriptHeader = Font.system(size: 11, weight: .semibold)
    static let segment = Font.system(size: 14)
    static let timestamp = Font.system(size: 11.5, weight: .semibold).monospacedDigit()
    static let playerTime = Font.system(size: 11.5).monospacedDigit()
    static let speed = Font.system(size: 12, weight: .medium)

    // Empty state and headings.
    static let largeTitle = Font.system(size: 24, weight: .bold)
    static let lead = Font.system(size: 14)
    static let stepTitle = Font.system(size: 13.5, weight: .semibold)
    static let sectionTitle = Font.system(size: 13, weight: .bold)

    // Device panel.
    static let deviceName = Font.system(size: 18, weight: .bold)
    static let statValue = Font.system(size: 19, weight: .bold).monospacedDigit()
    static let statValueSmall = Font.system(size: 15, weight: .bold)
    static let timer = Font.system(size: 26, weight: .semibold).monospacedDigit()
    static let cardTitle = Font.system(size: 13.5, weight: .semibold)

    // Menu-bar menu.
    static let menuItem = Font.system(size: 13.5)
    static let menuInfo = Font.system(size: 12)
}

/// Line spacing helper: CSS line-height × size minus the font's natural leading (~1.2 × size).
extension View {
    func cssLineHeight(_ multiple: CGFloat, size: CGFloat) -> some View {
        lineSpacing(max(0, (multiple - 1.2) * size))
    }
}
