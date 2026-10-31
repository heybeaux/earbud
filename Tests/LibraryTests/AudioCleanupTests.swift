import Foundation
import GRDB
@testable import Library
import Testing

/// 3.4: the automatic-cleanup age query, the cleanup pass, and the Storage snapshot.
@Suite("AudioCleanup")
struct AudioCleanupTests {
    private var fm: FileManager { .default }

    /// A transcribed recording with an M4A (`m4aBytes`) and `.opus` (`opusBytes`) on disk.
    private func transcribed(_ s: LibraryStore, at t: TimeInterval, m4aBytes: Int = 16, opusBytes: Int = 8,
                             transcript: String = "words") throws -> Recording {
        let id = UUID().uuidString
        let dir = s.paths.audioDirectory(for: Date(timeIntervalSince1970: t))
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let m4a = dir.appendingPathComponent("\(id).m4a"), opus = dir.appendingPathComponent("\(id).opus")
        try Data(repeating: 0x41, count: m4aBytes).write(to: m4a)
        try Data(repeating: 0x42, count: opusBytes).write(to: opus)
        let r = Recording(id: id, recordedAt: Date(timeIntervalSince1970: t), durationSeconds: 10, frameCount: 500,
                          rawPath: "raw/s/\(id).bin", opusPath: s.paths.relative(opus), audioPath: s.paths.relative(m4a),
                          createdAt: Date(timeIntervalSince1970: 1_800_000_000))
        try s.insert(r)
        try s.completeTranscription(recordingId: id, segments: [
            Segment(recordingId: id, position: 0, start: 0, end: 4, text: transcript),
        ], model: "m")
        return try #require(try s.recording(id: id))
    }

    // MARK: Age query

    @Test func candidatesOnlyFinishedTranscriptsPastCutoff() throws {
        let s = try makeStore()
        let now = Date(timeIntervalSince1970: 100 * 86_400)
        // Old and transcribed: a candidate.
        let old = try transcribed(s, at: 10 * 86_400)
        // Recent and transcribed: too new.
        _ = try transcribed(s, at: 99 * 86_400)
        // Old but still waiting for a transcript: audio is the only copy of the words.
        let waiting = try rec(s, at: 11 * 86_400)
        try s.enqueueTranscription(recordingId: waiting.id, model: "m")

        let due = try AudioCleanup.candidates(store: s, olderThanDays: 30, now: now)
        #expect(due.map(\.id) == [old.id])
    }

    @Test func candidatesSkipsAlreadyDeletedAudioAndTrashedRecordings() throws {
        let s = try makeStore()
        let now = Date(timeIntervalSince1970: 100 * 86_400)
        let a = try transcribed(s, at: 1 * 86_400)
        let b = try transcribed(s, at: 2 * 86_400)
        let c = try transcribed(s, at: 3 * 86_400)
        try s.deleteAudio(recordingIds: [a.id])      // audio already gone
        try s.moveToTrash(recordingId: b.id)          // whole recording in Recently Deleted

        let due = try AudioCleanup.candidates(store: s, olderThanDays: 30, now: now)
        #expect(due.map(\.id) == [c.id])
    }

    // MARK: Cleanup pass

    @Test func runMovesCandidatesToTranscriptOnlyAndKeepsTranscripts() throws {
        let s = try makeStore()
        let now = Date(timeIntervalSince1970: 100 * 86_400)
        let old = try transcribed(s, at: 5 * 86_400, transcript: "keep these words")
        _ = try transcribed(s, at: 99 * 86_400)

        let moved = try AudioCleanup.run(store: s, olderThanDays: 30, now: now)
        #expect(moved == [old.id])

        let after = try #require(try s.recording(id: old.id))
        #expect(after.isTranscriptOnly)
        #expect(after.audioDeletedAt != nil)
        // The transcript and search survive.
        #expect(try s.segments(recordingId: old.id).map(\.text) == ["keep these words"])
        #expect(try s.search("keep these words").map(\.recording.id) == [old.id])
        // Running again is a no-op (it is already transcript-only).
        #expect(try AudioCleanup.run(store: s, olderThanDays: 30, now: now).isEmpty)
    }

    // MARK: Storage snapshot

    @Test func storageCountsAudioTranscriptsAndRecentlyDeleted() throws {
        let s = try makeStore()
        let a = try transcribed(s, at: 1 * 86_400, m4aBytes: 100, opusBytes: 40, transcript: "hello")
        _ = try transcribed(s, at: 2 * 86_400, m4aBytes: 60, opusBytes: 20, transcript: "world")

        let before = try AudioCleanup.storage(store: s)
        #expect(before.recordingCount == 2)
        #expect(before.audioBytes == 220)               // 100+40 + 60+20
        #expect(before.transcriptBytes == 10)           // "hello" + "world"
        #expect(before.recentlyDeletedBytes == 0)

        // Delete one recording's audio: its bytes move from audio to Recently Deleted.
        try s.deleteAudio(recordingIds: [a.id])
        let after = try AudioCleanup.storage(store: s)
        #expect(after.audioBytes == 80)                 // only the second recording's audio
        #expect(after.transcriptBytes == 10)            // transcripts untouched
        #expect(after.recentlyDeletedBytes >= 140)      // a's audio now in trash/audio/<id>/
    }
}
