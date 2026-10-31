import AVFoundation
import CryptoKit
import Foundation
import Testing
@testable import AudioIngest

struct FormatCase: Sendable, CustomTestStringConvertible {
    var name: String
    var fileName: String
    var settings: @Sendable () -> [String: Any]
    var amplitudes: [Float]
    var playbackRate: Double
    var testDescription: String { name }
}

let formatCases: [FormatCase] = [
    FormatCase(name: "WAV 16-bit mono 44.1 kHz", fileName: "pcm16.wav",
               settings: { linearPCM(rate: 44_100, channels: 1, bits: 16) }, amplitudes: [0.3], playbackRate: 44_100),
    FormatCase(name: "WAV 24-bit mono 96 kHz", fileName: "pcm24.wav",
               settings: { linearPCM(rate: 96_000, channels: 1, bits: 24) }, amplitudes: [0.3], playbackRate: 48_000),
    FormatCase(name: "WAV 32-bit float stereo 48 kHz", fileName: "float32.wav",
               settings: { linearPCM(rate: 48_000, channels: 2, bits: 32, float: true) }, amplitudes: [0.4, 0.2], playbackRate: 48_000),
    FormatCase(name: "WAV 16-bit mono 8 kHz", fileName: "pcm8k.wav",
               settings: { linearPCM(rate: 8_000, channels: 1, bits: 16) }, amplitudes: [0.3], playbackRate: 8_000),
    FormatCase(name: "AIFF 16-bit stereo 22.05 kHz", fileName: "tone.aif",
               settings: { linearPCM(rate: 22_050, channels: 2, bits: 16, bigEndian: true) }, amplitudes: [0.3, 0.3], playbackRate: 22_050),
    FormatCase(name: "CAF 24-bit mono 16 kHz", fileName: "tone.caf",
               settings: { linearPCM(rate: 16_000, channels: 1, bits: 24) }, amplitudes: [0.3], playbackRate: 16_000),
    FormatCase(name: "M4A AAC mono 44.1 kHz", fileName: "tone.m4a",
               settings: { [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 96_000] },
               amplitudes: [0.3], playbackRate: 44_100),
    FormatCase(name: "FLAC stereo 48 kHz", fileName: "tone.flac",
               settings: { [AVFormatIDKey: kAudioFormatFLAC, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2] },
               amplitudes: [0.3, 0.3], playbackRate: 48_000),
]

@Suite("AudioIngest decode")
struct IngestTests {
    @Test(arguments: formatCases)
    func ingestsFormat(_ c: FormatCase) throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appendingPathComponent(c.fileName)
        let seconds = 3.5
        try writeTone(to: src, settings: c.settings(), seconds: seconds, amplitudes: c.amplitudes)
        #expect(AudioIngest.isSupported(src))

        let m4a = dir.appendingPathComponent("out.m4a")
        let f32 = dir.appendingPathComponent("out.f32")
        let r = try AudioIngest.ingest(src, playback: m4a, recognizer: f32)

        #expect(r.sourceChannels == c.amplitudes.count)
        #expect(abs(r.duration - seconds) < 0.05)
        #expect(abs(r.playbackDuration - r.duration) <= AudioIngest.verifyTolerance)
        #expect(r.playbackSampleRate == c.playbackRate)

        let playback = try AVAudioFile(forReading: m4a)
        #expect(playback.fileFormat.channelCount == 1)
        #expect(playback.fileFormat.sampleRate == c.playbackRate)
        #expect(playback.fileFormat.streamDescription.pointee.mFormatID == kAudioFormatMPEG4AAC)

        let samples = try readF32(f32)
        #expect(samples.count == r.recognizerSampleCount)
        #expect(abs(Double(samples.count) - r.duration * 16_000) <= 32)
        // Channels are averaged: amplitude of the mix over sqrt(2).
        let mixed = Double(c.amplitudes.reduce(0, +)) / Double(c.amplitudes.count)
        let middle = samples[3_200 ..< samples.count - 3_200]
        #expect(abs(rms(middle) - mixed / 2.squareRoot()) < 0.02)
    }

    @Test func bitRateFitsTheEncoder() {
        #expect(AudioIngest.playbackSettings(forSourceRate: 48_000) == .init(sampleRate: 48_000, bitRate: 64_000))
        #expect(AudioIngest.playbackSettings(forSourceRate: 192_000) == .init(sampleRate: 48_000, bitRate: 64_000))
        #expect(AudioIngest.playbackSettings(forSourceRate: 16_000).bitRate <= 48_000)
        #expect(AudioIngest.playbackSettings(forSourceRate: 8_000).bitRate <= 24_000)
    }

    @Test func blocksJoinWithoutGaps() throws {
        // 62 s crosses two 30-second block boundaries; resampler state must carry over.
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appendingPathComponent("long.wav")
        try writeTone(to: src, settings: linearPCM(rate: 48_000, channels: 2, bits: 32, float: true), seconds: 62, amplitudes: [0.3, 0.3])
        let m4a = dir.appendingPathComponent("out.m4a")
        let f32 = dir.appendingPathComponent("out.f32")
        var fractions: [Double] = []
        let r = try AudioIngest.ingest(src, playback: m4a, recognizer: f32) { fractions.append($0) }
        #expect(fractions.count == 3)
        #expect(fractions.last == 1)

        let samples = try readF32(f32)
        #expect(abs(samples.count - 62 * 16_000) <= 32)
        #expect(abs(r.playbackDuration - 62) <= AudioIngest.verifyTolerance)
        // A 440 Hz sine at 0.3 moves at most ~0.052 per 16 kHz sample; a gap or click would jump further.
        var maxStep: Float = 0
        for i in 200 ..< samples.count - 200 { maxStep = max(maxStep, abs(samples[i] - samples[i - 1])) }
        #expect(maxStep < 0.08)
        for boundary in [30, 60] {
            let at = boundary * 16_000
            #expect(abs(rms(samples[at - 800 ..< at + 800]) - 0.3 / 2.squareRoot()) < 0.01)
        }
    }

    @Test func partialCopyNameStillOpens() throws {
        // Task 2.2 copies imports to `<id>.<ext>.part`; AVAudioFile sniffs the content.
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appendingPathComponent("abc.wav.part")
        try bextWAV(date: nil, time: nil).write(to: src)
        #expect(AudioIngest.isSupported(src))
        let r = try AudioIngest.ingest(src, playback: dir.appendingPathComponent("a.m4a"), recognizer: dir.appendingPathComponent("a.f32"))
        #expect(abs(r.duration - 1) < 0.001)
    }
}

@Suite("AudioIngest errors")
struct IngestErrorTests {
    @Test func unreadableFiles() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pdf = dir.appendingPathComponent("notes.pdf")
        try Data("%PDF-1.7\n1 0 obj\n<<>>\nendobj\n".utf8).write(to: pdf)
        let fakeMP3 = dir.appendingPathComponent("song.mp3")
        try Data((0..<4096).map { UInt8(truncatingIfNeeded: $0 * 7) }).write(to: fakeMP3)
        let missing = dir.appendingPathComponent("gone.wav")

        for url in [pdf, fakeMP3, missing, dir] {
            #expect(!AudioIngest.isSupported(url))
            #expect(throws: AudioIngestError.unreadable(fileName: url.lastPathComponent)) {
                try AudioIngest.ingest(url, playback: dir.appendingPathComponent("o.m4a"), recognizer: dir.appendingPathComponent("o.f32"))
            }
        }
        #expect(AudioIngestError.unreadable(fileName: "notes.pdf").localizedDescription == "notes.pdf: EarBud can't read this kind of file.")
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("o.m4a").path))
    }

    @Test func emptyWAVHasNoAudio() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appendingPathComponent("empty.wav")
        try bextWAV(date: nil, time: nil, seconds: 0).write(to: src)
        #expect(throws: AudioIngestError.noAudio(fileName: "empty.wav")) {
            try AudioIngest.ingest(src, playback: dir.appendingPathComponent("o.m4a"), recognizer: dir.appendingPathComponent("o.f32"))
        }
    }

    @Test func failedWriteLeavesNoOutputs() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appendingPathComponent("tone.wav")
        try bextWAV(date: nil, time: nil).write(to: src)
        let f32 = dir.appendingPathComponent("o.f32")
        let m4a = dir.appendingPathComponent("no-such-dir/o.m4a")
        #expect(throws: AudioIngestError.self) {
            try AudioIngest.ingest(src, playback: m4a, recognizer: f32)
        }
        #expect(!FileManager.default.fileExists(atPath: f32.path))
    }

    @Test func verifyRejectsWrongLength() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appendingPathComponent("tone.wav")
        try bextWAV(date: nil, time: nil, seconds: 2).write(to: src)
        let m4a = dir.appendingPathComponent("o.m4a")
        try AudioIngest.ingest(src, playback: m4a, recognizer: dir.appendingPathComponent("o.f32"))
        #expect(try abs(AudioIngest.verifyPlayback(m4a, expectedDuration: 2.2) - 2) < 0.05)
        #expect(throws: AudioIngestError.self) { try AudioIngest.verifyPlayback(m4a, expectedDuration: 2.3) }
        #expect(throws: AudioIngestError.verificationFailed(expected: 2, actual: 0)) {
            try AudioIngest.verifyPlayback(src.deletingLastPathComponent().appendingPathComponent("none.m4a"), expectedDuration: 2)
        }
    }
}

@Suite("AudioIngest long file", .serialized)
struct LongFileTests {
    @Test func twentyMinutesWithFlatMemory() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appendingPathComponent("meeting.wav")
        let seconds = 20 * 60
        try writeSilentWAV(to: src, seconds: seconds, rate: 48_000)

        let m4a = dir.appendingPathComponent("out.m4a")
        let f32 = dir.appendingPathComponent("out.f32")
        let before = footprint()
        var peak = before
        let r = try AudioIngest.ingest(src, playback: m4a, recognizer: f32) { _ in peak = max(peak, footprint()) }

        #expect(r.sourceFrames == Int64(seconds * 48_000))
        #expect(r.duration == Double(seconds))
        #expect(abs(r.playbackDuration - Double(seconds)) <= AudioIngest.verifyTolerance)
        #expect(abs(r.recognizerSampleCount - seconds * 16_000) <= 32)
        let f32Bytes = try FileManager.default.attributesOfItem(atPath: f32.path)[.size] as! NSNumber
        #expect(f32Bytes.intValue == r.recognizerSampleCount * 4)
        // The whole file as mono floats would be 230 MB; 30-second blocks stay far below.
        let growthMB = Double(peak &- before) / 1_048_576
        #expect(peak < before || growthMB < 100, "footprint grew \(growthMB) MB")
    }
}

@Suite("Content hash")
struct ContentHashTests {
    @Test func knownVector() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("abc.bin")
        try Data("abc".utf8).write(to: url)
        #expect(try ContentHash.sha256(of: url) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func chunkedMatchesOneShot() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("data.wav")
        let data = bextWAV(date: "2026-10-28", time: "14:05:00", seconds: 3)
        try data.write(to: url)
        let expected = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #expect(try ContentHash.sha256(of: url, chunkSize: 1_000) == expected)
        #expect(try ContentHash.sha256(of: url) == expected)
        // Same content under another name hashes the same.
        let copy = dir.appendingPathComponent("renamed.wav")
        try FileManager.default.copyItem(at: url, to: copy)
        #expect(try ContentHash.sha256(of: copy) == expected)
    }

    @Test func missingFileThrows() {
        #expect(throws: AudioIngestError.unreadable(fileName: "nope.wav")) {
            try ContentHash.sha256(of: URL(fileURLWithPath: "/tmp/earbud-ingest-missing/nope.wav"))
        }
    }
}

@Suite("Recording time")
struct RecordingTimeTests {
    let vancouver = TimeZone(identifier: "America/Vancouver")!

    func components(_ date: Date, _ zone: TimeZone) -> DateComponents {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    }

    @Test func broadcastWaveOrigination() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("rode.wav")
        try bextWAV(date: "2026:10:28", time: "14:05:00", junkBytes: 33).write(to: url)
        #expect(AudioIngest.isSupported(url))

        let t = try await AudioIngest.recordingTime(of: url, timeZone: vancouver)
        #expect(t.origin == .broadcastWave)
        #expect(!t.timeFromFileDate)
        #expect(components(t.date, vancouver) == DateComponents(year: 2026, month: 10, day: 28, hour: 14, minute: 5, second: 0))
        // 14:05 PDT is 21:05 UTC.
        #expect(components(t.date, TimeZone(identifier: "UTC")!).hour == 21)

        // Default: the Mac's current time zone.
        let local = try await AudioIngest.recordingTime(of: url)
        #expect(components(local.date, .current).hour == 14)
        #expect(components(local.date, .current).day == 28)
    }

    @Test func bextSeparatorsAndInvalidValues() {
        func parse(_ date: String, _ time: String) -> Date? {
            var bext = Data(count: 320)
            bext.append(contentsOf: Array(date.utf8.prefix(10)) + [UInt8](repeating: 0, count: max(0, 10 - date.utf8.count)))
            bext.append(contentsOf: Array(time.utf8.prefix(8)) + [UInt8](repeating: 0, count: max(0, 8 - time.utf8.count)))
            return BroadcastWave.originationDate(bext: bext, timeZone: vancouver)
        }
        #expect(parse("2026-10-28", "14-05-09") != nil)
        #expect(parse("2026/10/28", "14.05.09") != nil)
        #expect(parse("2026_10_28", "14 05 09") != nil)
        #expect(parse("", "") == nil)
        #expect(parse("2026-10-28", "") == nil)
        #expect(parse("0000:00:00", "00:00:00") == nil)
        #expect(parse("2026-02-31", "10:00:00") == nil)
        #expect(parse("2026-13-01", "10:00:00") == nil)
        #expect(parse("2026-10-28", "25:00:00") == nil)
    }

    @Test func blankBextFallsBackToFileDate() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("copied.wav")
        try bextWAV(date: "", time: "").write(to: url)
        let created = Date(timeIntervalSince1970: 1_735_787_045) // 2025-01-02 03:04:05 UTC
        try FileManager.default.setAttributes([.creationDate: created], ofItemAtPath: url.path)

        let t = try await AudioIngest.recordingTime(of: url, timeZone: vancouver)
        #expect(t.origin == .fileDate)
        #expect(t.timeFromFileDate)
        #expect(abs(t.date.timeIntervalSince(created)) < 1)
    }

    @Test func plainWAVUsesFileDate() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("plain.wav")
        try bextWAV(date: nil, time: nil).write(to: url)
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.creationDate: created], ofItemAtPath: url.path)
        let t = try await AudioIngest.recordingTime(of: url)
        #expect(t == RecordingTime(date: t.date, origin: .fileDate))
        #expect(abs(t.date.timeIntervalSince(created)) < 1)
    }

    @Test func m4aCreationMetadata() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("memo.m4a")
        let start = Date()
        try writeTone(to: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 1], seconds: 1)
        // The file date is set far away so the metadata date is distinguishable.
        try FileManager.default.setAttributes([.creationDate: Date(timeIntervalSince1970: 1_600_000_000)], ofItemAtPath: url.path)

        let t = try await AudioIngest.recordingTime(of: url)
        #expect(t.origin == .fileMetadata)
        #expect(!t.timeFromFileDate)
        #expect(abs(t.date.timeIntervalSince(start)) < 120)
    }

    @Test func metadataDateStrings() {
        #expect(AudioIngest.parseMetadataDate("2026-10-28T14:05:00-07:00") == Date(timeIntervalSince1970: 1_793_221_500))
        #expect(AudioIngest.parseMetadataDate("2026-10-28T21:05:00.250Z") != nil)
        #expect(AudioIngest.parseMetadataDate("2026-10-28 14:05:00") != nil)
        #expect(AudioIngest.parseMetadataDate("2026-10-28") == nil)
        #expect(AudioIngest.parseMetadataDate("2026") == nil)
        #expect(AudioIngest.parseMetadataDate("yesterday") == nil)
    }
}
