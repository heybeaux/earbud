import Foundation
import Testing
@testable import FieldyProtocol

private func hex(_ s: String) -> Data { Data(hex: s)! }

@Suite("Storage status")
struct StorageStatusTests {
    @Test func realStatusOneFile() throws {
        // Captured from the device: 1 file, 60426 bytes, transport v2.
        let s = try StorageStatus(parsing: hex("2a 42 00 01 00 00 ec 0a 00 00 00 00 ec 0a 00 00 00 00 00 02"))
        #expect(s.totalFileCount == 1)
        #expect(s.totalFileSize == 60426)
        #expect(s.syncedFileCount == 0)
        #expect(s.remainingSyncSize == 60426)
        #expect(s.maxTransportVersion == 2)
        #expect(s.negotiatedTransportVersion == 2)
        #expect(!s.isEmpty)
    }

    @Test func realEmptyStatus() throws {
        let s = try StorageStatus(parsing: hex("2a 42 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 02"))
        #expect(s.isEmpty)
        #expect(s.maxTransportVersion == 2)
    }

    @Test func missingVersionMeansOne() throws {
        let s = try StorageStatus(parsing: hex("2a 42 00 02 00 00 01 00 00 00 00 00 01 00"))
        #expect(s.totalFileCount == 2)
        #expect(s.totalFileSize == 256)
        #expect(s.maxTransportVersion == 1)
        let zero = try StorageStatus(parsing: hex("2a 42 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00"))
        #expect(zero.maxTransportVersion == 1)
    }

    @Test func negotiatesAtMostThree() throws {
        let s = try StorageStatus(parsing: hex("2a 42 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 05"))
        #expect(s.maxTransportVersion == 5)
        #expect(s.negotiatedTransportVersion == 3)
    }

    @Test func rejectsBadInput() {
        #expect(throws: FieldyProtocolError.self) { try StorageStatus(parsing: hex("2a 42 00")) }
        #expect(throws: FieldyProtocolError.self) {
            try StorageStatus(parsing: hex("00 00 00 01 00 00 ec 0a 00 00 00 00 ec 0a 00 00 00 00 00 02"))
        }
    }
}

@Suite("Recording status")
struct RecordingStatusTests {
    @Test func observedRecords() throws {
        let start = try RecordingStatus(parsing: hex("01 01 01 0d 00 00 00 0a f0 e4 6a"))
        #expect(start.version == 1)
        #expect(start.state == .starting)
        #expect(start.source == .phone)
        #expect(start.recordingId == 13)
        #expect(start.stopReason == RecordingStatus.StopReason.none)
        #expect(start.errorReason == RecordingStatus.ErrorReason.none)
        #expect(start.timestamp == 0x6AE4_F00A)
        #expect(start.isRecording)

        let streaming = try RecordingStatus(parsing: hex("01 02 01 0d 00 00 00 0a f0 e4 6a"))
        #expect(streaming.state == .active)

        let stopping = try RecordingStatus(parsing: hex("01 03 01 0d 00 01 00 17 f0 e4 6a"))
        #expect(stopping.state == .stopping)
        #expect(stopping.stopReason == .manual)
        #expect(stopping.timestamp - start.timestamp == 13)

        let idle = try RecordingStatus(parsing: hex("01 00 02 11 00 01 00 d7 f2 e4 6a"))
        #expect(idle.state == .stopped)
        #expect(idle.source == .button)
        #expect(idle.recordingId == 17)
        #expect(!idle.isRecording)
    }

    @Test func errorStates() throws {
        let timeNotSet = try RecordingStatus(parsing: hex("01 04 00 00 00 00 01 00 00 00 00"))
        #expect(timeNotSet.state == .error)
        #expect(timeNotSet.errorReason == .timeNotSet)
        let muted = try RecordingStatus(parsing: hex("01 04 01 00 00 00 04 00 00 00 00"))
        #expect(muted.errorReason == .muted)
        let odd = try RecordingStatus(parsing: hex("01 09 07 00 00 0b 0a 00 00 00 00"))
        #expect(odd.state == .unknown(9))
        #expect(odd.source == .unknown(7))
        #expect(odd.stopReason == .unknown(11))
        #expect(odd.errorReason == .unknown(10))
        let armed = try RecordingStatus(parsing: hex("01 05 03 01 01 0a 09 00 00 00 00"))
        #expect(armed.state == .armed)
        #expect(armed.source == .system)
        #expect(armed.recordingId == 0x0101)
        #expect(armed.stopReason == .sleepMode)
        #expect(armed.errorReason == .fileIdLimit)
    }

    @Test func tooShort() {
        #expect(throws: FieldyProtocolError.self) { try RecordingStatus(parsing: hex("01 02 01")) }
    }
}

@Suite("Reset report and device records")
struct DeviceRecordTests {
    @Test func realResetReport() throws {
        let r = try ResetReport(parsing: hex("01 02 01 00 01 00 00 00 00 00"))
        #expect(r.version == 1)
        #expect(r.cause == 2)
        #expect(r.needsAcknowledgement)
        #expect(ResetReport.acknowledgement == hex("01"))
        let acked = try ResetReport(parsing: hex("01 02 00 00 01 00 00 00 00 00"))
        #expect(!acked.needsAcknowledgement)
    }

    @Test func profileStatusKeepsRaw() throws {
        let raw = Data((0..<18).map { UInt8($0) })
        #expect(try DeviceProfileStatus(parsing: raw).raw == raw)
        #expect(throws: FieldyProtocolError.self) { try DeviceProfileStatus(parsing: Data([1, 2])) }
    }

    @Test func standardValues() {
        #expect(DeviceValues.batteryPercent(hex("57")) == 87)
        #expect(DeviceValues.batteryMillivolts(hex("20 0f")) == 3872)
        #expect(DeviceValues.temperatureCelsius(hex("c4 09")) == 25.0)
        #expect(DeviceValues.temperatureCelsius(hex("38 ff")) == -2.0)
        #expect(DeviceValues.flag(hex("01")) == true)
        #expect(DeviceValues.flag(hex("00")) == false)
        #expect(DeviceValues.flag(true) == hex("01"))
        #expect(RecordingMode(data: hex("01")) == .automatic)
        #expect(RecordingMode(data: hex("00")) == .manual)
        #expect(RecordingMode(data: hex("07")) == nil)
        #expect(DeviceInfo.string(Data("3.3.5\0".utf8)) == "3.3.5")
        #expect(DeviceInfo(firmware: "3.3.5").isTestedFirmware)
        #expect(!DeviceInfo(firmware: "3.4.0").isTestedFirmware)
    }

    @Test func controlPayloads() {
        #expect(ControlCommand.buzz == hex("01 04"))
        #expect(ControlCommand.startRecording == hex("01"))
        #expect(ControlCommand.stopRecording == hex("00"))
    }
}

@Suite("Commands")
struct CommandTests {
    @Test func syncStartV2MatchesCapture() {
        #expect(StorageCommand.syncStart(transportVersion: 2).bytes == hex("2a 42 53 02 00 00 00 00 00 23"))
    }

    @Test func syncStartV1AndV3() {
        #expect(StorageCommand.syncStart(transportVersion: 1).bytes == hex("2a 42 53 00 00 00 00 00 00 23"))
        #expect(StorageCommand.syncStart(transportVersion: 3).bytes == hex("2a 42 53 03 00 00 00 00 00 23"))
    }

    @Test func ackRetryDrop() {
        #expect(StorageCommand.ack(fileId: 0x0102, byteCount: 60426).bytes == hex("2a 42 41 01 02 00 00 ec 0a 23"))
        #expect(StorageCommand.retry(fileId: 7, byteCount: 1).bytes == hex("2a 42 52 00 07 00 00 00 01 23"))
        #expect(StorageCommand.drop(fileId: 0xFFFF, byteCount: 0xDEADBEEF).bytes == hex("2a 42 44 ff ff de ad be ef 23"))
        for c in [StorageCommand.syncStart(transportVersion: 2), .ack(fileId: 1, byteCount: 2)] {
            #expect(c.bytes.count == StorageCommand.length)
        }
    }

    @Test func clockPayload() throws {
        // 2026-10-30 20:12:03 UTC is a Friday (weekday 5 with Mon=1).
        let date = Date(timeIntervalSince1970: 1_793_391_123)
        let payload = ClockPayload.make(date)
        #expect(payload == hex("07 ea 0a 1e 14 0c 03 05"))
        #expect(ClockPayload.parse(payload) == date)
        // Sunday maps to 7.
        let sunday = Date(timeIntervalSince1970: 1_793_563_200) // 2026-11-01 20:00:00 UTC
        #expect(ClockPayload.make(sunday).last == 7)
        // Monday maps to 1.
        #expect(ClockPayload.make(sunday.addingTimeInterval(86_400)).last == 1)
        #expect(ClockPayload.parse(hex("00 00 00 00 00 00 00 00")) == nil)
    }
}

@Suite("Sync notifications")
struct SyncNotificationTests {
    @Test func markers() {
        #expect(SyncNotification.parse(Data("*BENDOFREC".utf8), transportVersion: 2) == .endOfRecords)
        #expect(SyncNotification.parse(Data("*BNOFILES#".utf8), transportVersion: 2) == .noFiles)
        #expect(SyncNotification.parse(Data("*BNOFILES#".utf8), transportVersion: 1) == .noFiles)
    }

    @Test func transferHeader() {
        let h = hex("2a 42 00 03 00 00 00 00 42 23")
        #expect(SyncNotification.parse(h, transportVersion: 2) == .transferHeader(fileCount: 3))
    }

    @Test func fileFailed() {
        let f = FileFailure(flags: 1, fsResult: 0xFB, fileId: 9, fileSize: 60426, failureOffset: 4096)
        let bytes = f.encoded
        #expect(bytes == hex("2a 42 46 01 fb 00 09 00 00 ec 0a 00 00 10 00 23"))
        #expect(SyncNotification.parse(bytes, transportVersion: 3) == .fileFailed(f))
    }

    @Test func v2DataPacket() {
        let raw = hex("00 01 00 01 00 05 00 b8 01 02 03 04")
        #expect(SyncNotification.parse(raw, transportVersion: 2) == .data(DataPacket(
            fileId: 1, packetIndex: 1, payload: hex("b8 01 02 03 04"), isEndOfFile: false)))
        let eof = hex("00 01 00 02 00 02 01 aa bb 00 00")
        guard case .data(let p) = SyncNotification.parse(eof, transportVersion: 2) else {
            Issue.record("expected data"); return
        }
        #expect(p.isEndOfFile)
        #expect(p.packetIndex == 2)
        #expect(p.payload == hex("aa bb"))
    }

    @Test func v3DataPacketSameLayout() {
        let p = DataPacket(fileId: 0x1234, packetIndex: 300, payload: Data(repeating: 0xB8, count: 480), isEndOfFile: true)
        let raw = p.encoded(transportVersion: 3)
        #expect(raw.count == 487)
        #expect(SyncNotification.parse(raw, transportVersion: 3) == .data(p))
    }

    @Test func v2LengthLongerThanPacketIsClamped() {
        let raw = hex("00 01 00 01 00 ff 00 b8 01")
        guard case .data(let p) = SyncNotification.parse(raw, transportVersion: 2) else {
            Issue.record("expected data"); return
        }
        #expect(p.payload == hex("b8 01"))
    }

    @Test func v1DataPacket() {
        let payload = Data((0..<240).map { UInt8($0 & 0xFF) })
        let p = DataPacket(fileId: 2, packetIndex: 70_000, payload: payload, isEndOfFile: true)
        let raw = p.encoded(transportVersion: 1)
        #expect(raw.count == 247)
        #expect(SyncNotification.parse(raw, transportVersion: 1) == .data(p))
        var notEOF = [UInt8](raw); notEOF[246] = 0
        guard case .data(let q) = SyncNotification.parse(Data(notEOF), transportVersion: 1) else {
            Issue.record("expected data"); return
        }
        #expect(!q.isEndOfFile)
    }

    @Test func shortPacketsUnrecognized() {
        #expect(SyncNotification.parse(hex("00 01 00"), transportVersion: 2) == .unrecognized(hex("00 01 00")))
        let short = Data(repeating: 1, count: 100)
        #expect(SyncNotification.parse(short, transportVersion: 1) == .unrecognized(short))
    }
}

@Suite("File layout")
struct FileLayoutTests {
    static let frame = Data([0xB8] + [UInt8](repeating: 0x11, count: 39))

    @Test func crcXmodemCheckValue() {
        // Standard check value for CRC-16/XMODEM over "123456789".
        #expect(CRC16XMODEM.checksum(Array("123456789".utf8)) == 0x31C3)
    }

    @Test func v2HeaderWithValidCRC() throws {
        let header = FileHeader.makeV2(recordedAt: 1_793_391_123, recordingId: 42)
        #expect(header.count == 18)
        guard case .v2(let date, let id, let len, let ok)? = FileHeader.parse(header) else {
            Issue.record("expected v2 header"); return
        }
        #expect(date == Date(timeIntervalSince1970: 1_793_391_123))
        #expect(id == 42)
        #expect(len == 18)
        #expect(ok)
    }

    @Test func v2HeaderBadCRCDetected() {
        var b = [UInt8](FileHeader.makeV2(recordedAt: 1_793_391_123, recordingId: 42))
        b[5] ^= 0xFF
        guard case .v2(_, _, _, let ok)? = FileHeader.parse(Data(b)) else {
            Issue.record("expected v2 header"); return
        }
        #expect(!ok)
    }

    @Test func v2HeaderZeroTimeIsUnknown() {
        let header = FileHeader.makeV2(recordedAt: 0, recordingId: 1)
        #expect(FileHeader.parse(header)?.recordedAt == nil)
        let old = FileHeader.makeV2(recordedAt: 1000, recordingId: 1)
        #expect(FileHeader.parse(old)?.recordedAt == nil)
    }

    @Test func v1Header() {
        let date = Date(timeIntervalSince1970: 1_793_391_123)
        let header = FileHeader.makeV1(date)
        #expect(header == hex("2a 53 07 ea 0a 1e 14 0c 03 23"))
        #expect(FileHeader.parse(header) == .v1(recordedAt: date))
        #expect(FileHeader.parse(hex("2a 53 07 ea 0d 1e 14 0c 03 23")) == .v1(recordedAt: nil))
    }

    @Test func splitV2FileWithTrailerAndPadding() {
        var file = FileHeader.makeV2(recordedAt: 1_793_391_123, recordingId: 7)
        for _ in 0..<3 { file += Self.frame }
        file += hex("2a 45 00 00 00 03 00 00 00 23")
        file += Data(repeating: 0, count: 25)
        let f = RecordingFile(parsing: file)
        #expect(f.header?.recordingId == 7)
        #expect(f.frameCount == 3)
        #expect(f.hadTrailer)
        #expect(f.discardedBytes == 0)
        #expect(f.unexpectedTOCCount == 0)
        #expect(abs(f.durationSeconds - 0.06) < 1e-9)
    }

    @Test func splitWithoutTrailerKeepsFramesEndingInZero() {
        var file = FileHeader.makeV1(Date(timeIntervalSince1970: 1_793_391_123))
        let zeroEnding = Data([0xB8] + [UInt8](repeating: 0, count: 39))
        file += Self.frame + zeroEnding
        file += Data(repeating: 0, count: 80) // two frames of padding
        let f = RecordingFile(parsing: file)
        // The two all-zero padding frames are dropped; the frame that merely ends in zeros is kept.
        #expect(f.frameCount == 2)
        #expect(f.opusFrames.suffix(40) == zeroEnding)
        #expect(!f.hadTrailer)
    }

    @Test func splitPartialFrameDiscarded() {
        var file = FileHeader.makeV2(recordedAt: 1_793_391_123, recordingId: 1)
        file += Self.frame + Self.frame + Data([0xB8, 1, 2, 3, 4])
        let f = RecordingFile(parsing: file)
        #expect(f.frameCount == 2)
        #expect(f.discardedBytes == 5)
    }

    @Test func noHeader() {
        let f = RecordingFile(parsing: Self.frame + Self.frame)
        #expect(f.header == nil)
        #expect(f.frameCount == 2)
    }

    @Test func badTOCCounted() {
        let bad = Data([0x00] + [UInt8](repeating: 1, count: 39))
        let f = RecordingFile(parsing: Self.frame + bad)
        #expect(f.unexpectedTOCCount == 1)
    }
}
