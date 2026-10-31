import Foundation
import Library
import Testing

func makeStore() throws -> LibraryStore {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("earbudkit-lib-\(UUID().uuidString)", isDirectory: true)
    return try LibraryStore(paths: LibraryPaths(root: root))
}

func rec(_ store: LibraryStore, at t: TimeInterval, raw: String? = nil) throws -> Recording {
    // Whole-second dates: SQLite stores datetimes with millisecond precision.
    let r = Recording(recordedAt: Date(timeIntervalSince1970: t), durationSeconds: 10, frameCount: 500,
                      rawPath: raw ?? "raw/s/\(UUID().uuidString).bin", createdAt: Date(timeIntervalSince1970: 1_800_000_000))
    try store.insert(r)
    return r
}

@Suite("Library")
struct LibraryTests {
    @Test func pathsLayout() throws {
        let p = LibraryPaths(root: URL(fileURLWithPath: "/tmp/eb"))
        #expect(p.database.path == "/tmp/eb/library.sqlite")
        #expect(p.rawDirectory(syncID: "S1").path == "/tmp/eb/raw/S1")
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Vancouver")!
        let dir = p.audioDirectory(for: Date(timeIntervalSince1970: 1_793_391_123), calendar: cal)
        #expect(dir.path == "/tmp/eb/audio/2026/10")
        #expect(p.relative(URL(fileURLWithPath: "/tmp/eb/audio/2026/10/x.m4a")) == "audio/2026/10/x.m4a")
        #expect(p.absolute("audio/x.m4a").path == "/tmp/eb/audio/x.m4a")
        #expect(LibraryPaths.defaultRoot.path.hasSuffix("Library/Application Support/EarBud"))
    }

    @Test func createsDatabaseAndDirectories() throws {
        let s = try makeStore()
        for u in [s.paths.database, s.paths.audio, s.paths.raw, s.paths.models] {
            #expect(FileManager.default.fileExists(atPath: u.path))
        }
        // Reopening runs migrations idempotently and keeps data.
        let r = try rec(s, at: 1000)
        let again = try LibraryStore(paths: s.paths)
        #expect(try again.recording(id: r.id) == r)
    }

    @Test func listNewestFirstAndTrash() throws {
        let s = try makeStore()
        let a = try rec(s, at: 1000), b = try rec(s, at: 3000), c = try rec(s, at: 2000)
        #expect(try s.recordings().map(\.id) == [b.id, c.id, a.id])
        try s.moveToTrash(recordingId: c.id, at: Date(timeIntervalSince1970: 10_000))
        #expect(try s.recordings().map(\.id) == [b.id, a.id])
        #expect(try s.trash().map(\.id) == [c.id])
        try s.restore(recordingId: c.id)
        #expect(try s.recordings().count == 3)
        try s.moveToTrash(recordingId: c.id, at: Date(timeIntervalSince1970: 10_000))
        #expect(try s.purgeTrash(deletedBefore: Date(timeIntervalSince1970: 5_000)).isEmpty)
        #expect(try s.purgeTrash(deletedBefore: Date(timeIntervalSince1970: 20_000)).map(\.id) == [c.id])
        #expect(try s.recording(id: c.id) == nil)
    }

    @Test func rename() throws {
        let s = try makeStore()
        let r = try rec(s, at: 1)
        try s.rename(recordingId: r.id, title: "  Standup  ")
        #expect(try s.recording(id: r.id)?.title == "Standup")
        try s.rename(recordingId: r.id, title: "   ")
        #expect(try s.recording(id: r.id)?.title == nil)
    }

    @Test func rawPathIsUnique() throws {
        let s = try makeStore()
        _ = try rec(s, at: 1, raw: "raw/a/00001.bin")
        #expect(throws: (any Error).self) { _ = try rec(s, at: 2, raw: "raw/a/00001.bin") }
        #expect(try s.importedRawPaths() == ["raw/a/00001.bin"])
    }

    @Test func ftsSearchPhraseAndPrefix() throws {
        let s = try makeStore()
        let a = try rec(s, at: 1000), b = try rec(s, at: 2000)
        try s.completeTranscription(recordingId: a.id, segments: [
            Segment(recordingId: a.id, position: 0, start: 0, end: 4, text: "We drove up to Powell River on Friday."),
            Segment(recordingId: a.id, position: 1, start: 135, end: 140, text: "The ferry was late."),
        ], model: "m")
        try s.completeTranscription(recordingId: b.id, segments: [
            Segment(recordingId: b.id, position: 0, start: 0, end: 3, text: "The river was powerful, said Powell."),
        ], model: "m")
        let phrase = try s.search("Powell River")
        #expect(phrase.map(\.recording.id) == [a.id])
        #expect(phrase.first?.highlighted == "We drove up to «Powell River» on Friday.")
        #expect(try s.search("powell riv").map(\.recording.id) == [a.id])
        #expect(Set(try s.search("river").map(\.recording.id)) == [a.id, b.id])
        let ferry = try s.search("ferry")
        #expect(ferry.first?.segment.start == 135)
        #expect(try s.search("   ").isEmpty)
        #expect(try s.search("\"* OR (").isEmpty)
        // Replacing a transcript updates the index.
        try s.completeTranscription(recordingId: a.id, segments: [
            Segment(recordingId: a.id, position: 0, start: 0, end: 1, text: "Nothing about that town."),
        ], model: "m")
        #expect(try s.search("Powell River").isEmpty)
        // Trashed recordings are not found.
        try s.moveToTrash(recordingId: b.id)
        #expect(try s.search("river").isEmpty)
    }

    @Test func queueOldestFirstAndStates() throws {
        let s = try makeStore()
        let newer = try rec(s, at: 5000), older = try rec(s, at: 1000)
        try s.enqueueTranscription(recordingId: newer.id, model: "m", at: Date(timeIntervalSince1970: 1))
        try s.enqueueTranscription(recordingId: older.id, model: "m", at: Date(timeIntervalSince1970: 2))
        #expect(try s.recording(id: older.id)?.transcriptState == .waiting)
        #expect(try s.nextWaitingJob()?.recordingId == older.id)

        try s.markTranscribing(recordingId: older.id)
        #expect(try s.recording(id: older.id)?.transcriptState == .transcribing)
        #expect(try s.nextWaitingJob()?.recordingId == newer.id)

        // Quit mid-job: the job resumes on next launch.
        #expect(try s.resetInterruptedTranscriptions() == 1)
        #expect(try s.recording(id: older.id)?.transcriptState == .waiting)
        #expect(try s.nextWaitingJob()?.recordingId == older.id)

        try s.markTranscribing(recordingId: older.id)
        try s.failTranscription(recordingId: older.id, error: "boom")
        let failed = try s.recording(id: older.id)
        #expect(failed?.transcriptState == .failed)
        #expect(failed?.transcriptError == "boom")
        #expect(try s.nextWaitingJob()?.recordingId == newer.id)
        try s.retryTranscription(recordingId: older.id)
        #expect(try s.nextWaitingJob()?.recordingId == older.id)

        try s.completeTranscription(recordingId: older.id, segments: [], model: "m")
        let done = try s.recording(id: older.id)
        #expect(done?.transcriptState == .done)
        #expect(done?.noSpeech == true)
        #expect(try s.jobs().map(\.recordingId) == [newer.id])
    }

    @Test func transcribeAgainKeepsOldTranscriptUntilSuccess() throws {
        let s = try makeStore()
        let r = try rec(s, at: 1)
        try s.completeTranscription(recordingId: r.id, segments: [Segment(recordingId: r.id, position: 0, start: 0, end: 1, text: "old")], model: "base")
        try s.enqueueTranscription(recordingId: r.id, model: "small")
        #expect(try s.recording(id: r.id)?.transcriptState == .done)
        try s.markTranscribing(recordingId: r.id)
        try s.failTranscription(recordingId: r.id, error: "x")
        #expect(try s.recording(id: r.id)?.transcriptState == .done)
        #expect(try s.segments(recordingId: r.id).map(\.text) == ["old"])
        try s.retryTranscription(recordingId: r.id)
        try s.completeTranscription(recordingId: r.id, segments: [Segment(recordingId: r.id, position: 9, start: 0, end: 1, text: "new")], model: "small")
        let segs = try s.segments(recordingId: r.id)
        #expect(segs.map(\.text) == ["new"])
        #expect(segs.first?.position == 0)
        #expect(try s.recording(id: r.id)?.transcriptModel == "small")
    }

    @Test func syncHistoryNewestFirst() throws {
        let s = try makeStore()
        var e1 = try s.insert(SyncHistoryEntry(syncId: "a", startedAt: Date(timeIntervalSince1970: 100), result: .interrupted))
        _ = try s.insert(SyncHistoryEntry(syncId: "b", startedAt: Date(timeIntervalSince1970: 200), result: .failed))
        e1.result = .success
        e1.recordingCount = 3
        try s.update(e1)
        #expect(try s.syncHistory().map(\.syncId) == ["b", "a"])
        #expect(try s.lastSuccessfulSync()?.syncId == "a")
        #expect(try s.lastSuccessfulSync()?.recordingCount == 3)
    }

    @Test func rawCleanupCandidates() throws {
        let s = try makeStore()
        var old = try rec(s, at: 1)
        old.verifiedAt = Date(timeIntervalSince1970: 1000)
        try s.update(old)
        var fresh = try rec(s, at: 2)
        fresh.verifiedAt = Date(timeIntervalSince1970: 9000)
        try s.update(fresh)
        var incomplete = try rec(s, at: 3)
        incomplete.audioState = .incomplete
        incomplete.verifiedAt = Date(timeIntervalSince1970: 1000)
        try s.update(incomplete)
        #expect(try s.rawCleanupCandidates(verifiedBefore: Date(timeIntervalSince1970: 5000)).map(\.id) == [old.id])
        try s.markRawDeleted(recordingId: old.id)
        #expect(try s.rawCleanupCandidates(verifiedBefore: Date(timeIntervalSince1970: 5000)).isEmpty)
    }

    @Test func settings() throws {
        let s = try makeStore()
        #expect(try s.setting("x") == nil)
        try s.setSetting("x", "1")
        try s.setSetting("x", "2")
        #expect(try s.setting("x") == "2")
        try s.setSetting("x", nil)
        #expect(try s.setting("x") == nil)
        struct V: Codable, Equatable { var a: Int }
        try s.setSetting("v", json: V(a: 7))
        #expect(try s.setting("v", as: V.self) == V(a: 7))
    }
}
