import XCTest
@testable import EarBud

@MainActor
final class NotchPresenterTests: XCTestCase {
    let f = TestClock.formatting
    let now = TestClock.reference

    func device(connection: DeviceConnection = .connected, battery: Int? = 82, lastSynced: Date? = TestClock.date(10, 30, 13, 40),
                recordingStartedAt: Date? = nil) -> DeviceSnapshot {
        DeviceSnapshot(name: "Fieldy 3A7C", model: "Fieldy", firmware: "3.3.5", connection: connection, batteryPercent: battery,
                       waitingCount: 0, waitingBytes: 0, lastSynced: lastSynced, pairedAt: nil, checkedAt: nil,
                       recordingMode: .manual, lightOn: true, muted: false, recordingStartedAt: recordingStartedAt)
    }

    func recording(title: String? = "Run club planning", preview: String? = "Okay, so for Saturday we meet at the seawall.",
                   transcript: TranscriptStatus = .done, at date: Date = TestClock.date(10, 30, 13, 12)) -> RecordingItem {
        RecordingItem(id: "r1", recordedAt: date, duration: 300, title: title, audio: .ok, transcript: transcript, preview: preview,
                      copiedAt: nil, transcribedAt: nil, deletedAt: nil, waveformSeed: 1)
    }

    // MARK: Resting

    func testRestingShowsADotAndTimeSinceLastSync() {
        let activity = NotchPresenter.activity(device: device(), sync: .idle, lastResult: nil, now: now, formatting: f)
        XCTAssertEqual(activity, .resting(dot: .connected, sinceSync: "23m"))
        XCTAssertEqual(activity.layout, .resting)
    }

    func testRestingDotIsGreyWhenTheFieldyIsAwayOrUnknown() {
        XCTAssertEqual(NotchPresenter.activity(device: device(connection: .notNearby), sync: .idle, lastResult: nil, now: now, formatting: f),
                       .resting(dot: .away, sinceSync: "23m"))
        XCTAssertEqual(NotchPresenter.activity(device: nil, sync: .idle, lastResult: nil, now: now, formatting: f),
                       .resting(dot: .away, sinceSync: "–"))
    }

    func testTimeSinceSync() {
        XCTAssertEqual(NotchPresenter.sinceSync(nil, now: now), "–")
        XCTAssertEqual(NotchPresenter.sinceSync(now.addingTimeInterval(-20), now: now), "now")
        XCTAssertEqual(NotchPresenter.sinceSync(now.addingTimeInterval(5), now: now), "now")
        XCTAssertEqual(NotchPresenter.sinceSync(now.addingTimeInterval(-60), now: now), "1m")
        XCTAssertEqual(NotchPresenter.sinceSync(now.addingTimeInterval(-59 * 60), now: now), "59m")
        XCTAssertEqual(NotchPresenter.sinceSync(now.addingTimeInterval(-5 * 3600 - 100), now: now), "5h")
        XCTAssertEqual(NotchPresenter.sinceSync(now.addingTimeInterval(-3 * 86_400), now: now), "3d")
    }

    // MARK: Quick panel

    func testPanelMatchesTheMockup() {
        let panel = NotchPresenter.panel(device: device(), sync: .idle, newest: recording(), isChangingRecording: false, now: now, formatting: f)
        XCTAssertEqual(panel.deviceName, "Fieldy 3A7C")
        XCTAssertEqual(panel.status, "Connected · battery 82%")
        XCTAssertEqual(panel.lastSynced.plainSpaces, "Today, 1:40 PM")
        XCTAssertEqual(panel.syncTitle, "Sync now")
        XCTAssertTrue(panel.canSync)
        XCTAssertEqual(panel.recordTitle, "Record from Mac")
        XCTAssertTrue(panel.canRecord)
        XCTAssertEqual(panel.newest?.id, "r1")
        XCTAssertEqual(panel.newest?.heading.plainSpaces, "Newest · Run club planning · 1:12 PM")
        XCTAssertEqual(panel.newest?.text, "Okay, so for Saturday we meet at the seawall.")
    }

    func testPanelWithoutAFieldyOrRecordings() {
        let panel = NotchPresenter.panel(device: nil, sync: .idle, newest: nil, isChangingRecording: false, now: now, formatting: f)
        XCTAssertEqual(panel.deviceName, "Fieldy")
        XCTAssertEqual(panel.status, "Looking for your Fieldy…")
        XCTAssertEqual(panel.lastSynced, "Not yet")
        XCTAssertFalse(panel.canRecord)
        XCTAssertNil(panel.newest)
    }

    func testRecordIsUnavailableAwayOrMidChange() {
        XCTAssertFalse(NotchPresenter.panel(device: device(connection: .notNearby), sync: .idle, newest: nil, isChangingRecording: false,
                                            now: now, formatting: f).canRecord)
        XCTAssertFalse(NotchPresenter.panel(device: device(), sync: .idle, newest: nil, isChangingRecording: true,
                                            now: now, formatting: f).canRecord)
    }

    func testNewestCardForUntitledOlderAndUntranscribedRecordings() {
        let untitled = NotchPresenter.newestCard(recording(title: nil), now: now, formatting: f)
        XCTAssertEqual(untitled.heading.plainSpaces, "Newest · 1:12 PM")
        let older = NotchPresenter.newestCard(recording(at: TestClock.date(10, 29, 16, 30)), now: now, formatting: f)
        XCTAssertEqual(older.heading.plainSpaces, "Newest · Run club planning · Yesterday, 4:30 PM")
        XCTAssertEqual(NotchPresenter.newestText(recording(preview: nil, transcript: .waiting(position: 1))), "Waiting to be transcribed.")
        XCTAssertEqual(NotchPresenter.newestText(recording(preview: "", transcript: .noSpeech)), "Nothing was said.")
        XCTAssertEqual(NotchPresenter.newestText(recording(preview: nil, transcript: .transcribing(progress: 0.4, secondsLeft: nil))),
                       "Transcribing…")
    }

    // MARK: Hover

    func testHoverExpandsAfterHalfASecond() {
        var hover = NotchHoverTracker()
        XCTAssertFalse(hover.pointer(inside: true, at: now))
        XCTAssertEqual(hover.expandDeadline, now.addingTimeInterval(0.5))
        XCTAssertFalse(hover.pointer(inside: true, at: now.addingTimeInterval(0.3)))
        XCTAssertTrue(hover.pointer(inside: true, at: now.addingTimeInterval(0.5)))
        XCTAssertNil(hover.expandDeadline)
        XCTAssertTrue(hover.pointer(inside: true, at: now.addingTimeInterval(4)))
    }

    func testPassingOverQuicklyDoesNotExpand() {
        var hover = NotchHoverTracker()
        hover.pointer(inside: true, at: now)
        hover.pointer(inside: false, at: now.addingTimeInterval(0.3))
        XCTAssertNil(hover.expandDeadline)
        XCTAssertFalse(hover.pointer(inside: true, at: now.addingTimeInterval(0.6)))
        XCTAssertFalse(hover.isExpanded)
    }

    func testClickExpandsAtOnceAndLeavingCollapses() {
        var hover = NotchHoverTracker()
        hover.click()
        XCTAssertTrue(hover.isExpanded)
        XCTAssertTrue(hover.pointer(inside: true, at: now))
        XCTAssertFalse(hover.pointer(inside: false, at: now.addingTimeInterval(1)))
        XCTAssertFalse(hover.isExpanded)
    }
}
