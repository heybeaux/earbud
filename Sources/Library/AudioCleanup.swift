import Foundation
import GRDB

/// Space used by the library's audio, transcripts and Recently Deleted
/// (Settings > Storage, mockup 27).
public struct StorageUsage: Equatable, Sendable {
    public var recordingCount: Int
    public var audioBytes: Int
    public var transcriptBytes: Int
    public var recentlyDeletedBytes: Int

    public init(recordingCount: Int, audioBytes: Int, transcriptBytes: Int, recentlyDeletedBytes: Int) {
        self.recordingCount = recordingCount
        self.audioBytes = audioBytes
        self.transcriptBytes = transcriptBytes
        self.recentlyDeletedBytes = recentlyDeletedBytes
    }
}

/// Optional automatic cleanup: "Delete audio older than [30/90/365] days, keep
/// transcripts" (transcript-retention spec, "Optional automatic audio cleanup").
/// Runs at launch and once a day while the app is open.
public enum AudioCleanup {
    /// Transcribed recordings (source and audio state irrelevant) recorded
    /// more than `days` ago, whose audio is not already deleted.
    public static func candidates(store: LibraryStore, olderThanDays days: Int, now: Date = Date()) throws -> [Recording] {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        return try store.db.read { db in
            try Recording
                .filter(Column("transcriptState") == TranscriptState.done)
                .filter(Column("recordedAt") < cutoff)
                .filter(Column("deletedAt") == nil)
                .filter(Column("audioDeletedAt") == nil)
                .fetchAll(db)
        }
    }

    /// Moves every candidate's audio to Recently Deleted. Returns the recording
    /// IDs that were moved. A recording whose transcript turns out not to be
    /// done (a race with a retry) is skipped rather than failing the whole run.
    @discardableResult
    public static func run(store: LibraryStore, olderThanDays days: Int, now: Date = Date()) throws -> [String] {
        let ids = try candidates(store: store, olderThanDays: days, now: now).map(\.id)
        var moved: [String] = []
        for id in ids {
            do {
                try store.deleteAudio(recordingIds: [id], at: now)
                moved.append(id)
            } catch {
                continue
            }
        }
        return moved
    }

    /// Current space used by audio, transcripts and Recently Deleted (audio
    /// deleted-but-not-purged plus whole deleted recordings).
    public static func storage(store: LibraryStore) throws -> StorageUsage {
        let fm = FileManager.default
        func size(_ url: URL) -> Int {
            (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        }

        let live = try store.recordings()
        var audioBytes = 0
        for r in live where !r.isTranscriptOnly {
            for path in [r.audioPath, r.opusPath].compactMap({ $0 }) {
                audioBytes += size(store.paths.absolute(path))
            }
        }

        let transcriptBytes = try store.db.read { db -> Int in
            try Int.fetchOne(db, sql: """
                SELECT COALESCE(SUM(LENGTH(text)), 0) FROM segment
                JOIN recording ON recording.id = segment.recordingId
                WHERE recording.deletedAt IS NULL
                """) ?? 0
        }

        var recentlyDeletedBytes = 0
        for r in try store.trash() {
            for path in [r.audioPath, r.opusPath].compactMap({ $0 }) where r.audioDeletedAt == nil {
                recentlyDeletedBytes += size(store.paths.absolute(path))
            }
        }
        func directorySize(_ url: URL) -> Int {
            guard let e = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
            var total = 0
            for case let fileURL as URL in e { total += size(fileURL) }
            return total
        }
        recentlyDeletedBytes += directorySize(store.paths.trash.appendingPathComponent("audio", isDirectory: true))

        return StorageUsage(recordingCount: live.count, audioBytes: audioBytes, transcriptBytes: transcriptBytes,
                            recentlyDeletedBytes: recentlyDeletedBytes)
    }
}
