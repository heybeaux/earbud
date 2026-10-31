import COpusShim
import Copus
import FieldyProtocol
import Foundation

public enum AudioCodecError: Error, Equatable, Sendable {
    case opus(code: Int32, during: String)
    case noFrames
    case avFoundation(String)
}

/// PCM decoded from Fieldy Opus frames: 16 kHz mono signed 16-bit.
public struct DecodedAudio: Sendable, Equatable {
    public var samples: [Int16]
    public var sampleRate: Int
    /// Frames handed to the decoder.
    public var frameCount: Int
    /// Frames libopus rejected; each was replaced by packet-loss concealment.
    public var failedFrames: Int
    /// Frames whose TOC byte was not 0xB8.
    public var unexpectedTOCFrames: Int

    public var durationSeconds: Double { Double(samples.count) / Double(sampleRate) }

    /// Samples as Float in [-1, 1], the format Whisper expects.
    public var floatSamples: [Float] { samples.map { Float($0) / 32768 } }
}

/// Decodes bare 40-byte Fieldy Opus frames (TOC 0xB8, CELT, 16 kHz mono, 20 ms).
public final class FieldyOpusDecoder {
    private let decoder: OpaquePointer
    public let sampleRate: Int

    public init(sampleRate: Int = FieldyAudioFormat.sampleRate) throws {
        var err: Int32 = 0
        guard let d = opus_decoder_create(Int32(sampleRate), 1, &err), err == OPUS_OK else {
            throw AudioCodecError.opus(code: err, during: "decoder create")
        }
        decoder = d
        self.sampleRate = sampleRate
    }

    deinit { opus_decoder_destroy(decoder) }

    /// Decodes concatenated frames. A frame libopus rejects, or decodes to
    /// other than 20 ms, is concealed (PLC) so the output length always
    /// equals `frames * 20 ms`.
    public func decode(frames data: Data, frameBytes: Int = FieldyAudioFormat.frameBytes) throws -> DecodedAudio {
        let bytes = [UInt8](data)
        let frameCount = bytes.count / frameBytes
        guard frameCount > 0 else { throw AudioCodecError.noFrames }
        let samplesPerFrame = sampleRate * FieldyAudioFormat.frameDurationMs / 1000
        var pcm = [Int16](repeating: 0, count: frameCount * samplesPerFrame)
        var failed = 0
        var badTOC = 0
        try pcm.withUnsafeMutableBufferPointer { out in
            try bytes.withUnsafeBufferPointer { inp in
                for i in 0..<frameCount {
                    let src = inp.baseAddress! + i * frameBytes
                    let dst = out.baseAddress! + i * samplesPerFrame
                    if src.pointee != FieldyAudioFormat.toc { badTOC += 1 }
                    var n = opus_decode(decoder, src, Int32(frameBytes), dst, Int32(samplesPerFrame), 0)
                    // A valid Opus packet of another size (e.g. bytes that are not a
                    // frame start, TOC 0xE4 = 2.5 ms) is as wrong as a rejected one.
                    if n < 0 || Int(n) != samplesPerFrame {
                        failed += 1
                        n = opus_decode(decoder, nil, 0, dst, Int32(samplesPerFrame), 0)
                        if n < 0 { throw AudioCodecError.opus(code: n, during: "concealment of frame \(i)") }
                    }
                    if Int(n) != samplesPerFrame {
                        throw AudioCodecError.opus(code: n, during: "frame \(i) returned \(n) samples")
                    }
                }
            }
        }
        return DecodedAudio(samples: pcm, sampleRate: sampleRate, frameCount: frameCount,
                            failedFrames: failed, unexpectedTOCFrames: badTOC)
    }

    /// One-shot convenience.
    public static func decode(frames: Data) throws -> DecodedAudio {
        try FieldyOpusDecoder().decode(frames: frames)
    }
}

/// Produces Fieldy-format frames from PCM. Used by tests and the device simulator.
public final class FieldyOpusEncoder {
    private let encoder: OpaquePointer
    public let sampleRate: Int

    public init(sampleRate: Int = FieldyAudioFormat.sampleRate, bitrate: Int = 16_000) throws {
        var err: Int32 = 0
        guard let e = copus_shim_fieldy_encoder_create(Int32(sampleRate), Int32(bitrate), &err), err == OPUS_OK else {
            throw AudioCodecError.opus(code: err, during: "encoder create")
        }
        encoder = e
        self.sampleRate = sampleRate
    }

    deinit { opus_encoder_destroy(encoder) }

    /// Encodes whole 20 ms frames; a trailing partial frame is zero-padded.
    public func encode(_ samples: [Int16]) throws -> Data {
        let per = sampleRate * FieldyAudioFormat.frameDurationMs / 1000
        var input = samples
        if input.count % per != 0 { input += [Int16](repeating: 0, count: per - input.count % per) }
        var out = Data()
        var packet = [UInt8](repeating: 0, count: 1500)
        for start in stride(from: 0, to: input.count, by: per) {
            let n = input.withUnsafeBufferPointer { buf in
                opus_encode(encoder, buf.baseAddress! + start, Int32(per), &packet, Int32(packet.count))
            }
            if n < 0 { throw AudioCodecError.opus(code: n, during: "encode") }
            out.append(contentsOf: packet[0..<Int(n)])
        }
        return out
    }
}
