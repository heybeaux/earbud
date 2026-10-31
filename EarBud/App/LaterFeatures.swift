import Foundation
import os

// Entry points for features that come in a later batch. Each one is wired to the place in
// the app that will call it, so the later work only fills these in.

private let log = Logger(subsystem: "dev.heybeaux.earbud", category: "later")

/// The daily sync reminder notification (mockup 21).
@MainActor
final class SyncReminderScheduler {
    static let shared = SyncReminderScheduler()

    /// Called when reminder settings change and after each sync.
    func reschedule(enabled: Bool, afterDays: Int, atMinutes: Int, lastSynced: Date?) {
        log.info("Sync reminder not built yet (enabled: \(enabled), days: \(afterDays), at: \(atMinutes))")
    }
}
