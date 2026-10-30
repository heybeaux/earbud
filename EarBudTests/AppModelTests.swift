import XCTest
@testable import EarBud

@MainActor
final class AppModelTests: XCTestCase {
    func testStartLoadsLibraryAndSelectsNewest() async {
        let model = Fixtures().model()
        await model.start()
        XCTAssertEqual(model.recordings.count, 24)
        XCTAssertEqual(model.deleted.count, 2)
        XCTAssertEqual(model.selectedRecording?.title, "Run club planning")
        XCTAssertEqual(model.segments.count, 15)
        XCTAssertEqual(model.player.duration, 402)
        XCTAssertTrue(model.player.isReady)
        XCTAssertEqual(model.listGroups.first?.title, "Today")
        XCTAssertEqual(model.deviceState?.batteryPercent, 82)
        XCTAssertEqual(model.menuBarState, .ready)
    }

    func testSearchSelectsAndSteppingThroughMatches() async {
        let model = Fixtures().model()
        await model.start()
        model.searchText = "Powell River"
        await model.runSearch()

        XCTAssertTrue(model.isSearching)
        XCTAssertEqual(model.searchResults?.count, 3)
        XCTAssertEqual(model.listGroups.map(\.items.count), [1, 1, 1])
        XCTAssertEqual(model.selectedRecording?.title, "Run club planning")
        XCTAssertEqual(model.transcriptMatches.count, 2)
        XCTAssertEqual(model.currentMatch?.segmentPosition, 5)
        XCTAssertEqual(model.player.currentTime, 94)

        model.showMatch(offset: 1)
        XCTAssertEqual(model.currentMatch?.segmentPosition, 8)
        XCTAssertEqual(model.player.currentTime, 168)
        model.showMatch(offset: 1)
        XCTAssertEqual(model.currentMatch?.segmentPosition, 5, "Wraps round")
        model.showMatch(offset: -1)
        XCTAssertEqual(model.currentMatch?.segmentPosition, 8)

        model.searchText = ""
        await model.runSearch()
        XCTAssertFalse(model.isSearching)
        XCTAssertNil(model.currentMatch)
    }

    func testSearchMovesSelectionToFirstResult() async {
        let model = Fixtures().model()
        await model.start()
        await model.select(model.recordings.first { $0.title == "Groceries" }?.id)
        model.sidebar = .device
        model.searchText = "Willingdon Beach"
        await model.runSearch()
        XCTAssertEqual(model.sidebar, .recordings)
        XCTAssertEqual(model.selectedRecording?.title, "Run club planning")
    }

    func testSyncUpdatesLibraryDeviceAndHistory() async {
        let fx = Fixtures()
        let model = fx.model()
        await model.start()
        let historyBefore = model.history.count
        await model.syncNow()?.value

        XCTAssertEqual(model.sync, .idle)
        XCTAssertEqual(model.deviceState?.waitingCount, 0)
        XCTAssertEqual(model.history.count, historyBefore + 1)
        XCTAssertEqual(model.recordings.count, 27)
        XCTAssertNil(model.copyingEntry)
        XCTAssertEqual(model.listGroups.first?.items.count, 6)
        await fx.library.waitForTranscriptions()
    }

    func testDeviceSettingShowsSavedAfterReadBack() async {
        let model = Fixtures().model()
        await model.start()
        await model.setRecordingMode(.automatic)
        XCTAssertEqual(model.deviceState?.recordingMode, .automatic)
        XCTAssertTrue(model.pendingSettings.isEmpty)

        await model.setLight(false)
        XCTAssertEqual(model.deviceState?.lightOn, false)
    }

    func testRecordingWhileMutedShowsNoticeAndUnmuteClearsIt() async {
        let model = Fixtures().model()
        await model.start()
        await model.setMuted(true)
        await model.toggleRecording()
        XCTAssertEqual(model.deviceNotice, .muted)
        XCTAssertFalse(model.isRecordingOnDevice)

        await model.setMuted(false)
        XCTAssertNil(model.deviceNotice)
        await model.toggleRecording()
        XCTAssertTrue(model.isRecordingOnDevice)
        XCTAssertEqual(model.menuBarState, .recording)
        await model.toggleRecording()
        XCTAssertFalse(model.isRecordingOnDevice)
        XCTAssertEqual(model.deviceState?.waitingCount, 4)
    }

    func testTrashSelectsNextAndRestore() async {
        let model = Fixtures().model()
        await model.start()
        let first = model.recordings[0].id
        await model.moveToTrash(first)
        XCTAssertEqual(model.recordings.count, 23)
        XCTAssertEqual(model.selectedRecording?.title, "Groceries")
        await model.restore(first)
        XCTAssertEqual(model.recordings.count, 24)
    }

    func testTranscriptText() async {
        let model = Fixtures().model()
        await model.start()
        let text = model.transcriptText(timestamps: true)
        XCTAssertTrue(text.hasPrefix("[00:00] Okay, so for Saturday"))
        XCTAssertEqual(text.split(separator: "\n").count, 15)
    }

    func testModelDownloadInstallsFasterModel() async {
        let model = Fixtures().model()
        await model.start()
        await model.downloadModel("openai_whisper-base.en")
        XCTAssertTrue(model.modelDownloads.isEmpty)
        XCTAssertEqual(model.speechModels.first?.installed, true)
    }
}

@MainActor
final class PlaybackTests: XCTestCase {
    func testSeekSkipAndRate() throws {
        let dir = TestClock.audioDirectory
        let url = try SilentAudio.file(for: "t", duration: 30, in: dir)
        let player = PlaybackController()
        player.load(id: "t", url: url, duration: 30)
        XCTAssertTrue(player.isReady)
        player.seek(to: 10)
        XCTAssertEqual(player.currentTime, 10)
        player.skip(by: 15)
        XCTAssertEqual(player.currentTime, 25)
        player.skip(by: 15)
        XCTAssertEqual(player.currentTime, 30, "Clamped to the end")
        player.skip(by: -45)
        XCTAssertEqual(player.currentTime, 0)
        player.seek(fraction: 0.5)
        XCTAssertEqual(player.progress, 0.5, accuracy: 0.001)
        player.rate = 1.5
        XCTAssertEqual(player.rate, 1.5)
        player.unload()
        XCTAssertFalse(player.isReady)
    }
}
