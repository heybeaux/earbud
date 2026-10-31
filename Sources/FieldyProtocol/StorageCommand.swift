import Foundation

/// Commands written to `...66E1` (with response). Every command is 10 bytes:
/// `'*' 'B' <opcode> <6 payload bytes> '#'`.
public enum StorageCommand: Equatable, Sendable {
    /// Start a sync at the given transport version (version 1 sends all zeros).
    case syncStart(transportVersion: Int)
    /// File received (ACK). Transport v3 only.
    case ack(fileId: UInt16, byteCount: UInt32)
    /// Ask the device to resend a failed file.
    case retry(fileId: UInt16, byteCount: UInt32)
    /// Tell the device to drop a failed file.
    case drop(fileId: UInt16, byteCount: UInt32)

    public static let length = 10

    public var opcode: UInt8 {
        switch self {
        case .syncStart: 0x53 // S
        case .ack: 0x41 // A
        case .retry: 0x52 // R
        case .drop: 0x44 // D
        }
    }

    public var bytes: Data {
        var b: [UInt8] = [0x2A, 0x42, opcode]
        switch self {
        case .syncStart(let v):
            let version: UInt8 = v > 1 ? UInt8(clamping: v) : 0
            b += [version, 0, 0, 0, 0, 0]
        case .ack(let id, let n), .retry(let id, let n), .drop(let id, let n):
            b.appendBE(id)
            b.appendBE(n)
        }
        b.append(0x23) // #
        return Data(b)
    }
}
