import AudioCodec
import FieldyProtocol
import Foundation
import Library

/// Transcribes queued recordings one at a time, oldest first. Queue state
/// lives in the library database, so it resumes after relaunch.
public actor TranscriptionQueue {
    public enum Event: Sendable, Equatable {
        case started(recordingId: String)
        /// Fraction done (0-1), after each recognizer window.
        case progress(recordingId: String, fraction: Double)
        case finished(recordingId: String, segments: Int)
        case failed(recordingId: String, message: String)
    }

    public let library: LibraryStore
    private let recognizerFor: @Sendable (String) -> any SpeechRecognizer
    private var recognizers: [String: any SpeechRecognizer] = [:]
    private var observers: [UUID: AsyncStream<Event>.Continuation] = [:]
    private var running = false

    /// - Parameter recognizerFor: makes a recognizer for a model variant name.
    public init(library: LibraryStore, recognizerFor: @escaping @Sendable (String) -> any SpeechRecognizer) {
        self.library = library
        self.recognizerFor = recognizerFor
    }

    /// The production queue: WhisperKit models in the library's `models/` folder.
    public static func whisperKit(library: LibraryStore) -> TranscriptionQueue {
        let dir = library.paths.models
        return TranscriptionQueue(library: library) { variant in
            WhisperKitRecognizer(model: TranscriptionModel(variant: variant) ?? .default, modelsDirectory: dir)
        }
    }

    public func events() -> AsyncStream<Event> {
        let (stream, cont) = AsyncStream<Event>.makeStream()
        let id = UUID()
        observers[id] = cont
        cont.onTermination = { [weak self] _ in Task { await self?.dropObserver(id) } }
        return stream
    }

    private func dropObserver(_ id: UUID) { observers[id] = nil }
    private func emit(_ e: Event) { for c in observers.values { c.yield(e) } }

    /// Call on launch: jobs interrupted by a quit go back to waiting.
    public func resume() throws {
        try library.resetInterruptedTranscriptions()
    }

    /// "Transcribe again" with a model; the old transcript stays until this succeeds.
    public func transcribeAgain(recordingId: String, model: String) throws {
        try library.enqueueTranscription(recordingId: recordingId, model: model)
    }

    /// "Try again" after a failure.
    public func retry(recordingId: String) throws {
        try library.retryTranscription(recordingId: recordingId)
    }

    /// Processes waiting jobs until none are left. Returns how many ran.
    @discardableResult
    public func processAll() async throws -> Int {
        guard !running else { return 0 }
        running = true
        defer { running = false }
        var n = 0
        while let job = try library.nextWaitingJob() {
            try await process(job)
            n += 1
        }
        return n
    }

    private func process(_ job: TranscriptionJob) async throws {
        try library.markTranscribing(recordingId: job.recordingId)
        emit(.started(recordingId: job.recordingId))
        do {
            guard let rec = try library.recording(id: job.recordingId) else { return }
            let source = try Self.audioSource(rec, paths: library.paths)
            let recognizer = recognizers[job.model] ?? recognizerFor(job.model)
            recognizers[job.model] = recognizer
            let id = rec.id
            let raw = try await ChunkedTranscriber.transcribe(source, with: recognizer) { fraction in
                await self.emit(.progress(recordingId: id, fraction: fraction))
            }
            let kept = TranscriptFilter.clean(raw)
            let segments = kept.map { Segment(recordingId: rec.id, position: 0, start: $0.start, end: $0.end, text: $0.text) }
            try library.completeTranscription(recordingId: rec.id, segments: segments, model: job.model)
            emit(.finished(recordingId: rec.id, segments: segments.count))
        } catch {
            let message = "\(error)"
            try library.failTranscription(recordingId: job.recordingId, error: message)
            emit(.failed(recordingId: job.recordingId, message: message))
        }
    }

    /// 16 kHz mono audio: decoded from the original Opus frames when
    /// present (short Fieldy recordings, decoded whole), else read from the
    /// audio file a window at a time.
    static func audioSource(_ rec: Recording, paths: LibraryPaths) throws -> any AudioSampleSource {
        if let opus = rec.opusPath {
            let url = paths.absolute(opus)
            if FileManager.default.fileExists(atPath: url.path) {
                return InMemorySamples(try FieldyOpusDecoder.decode(frames: try Data(contentsOf: url)).floatSamples)
            }
        }
        if let audio = rec.audioPath {
            return try AudioSamples.open(paths.absolute(audio))
        }
        throw TranscriberError.audioMissing(rec.id)
    }
}
