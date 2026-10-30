import AVFoundation
import Foundation

/// 16-bit PCM WAV writer (RIFF, little-endian).
public enum WAVFile {
    public static func data(samples: [Int16], sampleRate: Int, channels: Int = 1) -> Data {
        let dataBytes = samples.count * 2
        var d = Data(capacity: 44 + dataBytes)
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + dataBytes))
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16)
        u16(1); u16(UInt16(channels)); u32(UInt32(sampleRate))
        u32(UInt32(sampleRate * channels * 2)); u16(UInt16(channels * 2)); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(UInt32(dataBytes))
        samples.withUnsafeBufferPointer { buf in
            for s in buf { withUnsafeBytes(of: s.littleEndian) { d.append(contentsOf: $0) } }
        }
        return d
    }

    public static func write(samples: [Int16], sampleRate: Int, to url: URL) throws {
        try data(samples: samples, sampleRate: sampleRate).write(to: url, options: .atomic)
    }

    public static func write(_ audio: DecodedAudio, to url: URL) throws {
        try write(samples: audio.samples, sampleRate: audio.sampleRate, to: url)
    }
}

/// AAC in an MPEG-4 container, for playback with AVFoundation.
public enum M4AFile {
    /// Default: 32 kbit/s mono, per design.md.
    public static let defaultBitRate = 32_000

    public static func write(samples: [Int16], sampleRate: Int, to url: URL, bitRate: Int = defaultBitRate) throws {
        try? FileManager.default.removeItem(at: url)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: bitRate,
        ]
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(sampleRate), channels: 1, interleaved: false) else {
            throw AudioCodecError.avFoundation("cannot create PCM format")
        }
        do {
            // The file is finalized when `file` is released at the end of this scope.
            let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            let chunk = 16_000
            var offset = 0
            while offset < samples.count {
                let n = min(chunk, samples.count - offset)
                guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n)) else {
                    throw AudioCodecError.avFoundation("cannot allocate buffer")
                }
                buf.frameLength = AVAudioFrameCount(n)
                let ch = buf.floatChannelData![0]
                for i in 0..<n { ch[i] = Float(samples[offset + i]) / 32768 }
                try file.write(from: buf)
                offset += n
            }
        } catch let e as AudioCodecError {
            throw e
        } catch {
            throw AudioCodecError.avFoundation("M4A write failed: \(error.localizedDescription)")
        }
    }

    public static func write(_ audio: DecodedAudio, to url: URL, bitRate: Int = defaultBitRate) throws {
        try write(samples: audio.samples, sampleRate: audio.sampleRate, to: url, bitRate: bitRate)
    }
}

public enum AudioFileInfo {
    /// Playable duration of any AVFoundation-readable file, in seconds.
    public static func duration(of url: URL) throws -> Double {
        do {
            let f = try AVAudioFile(forReading: url)
            return Double(f.length) / f.fileFormat.sampleRate
        } catch {
            throw AudioCodecError.avFoundation("cannot read \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    /// Reads any AVFoundation-readable file as 16 kHz mono Float samples.
    public static func readMono16k(_ url: URL) throws -> [Float] {
        let file: AVAudioFile
        do { file = try AVAudioFile(forReading: url) } catch {
            throw AudioCodecError.avFoundation("cannot read \(url.lastPathComponent): \(error.localizedDescription)")
        }
        let src = file.processingFormat
        guard let srcBuf = AVAudioPCMBuffer(pcmFormat: src, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw AudioCodecError.avFoundation("cannot allocate buffer")
        }
        try file.read(into: srcBuf)
        guard let dstFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: src, to: dstFormat) else {
            throw AudioCodecError.avFoundation("cannot create converter")
        }
        let ratio = 16_000 / src.sampleRate
        let capacity = AVAudioFrameCount(Double(srcBuf.frameLength) * ratio) + 1024
        guard let dst = AVAudioPCMBuffer(pcmFormat: dstFormat, frameCapacity: capacity) else {
            throw AudioCodecError.avFoundation("cannot allocate buffer")
        }
        nonisolated(unsafe) var fed = false
        var err: NSError?
        converter.convert(to: dst, error: &err) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true
            status.pointee = .haveData
            return srcBuf
        }
        if let err { throw AudioCodecError.avFoundation(err.localizedDescription) }
        return Array(UnsafeBufferPointer(start: dst.floatChannelData![0], count: Int(dst.frameLength)))
    }
}
