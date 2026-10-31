import Foundation

/// Reset/recovery report read from `...66EE` (10 bytes).
///
/// Only bit 0 of byte 2 is understood: set means the device has a pending
/// reset event the app must acknowledge by writing `01` (the official app
/// and fieldy-local's tools do this on every connect). Byte 0 looks like a
/// record version and byte 1 like a reset cause; both are kept raw.
///
/// Observed: `01 02 01 00 01 00 00 00 00 00` (pending).
public struct ResetReport: Equatable, Sendable {
    public static let length = 10
    /// Payload that acknowledges the report.
    public static let acknowledgement = Data([0x01])

    public var version: UInt8
    public var cause: UInt8
    public var flags: UInt8
    public var raw: Data

    public init(parsing data: Data) throws {
        let r = ByteReader(data)
        guard r.count >= 3 else {
            throw FieldyProtocolError.tooShort(record: "ResetReport", expected: 3, actual: r.count)
        }
        version = r.u8(0)
        cause = r.u8(1)
        flags = r.u8(2)
        raw = Data(data)
    }

    public var needsAcknowledgement: Bool { flags & 0x01 != 0 }
}

/// Device ("profile") status notified on `...66E9` after writing `01`
/// (18 bytes). The layout is not decoded yet (protocol.md "Next steps"), so
/// this keeps the raw bytes and exposes only the length check.
public struct DeviceProfileStatus: Equatable, Sendable {
    public static let length = 18
    public static let request = Data([0x01])

    public var raw: Data

    public init(parsing data: Data) throws {
        guard data.count >= Self.length else {
            throw FieldyProtocolError.tooShort(record: "DeviceProfileStatus", expected: Self.length, actual: data.count)
        }
        raw = Data(data)
    }
}

/// Device Information Service values.
public struct DeviceInfo: Equatable, Sendable, Codable {
    public var model: String?
    public var manufacturer: String?
    public var serialNumber: String?
    public var firmware: String?
    public var hardware: String?
    public var software: String?

    public init(model: String? = nil, manufacturer: String? = nil, serialNumber: String? = nil,
                firmware: String? = nil, hardware: String? = nil, software: String? = nil) {
        self.model = model
        self.manufacturer = manufacturer
        self.serialNumber = serialNumber
        self.firmware = firmware
        self.hardware = hardware
        self.software = software
    }

    /// False when the firmware is known and differs from the one EarBud was tested on.
    public var isTestedFirmware: Bool { firmware.map { $0 == FieldyGATT.testedFirmware } ?? true }

    /// DIS strings may carry trailing NULs.
    public static func string(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\0").union(.whitespaces))
    }
}

/// Small payload codecs for the standard and control characteristics.
public enum DeviceValues {
    /// Battery Level 0x2A19: percent, uint8.
    public static func batteryPercent(_ data: Data) -> Int? { data.first.map(Int.init) }

    /// Voltage 0x2B18: uint16 little-endian millivolts.
    public static func batteryMillivolts(_ data: Data) -> Int? {
        data.count >= 2 ? Int(ByteReader(data).u16le(0)) : nil
    }

    /// Temperature 0x2A6E: sint16 little-endian, 0.01 °C.
    public static func temperatureCelsius(_ data: Data) -> Double? {
        data.count >= 2 ? Double(ByteReader(data).i16le(0)) / 100 : nil
    }

    /// One-byte boolean controls (mute, LED).
    public static func flag(_ data: Data) -> Bool? { data.first.map { $0 != 0 } }
    public static func flag(_ on: Bool) -> Data { Data([on ? 0x01 : 0x00]) }
}

/// Recording mode on `...66E8`.
public enum RecordingMode: UInt8, Sendable, Codable, CaseIterable {
    case manual = 0x00
    case automatic = 0x01

    public init?(data: Data) {
        guard let b = data.first, let m = RecordingMode(rawValue: b) else { return nil }
        self = m
    }

    public var payload: Data { Data([rawValue]) }
}

/// Control payloads.
public enum ControlCommand {
    /// `...66E7`: start recording to device storage.
    public static let startRecording = Data([0x01])
    /// `...66E7`: stop recording.
    public static let stopRecording = Data([0x00])
    /// `...66EF`: buzz (find my device).
    public static let buzz = Data([0x01, 0x04])
}
