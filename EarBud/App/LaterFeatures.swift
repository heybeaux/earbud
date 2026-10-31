import Foundation
import os

// Entry points for features that come in a later batch. Each one is wired to the place in
// the app that will call it, so the later work only fills these in.

private let log = Logger(subsystem: "dev.heybeaux.earbud", category: "later")

/// The notch dock and floating capsule (mockups 19, 20).
@MainActor
final class NotchDockController {
    static let shared = NotchDockController()

    private(set) var isEnabled = false
    private(set) var displayName: String?

    /// Called when "Show EarBud in the notch" or "Show it on" changes in Settings.
    func update(enabled: Bool, displayName: String?) {
        isEnabled = enabled
        self.displayName = displayName
        log.info("Notch dock not built yet (enabled: \(enabled))")
    }
}
