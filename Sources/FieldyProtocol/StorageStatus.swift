import Foundation

/// Offline storage status, read from `...66E1` (20 bytes, big-endian).
///
/// ```
/// 0   '*' 'B'
/// 2   totalFileCount u16
/// 4   totalFileSize u32
/// 8   syncedFileCount u16
/// 10  remainingSyncSize u32
/// 14  5 bytes, unknown
/// 19  maxTransportVersion u8 (absent or 0 means 1)
/// ```
public struct StorageStatus: Equatable, Sendable {
    public var totalFileCount: Int
    public var totalFileSize: Int
    public var syncedFileCount: Int
    public var remainingSyncSize: Int
    public var maxTransportVersion: Int

    public init(totalFileCount: Int, totalFileSize: Int, syncedFileCount: Int, remainingSyncSize: Int, maxTransportVersion: Int) {
        self.totalFileCount = totalFileCount
        self.totalFileSize = totalFileSize
        self.syncedFileCount = syncedFileCount
        self.remainingSyncSize = remainingSyncSize
        self.maxTransportVersion = maxTransportVersion
    }

    public init(parsing data: Data) throws {
        let r = ByteReader(data)
        guard r.count >= 14 else {
            throw FieldyProtocolError.tooShort(record: "StorageStatus", expected: 14, actual: r.count)
        }
        guard r.u8(0) == 0x2A, r.u8(1) == 0x42 else {
            throw FieldyProtocolError.badMagic(record: "StorageStatus", bytes: Array(r.bytes.prefix(2)))
        }
        totalFileCount = Int(r.u16be(2))
        totalFileSize = Int(r.u32be(4))
        syncedFileCount = Int(r.u16be(8))
        remainingSyncSize = Int(r.u32be(10))
        let v = r.count >= 20 ? Int(r.u8(19)) : 0
        maxTransportVersion = v >= 1 ? v : 1
    }

    /// True when the device has nothing to send.
    public var isEmpty: Bool { totalFileCount == 0 && remainingSyncSize == 0 }

    /// The transport version EarBud uses: min(3, device maximum).
    public var negotiatedTransportVersion: Int { min(TransportVersion.highestSupported, maxTransportVersion) }
}

public enum TransportVersion {
    public static let highestSupported = 3
}
