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

/// The floating capsule shown instead on a display without a notch (mockup 20): a black pill
/// just below the menu bar at the top centre, which grows into the same quick panel.
enum CapsuleGeometry {
    /// Height of the collapsed pill; also the top row of the expanded panel.
    static let height: CGFloat = 32
    /// Space between the menu bar (or the top of the screen) and the capsule.
    static let gap: CGFloat = 8
    static let restingWidth: CGFloat = 240
    static let recordingWidth: CGFloat = 200
    static let syncingWidth: CGFloat = 270
    static let messageWidth: CGFloat = 240
    static let expandedWidth: CGFloat = 420

    static func size(for layout: NotchGeometry.Layout) -> CGSize {
        switch layout {
        case .resting: CGSize(width: restingWidth, height: height)
        case .recording: CGSize(width: recordingWidth, height: height)
        case .syncing: CGSize(width: syncingWidth, height: height)
        case .message: CGSize(width: messageWidth, height: height)
        case .expanded(let hasTranscript):
            CGSize(width: expandedWidth,
                   height: height + NotchGeometry.expandedBodyHeight + (hasTranscript ? NotchGeometry.expandedTranscriptHeight : 0))
        }
    }

    /// Centred on the display, hanging `gap` below the menu bar. `visibleFrame` is the screen's
    /// visible frame, whose top is the bottom of the menu bar (or the top of the screen when
    /// that display has no menu bar).
    static func frame(for layout: NotchGeometry.Layout, screenFrame: CGRect, visibleFrame: CGRect) -> CGRect {
        let size = size(for: layout)
        let width = min(size.width, screenFrame.width)
        let top = min(visibleFrame.maxY, screenFrame.maxY) - gap
        return CGRect(x: screenFrame.midX - width / 2, y: top - size.height, width: width, height: size.height).integral
    }

    /// Corner radius on all four corners: a full pill when collapsed, a rounded panel when expanded.
    static func cornerRadius(for layout: NotchGeometry.Layout) -> CGFloat {
        if case .expanded = layout { return NotchGeometry.expandedBottomRadius }
        return height / 2
    }
}

/// Which display gets the dock, and whether it's drawn around a notch or as a floating capsule.
enum NotchScreenPicker {
    struct Candidate: Equatable {
        var name: String
        var isBuiltIn: Bool
        var hasNotch: Bool
    }

    enum Placement: Equatable {
        case notch(Int)
        case capsule(Int)

        var index: Int {
            switch self {
            case .notch(let index), .capsule(let index): index
            }
        }
    }

    /// The display named in Settings while it's connected; otherwise the built-in display;
    /// otherwise any display with a notch. `nil` means menu bar only. Displays with a notch get
    /// the notch dock, others the floating capsule.
    static func pick(_ screens: [Candidate], preferred: String?) -> Placement? {
        let index = preferred.flatMap { name in screens.firstIndex { $0.name == name } }
            ?? screens.firstIndex(where: \.isBuiltIn)
            ?? screens.firstIndex(where: \.hasNotch)
        guard let index else { return nil }
        return screens[index].hasNotch ? .notch(index) : .capsule(index)
    }

    /// What "Show it on" starts as: the built-in display, else the first one.
    static func defaultName(_ screens: [Candidate]) -> String? {
        (screens.first(where: \.isBuiltIn) ?? screens.first)?.name
    }

    /// The choices for "Show it on": every connected display, plus the saved one if it's
    /// unplugged, so the picker keeps showing it and the dock moves back when it returns.
    static func choices(_ screens: [Candidate], saved: String) -> [String] {
        var names: [String] = []
        for screen in screens where !names.contains(screen.name) { names.append(screen.name) }
        if !saved.isEmpty, !names.contains(saved) { names.append(saved) }
        return names
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
