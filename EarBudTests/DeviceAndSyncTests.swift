import XCTest
@testable import EarBud

final class DeviceTests: XCTestCase {
    func testSnapshotMatchesMockup() async {
        let fx = Fixtures()
        let s = await fx.device.snapshot()
        XCTAssertEqual(s.name, "Fieldy 3A7C")
        XCTAssertEqual(s.model, "Fieldy 3 (FL3B)")
        XCTAssertEqual(s.firmware, DeviceSnapshot.testedFirmware)
        XCTAssertEqual(s.batteryPercent, 82)
        XCTAssertEqual(s.connection, .connected)
        XCTAssertEqual(s.waitingCount, 3)
        XCTAssertEqual(s.waitingBytes, (468 + 125 + 96) * FixtureData.bytesPerSecond)
        XCTAssertEqual(s.lastSynced, TestClock.date(10, 30, 13, 40))
        XCTAssertEqual(s.recordingMode, .manual)
        XCTAssertTrue(s.lightOn)
        XCTAssertFalse(s.muted)
    }

    func testSettersReturnReadBackValue() async throws {
        let fx = Fixtures()
        let mode = try await fx.device.setRecordingMode(.automatic)
        XCTAssertEqual(mode, .automatic)
        let light = try await fx.device.setLight(false)
        XCTAssertFalse(light)
        let muted = try await fx.device.setMuted(true)
        XCTAssertTrue(muted)
        let s = await fx.device.snapshot()
        XCTAssertEqual(s.recordingMode, .automatic)
        XCTAssertFalse(s.lightOn)
        XCTAssertTrue(s.muted)
    }

    func testRecordingFromMacAddsWaitingFile() async throws {
        let fx = Fixtures()
        _ = try await fx.device.startRecording()
        let recording = await fx.device.snapshot()
        XCTAssertTrue(recording.isRecording)
        try await fx.device.stopRecording()
        let after = await fx.device.snapshot()
        XCTAssertFalse(after.isRecording)
        XCTAssertEqual(after.waitingCount, 4)
    }

    func testMutedDeviceRefusesToRecord() async throws {
        let fx = Fixtures()
        _ = try await fx.device.setMuted(true)
        do {
            _ = try await fx.device.startRecording()
            XCTFail("Expected muted error")
        } catch {
            XCTAssertEqual(error as? DeviceError, .muted)
        }
    }
}

final class SyncTests: XCTestCase {
    func testSyncCopiesWaitingRecordingsAndTranscribesThem() async throws {
        let fx = Fixtures()
        var events: [SyncEvent] = []
        for await event in await fx.sync.startSync() { events.append(event) }

        XCTAssertEqual(events.last, .finished(.copied(count: 3)))
        let progress = events.compactMap { event -> SyncProgressSnapshot? in
            if case .progress(let p) = event { return p }
            return nil
        }
        XCTAssertEqual(progress.first?.phase, .connecting)
        XCTAssertTrue(progress.contains { $0.phase == .copying && $0.fileIndex == 3 && $0.fileCount == 3 })
        let fractions = progress.map(\.fraction)
        XCTAssertEqual(fractions, fractions.sorted(), "Progress never goes backwards")
        XCTAssertEqual(fractions.last, 1)

        let afterSync = try await fx.store.recordings()
        XCTAssertEqual(afterSync.count, 27)
        let device = await fx.device.snapshot()
        XCTAssertEqual(device.waitingCount, 0)
        XCTAssertEqual(device.lastSynced, TestClock.reference)
        let history = try await fx.store.syncHistory()
        XCTAssertEqual(history.count, FixtureData.history.count + 1)
        XCTAssertTrue(history.contains { $0.result == .success && $0.recordingCount == 3 && $0.startedAt == TestClock.reference })

        await fx.library.waitForTranscriptions()
        let new = try await fx.store.recordings().filter { $0.id.hasPrefix("fixture-sync") }
        XCTAssertEqual(new.count, 3)
        XCTAssertEqual(new.filter { $0.transcript == .done }.count, 2)
        let failed = try XCTUnwrap(new.first { if case .failed = $0.transcript { return true } else { return false } })
        XCTAssertEqual(failed.duration, 125)
        XCTAssertNil(failed.preview)

        try await fx.store.retryTranscription(failed.id)
        await fx.library.waitForTranscriptions()
        let retried = try await fx.store.recordings().first { $0.id == failed.id }
        XCTAssertEqual(retried?.transcript, .done)
        let segments = try await fx.store.segments(for: failed.id)
        XCTAssertEqual(segments.count, 3)
    }

    func testSecondSyncFindsNothingNew() async throws {
        let fx = Fixtures()
        for await _ in await fx.sync.startSync() {}
        var last: SyncEvent?
        for await event in await fx.sync.startSync() { last = event }
        XCTAssertEqual(last, .finished(.nothingNew))
        let newest = try await fx.store.syncHistory().first
        XCTAssertEqual(newest?.result, .nothingNew)
        await fx.library.waitForTranscriptions()
    }

    func testSpeechModelDownload() async {
        let speech = FixtureSpeechModels(pace: .zero)
        let before = await speech.models()
        XCTAssertEqual(before.map(\.installed), [false, true])
        var last = 0.0
        for await fraction in await speech.download("openai_whisper-base.en") { last = fraction }
        XCTAssertEqual(last, 1)
        let after = await speech.models()
        XCTAssertEqual(after.map(\.installed), [true, true])
    }
}
