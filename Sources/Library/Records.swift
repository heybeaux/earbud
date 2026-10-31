import Foundation
import GRDB

/// Whether a recording's audio could be decoded.
public enum AudioState: String, Codable, Sendable, DatabaseValueConvertible {
    /// Complete file, decoded and verified.
    case ok
    /// Recovered from a `.part` file after an interrupted sync or crash.
    case incomplete
    /// "Couldn't read this recording": the raw file is kept.
    case unreadable
}

/// Transcript state shown in the library.
public enum TranscriptState: String, Codable, Sendable, DatabaseValueConvertible {
    case none, waiting, transcribing, done, failed
}

/// Where a recording came from.
public enum RecordingSource: String, Codable, Sendable, CaseIterable, DatabaseValueConvertible {
    /// Synced from the Fieldy. Every v1 recording.
    case fieldy
    /// An audio file the user dropped or chose with Import Audio.
    case imported
    /// Recorded live from a Mac microphone.
    case microphone
}

public struct Recording: Codable, Sendable, Identifiable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "recording"

    public var id: String
    /// UTC instant; shown in local time.
    public var recordedAt: Date
    /// The header had no valid time; `recordedAt` is the sync time.
    public var timeUnknown: Bool
    public var durationSeconds: Double
    public var frameCount: Int
    public var title: String?
    public var audioState: AudioState
    /// Paths relative to the library root.
    public var rawPath: String
    public var opusPath: String?
    public var audioPath: String?
    public var syncId: String?
    public var deviceFileId: Int?
    public var deviceRecordingId: Int?
    /// Set once the decoded audio was verified; raw cleanup counts from here.
    public var verifiedAt: Date?
    public var rawDeletedAt: Date?
    public var createdAt: Date
    /// In Recently Deleted since this time.
    public var deletedAt: Date?
    public var transcriptState: TranscriptState
    public var transcriptError: String?
    public var transcriptModel: String?
    public var transcribedAt: Date?
    /// Transcribed and nothing was said: show "No speech detected".
    public var noSpeech: Bool
    public var source: RecordingSource
    /// Original file name for imports, device name for microphone recordings; nil for Fieldy.
    public var sourceName: String?
    /// SHA-256 (hex) of an imported file, kept after the copy is gone for duplicate checks.
    public var contentHash: String?
    /// Audio (M4A and `.opus`) in Recently Deleted since this time; the transcript stays.
    public var audioDeletedAt: Date?
    /// Deleted audio files were removed for good; the recording is transcript only.
    public var audioPurgedAt: Date?
    /// `recordedAt` came from the file's creation date, not embedded metadata
    /// (design.md "Recording time"); the detail view says "Time taken from the file".
    public var timeFromFileDate: Bool

    public init(id: String = UUID().uuidString, recordedAt: Date, timeUnknown: Bool = false, durationSeconds: Double,
                frameCount: Int, title: String? = nil, audioState: AudioState = .ok, rawPath: String,
                opusPath: String? = nil, audioPath: String? = nil, syncId: String? = nil, deviceFileId: Int? = nil,
                deviceRecordingId: Int? = nil, verifiedAt: Date? = nil, rawDeletedAt: Date? = nil,
                createdAt: Date = Date(), deletedAt: Date? = nil, transcriptState: TranscriptState = .none,
                transcriptError: String? = nil, transcriptModel: String? = nil, transcribedAt: Date? = nil,
                noSpeech: Bool = false, source: RecordingSource = .fieldy, sourceName: String? = nil,
                contentHash: String? = nil, audioDeletedAt: Date? = nil, audioPurgedAt: Date? = nil,
                timeFromFileDate: Bool = false) {
        self.id = id
        self.recordedAt = recordedAt
        self.timeUnknown = timeUnknown
        self.durationSeconds = durationSeconds
        self.frameCount = frameCount
        self.title = title
        self.audioState = audioState
        self.rawPath = rawPath
        self.opusPath = opusPath
        self.audioPath = audioPath
        self.syncId = syncId
        self.deviceFileId = deviceFileId
        self.deviceRecordingId = deviceRecordingId
        self.verifiedAt = verifiedAt
        self.rawDeletedAt = rawDeletedAt
        self.createdAt = createdAt
        self.deletedAt = deletedAt
        self.transcriptState = transcriptState
        self.transcriptError = transcriptError
        self.transcriptModel = transcriptModel
        self.transcribedAt = transcribedAt
        self.noSpeech = noSpeech
        self.source = source
        self.sourceName = sourceName
        self.contentHash = contentHash
        self.audioDeletedAt = audioDeletedAt
        self.audioPurgedAt = audioPurgedAt
        self.timeFromFileDate = timeFromFileDate
    }

    /// The audio was deleted (in Recently Deleted or purged); only the transcript is left.
    public var isTranscriptOnly: Bool { audioDeletedAt != nil || audioPurgedAt != nil }
}

public struct Segment: Codable, Sendable, Equatable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "segment"

    public var id: Int64?
    public var recordingId: String
    public var position: Int
    public var start: Double
    public var end: Double
    public var text: String

    public init(id: Int64? = nil, recordingId: String, position: Int, start: Double, end: Double, text: String) {
        self.id = id
        self.recordingId = recordingId
        self.position = position
        self.start = start
        self.end = end
        self.text = text
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public enum SyncResult: String, Codable, Sendable, DatabaseValueConvertible {
    case success
    case nothingNew
    /// Connection lost or app quit mid-sync; partial data kept.
    case interrupted
    case failed
}

public struct SyncHistoryEntry: Codable, Sendable, Equatable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "syncHistory"

    public var id: Int64?
    public var syncId: String
    public var startedAt: Date
    public var finishedAt: Date?
    public var result: SyncResult
    public var recordingCount: Int
    public var totalSeconds: Double
    public var bytesReceived: Int
    /// Files the device reported as damaged and that were dropped after a retry.
    public var droppedFiles: Int
    public var message: String?
    public var deviceName: String?

    public init(id: Int64? = nil, syncId: String, startedAt: Date, finishedAt: Date? = nil, result: SyncResult,
                recordingCount: Int = 0, totalSeconds: Double = 0, bytesReceived: Int = 0, droppedFiles: Int = 0,
                message: String? = nil, deviceName: String? = nil) {
        self.id = id
        self.syncId = syncId
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.result = result
        self.recordingCount = recordingCount
        self.totalSeconds = totalSeconds
        self.bytesReceived = bytesReceived
        self.droppedFiles = droppedFiles
        self.message = message
        self.deviceName = deviceName
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public enum JobState: String, Codable, Sendable, DatabaseValueConvertible {
    case waiting, running, failed
}

/// A pending transcription. Kept in SQLite so the queue survives relaunch.
public struct TranscriptionJob: Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "transcriptionJob"

    public var recordingId: String
    public var model: String
    public var state: JobState
    public var enqueuedAt: Date
    public var attempts: Int
    public var lastError: String?

    public init(recordingId: String, model: String, state: JobState = .waiting, enqueuedAt: Date = Date(),
                attempts: Int = 0, lastError: String? = nil) {
        self.recordingId = recordingId
        self.model = model
        self.state = state
        self.enqueuedAt = enqueuedAt
        self.attempts = attempts
        self.lastError = lastError
    }
}

/// A search result: one recording with its best-matching segment.
public struct SearchHit: Sendable, Equatable {
    public var recording: Recording
    public var segment: Segment
    /// Segment text with matches wrapped in `SearchHit.markStart` / `markEnd`.
    public var highlighted: String

    public static let markStart = "«"
    public static let markEnd = "»"
}
