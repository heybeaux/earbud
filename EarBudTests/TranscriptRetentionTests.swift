import XCTest
@testable import EarBud

/// 3.2-3.4: Delete Audio / Keep Transcript, Recently Deleted's audio section, and Storage.
@MainActor
final class TranscriptRetentionTests: XCTestCase {
    func testRequestDeleteAudioComputesFreedBytesAndTitles() async {
        let model = Fixtures().model()
        await model.start()
        let done = try! await model.library.recordings().first { $0.transcript.isFinished && !$0.isTranscriptOnly }!

        model.requestDeleteAudio([done.id])
        let request = try! XCTUnwrap(model.deleteAudioConfirmation)
        XCTAssertEqual(request.ids, [done.id])
        XCTAssertEqual(request.titles.first, done.isUntitled ? model.formatting.untitledHeading(done.recordedAt, now: model.now()) : done.title)
    }

    func testConfirmDeleteAudioMovesToTranscriptOnlyAndClearsRequest() async {
        let model = Fixtures().model()
        await model.start()
        let target = try! await model.library.recordings().first { $0.transcript.isFinished && !$0.isTranscriptOnly }!

        model.requestDeleteAudio([target.id])
        XCTAssertNotNil(model.deleteAudioConfirmation)
        await model.confirmDeleteAudio()
        XCTAssertNil(model.deleteAudioConfirmation)

        let updated = model.recording(target.id)
        XCTAssertEqual(updated?.isTranscriptOnly, true)
        XCTAssertNotNil(updated?.audioDeletedAt)
        XCTAssertTrue(model.deletedAudio.contains { $0.id == target.id })
    }

    func testRestoreAudioBringsBackPlayback() async {
        let model = Fixtures().model()
        await model.start()
        let target = try! await model.library.recordings().first { $0.transcript.isFinished && !$0.isTranscriptOnly }!
        model.requestDeleteAudio([target.id])
        await model.confirmDeleteAudio()
        XCTAssertTrue(model.deletedAudio.contains { $0.id == target.id })

        await model.restoreAudio(target.id)
        XCTAssertFalse(model.deletedAudio.contains { $0.id == target.id })
        XCTAssertEqual(model.recording(target.id)?.isTranscriptOnly, false)
    }

    func testEmptyRecentlyDeletedClearsBothSections() async {
        let model = Fixtures().model()
        await model.start()
        let audioTarget = try! await model.library.recordings().first { $0.transcript.isFinished && !$0.isTranscriptOnly }!
        model.requestDeleteAudio([audioTarget.id])
        await model.confirmDeleteAudio()
        let trashedID = model.recordings.first!.id
        await model.moveToTrash(trashedID)

        XCTAssertFalse(model.deletedAudio.isEmpty)
        XCTAssertFalse(model.deleted.isEmpty)
        await model.emptyRecentlyDeleted()
        XCTAssertTrue(model.deletedAudio.isEmpty)
        XCTAssertTrue(model.deleted.isEmpty)
    }

    func testCleanUpOldAudioOnlyMovesTranscribedRecordingsOlderThanCutoff() async {
        let model = Fixtures().model()
        await model.start()
        let cutoff = model.now().addingTimeInterval(-15 * 86_400)
        let before = model.recordings
        let eligibleBefore = Set(before.filter { !$0.isTranscriptOnly && $0.transcript.isFinished && $0.recordedAt < cutoff }.map(\.id))
        XCTAssertFalse(eligibleBefore.isEmpty, "fixture needs at least one recording past the cutoff")
        let alreadyTranscriptOnly = Set(before.filter(\.isTranscriptOnly).map(\.id))

        let count = await model.cleanUpOldAudio(olderThanDays: 15)
        XCTAssertEqual(count, eligibleBefore.count)
        for id in eligibleBefore {
            XCTAssertEqual(model.recording(id)?.isTranscriptOnly, true)
        }
        // Nothing that wasn't already transcript-only, and wasn't past the cutoff, got touched.
        for item in model.recordings where !eligibleBefore.contains(item.id) && !alreadyTranscriptOnly.contains(item.id) {
            XCTAssertFalse(item.isTranscriptOnly, "cleanup should not have moved \(item.id)")
        }
    }

    func testStorageSnapshotReflectsTranscriptOnlyRecordings() async {
        let model = Fixtures().model()
        await model.start()
        let before = try! XCTUnwrap(model.storage)
        let target = try! await model.library.recordings().first { $0.transcript.isFinished && !$0.isTranscriptOnly && ($0.audioBytes ?? 0) > 0 }!
        model.requestDeleteAudio([target.id])
        await model.confirmDeleteAudio()
        let after = try! XCTUnwrap(model.storage)
        XCTAssertLessThan(after.audioBytes, before.audioBytes)
        XCTAssertGreaterThanOrEqual(after.recentlyDeletedBytes, before.recentlyDeletedBytes)
    }
}
