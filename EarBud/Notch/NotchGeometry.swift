import CoreGraphics

/// Where the notch is and how big the dock is in each state. Pure math in AppKit screen
/// coordinates (origin bottom-left, y up), so it can be tested without a screen.
enum NotchGeometry {
    /// Width of each indicator beside the notch while resting (status dot, "23m").
    static let restingWing: CGFloat = 36
    /// Width of each side while something is live ("2 of 3", "03:42").
    static let liveWing: CGFloat = 56
    /// Extra height below the notch for the sync progress bar.
    static let progressBarHeight: CGFloat = 14
    /// Extra height below the notch for "3 new recordings".
    static let messageHeight: CGFloat = 28
    /// Narrowest the expanded panel gets.
    static let expandedMinWidth: CGFloat = 380
    /// Panel body below the notch row, with and without the newest-transcript card.
    static let expandedBodyHeight: CGFloat = 112
    static let expandedTranscriptHeight: CGFloat = 94
    static let bottomRadius: CGFloat = 10
    static let expandedBottomRadius: CGFloat = 18

    /// The shape the dock is drawn in.
    enum Layout: Equatable {
        case resting
        case recording
        case syncing
        case message
        case expanded(hasTranscript: Bool)
    }

    /// The camera housing: the gap between the two auxiliary top areas, as tall as the
    /// top safe-area inset. `nil` on screens without a notch. Only the areas' widths are used,
    /// so it doesn't matter whether AppKit reports them in global or screen-local coordinates.
    static func notchRect(screenFrame: CGRect, safeAreaTop: CGFloat, leftArea: CGRect?, rightArea: CGRect?) -> CGRect? {
        guard safeAreaTop > 0, let leftArea, let rightArea else { return nil }
        let minX = screenFrame.minX + leftArea.width, maxX = screenFrame.maxX - rightArea.width
        guard maxX > minX else { return nil }
        return CGRect(x: minX, y: screenFrame.maxY - safeAreaTop, width: maxX - minX, height: safeAreaTop)
    }

    /// Size of the drawn dock around a notch of `notch` size.
    static func size(for layout: Layout, notch: CGSize) -> CGSize {
        switch layout {
        case .resting:
            return CGSize(width: notch.width + 2 * restingWing, height: notch.height)
        case .recording:
            return CGSize(width: notch.width + 2 * liveWing, height: notch.height)
        case .syncing:
            return CGSize(width: notch.width + 2 * liveWing, height: notch.height + progressBarHeight)
        case .message:
            return CGSize(width: notch.width + 2 * liveWing, height: notch.height + messageHeight)
        case .expanded(let hasTranscript):
            let body = expandedBodyHeight + (hasTranscript ? expandedTranscriptHeight : 0)
            return CGSize(width: max(notch.width + 2 * liveWing, expandedMinWidth), height: notch.height + body)
        }
    }

    /// The dock's frame: centred on the notch, its top flush with the top of the screen,
    /// and kept inside the screen horizontally.
    static func frame(for layout: Layout, notch: CGRect, screenFrame: CGRect) -> CGRect {
        let size = size(for: layout, notch: notch.size)
        let width = min(size.width, screenFrame.width)
        let x = min(max(notch.midX - width / 2, screenFrame.minX), screenFrame.maxX - width)
        return CGRect(x: x, y: screenFrame.maxY - size.height, width: width, height: size.height).integral
    }

    /// Bottom corner radius of the drawn shape.
    static func bottomRadius(for layout: Layout) -> CGFloat {
        if case .expanded = layout { return expandedBottomRadius }
        return bottomRadius
    }
}

/// Which display gets the dock.
enum NotchScreenPicker {
    struct Candidate: Equatable {
        var name: String
        var isBuiltIn: Bool
        var hasNotch: Bool
    }

    /// The display named in Settings if it has a notch, else the built-in notched display,
    /// else any notched display. `nil` when no display has a notch (the floating capsule
    /// for those comes later).
    static func pick(_ screens: [Candidate], preferred: String?) -> Int? {
        if let preferred, let index = screens.firstIndex(where: { $0.name == preferred && $0.hasNotch }) {
            return index
        }
        return screens.firstIndex { $0.isBuiltIn && $0.hasNotch } ?? screens.firstIndex(where: \.hasNotch)
    }
}

/// Detects a full-screen app on a display from the on-screen window list. Bounds, layer and
/// owner are readable without Screen Recording permission.
enum FullScreenDetector {
    struct Window: Equatable {
        /// Quartz coordinates (origin top-left of the main display).
        var bounds: CGRect
        var layer: Int
        var ownerPID: Int32
    }

    /// True when another app's normal-level window covers the whole display, menu bar included.
    /// A zoomed window stops below the menu bar, so it doesn't count.
    static func isFullScreen(_ windows: [Window], displayBounds: CGRect, ownPID: Int32) -> Bool {
        windows.contains { window in
            window.layer == 0 && window.ownerPID != ownPID
                && window.bounds.insetBy(dx: -1, dy: -1).contains(displayBounds)
        }
    }
}
