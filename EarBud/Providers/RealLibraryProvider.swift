import AudioCodec
import Foundation
import Library
import Transcriber

/// Adapts EarBudKit's `Library.LibraryStore` (SQLite + FTS5 at
/// `~/Library/Application Support/EarBud`) to `LibraryProviding`.
///
/// Also runs the transcription queue: library changes made by a sync (new
/// recordings queued for transcription) are followed up here so transcripts
/// appear without the UI having to know about `TranscriptionQueue`.
final class RealLibraryProvider: LibraryProviding, Sendable {
    let store: LibraryStore
    private let queue: TranscriptionQueue
    private let changeContinuations = ChangeBroadcaster()

    init(store: LibraryStore) {
        self.store = store
        self.queue = .whisperKit(library: store)
    }

    convenience init(paths: LibraryPaths = .default) throws {
        self.init(store: try LibraryStore(paths: paths))
    }

    /// Launch-time housekeeping: resume interrupted transcription jobs, then drain the queue.
    func resumeTranscriptionQueue() {
        Task.detached { [queue, changeContinuations] in
            try? await queue.resume()
            let events = await queue.events()
            Task {
                for await event in events {
                    switch event {
                    case .started(let id), .finished(let id, _), .failed(let id, _):
                        await changeContinuations.yield(.recording(id: id))
                    }
                }
            }
            _ = try? await queue.processAll()
        }
    }

    // MARK: LibraryProviding

    func recordings() async throws -> [RecordingItem] {
        try store.recordings().map(mapWithPreview)
    }

    func segments(for recordingID: String) async throws -> [TranscriptSegment] {
        try store.segments(recordingId: recordingID).map { TranscriptSegment(position: $0.position, start: $0.start, end: $0.end, text: $0.text) }
    }

    func search(_ query: String) async throws -> [SearchResult] {
        try store.search(query).map { hit in
            SearchResult(recording: Self.map(hit.recording), snippet: hit.highlighted, matchCount: Self.matchCount(hit.highlighted))
        }
    }

    func recentlyDeleted() async throws -> [RecordingItem] {
        try store.trash().map(mapWithPreview)
    }

    func syncHistory() async throws -> [SyncHistoryItem] {
        try store.syncHistory().map(Self.map)
    }

    func rename(_ recordingID: String, to title: String?) async throws {
        try store.rename(recordingId: recordingID, title: title)
    }

    func moveToTrash(_ recordingID: String) async throws {
        try store.moveToTrash(recordingId: recordingID)
        await changeContinuations.yield(.recordings)
    }

    func restore(_ recordingID: String) async throws {
        try store.restore(recordingId: recordingID)
        await changeContinuations.yield(.recordings)
    }

    func retryTranscription(_ recordingID: String) async throws {
        try await queue.retry(recordingId: recordingID)
        await changeContinuations.yield(.recording(id: recordingID))
        Task.detached { [queue] in _ = try? await queue.processAll() }
    }

    func audioURL(for recordingID: String) async throws -> URL? {
        guard let rec = try store.recording(id: recordingID), let path = rec.audioPath else { return nil }
        return store.paths.absolute(path)
    }

    func fileURL(for recordingID: String) async throws -> URL? {
        guard let rec = try store.recording(id: recordingID) else { return nil }
        if let audioPath = rec.audioPath { return store.paths.absolute(audioPath) }
        return store.paths.absolute(rec.rawPath)
    }

    func changes() async -> AsyncStream<LibraryChange> {
        await changeContinuations.makeStream()
    }

    // MARK: Mapping

    /// List rows show the opening of the transcript, so done recordings need their segments.
    private func mapWithPreview(_ rec: Recording) throws -> RecordingItem {
        guard rec.transcriptState == .done, !rec.noSpeech else { return Self.map(rec) }
        let text = try store.segments(recordingId: rec.id).prefix(3).map { $0.text.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
        return Self.map(rec, preview: text.isEmpty ? nil : text)
    }

    static func map(_ rec: Recording, preview: String? = nil) -> RecordingItem {
        RecordingItem(
            id: rec.id,
            recordedAt: rec.recordedAt,
            duration: rec.durationSeconds,
            title: rec.title,
            audio: map(rec.audioState),
            transcript: map(rec),
            preview: preview,
            copiedAt: rec.createdAt,
            transcribedAt: rec.transcribedAt,
            deletedAt: rec.deletedAt,
            waveformSeed: abs(rec.id.hashValue % 1000))
    }

    static func map(_ state: Library.AudioState) -> AudioState {
        switch state {
        case .ok: .ok
        case .incomplete: .incomplete
        case .unreadable: .unreadable
        }
    }

    static func map(_ rec: Recording) -> TranscriptStatus {
        switch rec.transcriptState {
        case .none: .none
        case .waiting: .waiting(position: 1)
        case .transcribing: .transcribing(progress: 0, secondsLeft: nil)
        case .done: rec.noSpeech ? .noSpeech : .done
        case .failed: .failed(message: rec.transcriptError ?? "Transcription failed")
        }
    }

    static func map(_ entry: SyncHistoryEntry) -> SyncHistoryItem {
        SyncHistoryItem(
            id: entry.syncId,
            startedAt: entry.startedAt,
            finishedAt: entry.finishedAt,
            result: map(entry.result),
            recordingCount: entry.recordingCount,
            totalSeconds: entry.totalSeconds,
            bytes: entry.bytesReceived,
            message: entry.message)
    }

    static func map(_ result: SyncResult) -> SyncHistoryItem.Result {
        switch result {
        case .success: .success
        case .nothingNew: .nothingNew
        case .interrupted: .interrupted
        case .failed: .failed
        }
    }

    private static func matchCount(_ highlighted: String) -> Int {
        highlighted.components(separatedBy: Library.SearchHit.markStart).count - 1
    }
}

/// A small actor to fan library changes out to any number of `AsyncStream` consumers,
/// since `LibraryProviding.changes()` can be called more than once (app + onboarding).
actor ChangeBroadcaster {
    private var continuations: [UUID: AsyncStream<LibraryChange>.Continuation] = [:]

    func makeStream() -> AsyncStream<LibraryChange> {
        let (stream, continuation) = AsyncStream<LibraryChange>.makeStream(bufferingPolicy: .bufferingNewest(8))
        let id = UUID()
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.remove(id) }
        }
        return stream
    }

    func yield(_ change: LibraryChange) {
        for c in continuations.values { c.yield(change) }
    }

    private func remove(_ id: UUID) {
        continuations[id] = nil
    }
}
