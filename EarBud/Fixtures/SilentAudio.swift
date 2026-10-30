import Foundation

/// Writes silent WAV files so fixture recordings can be played, scrubbed and sped up
/// without shipping any real audio.
enum SilentAudio {
    static let sampleRate = 8_000

    /// 8-bit mono PCM at 8 kHz: 8 KB per second of silence.
    static func wavData(duration: TimeInterval) -> Data {
        let sampleCount = max(1, Int(duration * Double(sampleRate)))
        var data = Data()
        data.reserveCapacity(44 + sampleCount)
        func append32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8))
        append32(UInt32(36 + sampleCount))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append32(16)
        append16(1) // PCM
        append16(1) // mono
        append32(UInt32(sampleRate))
        append32(UInt32(sampleRate)) // byte rate
        append16(1) // block align
        append16(8) // bits per sample
        data.append(contentsOf: Array("data".utf8))
        append32(UInt32(sampleCount))
        data.append(Data(repeating: 128, count: sampleCount)) // 8-bit PCM silence is 128
        return data
    }

    /// Returns a cached file for this recording, writing it on first use.
    static func file(for recordingID: String, duration: TimeInterval, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("\(recordingID).wav")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try wavData(duration: duration).write(to: url, options: .atomic)
        return url
    }

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("dev.heybeaux.earbud/SampleAudio", isDirectory: true)
    }
}
