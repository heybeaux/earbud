import Foundation
import GRDB
@testable import Library
import Testing

private var fm: FileManager { .default }

/// A transcribed recording with an M4A and `.opus` on disk.
private func transcribed(_ s: LibraryStore, at t: TimeInterval, text: String,
                         source: RecordingSource = .fieldy) throws -> Recording {
    let id = UUID().uuidString
    let dir = s.paths.audioDirectory(for: Date(timeIntervalSince1970: t))
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    let m4a = dir.appendingPathComponent("\(id).m4a"), opus = dir.appendingPathComponent("\(id).opus")
    try Data("m4a-\(id)".utf8).write(to: m4a)
    try Data("opus-\(id)".utf8).write(to: opus)
    let r = Recording(id: id, recordedAt: Date(timeIntervalSince1970: t), durationSeconds: 10, frameCount: 500,
                      rawPath: "raw/s/\(id).bin", opusPath: s.paths.relative(opus), audioPath: s.paths.relative(m4a),
                      createdAt: Date(timeIntervalSince1970: 1_800_000_000), source: source)
    try s.insert(r)
    try s.completeTranscription(recordingId: id, segments: [
        Segment(recordingId: id, position: 0, start: 0, end: 4, text: text),
    ], model: "m")
    return try #require(try s.recording(id: id))
}

private func exists(_ s: LibraryStore, _ rel: String?) -> Bool {
    guard let rel else { return false }
    return fm.fileExists(atPath: s.paths.absolute(rel).path)
}

private func trashed(_ s: LibraryStore, _ r: Recording, _ ext: String) -> URL {
    s.paths.trashedAudioDirectory(recordingID: r.id).appendingPathComponent("\(r.id).\(ext)")
}

@Suite("Library v1.1")
struct LibraryV2Tests {
    // MARK: 1.1 sources

    @Test func migratesV1Library() throws {
        let root = fm.temporaryDirectory.appendingPathComponent("earbudkit-v1-\(UUID().uuidString)", isDirectory: true)
        let paths = LibraryPaths(root: root)
        do {
            let v1 = try LibraryStore(paths: paths, migratingUpTo: "v1")
            try v1.db.write { db in
                #expect(try !db.columns(in: "recording").map(\.name).contains("source"))
                try db.execute(sql: """
                    INSERT INTO recording (id, recordedAt, timeUnknown, durationSeconds, frameCount, audioState, rawPath,
                        audioPath, createdAt, transcriptState, noSpeech)
                    VALUES ('old', ?, 0, 12, 600, 'ok', 'raw/S1/00001.bin', 'audio/2026/10/old.m4a', ?, 'done', 0)
                    """, arguments: [Date(timeIntervalSince1970: 1000), Date(timeIntervalSince1970: 2000)])
                try db.execute(sql: """
                    INSERT INTO segment (recordingId, position, start, end, text) VALUES ('old', 0, 0, 3, 'Meet at the ferry dock')
                    """)
            }
        }
        let s = try LibraryStore(paths: paths)
        let r = try #require(try s.recording(id: "old"))
        #expect(r.source == .fieldy)
        #expect(r.sourceName == nil && r.contentHash == nil)
        #expect(r.audioDeletedAt == nil && r.audioPurgedAt == nil && !r.isTranscriptOnly)
        #expect(r.rawPath == "raw/S1/00001.bin" && r.audioPath == "audio/2026/10/old.m4a")
        #expect(try s.segments(recordingId: "old").map(\.text) == ["Meet at the ferry dock"])
        #expect(try s.search("ferry dock").map(\.recording.id) == ["old"])
        let indexed = try s.db.read { db in try db.indexes(on: "recording").flatMap(\.columns) }
        #expect(indexed.contains("contentHash"))
        // New rows of every source work in the migrated library.
        var imp = try rec(s, at: 5000)
        imp.source = .imported
        imp.sourceName = "Interview.wav"
        imp.contentHash = "abc"
        try s.update(imp)
        #expect(try s.recording(id: imp.id) == imp)
    }

    @Test func migratesV3LibraryToAddTimeFromFileDate() throws {
        let root = fm.temporaryDirectory.appendingPathComponent("earbudkit-v3-\(UUID().uuidString)", isDirectory: true)
        let paths = LibraryPaths(root: root)
        do {
            let v3 = try LibraryStore(paths: paths, migratingUpTo: "v3")
            try v3.db.write { db in
                #expect(try !db.columns(in: "recording").map(\.name).contains("timeFromFileDate"))
                try db.execute(sql: """
                    INSERT INTO recording (id, recordedAt, timeUnknown, durationSeconds, frameCount, audioState, rawPath,
                        createdAt, transcriptState, noSpeech, source)
                    VALUES ('old', ?, 0, 12, 0, 'ok', 'imported/old.wav', ?, 'none', 0, 'imported')
                    """, arguments: [Date(timeIntervalSince1970: 1000), Date(timeIntervalSince1970: 2000)])
            }
        }
        let s = try LibraryStore(paths: paths)
        let r = try #require(try s.recording(id: "old"))
        #expect(r.timeFromFileDate == false)
        var imp = try rec(s, at: 5000)
        imp.timeFromFileDate = true
        try s.update(imp)
        #expect(try s.recording(id: imp.id)?.timeFromFileDate == true)
    }

    @Test func sourceFieldsRoundTrip() throws {
        let s = try makeStore()
        let mic = Recording(recordedAt: Date(timeIntervalSince1970: 100), durationSeconds: 3600, frameCount: 0,
                            rawPath: "capture/m.caf", createdAt: Date(timeIntervalSince1970: 200),
                            source: .microphone, sourceName: "Wireless PRO RX")
        try s.insert(mic)
        let got = try #require(try s.recording(id: mic.id))
        #expect(got == mic)
        #expect(got.syncId == nil && got.deviceFileId == nil && got.opusPath == nil)
        #expect(try rec(s, at: 1).source == .fieldy)
    }

    @Test func contentHashLookupIncludesTrash() throws {
        let s = try makeStore()
        #expect(try s.recording(contentHash: "h1") == nil)
        var r = try rec(s, at: 1)
        r.source = .imported
        r.contentHash = "h1"
        try s.update(r)
        #expect(try s.recording(contentHash: "h1")?.id == r.id)
        try s.moveToTrash(recordingId: r.id)
        #expect(try s.recording(contentHash: "h1")?.id == r.id)
        #expect(try s.recording(contentHash: "h2") == nil)
        // After the import copy is gone the hash still finds it.
        try s.markRawDeleted(recordingId: r.id)
        #expect(try s.recording(contentHash: "h1")?.rawDeletedAt != nil)
    }

    @Test func rawCleanupCoversEverySource() throws {
        let s = try makeStore()
        var ids: [String] = []
        for (i, src) in RecordingSource.allCases.enumerated() {
            var r = try rec(s, at: TimeInterval(i))
            r.source = src
            r.verifiedAt = Date(timeIntervalSince1970: 1000)
            try s.update(r)
            ids.append(r.id)
        }
        let due = try s.rawCleanupCandidates(verifiedBefore: Date(timeIntervalSince1970: 5000))
        #expect(Set(due.map(\.id)) == Set(ids))
        for id in ids { try s.markRawDeleted(recordingId: id, at: Date(timeIntervalSince1970: 6000)) }
        #expect(try s.rawCleanupCandidates(verifiedBefore: Date(timeIntervalSince1970: 5000)).isEmpty)
        for id in ids { #expect(try s.recording(id: id)?.rawDeletedAt == Date(timeIntervalSince1970: 6000)) }
    }

    // MARK: 3.1 transcripts outlive audio

    @Test func deleteAudioRequiresFinishedTranscript() throws {
        let s = try makeStore()
        let done = try transcribed(s, at: 1, text: "ready")
        let none = try rec(s, at: 2)
        let waiting = try rec(s, at: 3)
        try s.enqueueTranscription(recordingId: waiting.id, model: "m")
        let running = try rec(s, at: 4)
        try s.enqueueTranscription(recordingId: running.id, model: "m")
        try s.markTranscribing(recordingId: running.id)
        let failed = try rec(s, at: 5)
        try s.enqueueTranscription(recordingId: failed.id, model: "m")
        try s.failTranscription(recordingId: failed.id, error: "x")
        for r in [none, waiting, running, failed] {
            #expect(throws: AudioRetentionError.transcriptNotReady(r.id)) { try s.deleteAudio(recordingIds: [r.id]) }
        }
        // One bad recording in a selection: nothing moves.
        #expect(throws: AudioRetentionError.transcriptNotReady(waiting.id)) {
            try s.deleteAudio(recordingIds: [done.id, waiting.id])
        }
        #expect(exists(s, done.audioPath) && exists(s, done.opusPath))
        #expect(try s.recording(id: done.id)?.audioDeletedAt == nil)
        #expect(throws: AudioRetentionError.recordingNotFound("nope")) { try s.deleteAudio(recordingIds: ["nope"]) }
        // No speech detected is still a finished transcript.
        let silent = try rec(s, at: 6)
        try s.completeTranscription(recordingId: silent.id, segments: [], model: "m")
        try s.deleteAudio(recordingIds: [silent.id])
        #expect(try s.recording(id: silent.id)?.isTranscriptOnly == true)
    }

    @Test func deleteRestorePurgeKeepsTranscript() throws {
        let s = try makeStore()
        let a = try transcribed(s, at: 1000, text: "We drove up to Powell River", source: .imported)
        let b = try transcribed(s, at: 2000, text: "The ferry was late")
        let t0 = Date(timeIntervalSince1970: 10_000)

        func transcriptIntact() throws {
            #expect(try s.segments(recordingId: a.id).map(\.text) == ["We drove up to Powell River"])
            #expect(try s.search("powell riv").map(\.recording.id) == [a.id])
            #expect(try s.recordings().map(\.id) == [b.id, a.id])
        }

        // Delete: files move to trash/audio/<id>/, the row stays listed and searchable.
        try s.deleteAudio(recordingIds: [a.id, b.id], at: t0)
        for r in [a, b] {
            #expect(!exists(s, r.audioPath) && !exists(s, r.opusPath))
            #expect(fm.fileExists(atPath: trashed(s, r, "m4a").path) && fm.fileExists(atPath: trashed(s, r, "opus").path))
            let got = try #require(try s.recording(id: r.id))
            #expect(got.audioDeletedAt == t0 && got.audioPurgedAt == nil && got.isTranscriptOnly)
            #expect(got.audioPath == r.audioPath)
        }
        try transcriptIntact()
        #expect(try s.search("powell").first?.recording.isTranscriptOnly == true)
        #expect(Set(try s.deletedAudio().map(\.id)) == [a.id, b.id])
        #expect(try s.trash().isEmpty)
        // Deleting again is a no-op.
        try s.deleteAudio(recordingIds: [a.id], at: Date(timeIntervalSince1970: 99_999))
        #expect(try s.recording(id: a.id)?.audioDeletedAt == t0)

        // Restore: files back in place, playable again.
        try s.restoreAudio(recordingId: b.id)
        #expect(exists(s, b.audioPath) && exists(s, b.opusPath))
        #expect(try String(contentsOf: s.paths.absolute(b.audioPath!), encoding: .utf8) == "m4a-\(b.id)")
        #expect(!fm.fileExists(atPath: s.paths.trashedAudioDirectory(recordingID: b.id).path))
        #expect(try s.recording(id: b.id)?.isTranscriptOnly == false)
        #expect(try s.deletedAudio().map(\.id) == [a.id])
        #expect(throws: AudioRetentionError.audioNotDeleted(b.id)) { try s.restoreAudio(recordingId: b.id) }
        try transcriptIntact()

        // 30-day purge: only audio deleted before the cutoff.
        #expect(try s.purgeAudio(deletedBefore: Date(timeIntervalSince1970: 5_000)).isEmpty)
        let t1 = Date(timeIntervalSince1970: 50_000)
        let purged = try s.purgeAudio(deletedBefore: Date(timeIntervalSince1970: 20_000), at: t1)
        #expect(purged.map(\.id) == [a.id])
        #expect(!fm.fileExists(atPath: s.paths.trashedAudioDirectory(recordingID: a.id).path))
        let gone = try #require(try s.recording(id: a.id))
        #expect(gone.audioPurgedAt == t1 && gone.audioDeletedAt == t0 && gone.isTranscriptOnly)
        #expect(gone.audioPath == nil && gone.opusPath == nil)
        #expect(try s.deletedAudio().isEmpty)
        #expect(throws: AudioRetentionError.audioPurged(a.id)) { try s.restoreAudio(recordingId: a.id) }
        #expect(try s.purgeAudio(deletedBefore: .distantFuture).isEmpty)
        try transcriptIntact()
        // Transcript-only rows can still be renamed.
        try s.rename(recordingId: a.id, title: "Trip")
        #expect(try s.recording(id: a.id)?.title == "Trip")
    }

    @Test func emptyRecentlyDeletedPurgesAudioAndRecordings() throws {
        let s = try makeStore()
        let keep = try transcribed(s, at: 1, text: "keep the words")
        let drop = try transcribed(s, at: 2, text: "drop everything")
        try s.deleteAudio(recordingIds: [keep.id], at: Date())
        try s.moveToTrash(recordingId: drop.id)
        try s.emptyRecentlyDeleted(at: Date(timeIntervalSince1970: 77))
        #expect(try s.recording(id: keep.id)?.audioPurgedAt == Date(timeIntervalSince1970: 77))
        #expect(!fm.fileExists(atPath: s.paths.trashedAudioDirectory(recordingID: keep.id).path))
        #expect(try s.search("keep the").map(\.recording.id) == [keep.id])
        #expect(try s.recording(id: drop.id) == nil)
        #expect(!exists(s, drop.audioPath) && !exists(s, drop.opusPath))
        #expect(try s.trash().isEmpty && s.deletedAudio().isEmpty)
    }

    @Test func fullDeleteRemovesEverything() throws {
        let s = try makeStore()
        let r = try transcribed(s, at: 1, text: "secret plans")
        let raw = s.paths.absolute(r.rawPath)
        try fm.createDirectory(at: raw.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("raw".utf8).write(to: raw)
        let other = try transcribed(s, at: 2, text: "other plans")
        try s.deleteAudio(recordingIds: [r.id])
        try s.moveToTrash(recordingId: r.id, at: Date(timeIntervalSince1970: 100))
        // Audio of a recording in Recently Deleted is listed with the recording, not twice.
        #expect(try s.deletedAudio().isEmpty)
        #expect(try s.trash().map(\.id) == [r.id])
        #expect(try s.purgeTrash(deletedBefore: Date(timeIntervalSince1970: 200)).map(\.id) == [r.id])
        #expect(try s.recording(id: r.id) == nil)
        #expect(try s.segments(recordingId: r.id).isEmpty)
        #expect(try s.search("plans").map(\.recording.id) == [other.id])
        #expect(!fm.fileExists(atPath: raw.path))
        #expect(!fm.fileExists(atPath: s.paths.trashedAudioDirectory(recordingID: r.id).path))
        #expect(exists(s, other.audioPath) && exists(s, other.opusPath))
    }

    @Test func restoringRecordingBringsBackItsDeletedAudioEntry() throws {
        let s = try makeStore()
        let r = try transcribed(s, at: 1, text: "words")
        try s.deleteAudio(recordingIds: [r.id])
        try s.moveToTrash(recordingId: r.id)
        #expect(try s.deletedAudio().isEmpty)
        try s.restore(recordingId: r.id)
        #expect(try s.deletedAudio().map(\.id) == [r.id])
        try s.restoreAudio(recordingId: r.id)
        #expect(exists(s, r.audioPath))
    }

    @Test func transcriptOnlyCannotBeQueued() throws {
        let s = try makeStore()
        let r = try transcribed(s, at: 1, text: "words")
        try s.enqueueTranscription(recordingId: r.id, model: "small")
        #expect(try s.jobs().map(\.recordingId) == [r.id])
        // Deleting the audio drops a queued "Transcribe again" that would find no file.
        try s.deleteAudio(recordingIds: [r.id])
        #expect(try s.jobs().isEmpty)
        #expect(throws: AudioRetentionError.audioDeleted(r.id)) { try s.enqueueTranscription(recordingId: r.id, model: "m") }
        #expect(try s.recording(id: r.id)?.transcriptState == .done)
        try s.restoreAudio(recordingId: r.id)
        try s.enqueueTranscription(recordingId: r.id, model: "m")
        #expect(try s.jobs().map(\.recordingId) == [r.id])
    }

    @Test func deleteAudioWithMissingFilesStillMarksRow() throws {
        let s = try makeStore()
        let r = try transcribed(s, at: 1, text: "words")
        try fm.removeItem(at: s.paths.absolute(r.opusPath!))
        try s.deleteAudio(recordingIds: [r.id])
        #expect(fm.fileExists(atPath: trashed(s, r, "m4a").path))
        #expect(!fm.fileExists(atPath: trashed(s, r, "opus").path))
        try s.restoreAudio(recordingId: r.id)
        #expect(exists(s, r.audioPath) && !exists(s, r.opusPath))
    }

    @Test func trashPaths() {
        let p = LibraryPaths(root: URL(fileURLWithPath: "/tmp/eb"))
        #expect(p.trashedAudioDirectory(recordingID: "R1").path == "/tmp/eb/trash/audio/R1")
        #expect(p.imported.path == "/tmp/eb/imported")
        #expect(p.capture.path == "/tmp/eb/capture")
    }
}
