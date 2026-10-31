import UserNotifications
import XCTest
@testable import EarBud

final class SyncReminderPlanTests: XCTestCase {
    private let calendar = TestClock.calendar
    private let daily = ReminderSettings()

    private func fireDates(_ settings: ReminderSettings? = nil, lastSynced: Date?, now: Date = TestClock.reference) -> [Date] {
        SyncReminderPlan.fireDates(settings: settings ?? daily, lastSynced: lastSynced, now: now, calendar: calendar)
    }

    func testDefaultsAreOneDayAtSevenPM() {
        XCTAssertEqual(daily, ReminderSettings(enabled: true, afterDays: 1, atMinutes: 19 * 60))
    }

    func testSyncedTodayRemindsTomorrowEveningThenDaily() {
        // Mockup 21: synced Friday 1:40 PM, reminded Saturday 7:00 PM.
        let dates = fireDates(lastSynced: TestClock.date(10, 30, 13, 40))
        XCTAssertEqual(dates.count, SyncReminderPlan.maxReminders)
        XCTAssertEqual(dates.first, TestClock.date(10, 31, 19, 0))
        XCTAssertEqual(dates[1], TestClock.date(11, 1, 19, 0))
        XCTAssertEqual(dates.last, TestClock.date(11, 6, 19, 0))
    }

    func testNoReminderWhenSyncedWithinTheInterval() {
        // Synced 8 PM last night: at 7 PM tonight it has only been 23 hours.
        let dates = fireDates(lastSynced: TestClock.date(10, 29, 20, 0))
        XCTAssertFalse(dates.contains { calendar.isDate($0, inSameDayAs: TestClock.reference) })
        XCTAssertEqual(dates.first, TestClock.date(10, 31, 19, 0))
    }

    func testOverdueRemindsAtTodaysTime() {
        let dates = fireDates(lastSynced: TestClock.date(10, 27, 9, 0))
        XCTAssertEqual(dates.first, TestClock.date(10, 30, 19, 0))
    }

    func testOverdueAfterTodaysTimeWaitsForTomorrow() {
        let dates = fireDates(lastSynced: TestClock.date(10, 27, 9, 0), now: TestClock.date(10, 30, 20, 15))
        XCTAssertEqual(dates.first, TestClock.date(10, 31, 19, 0))
    }

    func testReminderTimeExactlyNowIsSkipped() {
        let dates = fireDates(lastSynced: TestClock.date(10, 27, 9, 0), now: TestClock.date(10, 30, 19, 0))
        XCTAssertEqual(dates.first, TestClock.date(10, 31, 19, 0))
    }

    func testLongerIntervalAndOtherTime() {
        let weekly = ReminderSettings(enabled: true, afterDays: 7, atMinutes: 9 * 60)
        let dates = fireDates(weekly, lastSynced: TestClock.date(10, 30, 13, 40))
        // 9 AM on 6 November is before 1:40 PM, so not yet a week.
        XCTAssertEqual(dates.first, TestClock.date(11, 7, 9, 0))

        let twoDays = ReminderSettings(enabled: true, afterDays: 2, atMinutes: 21 * 60)
        XCTAssertEqual(fireDates(twoDays, lastSynced: TestClock.date(10, 30, 13, 40)).first, TestClock.date(11, 1, 21, 0))
    }

    func testStaysAtTheSameWallClockTimeAcrossDaylightSavingChange() {
        // Vancouver leaves daylight time on Sunday 1 November 2026.
        let dates = fireDates(lastSynced: TestClock.date(10, 30, 13, 40))
        for date in dates {
            XCTAssertEqual(calendar.component(.hour, from: date), 19)
            XCTAssertEqual(calendar.component(.minute, from: date), 0)
        }
        XCTAssertEqual(Set(dates.map { calendar.startOfDay(for: $0) }).count, dates.count, "One per day")
    }

    func testNothingWhenOffNeverSyncedOrNoInterval() {
        let synced = TestClock.date(10, 27, 9, 0)
        XCTAssertEqual(fireDates(ReminderSettings(enabled: false), lastSynced: synced), [])
        XCTAssertEqual(fireDates(lastSynced: nil), [])
        XCTAssertEqual(fireDates(ReminderSettings(afterDays: 0), lastSynced: synced), [])
    }

    func testOutOfRangeTimeIsClamped() {
        let late = ReminderSettings(atMinutes: 5000)
        let date = fireDates(late, lastSynced: TestClock.date(10, 27, 9, 0)).first
        XCTAssertEqual(date, TestClock.date(10, 30, 23, 59))
    }

    func testRemindersHaveMockupWordingForWhenTheyFire() throws {
        let reminders = SyncReminderPlan.reminders(settings: daily, lastSynced: TestClock.date(10, 30, 13, 40),
                                                   now: TestClock.reference, formatting: TestClock.formatting)
        XCTAssertEqual(reminders.map(\.id), SyncReminderPlan.allIDs)
        let first = try XCTUnwrap(reminders.first)
        XCTAssertEqual(first.title, "Time to sync your Fieldy")
        XCTAssertEqual(first.body.plainSpaces, "Your last sync was yesterday at 1:40 PM. Click to sync now.")
        XCTAssertEqual(reminders[2].body, "Your last sync was on Friday 30 October. Click to sync now.")
        XCTAssertEqual(SyncReminderPlan.reminders(settings: daily, lastSynced: nil, now: TestClock.reference,
                                                  formatting: TestClock.formatting), [])
    }

    func testActionsFromNotificationResponses() {
        XCTAssertEqual(ReminderAction(actionIdentifier: UNNotificationDefaultActionIdentifier), .syncNow)
        XCTAssertEqual(ReminderAction(actionIdentifier: ReminderAction.syncNowID), .syncNow)
        XCTAssertEqual(ReminderAction(actionIdentifier: ReminderAction.openID), .open)
        XCTAssertNil(ReminderAction(actionIdentifier: UNNotificationDismissActionIdentifier))
        XCTAssertNil(ReminderAction(actionIdentifier: "something-else"))
    }
}

final class ReminderSettingsTests: XCTestCase {
    func testReadsDefaultsWhenUnsetAndSettingsValuesWhenSet() throws {
        let suite = "EarBudTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(ReminderSettings(defaults: defaults), ReminderSettings())

        defaults.set(false, forKey: SettingsKey.reminderEnabled)
        defaults.set(3, forKey: SettingsKey.reminderDays)
        defaults.set(9 * 60, forKey: SettingsKey.reminderTime)
        XCTAssertEqual(ReminderSettings(defaults: defaults), ReminderSettings(enabled: false, afterDays: 3, atMinutes: 9 * 60))
    }
}

@MainActor
private final class FakeReminderCenter: ReminderNotificationCenter {
    var granted = true
    private(set) var authorizationRequests = 0
    private(set) var removed: [[String]] = []
    private(set) var pending: [SyncReminder] = []

    func requestAuthorization() async -> Bool {
        authorizationRequests += 1
        return granted
    }

    func removeReminders(ids: [String]) {
        removed.append(ids)
        pending.removeAll { ids.contains($0.id) }
    }

    func add(_ reminder: SyncReminder, calendar: Calendar) async {
        pending.append(reminder)
    }
}

@MainActor
final class SyncReminderSchedulerTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!
    private var center: FakeReminderCenter!
    private var canAsk = true

    override func setUp() async throws {
        suite = "EarBudTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        center = FakeReminderCenter()
        canAsk = true
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    private func makeScheduler() -> SyncReminderScheduler {
        let center = center!
        return SyncReminderScheduler(defaults: defaults, formatting: TestClock.formatting, now: { TestClock.reference },
                                     canAskPermission: { [unowned self] in canAsk }, makeCenter: { _ in center })
    }

    func testRescheduleReplacesPendingReminders() async {
        let scheduler = makeScheduler()
        await scheduler.reschedule(enabled: true, afterDays: 1, atMinutes: 19 * 60, lastSynced: TestClock.date(10, 30, 13, 40))?.value
        XCTAssertEqual(center.pending.count, SyncReminderPlan.maxReminders)
        XCTAssertEqual(center.pending.first?.fireDate, TestClock.date(10, 31, 19, 0))
        XCTAssertEqual(center.authorizationRequests, 1)

        await scheduler.reschedule(enabled: true, afterDays: 2, atMinutes: 9 * 60, lastSynced: TestClock.date(10, 30, 13, 40))?.value
        XCTAssertEqual(center.pending.count, SyncReminderPlan.maxReminders)
        XCTAssertEqual(center.pending.first?.fireDate, TestClock.date(11, 2, 9, 0))
        XCTAssertEqual(center.removed.last, SyncReminderPlan.allIDs)
    }

    func testTurningRemindersOffCancelsWithoutAskingPermission() async {
        let scheduler = makeScheduler()
        await scheduler.reschedule(enabled: true, afterDays: 1, atMinutes: 19 * 60, lastSynced: TestClock.date(10, 30, 13, 40))?.value
        await scheduler.reschedule(enabled: false, afterDays: 1, atMinutes: 19 * 60, lastSynced: TestClock.date(10, 30, 13, 40))?.value
        XCTAssertEqual(center.pending, [])
        XCTAssertEqual(center.authorizationRequests, 1)
    }

    func testUnchangedInputsDoNothing() async {
        let scheduler = makeScheduler()
        await scheduler.reschedule(enabled: true, afterDays: 1, atMinutes: 19 * 60, lastSynced: TestClock.date(10, 30, 13, 40))?.value
        XCTAssertNil(scheduler.reschedule(enabled: true, afterDays: 1, atMinutes: 19 * 60, lastSynced: TestClock.date(10, 30, 13, 40)))
        XCTAssertEqual(center.removed.count, 1)
    }

    func testNothingAddedWhenPermissionDenied() async {
        center.granted = false
        let scheduler = makeScheduler()
        await scheduler.reschedule(enabled: true, afterDays: 1, atMinutes: 19 * 60, lastSynced: TestClock.date(10, 30, 13, 40))?.value
        XCTAssertEqual(center.pending, [])
    }

    func testDuringOnboardingDoesNotAskAndRetriesLater() async {
        canAsk = false
        let scheduler = makeScheduler()
        await scheduler.reschedule(enabled: true, afterDays: 1, atMinutes: 19 * 60, lastSynced: TestClock.date(10, 30, 13, 40))?.value
        XCTAssertEqual(center.authorizationRequests, 0)
        XCTAssertEqual(center.pending, [])
        XCTAssertNil(scheduler.scheduled)

        canAsk = true
        await scheduler.reschedule(enabled: true, afterDays: 1, atMinutes: 19 * 60, lastSynced: TestClock.date(10, 30, 13, 40))?.value
        XCTAssertEqual(center.pending.count, SyncReminderPlan.maxReminders)
    }

    func testFollowsSettingsAndTheModelsLastSync() async throws {
        let model = Fixtures().model()
        let scheduler = makeScheduler()
        scheduler.attach(model: model)
        XCTAssertNil(scheduler.scheduled, "Waits for the model to load")

        await model.start()
        scheduler.update()
        var first = try XCTUnwrap(scheduler.scheduled?.first)
        XCTAssertEqual(first.fireDate, TestClock.date(10, 31, 19, 0))
        XCTAssertEqual(first.body.plainSpaces, "Your last sync was yesterday at 1:40 PM. Click to sync now.")

        // Settings writes these keys; the scheduler reads them.
        defaults.set(9 * 60, forKey: SettingsKey.reminderTime)
        scheduler.update()
        first = try XCTUnwrap(scheduler.scheduled?.first)
        XCTAssertEqual(first.fireDate, TestClock.date(11, 1, 9, 0))

        defaults.set(false, forKey: SettingsKey.reminderEnabled)
        scheduler.update()
        XCTAssertEqual(scheduler.scheduled, [])

        // After a sync the reminder counts from the new sync.
        defaults.set(true, forKey: SettingsKey.reminderEnabled)
        defaults.set(19 * 60, forKey: SettingsKey.reminderTime)
        await model.syncNow()?.value
        scheduler.update()
        first = try XCTUnwrap(scheduler.scheduled?.first)
        XCTAssertEqual(first.body.plainSpaces, "Your last sync was yesterday at 2:03 PM. Click to sync now.")
    }
}
