import AudioCodec
import Foundation
import Library
import Testing
@testable import Transcriber

@Suite("Transcript filter")
struct TranscriptFilterTests {
    @Test func dropsNoSpeechAndAnnotations() {
        let raw = [
            RecognizedSegment(start: 0, end: 2, text: " Hello there.", noSpeechProbability: 0.1),
            RecognizedSegment(start: 2, end: 4, text: " Thank you.", noSpeechProbability: 0.9),
            RecognizedSegment(start: 4, end: 6, text: "[BLANK_AUDIO]", noSpeechProbability: 0.2),
            RecognizedSegment(start: 6, end: 8, text: " (silence) ", noSpeechProbability: 0.2),
            RecognizedSegment(start: 8, end: 9, text: "<|startoftranscript|><|en|> Next bit.<|endoftext|>", noSpeechProbability: 0.3),
            RecognizedSegment(start: 9, end: 10, text: " ... ", noSpeechProbability: 0.3),
            RecognizedSegment(start: 10, end: 11, text: "Right at threshold", noSpeechProbability: 0.6),
        ]
        let kept = TranscriptFilter.clean(raw)
        #expect(kept.map(\.text) == ["Hello there.", "Next bit.", "Right at threshold"])
        #expect(kept.map(\.start) == [0, 8, 10])
    }

    @Test func emptyTranscriptText() {
        #expect(TranscriptFilter.plainText([]) == "No speech detected")
        let t = TranscriptFilter.plainText([TranscriptSegment(start: 135.4, end: 140, text: "Hi"), TranscriptSegment(start: 3725, end: 3726, text: "Bye")])
        #expect(t == "[02:15] Hi\n[1:02:05] Bye")
    }

    @Test func models() {
        #expect(TranscriptionModel.default == .accurate)
        #expect(TranscriptionModel.accurate.rawValue == "openai_whisper-small.en")
        #expect(TranscriptionModel.faster.rawValue == "openai_whisper-base.en")
        #expect(TranscriptionModel.accurate.displayName == "More accurate")
        #expect(TranscriptionModel.faster.displayName == "Faster")
    }

    @Test func modelNotInstalled() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        #expect(!WhisperKitRecognizer.isInstalled(.faster, in: dir))
        let r = WhisperKitRecognizer(model: .faster, modelsDirectory: dir)
        await #expect(throws: TranscriberError.self) { try await r.recognize(samples: [0]) }
    }
}

struct FakeRecognizer: SpeechRecognizer {
    var result: [RecognizedSegment]
    var fail: Bool = false
    let calls: Calls

    final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var _sampleCounts: [Int] = []
        func add(_ n: Int) { lock.lock(); _sampleCounts.append(n); lock.unlock() }
        var sampleCounts: [Int] { lock.lock(); defer { lock.unlock() }; return _sampleCounts }
    }

    func recognize(samples: [Float]) async throws -> [RecognizedSegment] {
        calls.add(samples.count)
        if fail { throw CocoaError(.featureUnsupported) }
        return result
    }
}

func makeLibraryWithAudio(seconds: [Double]) throws -> (LibraryStore, [Recording]) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("earbudkit-tx-\(UUID().uuidString)", isDirectory: true)
    let lib = try LibraryStore(paths: LibraryPaths(root: root))
    var recs: [Recording] = []
    for (i, s) in seconds.enumerated() {
        let pcm = [Int16](repeating: 0, count: Int(s * 16_000))
        let frames = try FieldyOpusEncoder().encode(pcm)
        let opus = lib.paths.audio.appendingPathComponent("\(i).opus")
        try frames.write(to: opus)
        let r = Recording(recordedAt: Date(timeIntervalSince1970: TimeInterval(10_000 - i * 1000)), durationSeconds: s,
                          frameCount: frames.count / 40, rawPath: "raw/x/\(i).bin", opusPath: lib.paths.relative(opus))
        try lib.insert(r)
        try lib.enqueueTranscription(recordingId: r.id, model: "fake")
        recs.append(r)
    }
    return (lib, recs)
}

@Suite("Transcription queue")
struct TranscriptionQueueTests {
    @Test func processesOldestFirstAndStoresSegments() async throws {
        let (lib, recs) = try makeLibraryWithAudio(seconds: [1, 2])
        let calls = FakeRecognizer.Calls()
        let fake = FakeRecognizer(result: [
            RecognizedSegment(start: 0, end: 1, text: " One.", noSpeechProbability: 0.1),
            RecognizedSegment(start: 1, end: 2, text: " ghost", noSpeechProbability: 0.95),
        ], calls: calls)
        let q = TranscriptionQueue(library: lib) { _ in fake }
        #expect(try await q.processAll() == 2)
        // recs[1] is older (recordedAt 9000 < 10000), so it ran first: 2 s of samples.
        #expect(calls.sampleCounts == [32_000, 16_000])
        for r in recs {
            let done = try #require(try lib.recording(id: r.id))
            #expect(done.transcriptState == .done)
            #expect(done.transcriptModel == "fake")
            #expect(!done.noSpeech)
            #expect(try lib.segments(recordingId: r.id).map(\.text) == ["One."])
        }
        #expect(try lib.jobs().isEmpty)
        #expect(try lib.search("one").count == 2)
    }

    @Test func silentRecordingGetsNoSpeech() async throws {
        let (lib, recs) = try makeLibraryWithAudio(seconds: [1])
        let fake = FakeRecognizer(result: [RecognizedSegment(start: 0, end: 1, text: " Thank you.", noSpeechProbability: 0.8)],
                                  calls: .init())
        let q = TranscriptionQueue(library: lib) { _ in fake }
        try await q.processAll()
        let r = try #require(try lib.recording(id: recs[0].id))
        #expect(r.transcriptState == .done)
        #expect(r.noSpeech)
        #expect(TranscriptFilter.plainText([]) == "No speech detected")
    }

    @Test func failureThenRetry() async throws {
        let (lib, recs) = try makeLibraryWithAudio(seconds: [1])
        let failing = TranscriptionQueue(library: lib) { _ in FakeRecognizer(result: [], fail: true, calls: .init()) }
        let events = await failing.events()
        try await failing.processAll()
        var it = events.makeAsyncIterator()
        #expect(await it.next() == .started(recordingId: recs[0].id))
        if case .failed(let id, _)? = await it.next() { #expect(id == recs[0].id) } else { Issue.record("expected failure") }
        #expect(try lib.recording(id: recs[0].id)?.transcriptState == .failed)
        // Audio unaffected.
        #expect(try lib.recording(id: recs[0].id)?.opusPath != nil)

        let ok = TranscriptionQueue(library: lib) { _ in
            FakeRecognizer(result: [RecognizedSegment(start: 0, end: 1, text: "ok", noSpeechProbability: 0)], calls: .init())
        }
        #expect(try await ok.processAll() == 0) // failed jobs wait for "Try again"
        try await ok.retry(recordingId: recs[0].id)
        #expect(try await ok.processAll() == 1)
        #expect(try lib.recording(id: recs[0].id)?.transcriptState == .done)
    }

    @Test func resumesAfterRelaunch() async throws {
        let (lib, recs) = try makeLibraryWithAudio(seconds: [1])
        try lib.markTranscribing(recordingId: recs[0].id) // the app quit here
        let q = TranscriptionQueue(library: lib) { _ in
            FakeRecognizer(result: [RecognizedSegment(start: 0, end: 1, text: "back", noSpeechProbability: 0)], calls: .init())
        }
        #expect(try await q.processAll() == 0)
        try await q.resume()
        #expect(try await q.processAll() == 1)
        #expect(try lib.segments(recordingId: recs[0].id).map(\.text) == ["back"])
    }
}
