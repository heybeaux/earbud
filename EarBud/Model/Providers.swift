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

/// Why a Delete Audio / Restore Audio request was refused (EarBudKit `AudioRetentionError`).
enum AudioActionError: Error, Equatable, Sendable {
    /// Waiting, transcribing, failed or never transcribed: audio is the only copy of the words.
    case transcriptNotReady
    /// Restore asked for audio that is not in Recently Deleted.
    case audioNotDeleted
    /// The deleted audio was already removed for good.
    case audioPurged
}

/// Storage space used by the library, for Settings > Storage (mockup 27).
struct StorageSnapshot: Equatable, Sendable {
    var recordingCount: Int
    var audioBytes: Int
    var transcriptBytes: Int
    var recentlyDeletedBytes: Int
}

/// Recordings, transcripts, search, trash and sync history.
protocol LibraryProviding: Sendable {
    /// Recordings not in Recently Deleted, newest first.
    func recordings() async throws -> [RecordingItem]
    func segments(for recordingID: String) async throws -> [TranscriptSegment]
    /// Recordings whose title or transcript contains `query`, newest first.
    func search(_ query: String) async throws -> [SearchResult]
    func recentlyDeleted() async throws -> [RecordingItem]
    /// Recordings whose audio is in Recently Deleted (but the recording itself is not), newest first.
    func recentlyDeletedAudio() async throws -> [RecordingItem]
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
    /// Moves audio to Recently Deleted, keeping the transcript. Throws `AudioActionError.transcriptNotReady`
    /// if any recording's transcript isn't done yet; nothing moves in that case.
    func deleteAudio(_ recordingIDs: [String]) async throws
    /// Puts deleted audio back and restores playback.
    func restoreAudio(_ recordingID: String) async throws
    /// Empties Recently Deleted: every deleted recording and all deleted audio go now.
    func emptyRecentlyDeleted() async throws
    /// Current space used by audio, transcripts and Recently Deleted.
    func storage() async throws -> StorageSnapshot
    /// Moves audio older than `days` to Recently Deleted for every finished-transcript recording. For the Storage setting and the daily cleanup pass.
    func cleanUpOldAudio(olderThanDays days: Int) async throws -> Int
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

/// Importing audio files and folders (EarBudKit `AudioImport.AudioImporter`).
/// The app asks for the file list first, then imports one file at a time so it can show progress.
protocol ImportProviding: Sendable {
    /// Every file `importFile` should be given: files as they are, folders searched recursively
    /// (hidden files and folders skipped).
    func files(in urls: [URL]) async -> [URL]
    /// Copies one file into the library, skips it as a duplicate, or rejects it with a reason.
    /// New recordings are queued for transcription; `LibraryProviding.transcribeWaiting()` runs them.
    func importFile(_ url: URL) async -> ImportReport
    /// Removes partial copies left by a quit during an earlier import. Call once at launch;
    /// `importFile` waits for it.
    @discardableResult
    func cleanupAfterLaunch() async -> Int
}

/// On-device speech models.
protocol SpeechModelProviding: Sendable {
    func models() async -> [SpeechModel]
    /// Downloads a model; yields 0...1 and ends when the model is installed.
    func download(_ modelID: String) async -> AsyncStream<Double>
}
