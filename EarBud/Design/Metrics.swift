import CoreGraphics

/// Spacing, sizes and corner radii from `mockups.css`.
enum Metrics {
    // Window.
    static let windowWidth: CGFloat = 1340
    static let windowHeight: CGFloat = 830
    static let windowMinWidth: CGFloat = 1020
    static let windowMinHeight: CGFloat = 620

    // Columns.
    static let sidebarWidth: CGFloat = 222
    static let listWidth: CGFloat = 336
    static let searchWidth: CGFloat = 220

    // Recording list.
    static let rowInset: CGFloat = 8
    static let rowPaddingH: CGFloat = 10
    static let rowPaddingTop: CGFloat = 9
    static let rowPaddingBottom: CGFloat = 10
    static let rowRadius: CGFloat = 8
    static let dayPaddingH: CGFloat = 18

    // Detail.
    static let detailPaddingH: CGFloat = 32
    static let playerRadius: CGFloat = 12
    static let playButton: CGFloat = 38
    static let segmentRadius: CGFloat = 8
    static let timestampColumn: CGFloat = 52

    // Grouped forms.
    static let groupRadius: CGFloat = 9
    static let rowMinHeight: CGFloat = 42
    static let rowIcon: CGFloat = 26
    static let rowIconRadius: CGFloat = 7
    static let cardRadius: CGFloat = 14
    static let statRadius: CGFloat = 10

    // Controls.
    static let buttonRadius: CGFloat = 6
    static let buttonLargeRadius: CGFloat = 7
    static let pillHeight: CGFloat = 18

    // Hairlines.
    static let hairline: CGFloat = 0.5
}
