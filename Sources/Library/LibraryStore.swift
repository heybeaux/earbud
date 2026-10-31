import Foundation
import GRDB

/// The EarBud library database (GRDB, SQLite WAL, FTS5 transcript search).
public final class LibraryStore: Sendable {
    public let paths: LibraryPaths
    public let db: DatabasePool

    public init(paths: LibraryPaths) throws {
        self.paths = paths
        try paths.createDirectories()
        var config = Configuration()
        config.foreignKeysEnabled = true
        db = try DatabasePool(path: paths.database.path, configuration: config)
        try Self.migrator.migrate(db)
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

    public func recording(rawPath: String) throws -> Recording? {
        try db.read { try Recording.filter(Column("rawPath") == rawPath).fetchOne($0) }
    }

    /// Raw paths already imported, for crash recovery.
    public func importedRawPaths() throws -> Set<String> {
        try db.read { Set(try String.fetchAll($0, sql: "SELECT rawPath FROM recording")) }
    }

    /// Library list: newest first, excluding Recently Deleted.
    public func recordings(limit: Int? = nil) throws -> [Recording] {
        try db.read { db in
            var q = Recording.filter(Column("deletedAt") == nil).order(Column("recordedAt").desc)
            if let limit { q = q.limit(limit) }
            return try q.fetchAll(db)
        }
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

    /// Removes rows deleted before `cutoff` and returns them so the caller can delete their files.
    public func purgeTrash(deletedBefore cutoff: Date) throws -> [Recording] {
        try db.write { db in
            let rows = try Recording.filter(Column("deletedAt") != nil && Column("deletedAt") < cutoff).fetchAll(db)
            for r in rows { _ = try r.delete(db) }
            return rows
        }
    }

    // MARK: Raw cleanup

    /// Verified recordings whose raw bytes are older than `cutoff` and still on disk.
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
    public func enqueueTranscription(recordingId: String, model: String, at date: Date = Date()) throws {
        try db.write { db in
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

    /// Replaces the transcript atomically and removes the job.
    public func completeTranscription(recordingId: String, segments: [Segment], model: String, at date: Date = Date()) throws {
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
            try db.execute(sql: "DELETE FROM transcriptionJob WHERE recordingId = ?", arguments: [recordingId])
        }
    }

    /// Marks the job failed. A recording that already had a transcript keeps it.
    public func failTranscription(recordingId: String, error: String) throws {
        try db.write { db in
            try db.execute(sql: "UPDATE transcriptionJob SET state = 'failed', lastError = ? WHERE recordingId = ?",
                           arguments: [error, recordingId])
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

/// Well-known setting keys.
public enum SettingKey {
    public static let deviceIdentifier = "device.identifier"
    public static let deviceName = "device.name"
    public static let lastKnownDevice = "device.lastKnown"
    public static let transcriptionModel = "transcription.model"
}
