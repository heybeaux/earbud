import Accelerate
import AVFoundation
import Foundation

public enum AudioIngestError: Error, Equatable, LocalizedError {
    /// The system cannot decode the file (not audio, or an unsupported format).
    case unreadable(fileName: String)
    /// The file opens but holds no audio frames.
    case noAudio(fileName: String)
    /// Decoding failed partway through the file.
    case readFailed(fileName: String, detail: String)
    /// An output file could not be created or written.
    case writeFailed(String)
    /// The playback M4A is unreadable or its length differs from the source.
    case verificationFailed(expected: Double, actual: Double)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let name): "\(name): EarBud can't read this kind of file."
        case .noAudio(let name): "\(name) has no audio."
        case .readFailed(let name, let detail): "\(name) could not be read to the end: \(detail)"
        case .writeFailed(let detail): "Could not write audio: \(detail)"
        case .verificationFailed(let expected, let actual):
            String(format: "The compressed copy is %.2f s long, the source is %.2f s.", actual, expected)
        }
    }
}

/// What `AudioIngest.ingest` produced.
public struct IngestResult: Sendable, Equatable {
    public var sourceSampleRate: Double
    public var sourceChannels: Int
    /// Frames actually decoded from the source.
    public var sourceFrames: Int64
    /// Source length in seconds, from the decoded frames.
    public var duration: Double
    public var playbackSampleRate: Double
    public var playbackBitRate: Int
    /// Length of the verified playback M4A, in seconds.
    public var playbackDuration: Double
    /// Float32 samples (16 kHz mono) in the recognizer file.
    public var recognizerSampleCount: Int
}

/// Turns any AVAudioFile-readable file into a playback M4A and a 16 kHz mono
/// recognizer file, reading 30-second blocks so memory stays flat for any length.
public enum AudioIngest {
    public static let blockSeconds: Double = 30
    public static let recognizerSampleRate: Double = 16_000
    /// About 30 MB per hour of mono AAC (design.md, "Import copies the file").
    public static let targetBitRate = 64_000
    /// Highest sample rate the system AAC encoder accepts.
    public static let maxPlaybackSampleRate: Double = 48_000
    /// Allowed difference between the playback M4A and the source, in seconds.
    public static let verifyTolerance: Double = 0.25

    /// True when the system can open the file for decoding.
    public static func isSupported(_ url: URL) -> Bool {
        guard let file = try? AVAudioFile(forReading: url) else { return false }
        return file.processingFormat.channelCount > 0
    }

    /// Decodes `source` and writes `playback` (AAC M4A, mono) and `recognizer`
    /// (headerless little-endian Float32, 16 kHz mono). Existing files at either
    /// URL are replaced. On any error both outputs are removed.
    /// `progress` receives the decoded fraction (0...1) after each block.
    @discardableResult
    public static func ingest(
        _ source: URL,
        playback: URL,
        recognizer: URL,
        progress: ((Double) -> Void)? = nil
    ) throws -> IngestResult {
        let name = source.lastPathComponent
        let file: AVAudioFile
        do { file = try AVAudioFile(forReading: source) } catch { throw AudioIngestError.unreadable(fileName: name) }
        let format = file.processingFormat
        let rate = format.sampleRate
        let channels = Int(format.channelCount)
        guard channels > 0, rate > 0 else { throw AudioIngestError.unreadable(fileName: name) }
        guard file.length > 0 else { throw AudioIngestError.noAudio(fileName: name) }

        let blockFrames = AVAudioFrameCount(rate * blockSeconds)
        guard let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false),
              let readBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: blockFrames),
              let monoBuf = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: blockFrames) else {
            throw AudioIngestError.writeFailed("cannot allocate buffers")
        }

        let fm = FileManager.default
        try? fm.removeItem(at: playback)
        try? fm.removeItem(at: recognizer)
        let settings = playbackSettings(forSourceRate: rate)
        var frames: Int64 = 0
        do {
            // Writers live only in this scope: AVAudioFile finalizes the M4A when released.
            let recognizerWriter = try RecognizerWriter(url: recognizer, sourceRate: rate, maxInputFrames: blockFrames)
            let playbackWriter = try PlaybackWriter(url: playback, sourceRate: rate, settings: settings, maxInputFrames: blockFrames)
            while file.framePosition < file.length {
                try autoreleasepool {
                    do { try file.read(into: readBuf, frameCount: blockFrames) } catch {
                        throw AudioIngestError.readFailed(fileName: name, detail: error.localizedDescription)
                    }
                }
                if readBuf.frameLength == 0 { break }
                mixToMono(readBuf, into: monoBuf)
                try autoreleasepool {
                    try playbackWriter.write(monoBuf)
                    try recognizerWriter.write(monoBuf)
                }
                frames += Int64(readBuf.frameLength)
                progress?(min(1, Double(frames) / Double(file.length)))
            }
            try playbackWriter.finish()
            try recognizerWriter.finish()
        } catch {
            try? fm.removeItem(at: playback)
            try? fm.removeItem(at: recognizer)
            if let e = error as? AudioIngestError { throw e }
            throw AudioIngestError.writeFailed(error.localizedDescription)
        }
        guard frames > 0 else {
            try? fm.removeItem(at: playback)
            try? fm.removeItem(at: recognizer)
            throw AudioIngestError.noAudio(fileName: name)
        }

        let duration = Double(frames) / rate
        let playbackDuration: Double
        do { playbackDuration = try verifyPlayback(playback, expectedDuration: duration) } catch {
            try? fm.removeItem(at: playback)
            try? fm.removeItem(at: recognizer)
            throw error
        }
        let recognizerBytes = (try? fm.attributesOfItem(atPath: recognizer.path)[.size] as? NSNumber)?.intValue ?? 0
        return IngestResult(
            sourceSampleRate: rate,
            sourceChannels: channels,
            sourceFrames: frames,
            duration: duration,
            playbackSampleRate: settings.sampleRate,
            playbackBitRate: settings.bitRate,
            playbackDuration: playbackDuration,
            recognizerSampleCount: recognizerBytes / MemoryLayout<Float>.size
        )
    }

    /// Checks that `url` opens, decodes, and lasts within `tolerance` of
    /// `expectedDuration`. Returns its duration in seconds.
    @discardableResult
    public static func verifyPlayback(_ url: URL, expectedDuration: Double, tolerance: Double = verifyTolerance) throws -> Double {
        let file: AVAudioFile
        do { file = try AVAudioFile(forReading: url) } catch {
            throw AudioIngestError.verificationFailed(expected: expectedDuration, actual: 0)
        }
        let duration = Double(file.length) / file.fileFormat.sampleRate
        let probe = AVAudioFrameCount(min(Double(file.length), file.processingFormat.sampleRate))
        guard probe > 0, let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: probe),
              (try? file.read(into: buf, frameCount: probe)) != nil, buf.frameLength > 0 else {
            throw AudioIngestError.verificationFailed(expected: expectedDuration, actual: 0)
        }
        guard abs(duration - expectedDuration) <= tolerance else {
            throw AudioIngestError.verificationFailed(expected: expectedDuration, actual: duration)
        }
        return duration
    }

    struct PlaybackSettings: Equatable {
        var sampleRate: Double
        var bitRate: Int
    }

    /// Source rate when the AAC encoder accepts it (else 48 kHz), and the
    /// encoder bit rate closest to `targetBitRate` without exceeding it.
    static func playbackSettings(forSourceRate rate: Double) -> PlaybackSettings {
        let encodeRate = rate > maxPlaybackSampleRate ? maxPlaybackSampleRate : rate
        let allowed = aacBitRates(sampleRate: encodeRate)
        if allowed.isEmpty {
            return PlaybackSettings(sampleRate: maxPlaybackSampleRate, bitRate: targetBitRate)
        }
        let bitRate = allowed.filter { $0 <= targetBitRate }.max() ?? allowed.min()!
        return PlaybackSettings(sampleRate: encodeRate, bitRate: bitRate)
    }

    static func aacBitRates(sampleRate: Double) -> [Int] {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate, mFormatID: kAudioFormatMPEG4AAC, mFormatFlags: 0, mBytesPerPacket: 0,
            mFramesPerPacket: 1024, mBytesPerFrame: 0, mChannelsPerFrame: 1, mBitsPerChannel: 0, mReserved: 0
        )
        guard let pcm = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let aac = AVAudioFormat(streamDescription: &asbd),
              let converter = AVAudioConverter(from: pcm, to: aac) else { return [] }
        return converter.applicableEncodeBitRates?.map(\.intValue) ?? []
    }

    /// Averages all channels of `src` into the single channel of `dst`.
    static func mixToMono(_ src: AVAudioPCMBuffer, into dst: AVAudioPCMBuffer) {
        let n = vDSP_Length(src.frameLength)
        let channels = Int(src.format.channelCount)
        let input = src.floatChannelData!
        let out = dst.floatChannelData![0]
        out.update(from: input[0], count: Int(n))
        if channels > 1 {
            for c in 1..<channels { vDSP_vadd(out, 1, input[c], 1, out, 1, n) }
            var scale = 1 / Float(channels)
            vDSP_vsmul(out, 1, &scale, out, 1, n)
        }
        dst.frameLength = src.frameLength
    }
}

/// AAC M4A, mono, resampled when the source rate is above what AAC accepts.
final class PlaybackWriter {
    private let file: AVAudioFile
    private let resampler: StreamResampler?

    init(url: URL, sourceRate: Double, settings: AudioIngest.PlaybackSettings, maxInputFrames: AVAudioFrameCount) throws {
        let fileSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: settings.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: settings.bitRate,
        ]
        do {
            file = try AVAudioFile(forWriting: url, settings: fileSettings, commonFormat: .pcmFormatFloat32, interleaved: false)
        } catch {
            throw AudioIngestError.writeFailed("cannot create \(url.lastPathComponent): \(error.localizedDescription)")
        }
        resampler = settings.sampleRate == sourceRate
            ? nil
            : try StreamResampler(from: sourceRate, to: settings.sampleRate, maxInputFrames: maxInputFrames)
    }

    func write(_ mono: AVAudioPCMBuffer) throws {
        if let resampler {
            try resampler.convert(mono) { try file.write(from: $0) }
        } else {
            try file.write(from: mono)
        }
    }

    func finish() throws {
        try resampler?.flush { try file.write(from: $0) }
        if #available(macOS 15, iOS 18, *) { file.close() }
    }
}

/// Headerless little-endian Float32, 16 kHz mono.
final class RecognizerWriter {
    private let handle: FileHandle
    private let resampler: StreamResampler?

    init(url: URL, sourceRate: Double, maxInputFrames: AVAudioFrameCount) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: url) else {
            throw AudioIngestError.writeFailed("cannot create \(url.lastPathComponent)")
        }
        self.handle = handle
        resampler = sourceRate == AudioIngest.recognizerSampleRate
            ? nil
            : try StreamResampler(from: sourceRate, to: AudioIngest.recognizerSampleRate, maxInputFrames: maxInputFrames)
    }

    deinit { try? handle.close() }

    func write(_ mono: AVAudioPCMBuffer) throws {
        if let resampler {
            try resampler.convert(mono) { try append($0) }
        } else {
            try append(mono)
        }
    }

    func finish() throws {
        try resampler?.flush { try append($0) }
        try handle.close()
    }

    private func append(_ buf: AVAudioPCMBuffer) throws {
        let n = Int(buf.frameLength)
        guard n > 0 else { return }
        let samples = UnsafeBufferPointer(start: buf.floatChannelData![0], count: n)
        try handle.write(contentsOf: Data(buffer: samples))
    }
}

/// Mono Float32 sample-rate conversion over a stream of blocks.
final class StreamResampler {
    private let converter: AVAudioConverter
    private let output: AVAudioPCMBuffer

    init(from: Double, to: Double, maxInputFrames: AVAudioFrameCount) throws {
        guard let src = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: from, channels: 1, interleaved: false),
              let dst = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: to, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: src, to: dst),
              let output = AVAudioPCMBuffer(pcmFormat: dst, frameCapacity: AVAudioFrameCount(Double(maxInputFrames) * to / from) + 8192) else {
            throw AudioIngestError.writeFailed("cannot create a \(Int(from)) Hz to \(Int(to)) Hz converter")
        }
        converter.sampleRateConverterQuality = AVAudioQuality.high.rawValue
        self.converter = converter
        self.output = output
    }

    func convert(_ input: AVAudioPCMBuffer, sink: (AVAudioPCMBuffer) throws -> Void) throws {
        nonisolated(unsafe) var given = false
        nonisolated(unsafe) let input = input
        try run(sink) { _, status in
            if given { status.pointee = .noDataNow; return nil }
            given = true
            status.pointee = .haveData
            return input
        }
    }

    /// Drains the converter's tail at the end of the stream.
    func flush(sink: (AVAudioPCMBuffer) throws -> Void) throws {
        try run(sink) { _, status in
            status.pointee = .endOfStream
            return nil
        }
    }

    private func run(_ sink: (AVAudioPCMBuffer) throws -> Void, input: @escaping AVAudioConverterInputBlock) throws {
        while true {
            output.frameLength = 0
            var err: NSError?
            let status = converter.convert(to: output, error: &err, withInputFrom: input)
            if status == .error {
                throw AudioIngestError.writeFailed("sample rate conversion failed: \(err?.localizedDescription ?? "unknown")")
            }
            if output.frameLength > 0 { try sink(output) }
            if status != .haveData { break }
        }
    }
}
