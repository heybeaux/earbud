import AudioCodec
import Foundation
import Library
import Testing
@testable import Transcriber

/// Returns a scripted list of segments per call (window), and records what it was given.
final class ScriptedRecognizer: SpeechRecognizer, @unchecked Sendable {
    private let lock = NSLock()
    private let script: [[RecognizedSegment]]
    private var _sampleCounts: [Int] = []
    private var _firstSamples: [Float] = []

    init(_ script: [[RecognizedSegment]]) { self.script = script }

    var sampleCounts: [Int] { lock.withLock { _sampleCounts } }
    var firstSamples: [Float] { lock.withLock { _firstSamples } }

    func recognize(samples: [Float]) async throws -> [RecognizedSegment] {
        lock.withLock {
            let i = _sampleCounts.count
            _sampleCounts.append(samples.count)
            _firstSamples.append(samples.first ?? .nan)
            return i < script.count ? script[i] : []
        }
    }
}

/// A source of any length that never holds more than one window: sample `i` is `Float(i)`.
struct CountingSource: AudioSampleSource {
    var sampleCount: Int
    func read(from start: Int, count: Int) throws -> [Float] {
        let n = max(0, min(count, sampleCount - start))
        return (0..<n).map { Float(start + $0) }
    }
}

/// Silence of any length, one window at a time.
struct SilentSource: AudioSampleSource {
    var sampleCount: Int
    func read(from start: Int, count: Int) throws -> [Float] {
        [Float](repeating: 0, count: max(0, min(count, sampleCount - start)))
    }
}

final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [Double] = []
    func add(_ v: Double) { lock.withLock { _values.append(v) } }
    var values: [Double] { lock.withLock { _values } }
}

private func seg(_ start: Double, _ end: Double, _ text: String, _ noSpeech: Double = 0.1) -> RecognizedSegment {
    RecognizedSegment(start: start, end: end, text: text, noSpeechProbability: noSpeech)
}

@Suite("Chunked transcription")
struct ChunkedTranscriptionTests {
    static let rate = AudioSamples.sampleRate

    @Test func defaults() {
        #expect(ChunkedTranscriber.windowSamples == 600 * 16_000)
        #expect(ChunkedTranscriber.overlapSamples == 5 * 16_000)
    }

    @Test func shortFileIsOneWindow() {
        let total = 90 * Self.rate
        #expect(ChunkedTranscriber.plan(totalSamples: total) == [TranscriptionWindow(start: 0, count: total)])
        // Exactly ten minutes still fits.
        let ten = 600 * Self.rate
        #expect(ChunkedTranscriber.plan(totalSamples: ten) == [TranscriptionWindow(start: 0, count: ten)])
        #expect(ChunkedTranscriber.plan(totalSamples: 0) == [TranscriptionWindow(start: 0, count: 0)])
    }

    @Test func threeHourPlan() {
        let total = 3 * 3600 * Self.rate
        let windows = ChunkedTranscriber.plan(totalSamples: total)
        // Starts every 595 s: 0, 595, …, 10 710; the last covers the final 90 s.
        #expect(windows.count == 19)
        #expect(windows.first == TranscriptionWindow(start: 0, count: 600 * Self.rate))
        #expect(windows.last == TranscriptionWindow(start: 10_710 * Self.rate, count: 90 * Self.rate))
        #expect(windows.last?.end == total)
        for (a, b) in zip(windows, windows.dropFirst()) {
            #expect(b.start == a.start + 595 * Self.rate)
            #expect(a.end - b.start == 5 * Self.rate) // 5 s overlap
            #expect(a.count == 600 * Self.rate)
        }
    }

    @Test func justOverOneWindow() {
        let total = 600 * Self.rate + 1
        let windows = ChunkedTranscriber.plan(totalSamples: total)
        #expect(windows == [TranscriptionWindow(start: 0, count: 600 * Self.rate),
                            TranscriptionWindow(start: 595 * Self.rate, count: 5 * Self.rate + 1)])
    }

    @Test func shortFileMatchesOnePass() async throws {
        let samples = (0..<(3 * Self.rate)).map { Float($0) / 100 }
        let raw = [seg(0, 1.2, " Hello."), seg(1.2, 2.9, " Bye.")]
        let r = ScriptedRecognizer([raw])
        let log = ProgressLog()
        let out = try await ChunkedTranscriber.transcribe(InMemorySamples(samples), with: r) { log.add($0) }
        #expect(out == raw)
        #expect(r.sampleCounts == [samples.count])
        #expect(log.values == [1])
    }

    @Test func offsetsAndOverlapDeduplication() async throws {
        // 10 s windows, 2 s overlap, 25 s of audio: windows at 0, 8, 16 (16-25 s).
        let window = 10 * Self.rate, overlap = 2 * Self.rate
        let source = CountingSource(sampleCount: 25 * Self.rate)
        #expect(ChunkedTranscriber.plan(totalSamples: source.sampleCount, window: window, overlap: overlap).map(\.start)
                == [0, 8 * Self.rate, 16 * Self.rate])
        let r = ScriptedRecognizer([
            // Overlaps are 8-10 s and 16-18 s; they split at 9 s and 17 s.
            [seg(0, 4, "a"), seg(4, 8.5, "b"), seg(8.5, 10, "c")],           // 8.5 s is before 9 s: kept here
            [seg(0.4, 2, "c again"), seg(2, 6, "d"), seg(6, 9, "e"), seg(9, 10, "f")], // 8.4 s dropped; 17 s left to the next window
            [seg(1, 2, "f"), seg(2.5, 9, "g")],                              // 17 s kept; 18.5 s kept
        ])
        let log = ProgressLog()
        let out = try await ChunkedTranscriber.transcribe(source, with: r, window: window, overlap: overlap) { log.add($0) }
        #expect(out.map(\.text) == ["a", "b", "c", "d", "e", "f", "g"])
        #expect(out.map(\.start) == [0, 4, 8.5, 10, 14, 17, 18.5])
        #expect(out.map(\.end) == [4, 8.5, 10, 14, 17, 18, 25])
        // Each window was read on its own, from the right place.
        #expect(r.sampleCounts == [window, window, 9 * Self.rate])
        #expect(r.firstSamples == [0, Float(8 * Self.rate), Float(16 * Self.rate)])
        #expect(log.values.count == 3)
        #expect(log.values.last == 1)
        #expect(log.values == log.values.sorted())
    }

    @Test func overlapSplitsAtItsMiddle() {
        // Overlap 8-10 s: the earlier window keeps up to 9 s, the later one from 9 s.
        let prev = TranscriptionWindow(start: 0, count: 10 * Self.rate)
        let next = TranscriptionWindow(start: 8 * Self.rate, count: 10 * Self.rate)
        var merged: [RecognizedSegment] = []
        ChunkedTranscriber.merge([seg(4, 8.99, "early"), seg(9, 10, "late in earlier")], from: prev,
                                 previous: nil, next: next, into: &merged)
        ChunkedTranscriber.merge([seg(0.99, 2, "dup"), seg(1, 2, "late"), seg(4, 5, "after")], from: next,
                                 previous: prev, next: nil, into: &merged)
        #expect(merged.map(\.text) == ["early", "late", "after"])
        #expect(merged.map(\.start) == [4, 9, 12])
    }

    @Test func wordCutOffAtWindowEndIsKeptFromNextWindow() {
        // Whisper leaves out a word cut off at 10 s; the later window hears it whole.
        let prev = TranscriptionWindow(start: 0, count: 10 * Self.rate)
        let next = TranscriptionWindow(start: 8 * Self.rate, count: 10 * Self.rate)
        var merged: [RecognizedSegment] = []
        ChunkedTranscriber.merge([seg(5, 8.5, "before")], from: prev, previous: nil, next: next, into: &merged)
        ChunkedTranscriber.merge([seg(0.5, 1.3, "before"), seg(1.5, 2.4, "cut word")], from: next,
                                 previous: prev, next: nil, into: &merged)
        #expect(merged.map(\.text) == ["before", "cut word"])
        #expect(merged.last?.start == 9.5)
    }

    @Test func laterSegmentRepeatingEarlierOneIsDropped() {
        // The earlier window's last segment runs past the split (8.5-9.8 s);
        // the later window's copy starts at 9.2 s, inside it.
        let prev = TranscriptionWindow(start: 0, count: 10 * Self.rate)
        let next = TranscriptionWindow(start: 8 * Self.rate, count: 10 * Self.rate)
        var merged: [RecognizedSegment] = []
        ChunkedTranscriber.merge([seg(8.5, 9.8, "long line")], from: prev, previous: nil, next: next, into: &merged)
        ChunkedTranscriber.merge([seg(1.2, 1.8, "line"), seg(1.8, 3, "next")], from: next,
                                 previous: prev, next: nil, into: &merged)
        #expect(merged.map(\.text) == ["long line", "next"])
    }

    @Test func threeHourRunReportsProgress() async throws {
        let source = SilentSource(sampleCount: 3 * 3600 * Self.rate)
        // Every window hears one line at its own 10 s mark (never in an overlap).
        let r = ScriptedRecognizer(Array(repeating: [seg(10, 12, "line")], count: 19))
        let log = ProgressLog()
        let out = try await ChunkedTranscriber.transcribe(source, with: r) { log.add($0) }
        #expect(out.count == 19)
        #expect(out.map(\.start) == (0..<19).map { Double($0 * 595 + 10) })
        #expect(log.values.count == 19)
        #expect(log.values.first.map { abs($0 - 1.0 / 19) < 1e-9 } == true)
        #expect(log.values.last == 1)
    }

    @Test func float32FileSource() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("earbud-\(UUID().uuidString).f32")
        defer { try? FileManager.default.removeItem(at: url) }
        let samples: [Float] = (0..<1000).map { Float($0) * 0.5 }
        try samples.withUnsafeBufferPointer { Data(buffer: $0) }.write(to: url)
        let source = try AudioSamples.open(url)
        #expect(source is Float32FileSamples)
        #expect(source.sampleCount == 1000)
        #expect(try source.read(from: 0, count: 1000) == samples)
        #expect(try source.read(from: 990, count: 50) == Array(samples[990...]))
        #expect(try source.read(from: 1000, count: 10).isEmpty)
    }

    @Test func audioFileSourceReadsWindows() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("earbud-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("tone.m4a")
        let pcm = (0..<(4 * 16_000)).map { Int16(8000 * sin(Double($0) * 2 * .pi * 440 / 16_000)) }
        try M4AFile.write(samples: pcm, sampleRate: 16_000, to: url)

        let source = try AudioSamples.open(url)
        #expect(source is AudioFileSamples)
        let whole = try AudioFileInfo.readMono16k(url)
        // A file that fits in one window reads through the one-shot reader, as
        // before. (Repeated AAC decodes can differ in the last float bit.)
        let viaSource = try source.read(from: 0, count: ChunkedTranscriber.windowSamples)
        #expect(viaSource.count == whole.count)
        #expect(zip(viaSource, whole).allSatisfy { abs($0 - $1) < 1e-5 })
        // Windows read only their own part.
        let part = try source.read(from: 16_000, count: 16_000)
        #expect(part.count == 16_000)
        let rms = sqrt(part.map { $0 * $0 }.reduce(0, +) / Float(part.count))
        #expect(rms > 0.1)
        let tail = try source.read(from: source.sampleCount - 8000, count: 16_000)
        #expect(tail.count <= 8000 && tail.count > 7000)
    }
}

@Suite("Chunked queue")
struct ChunkedQueueTests {
    @Test func longAudioFileIsTranscribedInWindowsWithProgress() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("earbudkit-chunk-\(UUID().uuidString)", isDirectory: true)
        let lib = try LibraryStore(paths: LibraryPaths(root: root))
        // 20 minutes 16 kHz Float32: three windows (0, 595 s, 1190 s).
        let url = lib.paths.audio.appendingPathComponent("long.f32")
        let total = 1200 * 16_000
        try [Float](repeating: 0, count: total).withUnsafeBufferPointer { Data(buffer: $0) }.write(to: url)
        let rec = Recording(recordedAt: Date(timeIntervalSince1970: 1000), durationSeconds: 1200, frameCount: 0,
                            rawPath: "raw/x/long.bin", audioPath: lib.paths.relative(url))
        try lib.insert(rec)
        try lib.enqueueTranscription(recordingId: rec.id, model: "fake")

        let r = ScriptedRecognizer([[seg(1, 2, " one")], [seg(1, 2, " overlap"), seg(10, 11, " two")], [seg(10, 11, " three")]])
        let q = TranscriptionQueue(library: lib) { _ in r }
        let events = await q.events()
        #expect(try await q.processAll() == 1)
        #expect(r.sampleCounts == [600 * 16_000, 600 * 16_000, 10 * 16_000])
        let segs = try lib.segments(recordingId: rec.id)
        #expect(segs.map(\.text) == ["one", "two", "three"])
        #expect(segs.map(\.start) == [1, 605, 1200])

        var it = events.makeAsyncIterator()
        var progress: [Double] = []
        #expect(await it.next() == .started(recordingId: rec.id))
        while let e = await it.next() {
            if case .progress(_, let f) = e { progress.append(f); continue }
            #expect(e == .finished(recordingId: rec.id, segments: 3))
            break
        }
        #expect(progress.count == 3)
        #expect(progress.last == 1)
    }
}
