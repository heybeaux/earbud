import Foundation

/// One data packet of a file being synced.
public struct DataPacket: Equatable, Sendable {
    public var fileId: UInt16
    /// Starts at 1 for each file.
    public var packetIndex: UInt32
    public var payload: Data
    public var isEndOfFile: Bool

    public init(fileId: UInt16, packetIndex: UInt32, payload: Data, isEndOfFile: Bool) {
        self.fileId = fileId
        self.packetIndex = packetIndex
        self.payload = payload
        self.isEndOfFile = isEndOfFile
    }

    /// Builds the on-air bytes (for tests and simulators).
    public func encoded(transportVersion: Int) -> Data {
        var b = [UInt8]()
        b.appendBE(fileId)
        if transportVersion == 1 {
            b.appendBE(packetIndex)
            var p = [UInt8](payload.prefix(SyncNotification.v1PayloadLength))
            p += [UInt8](repeating: 0, count: SyncNotification.v1PayloadLength - p.count)
            b += p
            b.append(isEndOfFile ? 1 : 0)
        } else {
            b.appendBE(UInt16(truncatingIfNeeded: packetIndex))
            b.appendBE(UInt16(payload.count))
            b.append(isEndOfFile ? 0x01 : 0x00)
            b += payload
        }
        return Data(b)
    }
}

/// FILE_FAILED report (16 bytes, transport v3):
/// `'*' 'B' 'F' flags u8, fsResult u8, fileId u16, fileSize u32, failureOffset u32, '#'`.
public struct FileFailure: Equatable, Sendable {
    public var flags: UInt8
    public var fsResult: UInt8
    public var fileId: UInt16
    public var fileSize: UInt32
    public var failureOffset: UInt32

    public init(flags: UInt8, fsResult: UInt8, fileId: UInt16, fileSize: UInt32, failureOffset: UInt32) {
        self.flags = flags
        self.fsResult = fsResult
        self.fileId = fileId
        self.fileSize = fileSize
        self.failureOffset = failureOffset
    }

    public var encoded: Data {
        var b: [UInt8] = [0x2A, 0x42, 0x46, flags, fsResult]
        b.appendBE(fileId)
        b.appendBE(fileSize)
        b.appendBE(failureOffset)
        b.append(0x23)
        return Data(b)
    }
}

/// A notification received on `...66E1` during a sync.
public enum SyncNotification: Equatable, Sendable {
    /// `*BENDOFREC`: all files sent.
    case endOfRecords
    /// `*BNOFILES#`: nothing to send.
    case noFiles
    /// Transfer header: `'*' 'B' fileCount u16 ... 'B' '#'`.
    case transferHeader(fileCount: Int)
    case fileFailed(FileFailure)
    /// The 20-byte storage status record. It is never sent as a notification
    /// during a sync, but CoreBluetooth delivers the reply to a read of
    /// `...66E1` through the same callback as notifications, so a status read
    /// made mid-sync arrives here.
    case storageStatus(StorageStatus)
    case data(DataPacket)
    /// Too short or otherwise not understood. Kept so callers can log it.
    case unrecognized(Data)

    public static let endOfRecordsMarker = Data("*BENDOFREC".utf8)
    public static let noFilesMarker = Data("*BNOFILES#".utf8)
    public static let v1PacketLength = 247
    public static let v1PayloadLength = 240
    public static let v2HeaderLength = 7

    public static func parse(_ data: Data, transportVersion: Int) -> SyncNotification {
        let b = [UInt8](data)
        if b == [UInt8](endOfRecordsMarker) { return .endOfRecords }
        if b == [UInt8](noFilesMarker) { return .noFiles }
        let r = ByteReader(b)
        if b.count == 10, b[0] == 0x2A, b[1] == 0x42, b[8] == 0x42, b[9] == 0x23 {
            return .transferHeader(fileCount: Int(r.u16be(2)))
        }
        if b.count == 16, b[0] == 0x2A, b[1] == 0x42, b[2] == 0x46, b[15] == 0x23 {
            return .fileFailed(FileFailure(
                flags: b[3], fsResult: b[4], fileId: r.u16be(5), fileSize: r.u32be(7), failureOffset: r.u32be(11)))
        }
        // Every control and status record starts with '*' 'B'. Anything else
        // with that prefix is not file data either: read as a data packet it
        // would be file 0x2A42 (10818), far above any real file ID, and the
        // status record's size bytes even set the end-of-file flag.
        if b.count >= 2, b[0] == 0x2A, b[1] == 0x42 {
            if b.count == 20, let s = try? StorageStatus(parsing: data) { return .storageStatus(s) }
            return .unrecognized(Data(b))
        }
        if transportVersion <= 1 {
            guard b.count >= v1PacketLength else { return .unrecognized(Data(b)) }
            return .data(DataPacket(
                fileId: r.u16be(0), packetIndex: r.u32be(2),
                payload: Data(b[6..<246]), isEndOfFile: b[246] == 1))
        }
        guard b.count >= v2HeaderLength else { return .unrecognized(Data(b)) }
        let length = Int(r.u16be(4))
        let end = min(b.count, v2HeaderLength + length)
        return .data(DataPacket(
            fileId: r.u16be(0), packetIndex: UInt32(r.u16be(2)),
            payload: Data(b[v2HeaderLength..<end]), isEndOfFile: b[6] & 0x01 != 0))
    }
}
