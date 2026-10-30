import Foundation

// App-side value types. They mirror EarBudKit's public records (`Recording`, `Segment`,
// `SyncHistoryEntry`, `SyncProgress`, `ConnectionState`) closely enough that the later
// integration batch is a thin adapter, but they carry only what the UI needs.

/// One recording in the library.
struct RecordingItem: Identifiable, Equatable, Sendable {
    var id: String
    /// When the recording started (EarBudKit `Recording.recordedAt`).
    var recordedAt: Date
    var duration: TimeInterval
    /// `nil` until the user gives it a title. Untitled recordings show their start time.
    var title: String?
    var audio: AudioState
    var transcript: TranscriptStatus
    /// First line of the transcript, for the list.
    var preview: String?
    /// When it arrived on this Mac (EarBudKit `Recording.createdAt`).
    var copiedAt: Date?
    var transcribedAt: Date?
    /// In Recently Deleted since this time.
    var deletedAt: Date?
    /// Seeds the drawn waveform so each recording keeps the same shape.
    var waveformSeed: Int

    var isUntitled: Bool { title?.isEmpty ?? true }
}

/// Whether a recording's audio can be played (EarBudKit `AudioState`).
enum AudioState: Equatable, Sendable {
    case ok
    /// Recovered after an interrupted sync: plays up to where it stopped.
    case incomplete
    /// Couldn't be read. The raw file is kept.
    case unreadable
}

/// Transcript progress for one recording (EarBudKit `TranscriptState` plus queue details).
enum TranscriptStatus: Equatable, Sendable {
    /// Not queued, for example while the speech model is missing.
    case none
    /// Queued. `position` 1 means next in line.
    case waiting(position: Int)
    case transcribing(progress: Double, secondsLeft: TimeInterval?)
    case done
    /// Transcribed and nothing was said.
    case noSpeech
    case failed(message: String)

    var isFinished: Bool {
        switch self {
        case .done, .noSpeech: true
        default: false
        }
    }
}

/// One timestamped line of a transcript (EarBudKit `Segment`).
struct TranscriptSegment: Identifiable, Equatable, Sendable {
    var id: Int { position }
    var position: Int
    var start: TimeInterval
    var end: TimeInterval
    var text: String
}

/// A recording that matches a search.
struct SearchResult: Identifiable, Equatable, Sendable {
    var id: String { recording.id }
    var recording: RecordingItem
    /// The first matching transcript line.
    var snippet: String
    /// Times the phrase appears in the transcript and title.
    var matchCount: Int
}

/// One past sync (EarBudKit `SyncHistoryEntry`).
struct SyncHistoryItem: Identifiable, Equatable, Sendable {
    enum Result: Equatable, Sendable {
        case success, nothingNew, interrupted, failed
    }

    var id: String
    var startedAt: Date
    var finishedAt: Date?
    var result: Result
    var recordingCount: Int
    var totalSeconds: TimeInterval
    var bytes: Int
    var message: String?
}

// MARK: - Device

/// How EarBud can currently reach the Fieldy (EarBudKit `ConnectionState`).
enum DeviceConnection: Equatable, Sendable {
    case connected
    case connecting
    case searching
    case notNearby
    case bluetoothOff
    case pairedElsewhere
    case notSetUp
}

/// Recording mode on the device (EarBudKit `RecordingMode`).
enum RecordingMode: String, CaseIterable, Equatable, Sendable {
    case manual, automatic
}

/// Everything the device panel, sidebar card and menu show about the Fieldy.
struct DeviceSnapshot: Equatable, Sendable {
    var name: String
    var model: String
    var firmware: String
    var connection: DeviceConnection
    var batteryPercent: Int?
    /// Recordings stored on the Fieldy that have not been copied yet.
    var waitingCount: Int
    var waitingBytes: Int
    var lastSynced: Date?
    var pairedAt: Date?
    /// When the values above were last read from the device.
    var checkedAt: Date?
    var recordingMode: RecordingMode
    var lightOn: Bool
    var muted: Bool
    /// Set while the Fieldy is recording.
    var recordingStartedAt: Date?

    var isRecording: Bool { recordingStartedAt != nil }
    /// Firmware EarBud was tested with; other versions show a notice.
    static let testedFirmware = "3.3.5"
}

/// A device setting the user can change; each change is read back from the device.
enum DeviceSetting: Hashable, Sendable {
    case recordingMode, light, mute
}

enum DeviceError: Error, Equatable, Sendable {
    /// The Fieldy refused to record because its microphone is muted.
    case muted
    case notNearby
    /// The device did not confirm the change.
    case notConfirmed
}

// MARK: - Sync

/// Live progress of a sync (EarBudKit `SyncProgress`).
struct SyncProgressSnapshot: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case connecting, checking, copying, finishing
    }

    var phase: Phase
    /// 1-based index of the file being copied.
    var fileIndex: Int
    var fileCount: Int
    var bytesReceived: Int
    var bytesExpected: Int
    /// Start time of the recording being copied, once its header has arrived.
    var currentRecordingStart: Date?
    var currentFileFraction: Double

    /// 0...1 by bytes.
    var fraction: Double {
        guard bytesExpected > 0 else { return phase == .finishing ? 1 : 0 }
        return min(1, Double(bytesReceived) / Double(bytesExpected))
    }
}

/// How a sync ended.
enum SyncOutcome: Equatable, Sendable {
    case copied(count: Int)
    case nothingNew
    /// Connection lost part way. `saved` recordings are safe on the Mac.
    case interrupted(saved: Int)
    case failed(message: String)
}

enum SyncEvent: Equatable, Sendable {
    case progress(SyncProgressSnapshot)
    case finished(SyncOutcome)
}

// MARK: - Speech models

struct SpeechModel: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var detail: String
    var sizeBytes: Int
    var installed: Bool
    var recommended: Bool
}
