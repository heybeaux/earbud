import AVFoundation
import Foundation

func tempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("earbud-ingest-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func linearPCM(rate: Double, channels: Int, bits: Int, float: Bool = false, bigEndian: Bool = false) -> [String: Any] {
    [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: rate,
        AVNumberOfChannelsKey: channels,
        AVLinearPCMBitDepthKey: bits,
        AVLinearPCMIsFloatKey: float,
        AVLinearPCMIsBigEndianKey: bigEndian,
        AVLinearPCMIsNonInterleaved: false,
    ]
}

/// Writes `seconds` of a 440 Hz sine with channel c at amplitude `amplitudes[c]`.
func writeTone(
    to url: URL,
    settings: [String: Any],
    seconds: Double,
    amplitudes: [Float] = [0.3]
) throws {
    let rate = (settings[AVSampleRateKey] as! NSNumber).doubleValue
    let channels = AVAudioChannelCount(amplitudes.count)
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: channels, interleaved: false)!
    let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    let total = Int(seconds * rate)
    let chunk = Int(rate)
    let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(chunk))!
    var offset = 0
    while offset < total {
        let n = min(chunk, total - offset)
        buf.frameLength = AVAudioFrameCount(n)
        for c in 0..<Int(channels) {
            let ch = buf.floatChannelData![c]
            for i in 0..<n { ch[i] = amplitudes[c] * Float(sin(2 * .pi * 440 * Double(offset + i) / rate)) }
        }
        try file.write(from: buf)
        offset += n
    }
    if #available(macOS 15, *) { file.close() }
}

/// Hand-built 16-bit mono WAV: RIFF, fmt, optional odd-sized junk, optional bext, data.
func bextWAV(
    date: String?,
    time: String?,
    seconds: Double = 1,
    rate: Int = 16_000,
    junkBytes: Int? = nil
) -> Data {
    var d = Data()
    func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
    func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
    func ascii(_ s: String, _ width: Int) {
        var b = Array(s.utf8.prefix(width))
        b += [UInt8](repeating: 0, count: width - b.count)
        d.append(contentsOf: b)
    }
    let frames = Int(seconds * Double(rate))
    d.append(contentsOf: Array("RIFF".utf8)); u32(0) // patched below
    d.append(contentsOf: Array("WAVE".utf8))
    d.append(contentsOf: Array("fmt ".utf8)); u32(16)
    u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate * 2)); u16(2); u16(16)
    if let junkBytes {
        d.append(contentsOf: Array("junk".utf8)); u32(UInt32(junkBytes))
        d.append(Data(count: junkBytes))
        if junkBytes % 2 == 1 { d.append(0) }
    }
    if date != nil || time != nil {
        d.append(contentsOf: Array("bext".utf8)); u32(602)
        ascii("EarBud test", 256)   // Description
        ascii("RODE", 32)           // Originator
        ascii("REF", 32)            // OriginatorReference
        ascii(date ?? "", 10)       // OriginationDate
        ascii(time ?? "", 8)        // OriginationTime
        d.append(Data(count: 602 - 338)) // TimeReference, Version, UMID, reserved
    }
    d.append(contentsOf: Array("data".utf8)); u32(UInt32(frames * 2))
    for i in 0..<frames {
        let s = Int16(0.3 * 32767 * sin(2 * .pi * 440 * Double(i) / Double(rate)))
        withUnsafeBytes(of: s.littleEndian) { d.append(contentsOf: $0) }
    }
    let riffSize = UInt32(d.count - 8).littleEndian
    withUnsafeBytes(of: riffSize) { d.replaceSubrange(4..<8, with: $0) }
    return d
}

/// A 16-bit mono WAV of silence, written in chunks so the fixture itself is cheap.
func writeSilentWAV(to url: URL, seconds: Int, rate: Int) throws {
    let dataBytes = seconds * rate * 2
    var h = Data()
    func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { h.append(contentsOf: $0) } }
    func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { h.append(contentsOf: $0) } }
    h.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + dataBytes))
    h.append(contentsOf: Array("WAVE".utf8))
    h.append(contentsOf: Array("fmt ".utf8)); u32(16)
    u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate * 2)); u16(2); u16(16)
    h.append(contentsOf: Array("data".utf8)); u32(UInt32(dataBytes))
    FileManager.default.createFile(atPath: url.path, contents: h)
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    let chunk = Data(count: 8 << 20)
    var left = dataBytes
    while left > 0 {
        let n = min(left, chunk.count)
        try handle.write(contentsOf: chunk.prefix(n))
        left -= n
    }
}

func readF32(_ url: URL) throws -> [Float] {
    let data = try Data(contentsOf: url)
    return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
}

func rms(_ x: ArraySlice<Float>) -> Double {
    guard !x.isEmpty else { return 0 }
    return sqrt(x.reduce(0) { $0 + Double($1) * Double($1) } / Double(x.count))
}

/// Physical memory footprint of this process, in bytes.
func footprint() -> UInt64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return kr == KERN_SUCCESS ? info.phys_footprint : 0
}
