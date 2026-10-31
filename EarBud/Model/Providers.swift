import Foundation

// The seams between the UI and the engine. Batch 1 ships fixture implementations
// (`Fixture*`). The integration batch adds adapters over EarBudKit:
//   LibraryProviding     -> Library.LibraryStore (+ Transcriber.TranscriptionQueue events)
//   DeviceProviding      -> FieldyDevice.FieldyDevice
//   SyncProviding        -> SyncEngine.SyncEngine
//   SpeechModelProviding -> Transcriber (WhisperKit model download)

/// What changed in the library, so the UI can refresh.
enum LibraryChange: Equatable, Sendable {
    case recordings
    case recording(id: String)
    case history
}

/// Recordings, transcripts, search, trash and sync history.
protocol LibraryProviding: Sendable {
    /// Recordings not in Recently Deleted, newest first.
    func recordings() async throws -> [RecordingItem]
    func segments(for recordingID: String) async throws -> [TranscriptSegment]
    /// Recordings whose title or transcript contains `query`, newest first.
    func search(_ query: String) async throws -> [SearchResult]
    func recentlyDeleted() async throws -> [RecordingItem]
    func syncHistory() async throws -> [SyncHistoryItem]
    func rename(_ recordingID: String, to title: String?) async throws
    func moveToTrash(_ recordingID: String) async throws
    func restore(_ recordingID: String) async throws
    func retryTranscription(_ recordingID: String) async throws
    /// A playable audio file, or `nil` if there is none.
    func audioURL(for recordingID: String) async throws -> URL?
    /// The recording's files on disk, for Show in Finder.
    func fileURL(for recordingID: String) async throws -> URL?
    /// A stream of changes. Each call returns a new stream.
    func changes() async -> AsyncStream<LibraryChange>
    /// Transcribes every recording waiting for a transcript; returns when the queue is empty.
    func transcribeWaiting() async
}

extension LibraryProviding {
    func transcribeWaiting() async {}
}

/// The Fieldy: status and the settings it exposes.
protocol DeviceProviding: Sendable {
    func snapshot() async -> DeviceSnapshot
    /// Reads fresh values from the device.
    func refresh() async throws -> DeviceSnapshot
    /// Each setter writes the value, reads it back, and returns what the device reports.
    func setRecordingMode(_ mode: RecordingMode) async throws -> RecordingMode
    func setLight(_ on: Bool) async throws -> Bool
    func setMuted(_ muted: Bool) async throws -> Bool
    func buzz() async throws
    /// Starts a recording on the Fieldy. Throws `DeviceError.muted` if the microphone is muted.
    func startRecording() async throws -> Date
    func stopRecording() async throws
}

/// The Sync action.
protocol SyncProviding: Sendable {
    /// Starts a sync. The stream ends after `.finished`. Transcription carries on in the
    /// library afterwards and is reported through `LibraryProviding.changes()`.
    func startSync() async -> AsyncStream<SyncEvent>
}

/// On-device speech models.
protocol SpeechModelProviding: Sendable {
    func models() async -> [SpeechModel]
    /// Downloads a model; yields 0...1 and ends when the model is installed.
    func download(_ modelID: String) async -> AsyncStream<Double>
}
