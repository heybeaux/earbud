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

    // MARK: Live activity

    func progress(_ phase: SyncProgressSnapshot.Phase, file: Int, of count: Int, received: Int = 600, expected: Int = 1000) -> SyncProgressSnapshot {
        SyncProgressSnapshot(phase: phase, fileIndex: file, fileCount: count, bytesReceived: received, bytesExpected: expected,
                             currentRecordingStart: nil, currentFileFraction: 0.5)
    }

    func testSyncShowsFileCountAndProgress() {
        let activity = NotchPresenter.activity(device: device(), sync: .running(progress(.copying, file: 2, of: 3)), lastResult: nil,
                                               now: now, formatting: f)
        XCTAssertEqual(activity, .syncing(label: "2 of 3", fraction: 0.6))
        XCTAssertEqual(activity.layout, .syncing)
    }

    func testSyncBeforeCopyingHasNoFileCount() {
        let connecting = progress(.connecting, file: 0, of: 0, received: 0, expected: 0)
        XCTAssertEqual(NotchPresenter.activity(device: device(), sync: .running(connecting), lastResult: nil, now: now, formatting: f),
                       .syncing(label: "", fraction: 0))
        XCTAssertEqual(NotchPresenter.syncLabel(progress(.copying, file: 4, of: 3)), "3 of 3")
    }

    func testResultShowsForFiveSecondsThenRests() {
        let finished = now.addingTimeInterval(-2)
        let result = (outcome: SyncOutcome.copied(count: 3), at: finished)
        let synced = device(lastSynced: finished)
        let showing = NotchPresenter.activity(device: synced, sync: .finished(.copied(count: 3), at: finished), lastResult: result,
                                              now: now, formatting: f)
        XCTAssertEqual(showing, .syncResult(NotchSyncResult(message: "3 new recordings", tone: .success), dot: .connected, sinceSync: "now"))
        XCTAssertEqual(showing.layout, .message)

        // AppModel clears its own notice sooner; the dock keeps the result for the full five seconds.
        let afterModelCleared = NotchPresenter.activity(device: synced, sync: .idle, lastResult: result,
                                                        now: finished.addingTimeInterval(4.9), formatting: f)
        XCTAssertEqual(afterModelCleared.layout, .message)

        let later = NotchPresenter.activity(device: synced, sync: .idle, lastResult: result, now: finished.addingTimeInterval(5), formatting: f)
        XCTAssertEqual(later, .resting(dot: .connected, sinceSync: "now"))
    }

    func testResultMessages() {
        XCTAssertEqual(NotchPresenter.result(.copied(count: 1), formatting: f), NotchSyncResult(message: "1 new recording", tone: .success))
        XCTAssertEqual(NotchPresenter.result(.nothingNew, formatting: f), NotchSyncResult(message: "Nothing new", tone: .neutral))
        XCTAssertEqual(NotchPresenter.result(.interrupted(saved: 2), formatting: f),
                       NotchSyncResult(message: "Interrupted · 2 recordings saved", tone: .warning))
        XCTAssertEqual(NotchPresenter.result(.failed(message: "Bluetooth is off"), formatting: f).tone, .failure)
    }

    func testRecordingShowsRunningTimer() {
        let recordingDevice = device(recordingStartedAt: now.addingTimeInterval(-222))
        let activity = NotchPresenter.activity(device: recordingDevice, sync: .idle, lastResult: nil, now: now, formatting: f)
        XCTAssertEqual(activity, .recording(elapsed: "03:42"))
        XCTAssertEqual(activity.layout, .recording)
        // Recording outranks a sync running at the same time.
        XCTAssertEqual(NotchPresenter.activity(device: recordingDevice, sync: .running(progress(.copying, file: 1, of: 2)), lastResult: nil,
                                               now: now.addingTimeInterval(1), formatting: f),
                       .recording(elapsed: "03:43"))
    }

    func testPanelShowsSyncProgressAndStopWhileRecording() {
        let syncing = NotchPresenter.panel(device: device(), sync: .running(progress(.copying, file: 1, of: 2)), newest: nil,
                                           isChangingRecording: false, now: now, formatting: f)
        XCTAssertEqual(syncing.syncTitle, "Syncing… 60%")
        XCTAssertFalse(syncing.canSync)
        XCTAssertEqual(NotchPresenter.syncTitle(.running(progress(.checking, file: 0, of: 0))), "Syncing…")

        let recording = NotchPresenter.panel(device: device(recordingStartedAt: now.addingTimeInterval(-65)), sync: .idle, newest: nil,
                                             isChangingRecording: false, now: now, formatting: f)
        XCTAssertEqual(recording.recordTitle, "Stop recording")
        XCTAssertTrue(recording.isRecording)
        XCTAssertEqual(recording.status, "Recording · 01:05")
        XCTAssertEqual(recording.dot, .recording)
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
