import Foundation

/// Recording status notified/read on `...66E7` (11 bytes, little-endian).
///
/// ```
/// 0  version u8
/// 1  state u8
/// 2  source u8
/// 3  recordingId u16
/// 5  stopReason u8
/// 6  errorReason u8
/// 7  timestamp u32 (seconds, device local time)
/// ```
public struct RecordingStatus: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case stopped, starting, active, stopping, error, armed
        case unknown(UInt8)

        init(_ raw: UInt8) {
            switch raw {
            case 0: self = .stopped
            case 1: self = .starting
            case 2: self = .active
            case 3: self = .stopping
            case 4: self = .error
            case 5: self = .armed
            default: self = .unknown(raw)
            }
        }
    }

    public enum Source: Equatable, Sendable {
        case none, phone, button, system
        case unknown(UInt8)

        init(_ raw: UInt8) {
            switch raw {
            case 0: self = .none
            case 1: self = .phone
            case 2: self = .button
            case 3: self = .system
            default: self = .unknown(raw)
            }
        }
    }

    public enum StopReason: Equatable, Sendable {
        case none, manual, timeout, storageFull, fileLimit, internalError, realtimeHandoff, silence, lowBattery, watchdogReset, sleepMode
        case unknown(UInt8)

        init(_ raw: UInt8) {
            switch raw {
            case 0: self = .none
            case 1: self = .manual
            case 2: self = .timeout
            case 3: self = .storageFull
            case 4: self = .fileLimit
            case 5: self = .internalError
            case 6: self = .realtimeHandoff
            case 7: self = .silence
            case 8: self = .lowBattery
            case 9: self = .watchdogReset
            case 10: self = .sleepMode
            default: self = .unknown(raw)
            }
        }
    }

    public enum ErrorReason: Equatable, Sendable {
        case none, timeNotSet, storageFull, fileCountLimit, muted, busy, invalidRequest, otaInProgress, commandModeActive, fileIdLimit
        case unknown(UInt8)

        init(_ raw: UInt8) {
            switch raw {
            case 0: self = .none
            case 1: self = .timeNotSet
            case 2: self = .storageFull
            case 3: self = .fileCountLimit
            case 4: self = .muted
            case 5: self = .busy
            case 6: self = .invalidRequest
            case 7: self = .otaInProgress
            case 8: self = .commandModeActive
            case 9: self = .fileIdLimit
            default: self = .unknown(raw)
            }
        }
    }

    public static let length = 11

    public var version: UInt8
    public var state: State
    public var source: Source
    public var recordingId: UInt16
    public var stopReason: StopReason
    public var errorReason: ErrorReason
    /// Seconds; observed to be device local time rather than UTC.
    public var timestamp: UInt32
    public var raw: Data

    public init(parsing data: Data) throws {
        let r = ByteReader(data)
        guard r.count >= Self.length else {
            throw FieldyProtocolError.tooShort(record: "RecordingStatus", expected: Self.length, actual: r.count)
        }
        version = r.u8(0)
        state = State(r.u8(1))
        source = Source(r.u8(2))
        recordingId = r.u16le(3)
        stopReason = StopReason(r.u8(5))
        errorReason = ErrorReason(r.u8(6))
        timestamp = r.u32le(7)
        raw = Data(data)
    }

    /// True while the device is recording or about to.
    public var isRecording: Bool {
        switch state {
        case .starting, .active: true
        default: false
        }
    }

    public var summary: String {
        "state=\(state) source=\(source) recId=\(recordingId) stop=\(stopReason) error=\(errorReason) ts=\(timestamp)"
    }
}
