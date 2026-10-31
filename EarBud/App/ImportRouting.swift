import AppKit
import UniformTypeIdentifiers

/// Receives files and folders dropped on the Dock icon (or opened with EarBud from the Finder).
/// `CFBundleDocumentTypes` in Info.plist (audio and folders, rank Alternate) makes the Dock accept them.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated { ImportRouter.shared.open(urls) }
    }
}

/// Hands Dock drops to the model, holding them until the model is attached, and brings the main window
/// forward so the import sheet is visible.
@MainActor
final class ImportRouter {
    static let shared = ImportRouter()

    private weak var model: AppModel?
    private var pending: [URL] = []
    /// Opens the main window; set by a view that has `openWindow`.
    var openMainWindow: (() -> Void)?

    func attach(model: AppModel) {
        self.model = model
        if !pending.isEmpty {
            let urls = pending
            pending = []
            open(urls)
        }
    }

    func open(_ urls: [URL]) {
        guard let model else {
            pending += urls
            return
        }
        NSApp?.activate()
        if let openMainWindow {
            openMainWindow()
        } else {
            NSApp?.windows.first { $0.identifier?.rawValue == EarBudApp.mainWindowID }?.makeKeyAndOrderFront(nil)
        }
        model.importAudio(urls)
    }
}

/// File > Import Audio…: an open panel for audio files and folders, several at once.
@MainActor
enum ImportPanel {
    static func choose() -> [URL]? {
        let panel = NSOpenPanel()
        panel.title = "Import Audio"
        panel.message = "Choose audio files or folders. EarBud copies them into your library; your originals are not changed."
        panel.prompt = "Import"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.audio]
        return panel.runModal() == .OK ? panel.urls : nil
    }
}
