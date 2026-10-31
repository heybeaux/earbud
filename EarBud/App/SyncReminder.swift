import AppKit
import Foundation
import Observation
import os
import UserNotifications

private let log = Logger(subsystem: "dev.heybeaux.earbud", category: "reminder")

/// The "Sync reminder" settings (mockup 17, 21).
struct ReminderSettings: Equatable, Sendable {
    static let defaultDays = 1
    /// 7:00 PM, as in the mockups.
    static let defaultMinutes = 19 * 60

    var enabled = true
    /// Remind once it has been this many days without a sync.
    var afterDays = defaultDays
    /// Minutes after midnight.
    var atMinutes = defaultMinutes

    init(enabled: Bool = true, afterDays: Int = defaultDays, atMinutes: Int = defaultMinutes) {
        self.enabled = enabled
        self.afterDays = afterDays
        self.atMinutes = atMinutes
    }

    /// Reads the values Settings writes, falling back to the defaults for keys never set.
    init(defaults: UserDefaults) {
        enabled = defaults.object(forKey: SettingsKey.reminderEnabled) as? Bool ?? true
        afterDays = defaults.object(forKey: SettingsKey.reminderDays) as? Int ?? Self.defaultDays
        atMinutes = defaults.object(forKey: SettingsKey.reminderTime) as? Int ?? Self.defaultMinutes
    }
}

/// One notification to hand to the system.
struct SyncReminder: Equatable, Sendable {
    var id: String
    var fireDate: Date
    var title: String
    var body: String
}

/// Decides when reminders fire. Pure, so the rules can be tested without the notification centre.
enum SyncReminderPlan {
    static let title = "Time to sync your Fieldy"
    static let idPrefix = "sync-reminder-"
    /// After the first reminder, one more each day at the same time until the next sync (mockup 21:
    /// "the next reminder comes at the same time tomorrow"). Rescheduled whenever EarBud runs.
    static let maxReminders = 7

    /// Every identifier the plan can use, so old reminders can be removed without asking the system for them.
    static var allIDs: [String] { (0..<maxReminders).map { idPrefix + String($0) } }

    /// When reminders should fire: the first reminder time that is after `now` and at least
    /// `afterDays` days after the last sync, then the same time on each following day.
    /// Nothing when reminders are off or there has never been a sync to count from.
    static func fireDates(settings: ReminderSettings, lastSynced: Date?, now: Date, calendar: Calendar,
                          count: Int = maxReminders) -> [Date] {
        guard settings.enabled, settings.afterDays > 0, count > 0, let lastSynced else { return [] }
        let minutes = min(max(settings.atMinutes, 0), 24 * 60 - 1)
        let due = lastSynced.addingTimeInterval(TimeInterval(settings.afterDays) * 24 * 60 * 60)
        let earliest = max(due, now)

        var day = calendar.startOfDay(for: earliest)
        var dates: [Date] = []
        // A few extra days covers the first day being too early plus any skipped DST hours.
        for _ in 0..<(count + 3) {
            if let fire = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day),
               fire >= due, fire > now {
                dates.append(fire)
                if dates.count == count { break }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return dates
    }

    /// "Your last sync was yesterday at 1:40 PM. Click to sync now.", worded for when it is shown.
    static func body(lastSynced: Date, fireDate: Date, formatting: Formatting) -> String {
        "Your last sync was \(formatting.relativeMoment(lastSynced, now: fireDate)). Click to sync now."
    }

    static func reminders(settings: ReminderSettings, lastSynced: Date?, now: Date, formatting: Formatting) -> [SyncReminder] {
        guard let lastSynced else { return [] }
        return fireDates(settings: settings, lastSynced: lastSynced, now: now, calendar: formatting.calendar)
            .enumerated()
            .map { index, date in
                SyncReminder(id: idPrefix + String(index), fireDate: date, title: title,
                             body: body(lastSynced: lastSynced, fireDate: date, formatting: formatting))
            }
    }
}

/// What the user chose on a reminder.
enum ReminderAction: Equatable, Sendable {
    /// Clicking the banner or "Sync now": open EarBud and start a sync.
    case syncNow
    /// "Open EarBud" from the Options menu.
    case open

    static let categoryID = "sync-reminder"
    static let syncNowID = "sync-now"
    static let openID = "open"

    /// `nil` for dismissals and anything else that shouldn't do anything.
    init?(actionIdentifier: String) {
        switch actionIdentifier {
        case UNNotificationDefaultActionIdentifier, Self.syncNowID: self = .syncNow
        case Self.openID: self = .open
        default: return nil
        }
    }
}

/// The part of the notification centre the scheduler uses, so tests can stand in for it.
@MainActor
protocol ReminderNotificationCenter: AnyObject {
    /// Asks for permission the first time; later calls return the user's answer.
    func requestAuthorization() async -> Bool
    func removeReminders(ids: [String])
    func add(_ reminder: SyncReminder, calendar: Calendar) async
}

/// `UNUserNotificationCenter` behind `ReminderNotificationCenter`.
@MainActor
final class SystemReminderCenter: ReminderNotificationCenter {
    private let delegate: ReminderNotificationDelegate

    init(onAction: @escaping @MainActor @Sendable (ReminderAction) -> Void) {
        delegate = ReminderNotificationDelegate(onAction: onAction)
        let center = UNUserNotificationCenter.current()
        // Set before launch finishes so a click that launched EarBud still reaches us.
        center.delegate = delegate
        let sync = UNNotificationAction(identifier: ReminderAction.syncNowID, title: "Sync Now", options: [.foreground])
        let open = UNNotificationAction(identifier: ReminderAction.openID, title: "Open EarBud", options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: ReminderAction.categoryID, actions: [sync, open], intentIdentifiers: [], options: [])
        ])
    }

    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            log.error("Notification permission failed: \(error.localizedDescription)")
            return false
        }
    }

    func removeReminders(ids: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
    }

    func add(_ reminder: SyncReminder, calendar: Calendar) async {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        content.categoryIdentifier = ReminderAction.categoryID
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            log.error("Couldn't schedule reminder: \(error.localizedDescription)")
        }
    }
}

/// Receives reminder clicks and shows reminders even while EarBud is in front.
private final class ReminderNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    let onAction: @MainActor @Sendable (ReminderAction) -> Void

    init(onAction: @escaping @MainActor @Sendable (ReminderAction) -> Void) {
        self.onAction = onAction
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let isReminder = response.notification.request.content.categoryIdentifier == ReminderAction.categoryID
        if isReminder, let action = ReminderAction(actionIdentifier: response.actionIdentifier) {
            let onAction = onAction
            Task { @MainActor in onAction(action) }
        }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

/// The daily sync reminder notification (mockup 21). Keeps the system's pending reminders in step
/// with Settings and the last sync, whether or not the main window is open.
@MainActor
final class SyncReminderScheduler {
    static let shared = SyncReminderScheduler()

    private let makeCenter: @MainActor (SyncReminderScheduler) -> any ReminderNotificationCenter
    private var _center: (any ReminderNotificationCenter)?
    private let defaults: UserDefaults
    private let formatting: Formatting
    private let now: () -> Date
    /// Whether asking for notification permission would interrupt onboarding.
    private let canAskPermission: () -> Bool

    private weak var model: AppModel?
    /// Opens the main window; set by a view that has `openWindow`.
    var openMainWindow: (() -> Void)?
    private var defaultsObserver: NSObjectProtocol?
    /// The reminders last handed to the system, to skip work when nothing changed.
    private(set) var scheduled: [SyncReminder]?
    private var updateTask: Task<Void, Never>?

    convenience init() {
        self.init(defaults: .standard, formatting: .standard, now: Date.init, canAskPermission: { !OnboardingState.isNeeded }) { scheduler in
            SystemReminderCenter { [weak scheduler] action in scheduler?.handle(action) }
        }
    }

    init(defaults: UserDefaults, formatting: Formatting, now: @escaping () -> Date, canAskPermission: @escaping () -> Bool,
         makeCenter: @escaping @MainActor (SyncReminderScheduler) -> any ReminderNotificationCenter) {
        self.defaults = defaults
        self.formatting = formatting
        self.now = now
        self.canAskPermission = canAskPermission
        self.makeCenter = makeCenter
    }

    private var center: any ReminderNotificationCenter {
        if let _center { return _center }
        let made = makeCenter(self)
        _center = made
        return made
    }

    /// Starts listening for reminder clicks and follows Settings and the model's last sync from now on.
    func attach(model: AppModel) {
        self.model = model
        _ = center
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: defaults,
                                                                  queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        observeModel()
    }

    private func observeModel() {
        guard let model else { return }
        withObservationTracking {
            _ = model.isLoaded
            _ = model.deviceState?.lastSynced
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.update()
                self?.observeModel()
            }
        }
        update()
    }

    /// Reschedules from the stored settings and the attached model. Waits until the model has
    /// loaded, so a launch that hasn't read the device yet doesn't cancel pending reminders.
    func update() {
        guard let model, model.isLoaded else { return }
        let settings = ReminderSettings(defaults: defaults)
        reschedule(enabled: settings.enabled, afterDays: settings.afterDays, atMinutes: settings.atMinutes,
                   lastSynced: model.deviceState?.lastSynced)
    }

    /// Replaces the pending reminders. Called when reminder settings change and after each sync.
    @discardableResult
    func reschedule(enabled: Bool, afterDays: Int, atMinutes: Int, lastSynced: Date?) -> Task<Void, Never>? {
        let settings = ReminderSettings(enabled: enabled, afterDays: afterDays, atMinutes: atMinutes)
        let reminders = SyncReminderPlan.reminders(settings: settings, lastSynced: lastSynced, now: now(), formatting: formatting)
        guard reminders != scheduled else { return nil }
        let mayAsk = canAskPermission()
        // During onboarding nothing is added; leaving `scheduled` empty retries once it finishes.
        scheduled = reminders.isEmpty || mayAsk ? reminders : nil
        let previous = updateTask
        let center = center
        let calendar = formatting.calendar
        updateTask = Task {
            await previous?.value
            center.removeReminders(ids: SyncReminderPlan.allIDs)
            guard !reminders.isEmpty, mayAsk, await center.requestAuthorization() else { return }
            for reminder in reminders {
                await center.add(reminder, calendar: calendar)
            }
            log.info("Scheduled \(reminders.count) sync reminders from \(reminders[0].fireDate)")
        }
        return updateTask
    }

    /// A click on a reminder: bring EarBud forward and, for the banner or "Sync now", start a sync.
    func handle(_ action: ReminderAction) {
        NSApp?.activate()
        if let openMainWindow {
            openMainWindow()
        } else {
            NSApp?.windows.first { $0.identifier?.rawValue == EarBudApp.mainWindowID }?.makeKeyAndOrderFront(nil)
        }
        guard action == .syncNow, let model else { return }
        Task {
            await model.start()
            model.syncNow()
        }
    }
}
