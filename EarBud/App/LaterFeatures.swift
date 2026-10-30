import Foundation
import os

// Entry points for features that come in a later batch. Each one is wired to the place in
// the app that will call it, so the later work only fills these in.

private let log = Logger(subsystem: "dev.heybeaux.earbud", category: "later")

/// First-run setup (onboarding mockups 02–11).
@MainActor
enum Onboarding {
    /// Whether to show setup at launch. Batch 1 runs on the sample library, so never.
    static var isNeeded: Bool { false }

    /// Opens the setup window.
    static func start() {
        log.info("Onboarding is not built yet")
    }
}

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

/// The daily sync reminder notification (mockup 21).
@MainActor
final class SyncReminderScheduler {
    static let shared = SyncReminderScheduler()

    /// Called when reminder settings change and after each sync.
    func reschedule(enabled: Bool, afterDays: Int, atMinutes: Int, lastSynced: Date?) {
        log.info("Sync reminder not built yet (enabled: \(enabled), days: \(afterDays), at: \(atMinutes))")
    }
}
