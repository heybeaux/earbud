import Foundation

/// Opus frame format used by both the live stream and stored files:
/// CELT-only, wideband 16 kHz, mono, 20 ms, 40 bytes per frame (16 kbit/s CBR).
public enum FieldyAudioFormat {
    public static let frameBytes = 40
    public static let toc: UInt8 = 0xB8
    public static let sampleRate = 16_000
    public static let frameDurationMs = 20
    public static let samplesPerFrame = sampleRate * frameDurationMs / 1000
    public static func seconds(frames: Int) -> Double { Double(frames) * Double(frameDurationMs) / 1000 }
}

/// The header at the start of a synced file.
public enum FileHeader: Equatable, Sendable {
    /// `'*' 'S' year u16, month, day, hour, minute, second, '#'` (10 bytes, UTC).
    case v1(recordedAt: Date?)
    /// `'*' 0x02 headerLen u8, recordedAt u32 (UTC seconds), recordingId u16, ..., crc16, '#'`.
    case v2(recordedAt: Date?, recordingId: UInt16, length: Int, crcValid: Bool)

    public var length: Int {
        switch self {
        case .v1: 10
        case .v2(_, _, let length, _): length
        }
    }

    /// UTC time from the header, nil if absent or implausible.
    public var recordedAt: Date? {
        switch self {
        case .v1(let d): d
        case .v2(let d, _, _, _): d
        }
    }

    public var recordingId: UInt16? {
        if case .v2(_, let id, _, _) = self { return id }
        return nil
    }

    /// Earliest plausible recording time; anything before is treated as "time unknown".
    public static let earliestValidDate = Date(timeIntervalSince1970: 1_577_836_800) // 2020-01-01

    public static func parse(_ data: Data) -> FileHeader? {
        let b = [UInt8](data.prefix(255))
        let r = ByteReader(b)
        if b.count >= 10, b[0] == 0x2A, b[1] == 0x53 {
            var c = DateComponents()
            c.year = Int(r.u16be(2)); c.month = Int(b[4]); c.day = Int(b[5])
            c.hour = Int(b[6]); c.minute = Int(b[7]); c.second = Int(b[8])
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "UTC")!
            let valid = (1...12).contains(c.month!) && (1...31).contains(c.day!) && c.hour! < 24 && c.minute! < 60 && c.second! < 61
            let date = valid ? cal.date(from: c) : nil
            return .v1(recordedAt: date.flatMap { $0 >= earliestValidDate ? $0 : nil })
        }
        if b.count >= 16, b[0] == 0x2A, b[1] == 0x02 {
            let len = Int(b[2])
            guard len >= 16, b.count >= len else { return nil }
            let ts = r.u32be(3)
            let date = ts == 0 ? nil : Date(timeIntervalSince1970: TimeInterval(ts))
            return .v2(
                recordedAt: date.flatMap { $0 >= earliestValidDate ? $0 : nil },
                recordingId: r.u16be(7),
                length: len,
                crcValid: v2CRCValid(Array(b[0..<len])))
        }
        return nil
    }

    /// CRC-16/XMODEM over the header with the CRC bytes (just before the final '#') set to zero.
    /// The stored CRC is read big-endian.
    static func v2CRCValid(_ header: [UInt8]) -> Bool {
        let n = header.count
        guard n >= 16, header[n - 1] == 0x23 else { return false }
        let stored = UInt16(header[n - 3]) << 8 | UInt16(header[n - 2])
        var zeroed = header
        zeroed[n - 3] = 0
        zeroed[n - 2] = 0
        return CRC16XMODEM.checksum(zeroed) == stored
    }

    /// Builds a v2 header (for tests and simulators). `extra` fills the unknown bytes.
    public static func makeV2(recordedAt: UInt32, recordingId: UInt16, extra: [UInt8] = [0, 0, 0, 0, 0, 0]) -> Data {
        var b: [UInt8] = [0x2A, 0x02, 0]
        b.appendBE(recordedAt)
        b.appendBE(recordingId)
        b += extra
        b += [0, 0, 0x23]
        b[2] = UInt8(b.count)
        let crc = CRC16XMODEM.checksum(b)
        b[b.count - 3] = UInt8(crc >> 8)
        b[b.count - 2] = UInt8(crc & 0xFF)
        return Data(b)
    }

    public static func makeV1(_ date: Date) -> Data {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        var b: [UInt8] = [0x2A, 0x53]
        b.appendBE(UInt16(c.year!))
        b += [UInt8(c.month!), UInt8(c.day!), UInt8(c.hour!), UInt8(c.minute!), UInt8(c.second!), 0x23]
        return Data(b)
    }
}

/// A synced file split into header, Opus frames, and trailer.
public struct RecordingFile: Equatable, Sendable {
    public var header: FileHeader?
    /// Whole 40-byte frames only.
    public var opusFrames: Data
    public var hadTrailer: Bool
    /// Bytes after the last whole frame that were discarded (not counting padding).
    public var discardedBytes: Int

    public var frameCount: Int { opusFrames.count / FieldyAudioFormat.frameBytes }
    public var durationSeconds: Double { FieldyAudioFormat.seconds(frames: frameCount) }

    public static let trailerLength = 10

    /// Splits raw file bytes: header, then bare frames, then an optional
    /// `'*' 'E' ... '#'` trailer followed by zero padding.
    public init(parsing data: Data) {
        let all = [UInt8](data)
        header = FileHeader.parse(data)
        var body = Array(all.dropFirst(header?.length ?? 0))
        // Look for the trailer before any zero padding in the last packet.
        var stripped = body
        while let last = stripped.last, last == 0 { stripped.removeLast() }
        hadTrailer = false
        if stripped.count >= Self.trailerLength {
            let t = stripped.count - Self.trailerLength
            if stripped[t] == 0x2A, stripped[t + 1] == 0x45, stripped[stripped.count - 1] == 0x23 {
                body = Array(stripped.prefix(t))
                hadTrailer = true
            }
        }
        // Without a trailer, keep zero bytes (a frame may end in 0x00) but drop
        // whole frames of padding at the end.
        var whole = body.count - body.count % FieldyAudioFormat.frameBytes
        if !hadTrailer {
            while whole >= FieldyAudioFormat.frameBytes,
                  body[(whole - FieldyAudioFormat.frameBytes)..<whole].allSatisfy({ $0 == 0 }) {
                whole -= FieldyAudioFormat.frameBytes
            }
        }
        discardedBytes = hadTrailer ? body.count - whole : max(0, stripped.count - whole)
        opusFrames = Data(body.prefix(whole))
    }

    /// Number of frames whose first byte is not the expected TOC.
    public var unexpectedTOCCount: Int {
        let b = [UInt8](opusFrames)
        return stride(from: 0, to: b.count, by: FieldyAudioFormat.frameBytes).filter { b[$0] != FieldyAudioFormat.toc }.count
    }
}
