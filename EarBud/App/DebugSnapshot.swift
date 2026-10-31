#if DEBUG
import AppKit

/// Debug builds only: `EarBud -EarBudSnapshot /path/out.png [-EarBudSnapshotPane device]` saves the
/// main window as a PNG and quits. It captures the app's own window, which needs no Screen Recording
/// permission, so screens can be checked against the mockups from a script.
/// Other options: `-EarBudSnapshotSearch <query>`, `-EarBudSnapshotSync YES`, `-EarBudSnapshotImport YES`, `-EarBudSnapshotDelay <s>`,
/// `-EarBudSnapshotAppearance light|dark`.
@MainActor
enum DebugSnapshot {
    static func runIfRequested(model: AppModel) {
        let defaults = UserDefaults.standard
        guard let path = defaults.string(forKey: "EarBudSnapshot") else { return }
        switch defaults.string(forKey: "EarBudSnapshotAppearance") {
        case "dark": NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApplication.shared.appearance = NSAppearance(named: .aqua)
        default: break
        }
        let delay = defaults.double(forKey: "EarBudSnapshotDelay")
        Task { @MainActor in
            await model.start()
            switch defaults.string(forKey: "EarBudSnapshotPane") {
            case "history": model.sidebar = .syncHistory
            case "deleted": model.sidebar = .recentlyDeleted
            case "device": model.sidebar = .device
            default: break
            }
            if let query = defaults.string(forKey: "EarBudSnapshotSearch") { model.searchText = query }
            if defaults.bool(forKey: "EarBudSnapshotSync") { _ = model.syncNow() }
            // With fixtures: imports the "October interviews" folder from mockups 23-24 (summary after ~3 s).
            if defaults.bool(forKey: "EarBudSnapshotImport") { model.importAudio([FixtureImport.octoberInterviews]) }
            // Bring the main window on-screen and frontmost so the window server has
            // composited content to capture (otherwise the capture comes back blank).
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
                window.makeKeyAndOrderFront(nil)
            }
            try? await Task.sleep(for: .seconds(delay > 0 ? delay : 2.5))
            if let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) {
                let data: Data? = switch defaults.string(forKey: "EarBudSnapshotMethod") {
                case "draw": selfDrawnImage(window)
                case "layer": layerImage(window)
                default: windowServerImage(window) ?? selfDrawnImage(window)
                }
                try? data?.write(to: URL(fileURLWithPath: path))
            }
            NSApp.terminate(nil)
        }
    }

    /// The composited window from the window server, shadow and materials included.
    /// CGWindowListCreateImage is unavailable in the current SDK, so it's looked up at run time.
    private static func windowServerImage(_ window: NSWindow) -> Data? {
        typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return nil }
        let create = unsafeBitCast(symbol, to: CreateImage.self)
        // optionIncludingWindow, and boundsIgnoreFraming | bestResolution.
        guard let image = create(.null, 1 << 3, UInt32(window.windowNumber), 1 << 0 | 1 << 3)?.takeRetainedValue(),
              image.width > 1 else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    /// The window's layer tree rendered into a bitmap.
    private static func layerImage(_ window: NSWindow) -> Data? {
        guard let view = window.contentView?.superview, let layer = view.layer else { return nil }
        let scale = window.backingScaleFactor
        let size = view.bounds.size
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        let cg = context.cgContext
        cg.scaleBy(x: scale, y: scale)
        if !view.isFlipped {
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: 1, y: -1)
        }
        layer.render(in: cg)
        return rep.representation(using: .png, properties: [:])
    }

    /// The window drawing itself. Materials and some AppKit-backed lists come out blank.
    private static func selfDrawnImage(_ window: NSWindow) -> Data? {
        guard let view = window.contentView?.superview,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }
}
#endif
