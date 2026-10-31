import AppKit
import SwiftUI

/// The borderless panel the dock is drawn in. It never activates EarBud or takes keyboard
/// focus, sits above the menu bar, and is kept exactly the size of the drawn shape, so clicks
/// anywhere else land on the menu bar and windows underneath.
final class NotchPanelWindow: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .statusBar
        // No `.fullScreenAuxiliary`: the panel stays off full-screen spaces.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        // Left out of screenshots and screen sharing, so the notch area never shows it.
        sharingType = .none
        appearance = NSAppearance(named: .darkAqua)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Hosts the SwiftUI dock: buttons work on the first click without activating the app, and
/// the pointer entering or leaving is reported even while another app is active.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    var onHoverChange: ((Bool) -> Void)?
    private var hoverArea: NSTrackingArea?

    required init(rootView: Content) {
        super.init(rootView: rootView)
        sizingOptions = []
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHoverChange?(false)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    var isBuiltIn: Bool {
        displayID.map { CGDisplayIsBuiltin($0) != 0 } ?? false
    }

    /// The camera housing in global screen coordinates, or `nil` if this display has none.
    var notchRect: CGRect? {
        NotchGeometry.notchRect(screenFrame: frame, safeAreaTop: safeAreaInsets.top,
                                leftArea: auxiliaryTopLeftArea, rightArea: auxiliaryTopRightArea)
    }

    /// Whether another app is full screen on this display right now.
    var hasFullScreenApp: Bool {
        guard let displayID,
              let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        let windows = info.compactMap { entry -> FullScreenDetector.Window? in
            guard let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  let layer = entry[kCGWindowLayer as String] as? Int,
                  let pid = entry[kCGWindowOwnerPID as String] as? Int32
            else { return nil }
            return FullScreenDetector.Window(bounds: bounds, layer: layer, ownerPID: pid)
        }
        return FullScreenDetector.isFullScreen(windows, displayBounds: CGDisplayBounds(displayID),
                                               ownPID: ProcessInfo.processInfo.processIdentifier)
    }
}
