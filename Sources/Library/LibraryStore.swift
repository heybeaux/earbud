import Foundation
import GRDB

/// The EarBud library database (GRDB, SQLite WAL, FTS5 transcript search).
public final class LibraryStore: Sendable {
    public let paths: LibraryPaths
    public let db: DatabasePool

    public convenience init(paths: LibraryPaths) throws {
        try self.init(paths: paths, migratingUpTo: nil)
    }

    /// `migratingUpTo` stops at an older schema; tests use it to build a v1 library.
    init(paths: LibraryPaths, migratingUpTo target: String?) throws {
        self.paths = paths
        try paths.createDirectories()
        var config = Configuration()
        config.foreignKeysEnabled = true
        db = try DatabasePool(path: paths.database.path, configuration: config)
        if let target {
            try Self.migrator.migrate(db, upTo: target)
        } else {
            try Self.migrator.migrate(db)
        }
    }

    static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "recording") { t in
                t.primaryKey("id", .text)
                t.column("recordedAt", .datetime).notNull().indexed()
                t.column("timeUnknown", .boolean).notNull().defaults(to: false)
                t.column("durationSeconds", .double).notNull()
                t.column("frameCount", .integer).notNull()
                t.column("title", .text)
                t.column("audioState", .text).notNull()
                t.column("rawPath", .text).notNull().unique()
                t.column("opusPath", .text)
                t.column("audioPath", .text)
                t.column("syncId", .text)
                t.column("deviceFileId", .integer)
                t.column("deviceRecordingId", .integer)
                t.column("verifiedAt", .datetime)
                t.column("rawDeletedAt", .datetime)
                t.column("createdAt", .datetime).notNull()
                t.column("deletedAt", .datetime)
                t.column("transcriptState", .text).notNull()
                t.column("transcriptError", .text)
                t.column("transcriptModel", .text)
                t.column("transcribedAt", .datetime)
                t.column("noSpeech", .boolean).notNull().defaults(to: false)
            }
            try db.create(table: "segment") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("recordingId", .text).notNull().indexed()
                    .references("recording", onDelete: .cascade)
                t.column("position", .integer).notNull()
                t.column("start", .double).notNull()
                t.column("end", .double).notNull()
                t.column("text", .text).notNull()
            }
            try db.create(virtualTable: "segment_fts", using: FTS5()) { t in
                t.synchronize(withTable: "segment")
                t.tokenizer = .unicode61()
                t.column("text")
            }
            try db.create(table: "syncHistory") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("syncId", .text).notNull().unique()
                t.column("startedAt", .datetime).notNull().indexed()
                t.column("finishedAt", .datetime)
                t.column("result", .text).notNull()
                t.column("recordingCount", .integer).notNull()
                t.column("totalSeconds", .double).notNull()
                t.column("bytesReceived", .integer).notNull()
                t.column("droppedFiles", .integer).notNull()
                t.column("message", .text)
                t.column("deviceName", .text)
            }
            try db.create(table: "transcriptionJob") { t in
                t.primaryKey("recordingId", .text).references("recording", onDelete: .cascade)
                t.column("model", .text).notNull()
                t.column("state", .text).notNull()
                t.column("enqueuedAt", .datetime).notNull()
                t.column("attempts", .integer).notNull()
                t.column("lastError", .text)
            }
            try db.create(table: "setting") { t in
                t.primaryKey("key", .text)
                t.column("value", .text).notNull()
            }
        }
        // v1.1: imported and microphone recordings. Every v1 row came from the Fieldy.
        m.registerMigration("v2") { db in
            try db.alter(table: "recording") { t in
                t.add(column: "source", .text).notNull().defaults(to: RecordingSource.fieldy.rawValue)
                t.add(column: "sourceName", .text)
                t.add(column: "contentHash", .text)
            }
            try db.create(index: "recording_on_contentHash", on: "recording", columns: ["contentHash"])
        }
        // v1.1: transcripts outlive audio.
        m.registerMigration("v3") { db in
            try db.alter(table: "recording") { t in
                t.add(column: "audioDeletedAt", .datetime)
                t.add(column: "audioPurgedAt", .datetime)
            }
        }
        // v1.1: imported recording time can fall back to the file date.
        m.registerMigration("v4") { db in
            try db.alter(table: "recording") { t in
                t.add(column: "timeFromFileDate", .boolean).notNull().defaults(to: false)
            }
        }
        // One device recording split over several files: later files are parts.
        m.registerMigration("v5") { db in
            try db.create(table: "recordingPart") { t in
                t.primaryKey("rawPath", .text)
                t.column("recordingId", .text).notNull().indexed()
                    .references("recording", onDelete: .cascade)
                t.column("deviceFileId", .integer)
                t.column("frameCount", .integer).notNull()
                t.column("appendedAt", .datetime).notNull()
            }
        }
        return m
    }

    // MARK: Recordings

    public func insert(_ recording: Recording) throws {
        try db.write { try recording.insert($0) }
    }

    public func update(_ recording: Recording) throws {
        try db.write { try recording.update($0) }
    }

    public func recording(id: String) throws -> Recording? {
        try db.read { try Recording.fetchOne($0, key: id) }
    }

    /// The recording whose raw file, or one of whose parts, is `rawPath`.
    public func recording(rawPath: String) throws -> Recording? {
        try db.read { db in
            if let r = try Recording.filter(Column("rawPath") == rawPath).fetchOne(db) { return r }
            guard let part = try RecordingPart.fetchOne(db, key: rawPath) else { return nil }
            return try Recording.fetchOne(db, key: part.recordingId)
        }
    }

    /// Duplicate check for imports. Includes recordings in Recently Deleted.
    public func recording(contentHash: String) throws -> Recording? {
        try db.read {
            try Recording.filter(Column("contentHash") == contentHash).order(Column("createdAt")).fetchOne($0)
        }
    }

    /// Raw paths already imported, for crash recovery.
    public func importedRawPaths() throws -> Set<String> {
        try db.read { Set(try String.fetchAll($0, sql: "SELECT rawPath FROM recording UNION SELECT rawPath FROM recordingPart")) }
    }

    // MARK: Parts (one device recording over several files)

    /// Appended files of a recording, in the order they were appended.
    public func parts(recordingId: String) throws -> [RecordingPart] {
        try db.read {
            try RecordingPart.filter(Column("recordingId") == recordingId).order(Column("appendedAt"), Column("deviceFileId")).fetchAll($0)
        }
    }

    /// Saves a recording that now includes `part`, in one transaction.
    public func append(_ part: RecordingPart, updating recording: Recording) throws {
        try db.write { db in
            try part.insert(db)
            try recording.update(db)
        }
    }

    /// Deletes a recording for good: row, transcript, parts, and every file
    /// it owns. `keepRaw` leaves the raw files (its own and its parts') so
    /// they can be imported again. A raw sync folder left empty is removed.
    public func deleteRecording(id: String, keepRaw: Bool = false) throws {
        let found = try db.write { db -> (Recording, [String])? in
            guard let r = try Recording.fetchOne(db, key: id) else { return nil }
            let parts = try String.fetchAll(db, sql: "SELECT rawPath FROM recordingPart WHERE recordingId = ?", arguments: [id])
            _ = try r.delete(db)
            return (r, parts)
        }
        guard let (r, parts) = found else { return }
        removeFiles(of: r, partRawPaths: parts, keepRaw: keepRaw)
    }

    /// Library list: newest first, excluding Recently Deleted.
    public func recordings(limit: Int? = nil) throws -> [Recording] {
        try db.read { db in
            var q = Recording.filter(Column("deletedAt") == nil).order(Column("recordedAt").desc)
            if let limit { q = q.limit(limit) }
            return try q.fetchAll(db)
        }
    }

    /// Every recording, Recently Deleted included, oldest first.
    public func allRecordings() throws -> [Recording] {
        try db.read { try Recording.order(Column("recordedAt")).fetchAll($0) }
    }

    /// Every recording of one sync, Recently Deleted included, by device file ID.
    public func recordings(syncId: String) throws -> [Recording] {
        try db.read { try Recording.filter(Column("syncId") == syncId).order(Column("deviceFileId")).fetchAll($0) }
    }

    public func rename(recordingId: String, title: String?) throws {
        try db.write { db in
            let t = title?.trimmingCharacters(in: .whitespacesAndNewlines)
            try db.execute(sql: "UPDATE recording SET title = ? WHERE id = ?", arguments: [t?.isEmpty == false ? t : nil, recordingId])
        }
    }

    // MARK: Recently Deleted (30 days)

    public func moveToTrash(recordingId: String, at date: Date = Date()) throws {
        try db.write { try $0.execute(sql: "UPDATE recording SET deletedAt = ? WHERE id = ?", arguments: [date, recordingId]) }
    }

    public func restore(recordingId: String) throws {
        try db.write { try $0.execute(sql: "UPDATE recording SET deletedAt = NULL WHERE id = ?", arguments: [recordingId]) }
    }

    public func trash() throws -> [Recording] {
        try db.read { try Recording.filter(Column("deletedAt") != nil).order(Column("deletedAt").desc).fetchAll($0) }
    }

    /// Full delete: removes recordings deleted before `cutoff` with their
    /// transcripts and every file they own (audio, `.opus`, raw or capture
    /// file, deleted audio). Returns the removed rows.
    @discardableResult
    public func purgeTrash(deletedBefore cutoff: Date) throws -> [Recording] {
        let removed = try db.write { db in
            let rows = try Recording.filter(Column("deletedAt") != nil && Column("deletedAt") < cutoff).fetchAll(db)
            return try rows.map { r in
                let parts = try String.fetchAll(db, sql: "SELECT rawPath FROM recordingPart WHERE recordingId = ?", arguments: [r.id])
                _ = try r.delete(db)
                return (r, parts)
            }
        }
        // After the commit: a leftover raw file would otherwise be imported again by crash recovery.
        for (r, parts) in removed { removeFiles(of: r, partRawPaths: parts) }
        return removed.map(\.0)
    }

    /// Empty Recently Deleted: every deleted recording and all deleted audio go now.
    public func emptyRecentlyDeleted(at date: Date = Date()) throws {
        try purgeTrash(deletedBefore: .distantFuture)
        try purgeAudio(deletedBefore: .distantFuture, at: date)
    }

    private func removeFiles(of r: Recording, partRawPaths: [String], keepRaw: Bool = false) {
        let fm = FileManager.default
        var urls = [r.audioPath, r.opusPath].compactMap { $0 }.map(paths.absolute)
        let raws = keepRaw || r.rawDeletedAt != nil ? [] : ([r.rawPath] + partRawPaths).map(paths.absolute)
        urls += raws
        urls.append(paths.trashedAudioDirectory(recordingID: r.id))
        for url in urls where fm.fileExists(atPath: url.path) { try? fm.removeItem(at: url) }
        for dir in Set(raws.map { $0.deletingLastPathComponent() }) where dir.path.hasPrefix(paths.raw.path + "/") {
            if let left = try? fm.contentsOfDirectory(atPath: dir.path), left.allSatisfy({ $0 == ".DS_Store" }) {
                try? fm.removeItem(at: dir)
            }
        }
    }

    // MARK: Delete audio, keep transcript

    /// Moves the audio (M4A and `.opus`) of each recording to `trash/audio/<id>/`
    /// and sets `audioDeletedAt`. The row, segments and search are untouched.
    /// Throws before moving anything unless every recording has a finished
    /// transcript. Recordings whose audio is already deleted are skipped.
    public func deleteAudio(recordingIds: [String], at date: Date = Date()) throws {
        let rows = try db.read { db in
            try recordingIds.map { id in
                guard let r = try Recording.fetchOne(db, key: id) else { throw AudioRetentionError.recordingNotFound(id) }
                guard r.transcriptState == .done else { throw AudioRetentionError.transcriptNotReady(id) }
                return r
            }
        }
        let fm = FileManager.default
        for r in rows where !r.isTranscriptOnly {
            let dir = paths.trashedAudioDirectory(recordingID: r.id)
            var moved: [(from: URL, to: URL)] = []
            do {
                for rel in [r.audioPath, r.opusPath].compactMap({ $0 }) {
                    let from = paths.absolute(rel)
                    guard fm.fileExists(atPath: from.path) else { continue }
                    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                    let to = dir.appendingPathComponent(from.lastPathComponent)
                    if fm.fileExists(atPath: to.path) { try fm.removeItem(at: to) }
                    try fm.moveItem(at: from, to: to)
                    moved.append((from, to))
                }
                try db.write { db in
                    try db.execute(sql: "UPDATE recording SET audioDeletedAt = ? WHERE id = ?", arguments: [date, r.id])
                    // A queued "Transcribe again" would find no audio.
                    try db.execute(sql: "DELETE FROM transcriptionJob WHERE recordingId = ?", arguments: [r.id])
                }
            } catch {
                for m in moved.reversed() { try? fm.moveItem(at: m.to, to: m.from) }
                throw error
            }
        }
    }

    /// Puts deleted audio back where it was and clears `audioDeletedAt`.
    public func restoreAudio(recordingId: String) throws {
        guard let r = try recording(id: recordingId) else { throw AudioRetentionError.recordingNotFound(recordingId) }
        if r.audioPurgedAt != nil { throw AudioRetentionError.audioPurged(recordingId) }
        guard r.audioDeletedAt != nil else { throw AudioRetentionError.audioNotDeleted(recordingId) }
        let fm = FileManager.default
        let dir = paths.trashedAudioDirectory(recordingID: r.id)
        var moved: [(from: URL, to: URL)] = []
        do {
            for rel in [r.audioPath, r.opusPath].compactMap({ $0 }) {
                let to = paths.absolute(rel)
                let from = dir.appendingPathComponent(to.lastPathComponent)
                guard fm.fileExists(atPath: from.path) else { continue }
                try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: from, to: to)
                moved.append((from, to))
            }
            try db.write { try $0.execute(sql: "UPDATE recording SET audioDeletedAt = NULL WHERE id = ?", arguments: [r.id]) }
        } catch {
            for m in moved.reversed() { try? fm.moveItem(at: m.to, to: m.from) }
            throw error
        }
        try? fm.removeItem(at: dir)
    }

    /// Recently Deleted, audio section: recordings whose audio is deleted but
    /// not yet purged, most recent first. Recordings that are themselves in
    /// Recently Deleted are listed by `trash()` only.
    public func deletedAudio() throws -> [Recording] {
        try db.read {
            try Recording
                .filter(Column("audioDeletedAt") != nil && Column("audioPurgedAt") == nil && Column("deletedAt") == nil)
                .order(Column("audioDeletedAt").desc)
                .fetchAll($0)
        }
    }

    /// Removes deleted audio older than `cutoff` for good and sets
    /// `audioPurgedAt`. The rows and their transcripts stay. Returns the rows.
    @discardableResult
    public func purgeAudio(deletedBefore cutoff: Date, at date: Date = Date()) throws -> [Recording] {
        let rows = try db.read {
            try Recording
                .filter(Column("audioDeletedAt") != nil && Column("audioDeletedAt") < cutoff && Column("audioPurgedAt") == nil)
                .fetchAll($0)
        }
        let fm = FileManager.default
        var purged: [Recording] = []
        for var r in rows {
            let dir = paths.trashedAudioDirectory(recordingID: r.id)
            if fm.fileExists(atPath: dir.path) { try fm.removeItem(at: dir) }
            r.audioPurgedAt = date
            r.audioPath = nil
            r.opusPath = nil
            try db.write { db in
                try db.execute(sql: "UPDATE recording SET audioPurgedAt = ?, audioPath = NULL, opusPath = NULL WHERE id = ?",
                               arguments: [date, r.id])
            }
            purged.append(r)
        }
        return purged
    }

    // MARK: Raw cleanup

    /// Verified recordings whose raw bytes are older than `cutoff` and still on disk.
    /// Any source: Fieldy raw bytes, an import copy left by an interrupted import,
    /// a microphone capture file.
    public func rawCleanupCandidates(verifiedBefore cutoff: Date) throws -> [Recording] {
        try db.read {
            try Recording
                .filter(Column("verifiedAt") != nil && Column("verifiedAt") < cutoff && Column("rawDeletedAt") == nil)
                .filter(Column("audioState") == AudioState.ok)
                .fetchAll($0)
        }
    }

    public func markRawDeleted(recordingId: String, at date: Date = Date()) throws {
        try db.write { try $0.execute(sql: "UPDATE recording SET rawDeletedAt = ? WHERE id = ?", arguments: [date, recordingId]) }
    }

    // MARK: Segments and search

    public func segments(recordingId: String) throws -> [Segment] {
        try db.read { try Segment.filter(Column("recordingId") == recordingId).order(Column("position")).fetchAll($0) }
    }

    /// Searches transcripts as the user types. The words are matched as a
    /// phrase, the last word as a prefix ("powell riv" finds "Powell River").
    /// Returns one hit per recording, newest recording first.
    public func search(_ text: String, limit: Int = 200) throws -> [SearchHit] {
        guard let pattern = Self.phrasePrefixPattern(text) else { return [] }
        return try db.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT segment.*, highlight(segment_fts, 0, ?, ?) AS highlighted
                FROM segment_fts
                JOIN segment ON segment.id = segment_fts.rowid
                JOIN recording ON recording.id = segment.recordingId
                WHERE segment_fts MATCH ? AND recording.deletedAt IS NULL
                ORDER BY recording.recordedAt DESC, segment.position ASC
                LIMIT ?
                """, arguments: [SearchHit.markStart, SearchHit.markEnd, pattern, limit])
            var seen = Set<String>()
            var hits: [SearchHit] = []
            for row in rows {
                let seg = try Segment(row: row)
                guard seen.insert(seg.recordingId).inserted,
                      let rec = try Recording.fetchOne(db, key: seg.recordingId) else { continue }
                hits.append(SearchHit(recording: rec, segment: seg, highlighted: row["highlighted"]))
            }
            return hits
        }
    }

    /// `"tok1 tok2 tok3" *` with tokens stripped of FTS syntax. Nil when empty.
    static func phrasePrefixPattern(_ text: String) -> String? {
        let tokens = text
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return nil }
        return "\"\(tokens.joined(separator: " "))\" *"
    }

    // MARK: Transcription queue

    /// Queues a recording. If it already has a transcript, the old one stays until the new one succeeds.
    /// Throws `AudioRetentionError.audioDeleted` for a transcript-only recording.
    public func enqueueTranscription(recordingId: String, model: String, at date: Date = Date()) throws {
        try db.write { db in
            let audioGone = try Bool.fetchOne(db, sql: """
                SELECT audioDeletedAt IS NOT NULL OR audioPurgedAt IS NOT NULL FROM recording WHERE id = ?
                """, arguments: [recordingId]) ?? false
            if audioGone { throw AudioRetentionError.audioDeleted(recordingId) }
            try TranscriptionJob(recordingId: recordingId, model: model, enqueuedAt: date).upsert(db)
            try db.execute(sql: """
                UPDATE recording SET transcriptState = 'waiting', transcriptError = NULL
                WHERE id = ? AND transcriptState != 'done'
                """, arguments: [recordingId])
        }
    }

    /// Oldest recording first.
    public func nextWaitingJob() throws -> TranscriptionJob? {
        try db.read { db in
            try TranscriptionJob.fetchOne(db, sql: """
                SELECT transcriptionJob.* FROM transcriptionJob
                JOIN recording ON recording.id = transcriptionJob.recordingId
                WHERE transcriptionJob.state = 'waiting' AND recording.deletedAt IS NULL
                ORDER BY recording.recordedAt ASC, transcriptionJob.enqueuedAt ASC
                LIMIT 1
                """)
        }
    }

    public func jobs() throws -> [TranscriptionJob] {
        try db.read { try TranscriptionJob.order(Column("enqueuedAt")).fetchAll($0) }
    }

    public func markTranscribing(recordingId: String) throws {
        try db.write { db in
            try db.execute(sql: "UPDATE transcriptionJob SET state = 'running', attempts = attempts + 1 WHERE recordingId = ?",
                           arguments: [recordingId])
            try db.execute(sql: "UPDATE recording SET transcriptState = 'transcribing' WHERE id = ?", arguments: [recordingId])
        }
    }

    /// Replaces the transcript atomically and removes the job. With
    /// `jobEnqueuedAt`, a job queued again since (the audio grew while it was
    /// transcribed) stays queued.
    public func completeTranscription(recordingId: String, segments: [Segment], model: String, at date: Date = Date(),
                                      jobEnqueuedAt: Date? = nil) throws {
        try db.write { db in
            try Segment.filter(Column("recordingId") == recordingId).deleteAll(db)
            for (i, var s) in segments.enumerated() {
                s.id = nil
                s.recordingId = recordingId
                s.position = i
                try s.insert(db)
            }
            try db.execute(sql: """
                UPDATE recording SET transcriptState = 'done', transcriptError = NULL, transcriptModel = ?,
                    transcribedAt = ?, noSpeech = ? WHERE id = ?
                """, arguments: [model, date, segments.isEmpty, recordingId])
            try db.execute(sql: "DELETE FROM transcriptionJob WHERE recordingId = ? AND (? IS NULL OR enqueuedAt = ?)",
                           arguments: [recordingId, jobEnqueuedAt, jobEnqueuedAt])
        }
    }

    /// Marks the job failed. A recording that already had a transcript keeps it.
    /// `jobEnqueuedAt` as for `completeTranscription`.
    public func failTranscription(recordingId: String, error: String, jobEnqueuedAt: Date? = nil) throws {
        try db.write { db in
            try db.execute(sql: "UPDATE transcriptionJob SET state = 'failed', lastError = ? WHERE recordingId = ? AND (? IS NULL OR enqueuedAt = ?)",
                           arguments: [error, recordingId, jobEnqueuedAt, jobEnqueuedAt])
            let hadTranscript = try Bool.fetchOne(db, sql: "SELECT transcribedAt IS NOT NULL FROM recording WHERE id = ?",
                                                  arguments: [recordingId]) ?? false
            try db.execute(sql: "UPDATE recording SET transcriptState = ?, transcriptError = ? WHERE id = ?",
                           arguments: [hadTranscript ? TranscriptState.done : TranscriptState.failed, error, recordingId])
        }
    }

    /// "Try again": failed job back to waiting.
    public func retryTranscription(recordingId: String) throws {
        try db.write { db in
            try db.execute(sql: "UPDATE transcriptionJob SET state = 'waiting' WHERE recordingId = ? AND state = 'failed'",
                           arguments: [recordingId])
            try db.execute(sql: """
                UPDATE recording SET transcriptState = 'waiting', transcriptError = NULL
                WHERE id = ? AND transcriptState = 'failed'
                """, arguments: [recordingId])
        }
    }

    /// On launch: jobs left running by a quit or crash go back to waiting.
    @discardableResult
    public func resetInterruptedTranscriptions() throws -> Int {
        try db.write { db in
            try db.execute(sql: "UPDATE transcriptionJob SET state = 'waiting' WHERE state = 'running'")
            let n = db.changesCount
            try db.execute(sql: """
                UPDATE recording SET transcriptState = CASE WHEN transcribedAt IS NULL THEN 'waiting' ELSE 'done' END
                WHERE transcriptState = 'transcribing'
                """)
            return n
        }
    }

    // MARK: Sync history

    public func insert(_ entry: SyncHistoryEntry) throws -> SyncHistoryEntry {
        try db.write { db in
            var e = entry
            try e.insert(db)
            return e
        }
    }

    public func update(_ entry: SyncHistoryEntry) throws {
        try db.write { try entry.update($0) }
    }

    /// Newest first.
    public func syncHistory(limit: Int = 100) throws -> [SyncHistoryEntry] {
        try db.read { try SyncHistoryEntry.order(Column("startedAt").desc).limit(limit).fetchAll($0) }
    }

    public func lastSuccessfulSync() throws -> SyncHistoryEntry? {
        try db.read {
            try SyncHistoryEntry.filter([SyncResult.success, .nothingNew].contains(Column("result")))
                .order(Column("startedAt").desc).fetchOne($0)
        }
    }

    // MARK: Settings

    public func setting(_ key: String) throws -> String? {
        try db.read { try String.fetchOne($0, sql: "SELECT value FROM setting WHERE key = ?", arguments: [key]) }
    }

    public func setSetting(_ key: String, _ value: String?) throws {
        try db.write { db in
            if let value {
                try db.execute(sql: "INSERT INTO setting(key, value) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                               arguments: [key, value])
            } else {
                try db.execute(sql: "DELETE FROM setting WHERE key = ?", arguments: [key])
            }
        }
    }

    public func setting<T: Decodable>(_ key: String, as type: T.Type) throws -> T? {
        guard let s = try setting(key) else { return nil }
        return try JSONDecoder().decode(T.self, from: Data(s.utf8))
    }

    public func setSetting<T: Encodable>(_ key: String, json value: T) throws {
        try setSetting(key, String(decoding: try JSONEncoder().encode(value), as: UTF8.self))
    }
}

/// Why a Delete Audio / Restore Audio / queue request was refused.
public enum AudioRetentionError: Error, Sendable, Equatable, CustomStringConvertible {
    case recordingNotFound(String)
    /// Waiting, transcribing, failed or never transcribed: audio is the only copy of the words.
    case transcriptNotReady(String)
    /// Restore asked for audio that is not in Recently Deleted.
    case audioNotDeleted(String)
    /// The deleted audio was already removed for good.
    case audioPurged(String)
    /// Transcript only: there is no audio to transcribe.
    case audioDeleted(String)

    public var description: String {
        switch self {
        case .recordingNotFound(let id): "recording \(id) not found"
        case .transcriptNotReady: "Available when the transcript is ready"
        case .audioNotDeleted(let id): "audio of \(id) is not in Recently Deleted"
        case .audioPurged(let id): "audio of \(id) was permanently deleted"
        case .audioDeleted(let id): "audio of \(id) was deleted"
        }
    }
}

/// Well-known setting keys.
public enum SettingKey {
    public static let deviceIdentifier = "device.identifier"
    public static let deviceName = "device.name"
    public static let lastKnownDevice = "device.lastKnown"
    public static let transcriptionModel = "transcription.model"
}
