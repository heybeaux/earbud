import AVFoundation
import AudioCodec
import Foundation

/// 16 kHz mono Float32 audio that can be read a piece at a time, so long
/// files never have to be in memory whole.
public protocol AudioSampleSource: Sendable {
    /// Length in 16 kHz samples.
    var sampleCount: Int { get }
    /// Up to `count` samples starting at sample `start`.
    func read(from start: Int, count: Int) throws -> [Float]
}

public enum AudioSamples {
    public static let sampleRate = 16_000

    /// A file as a sample source: raw 16 kHz mono Float32 for `.f32`,
    /// anything AVFoundation reads (M4A, WAV, …) otherwise.
    public static func open(_ url: URL) throws -> any AudioSampleSource {
        url.pathExtension.lowercased() == "f32" ? try Float32FileSamples(url: url) : try AudioFileSamples(url: url)
    }
}

/// Samples already in memory (decoded Fieldy Opus, tests).
public struct InMemorySamples: AudioSampleSource {
    public let samples: [Float]
    public init(_ samples: [Float]) { self.samples = samples }
    public var sampleCount: Int { samples.count }

    public func read(from start: Int, count: Int) throws -> [Float] {
        let lo = min(max(0, start), samples.count)
        let hi = min(samples.count, lo + max(0, count))
        return lo == 0 && hi == samples.count ? samples : Array(samples[lo..<hi])
    }
}

/// Raw little-endian 16 kHz mono Float32, no header.
public struct Float32FileSamples: AudioSampleSource {
    public let url: URL
    public let sampleCount: Int

    public init(url: URL) throws {
        self.url = url
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
        sampleCount = size / MemoryLayout<Float>.size
    }

    public func read(from start: Int, count: Int) throws -> [Float] {
        let lo = min(max(0, start), sampleCount)
        let n = min(sampleCount - lo, max(0, count))
        guard n > 0 else { return [] }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(lo * MemoryLayout<Float>.size))
        let data = try handle.read(upToCount: n * MemoryLayout<Float>.size) ?? Data()
        let got = data.count / MemoryLayout<Float>.size
        return [Float](unsafeUninitializedCapacity: got) { buf, initialized in
            _ = data.copyBytes(to: buf, count: got * MemoryLayout<Float>.size)
            initialized = got
        }
    }
}

/// Any AVFoundation-readable file, decoded and resampled to 16 kHz mono one
/// window at a time, in 30-second blocks.
public struct AudioFileSamples: AudioSampleSource {
    public let url: URL
    public let sampleCount: Int
    private let sourceRate: Double
    private let sourceLength: AVAudioFramePosition

    static let blockSeconds = 30.0

    public init(url: URL) throws {
        self.url = url
        let file = try Self.openFile(url)
        sourceRate = file.processingFormat.sampleRate
        sourceLength = file.length
        sampleCount = Int(Double(sourceLength) * Double(AudioSamples.sampleRate) / sourceRate)
    }

    public func read(from start: Int, count: Int) throws -> [Float] {
        let lo = min(max(0, start), sampleCount)
        let hi = min(sampleCount, lo + max(0, count))
        // The whole file: exactly what the one-shot reader returns.
        if lo == 0 && hi == sampleCount { return try AudioFileInfo.readMono16k(url) }
        guard hi > lo else { return [] }

        let ratio = sourceRate / Double(AudioSamples.sampleRate)
        let srcStart = AVAudioFramePosition((Double(lo) * ratio).rounded(.down))
        let srcEnd = hi == sampleCount ? sourceLength : min(sourceLength, AVAudioFramePosition((Double(hi) * ratio).rounded(.up)))
        let file = try Self.openFile(url)
        file.framePosition = srcStart
        let src = file.processingFormat
        guard let dstFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(AudioSamples.sampleRate), channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: src, to: dstFormat),
              let dst = AVAudioPCMBuffer(pcmFormat: dstFormat, frameCapacity: AVAudioFrameCount(hi - lo) + 1024) else {
            throw AudioCodecError.avFoundation("cannot create converter")
        }
        let blockFrames = AVAudioFrameCount(Self.blockSeconds * sourceRate)
        let feed = Feed(remaining: srcEnd - srcStart)
        var err: NSError?
        converter.convert(to: dst, error: &err) { _, status in
            guard feed.remaining > 0, feed.error == nil,
                  let buf = AVAudioPCMBuffer(pcmFormat: src, frameCapacity: min(blockFrames, AVAudioFrameCount(feed.remaining))) else {
                status.pointee = .endOfStream
                return nil
            }
            do {
                try file.read(into: buf, frameCount: buf.frameCapacity)
            } catch {
                feed.error = error
            }
            guard buf.frameLength > 0 else {
                status.pointee = .endOfStream
                return nil
            }
            feed.remaining -= AVAudioFramePosition(buf.frameLength)
            status.pointee = .haveData
            return buf
        }
        if let e = feed.error ?? err { throw AudioCodecError.avFoundation("cannot read \(url.lastPathComponent): \(e.localizedDescription)") }
        let n = min(Int(dst.frameLength), hi - lo)
        return Array(UnsafeBufferPointer(start: dst.floatChannelData![0], count: n))
    }

    private final class Feed: @unchecked Sendable {
        var remaining: AVAudioFramePosition
        var error: Error?
        init(remaining: AVAudioFramePosition) { self.remaining = remaining }
    }

    private static func openFile(_ url: URL) throws -> AVAudioFile {
        do { return try AVAudioFile(forReading: url) } catch {
            throw AudioCodecError.avFoundation("cannot read \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }
}

/// One recognizer pass over part of a recording, in 16 kHz samples.
public struct TranscriptionWindow: Sendable, Equatable {
    public var start: Int
    public var count: Int
    public var end: Int { start + count }

    public init(start: Int, count: Int) {
        self.start = start
        self.count = count
    }

    public var startSeconds: Double { Double(start) / Double(AudioSamples.sampleRate) }
    public var endSeconds: Double { Double(end) / Double(AudioSamples.sampleRate) }
}

/// Long recordings are recognized in 10-minute windows that overlap by
/// 5 seconds. A recording that fits in one window is recognized in one pass,
/// exactly as before chunking.
public enum ChunkedTranscriber {
    public static let windowSeconds = 600
    public static let overlapSeconds = 5
    public static let windowSamples = windowSeconds * AudioSamples.sampleRate
    public static let overlapSamples = overlapSeconds * AudioSamples.sampleRate

    /// Windows covering `totalSamples`. Each starts `window - overlap` after
    /// the previous one; the last one ends at the end of the audio.
    public static func plan(totalSamples: Int, window: Int = windowSamples, overlap: Int = overlapSamples) -> [TranscriptionWindow] {
        precondition(window > overlap && overlap >= 0, "window must be longer than the overlap")
        let total = max(0, totalSamples)
        guard total > window else { return [TranscriptionWindow(start: 0, count: total)] }
        var windows: [TranscriptionWindow] = []
        var start = 0
        while true {
            let count = min(window, total - start)
            windows.append(TranscriptionWindow(start: start, count: count))
            if start + count >= total { break }
            start += window - overlap
        }
        return windows
    }

    /// Adds `window`'s raw segments (timestamps relative to the window) to
    /// `merged` (absolute timestamps). Segments that start inside the overlap
    /// with the previous window were already recognized there, so they are
    /// dropped.
    public static func merge(_ segments: [RecognizedSegment], from window: TranscriptionWindow,
                             previous: TranscriptionWindow?, into merged: inout [RecognizedSegment]) {
        let offset = window.startSeconds
        let keepFrom = previous.map { $0.endSeconds } ?? -.infinity
        for s in segments {
            let start = s.start + offset
            guard start >= keepFrom else { continue }
            merged.append(RecognizedSegment(start: start, end: s.end + offset, text: s.text,
                                            noSpeechProbability: s.noSpeechProbability))
        }
    }

    /// Recognizes `source` window by window, reading each window only when
    /// it is needed. `progress` gets the fraction done (0-1) after each window.
    public static func transcribe(_ source: any AudioSampleSource, with recognizer: any SpeechRecognizer,
                                  window: Int = windowSamples, overlap: Int = overlapSamples,
                                  progress: (@Sendable (Double) async -> Void)? = nil) async throws -> [RecognizedSegment] {
        let windows = plan(totalSamples: source.sampleCount, window: window, overlap: overlap)
        var merged: [RecognizedSegment] = []
        var previous: TranscriptionWindow?
        for (i, w) in windows.enumerated() {
            try Task.checkCancellation()
            let samples = try source.read(from: w.start, count: w.count)
            let raw = try await recognizer.recognize(samples: samples)
            merge(raw, from: w, previous: previous, into: &merged)
            previous = w
            await progress?(Double(i + 1) / Double(windows.count))
        }
        return merged
    }
}
