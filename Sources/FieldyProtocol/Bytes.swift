import Foundation

/// Errors raised when a byte record does not match the expected layout.
public enum FieldyProtocolError: Error, Equatable, Sendable {
    case tooShort(record: String, expected: Int, actual: Int)
    case badMagic(record: String, bytes: [UInt8])
    case invalidValue(record: String, detail: String)
}

/// Fixed-width integer reads over a byte array. Offsets are absolute.
/// Callers check the length first; these read zero for out-of-range bytes.
struct ByteReader {
    let bytes: [UInt8]

    init(_ data: Data) { bytes = [UInt8](data) }
    init(_ bytes: [UInt8]) { self.bytes = bytes }

    var count: Int { bytes.count }

    func u8(_ at: Int) -> UInt8 { at < bytes.count ? bytes[at] : 0 }

    func u16be(_ at: Int) -> UInt16 { UInt16(u8(at)) << 8 | UInt16(u8(at + 1)) }
    func u32be(_ at: Int) -> UInt32 {
        UInt32(u8(at)) << 24 | UInt32(u8(at + 1)) << 16 | UInt32(u8(at + 2)) << 8 | UInt32(u8(at + 3))
    }

    func u16le(_ at: Int) -> UInt16 { UInt16(u8(at)) | UInt16(u8(at + 1)) << 8 }
    func u32le(_ at: Int) -> UInt32 {
        UInt32(u8(at)) | UInt32(u8(at + 1)) << 8 | UInt32(u8(at + 2)) << 16 | UInt32(u8(at + 3)) << 24
    }
    func i16le(_ at: Int) -> Int16 { Int16(bitPattern: u16le(at)) }
}

extension Array where Element == UInt8 {
    mutating func appendBE(_ v: UInt16) { append(UInt8(v >> 8)); append(UInt8(v & 0xFF)) }
    mutating func appendBE(_ v: UInt32) {
        append(UInt8(v >> 24)); append(UInt8(v >> 16 & 0xFF)); append(UInt8(v >> 8 & 0xFF)); append(UInt8(v & 0xFF))
    }
}

extension Data {
    /// Space-separated lowercase hex, for logs and error messages.
    public var hexString: String { map { String(format: "%02x", $0) }.joined(separator: " ") }

    /// Parses "2a 42 00 ..." or "2a4200..." into bytes. Returns nil on bad input.
    public init?(hex: String) {
        let clean = hex.filter { !$0.isWhitespace }
        guard clean.count % 2 == 0 else { return nil }
        var out = [UInt8]()
        out.reserveCapacity(clean.count / 2)
        var idx = clean.startIndex
        while idx < clean.endIndex {
            let next = clean.index(idx, offsetBy: 2)
            guard let b = UInt8(clean[idx..<next], radix: 16) else { return nil }
            out.append(b)
            idx = next
        }
        self.init(out)
    }
}

/// CRC-16/XMODEM: poly 0x1021, init 0x0000, no reflection, no final XOR.
public enum CRC16XMODEM {
    public static func checksum<S: Sequence>(_ bytes: S) -> UInt16 where S.Element == UInt8 {
        var crc: UInt16 = 0
        for byte in bytes {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : crc << 1
            }
        }
        return crc
    }
}
