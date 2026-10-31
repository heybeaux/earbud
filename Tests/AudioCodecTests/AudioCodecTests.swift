import AudioCodec
import FieldyProtocol
import Foundation
import Testing

/// A 440 Hz tone, 16 kHz mono.
func tone(seconds: Double, frequency: Double = 440, amplitude: Double = 0.3) -> [Int16] {
    let n = Int(seconds * 16_000)
    return (0..<n).map { Int16(amplitude * 32767 * sin(2 * .pi * frequency * Double($0) / 16_000)) }
}

func tempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("earbudkit-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite("Opus")
struct OpusTests {
    @Test func encoderProducesFieldyFrames() throws {
        let frames = try FieldyOpusEncoder().encode(tone(seconds: 1))
        #expect(frames.count == 50 * 40)
        let bytes = [UInt8](frames)
        for i in stride(from: 0, to: bytes.count, by: 40) {
            #expect(bytes[i] == FieldyAudioFormat.toc)
        }
    }

    @Test func decodeRoundTrip() throws {
        let pcm = tone(seconds: 2)
        let frames = try FieldyOpusEncoder().encode(pcm)
        let audio = try FieldyOpusDecoder.decode(frames: frames)
        #expect(audio.frameCount == 100)
        #expect(audio.samples.count == 32_000)
        #expect(audio.failedFrames == 0)
        #expect(audio.unexpectedTOCFrames == 0)
        #expect(abs(audio.durationSeconds - 2.0) < 1e-9)
        // Energy survives the codec (CELT at 16 kbit/s is lossy).
        let rms = sqrt(audio.samples.dropFirst(1600).map { Double($0) * Double($0) }.reduce(0, +) / Double(audio.samples.count - 1600))
        #expect(rms > 3000)
        #expect(audio.floatSamples.allSatisfy { $0 >= -1 && $0 <= 1 })
    }

    @Test func garbageFrameIsConcealed() throws {
        var frames = try FieldyOpusEncoder().encode(tone(seconds: 0.2))
        // A frame with an invalid TOC code (code 3 with zero frame count) is rejected by libopus.
        frames.replaceSubrange(40..<80, with: [0xBB, 0x00] + [UInt8](repeating: 0, count: 38))
        let audio = try FieldyOpusDecoder.decode(frames: frames)
        #expect(audio.frameCount == 10)
        #expect(audio.samples.count == 3200)
        #expect(audio.unexpectedTOCFrames == 1)
        #expect(audio.failedFrames == 1)
    }

    @Test func wrongLengthFrameIsConcealed() throws {
        // The first 40 bytes of a headerless device file (2026-10-31): the tail
        // of a frame, not a frame. TOC 0xE4 is a valid 2.5 ms packet, which
        // libopus decodes to 40 samples; that used to fail the whole file
        // with "frame 0 returned 40 samples".
        let misaligned = Data(hex: "e4df8dac463686f2b82fde09f4df9fe0782c200028c391b9daf3f2780abe1ef585b1a13015b1c4fe")!
        #expect(misaligned.count == 40)
        let frames = misaligned + (try FieldyOpusEncoder().encode(tone(seconds: 0.2)))
        let audio = try FieldyOpusDecoder.decode(frames: frames)
        #expect(audio.frameCount == 11)
        #expect(audio.samples.count == 11 * FieldyAudioFormat.samplesPerFrame)
        #expect(audio.failedFrames == 1)
        #expect(audio.unexpectedTOCFrames == 1)
    }

    @Test func emptyInputThrows() {
        #expect(throws: AudioCodecError.noFrames) { try FieldyOpusDecoder.decode(frames: Data([0xB8, 1, 2])) }
    }
}

@Suite("Audio files")
struct AudioFileTests {
    @Test func wavHeader() throws {
        let d = WAVFile.data(samples: [0, 1, -1, 32767], sampleRate: 16_000)
        #expect(d.count == 44 + 8)
        #expect(String(decoding: d[0..<4], as: UTF8.self) == "RIFF")
        #expect(String(decoding: d[8..<12], as: UTF8.self) == "WAVE")
        let b = [UInt8](d)
        #expect(UInt32(b[24]) | UInt32(b[25]) << 8 | UInt32(b[26]) << 16 == 16_000)
        #expect(b[34] == 16) // bits per sample
        #expect(Array(b[44...]) == [0, 0, 1, 0, 0xFF, 0xFF, 0xFF, 0x7F])
    }

    @Test func wavReadsBack() throws {
        let dir = try tempDir()
        let url = dir.appendingPathComponent("t.wav")
        try WAVFile.write(samples: tone(seconds: 1.5), sampleRate: 16_000, to: url)
        #expect(abs(try AudioFileInfo.duration(of: url) - 1.5) < 0.001)
        #expect(try AudioFileInfo.readMono16k(url).count == 24_000)
    }

    @Test func m4aHasMatchingDuration() throws {
        let dir = try tempDir()
        let url = dir.appendingPathComponent("t.m4a")
        let audio = try FieldyOpusDecoder.decode(frames: try FieldyOpusEncoder().encode(tone(seconds: 3)))
        try M4AFile.write(audio, to: url)
        #expect(FileManager.default.fileExists(atPath: url.path))
        let seconds = try AudioFileInfo.duration(of: url)
        #expect(abs(seconds - 3.0) < 0.1)
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        #expect(size > 1000 && size < 40_000) // ~32 kbit/s
    }
}

@Suite("Real device file")
struct RealFileTests {
    /// File 1 of the 2026-10-31 00:25Z sync, v2 header, saved as received.
    static func fixture() throws -> Data {
        let url = try #require(Bundle.module.url(forResource: "v2-recording-0005", withExtension: "bin", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test func v2HeaderParsesAndDecodes() throws {
        let data = try Self.fixture()
        let header = try #require(FileHeader.parse(data))
        guard case .v2(let recordedAt, let recordingId, let length, let crcValid) = header else {
            Issue.record("expected v2 header, got \(header)"); return
        }
        #expect(length == 16)
        #expect(recordingId == 5)
        #expect(crcValid)
        #expect(recordedAt == Date(timeIntervalSince1970: 0x6AE5_33F3))

        let file = RecordingFile(parsing: data)
        #expect(file.hadTrailer)
        #expect(file.discardedBytes == 0)
        #expect(file.frameCount == 330)
        #expect(file.unexpectedTOCCount == 0)

        let audio = try FieldyOpusDecoder.decode(frames: file.opusFrames)
        #expect(audio.failedFrames == 0)
        #expect(audio.samples.count == 330 * FieldyAudioFormat.samplesPerFrame)
    }
}
