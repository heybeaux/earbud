import FieldyProtocol
import Foundation
import Library
import SyncEngine
import Testing

// Device test 2026-10-31 (tasks.md 4.5): an interrupted sync left
// `00001.part`; the next sync got file 1 again whole, plus a phantom file
// 10818 (a storage status reply read as data) and file 2 without its first
// packet. See docs/device-tests/interrupted-sync-20261031.md.

/// The 20-byte status reply of that sync. Bytes 7-19 are exactly what landed
/// in `10818.bin`; bytes 0-6 are rebuilt from the status layout.
let statusReplyMidSync = Data(hex: "2a 42 00 02 00 13 f9 54 00 00 00 13 f9 54 00 00 00 00 00 02")!

func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "bin", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

@Suite("Interrupted sync (device test 4.5)")
struct InterruptedSyncTests {
    @Test func statusReplyInSyncStreamIsNotAFile() throws {
        let dir = tempRoot()
        let events = EventBox()
        let w = try DurableSyncWriter(directory: dir, transportVersion: 2) { events.add($0) }
        let (a, _) = try makeDeviceFile(seconds: 1, recordingId: 10)
        let (b, _) = try makeDeviceFile(seconds: 1, recordingId: 11)
        for p in packets(fileId: 1, a, version: 2) { w.handle(p) }
        w.handle(statusReplyMidSync)
        for p in packets(fileId: 2, b, version: 2) { w.handle(p) }
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        #expect(names == ["00001.bin", "00002.bin"])
        #expect(try Data(contentsOf: dir.appendingPathComponent("00002.bin")) == b)
        #expect(events.all.contains(.storageStatus(try StorageStatus(parsing: statusReplyMidSync))))
        #expect(w.sessionBytes == a.count + b.count)
    }

    @Test func missingPacketsAreReported() throws {
        let dir = tempRoot()
        let events = EventBox()
        let w = try DurableSyncWriter(directory: dir, transportVersion: 2) { events.add($0) }
        let (b, _) = try makeDeviceFile(seconds: 2)
        let ps = packets(fileId: 2, b, version: 2)
        // Packet 1 lost (as on device), later packet 4 too.
        for (i, p) in ps.enumerated() where i != 0 && i != 3 { w.handle(p) }
        let gaps = events.all.filter { if case .packetGap = $0 { true } else { false } }
        #expect(gaps == [.packetGap(fileId: 2, expected: 1, received: 2), .packetGap(fileId: 2, expected: 4, received: 5)])
        #expect(w.completedFiles.count == 1)
    }

    /// The real `00002.bin` of sync 8, cut to its first 2048 bytes plus its
    /// last packet (50 bytes: one frame and the trailer). It has no header:
    /// it starts 8 bytes before a frame and ends `*E` with the end time.
    @Test func headerlessDeviceFileImportsWithTrailerTime() throws {
        let data = try fixture("headerless-00002-head-tail")
        #expect(data.count == 2098)
        let file = RecordingFile(parsing: data)
        #expect(file.header == nil)
        #expect(file.skippedBytes == 8)
        #expect(file.frameCount == 52)
        #expect(file.unexpectedTOCCount == 0)
        #expect(file.trailer == FileTrailer(stopReason: 1, endedAt: Date(timeIntervalSince1970: 0x6AE6_01EA)))

        let root = tempRoot()
        let lib = try LibraryStore(paths: LibraryPaths(root: root))
        let importer = RecordingImporter(library: lib, transcriptionModel: "m")
        let url = lib.paths.rawDirectory(syncID: "20261031T150603Z-c11b").appendingPathComponent("00002.bin")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        let syncTime = Date(timeIntervalSince1970: 1_793_463_963)
        let r = try importer.importRaw(url, syncId: "20261031T150603Z-c11b", deviceFileId: 2, incomplete: false, syncTime: syncTime)
        #expect(r.audioState == .ok)
        #expect(r.transcriptError == nil)
        #expect(r.frameCount == 52)
        #expect(!r.timeUnknown)
        #expect(abs(r.recordedAt.timeIntervalSince1970 - (0x6AE6_01EA - 52 * 0.02)) < 1e-6)
        #expect(r.verifiedAt != nil)
        #expect(r.transcriptState == .waiting)
        #expect(FileManager.default.fileExists(atPath: lib.paths.absolute(try #require(r.audioPath)).path))
    }

    /// Syncs 7 and 8 replayed: the first is cut off mid-file; the device keeps
    /// the file and sends it whole the next time, with the next file after it.
    @Test func resentFileRetiresTheIncompleteCopy() async throws {
        let root = tempRoot()
        let lib = try LibraryStore(paths: LibraryPaths(root: root))
        let importer = RecordingImporter(library: lib, transcriptionModel: "m")
        let (a, framesA) = try makeDeviceFile(seconds: 2, recordedAt: 0x6AE5_FF60, recordingId: 10)
        let (b, framesB) = try makeDeviceFile(seconds: 1, recordedAt: 0x6AE6_01BE, recordingId: 11)
        let psA = packets(fileId: 1, a, version: 2)

        let first = FakeDevice(status: status(files: 2, bytes: a.count + b.count, version: 2),
                               script: psA.prefix(psA.count / 2).map { .send($0) } + [.disconnect])
        let s1 = try await SyncEngine(device: first, importer: importer, idleTimeout: 5).sync()
        #expect(s1.result == .interrupted)
        let partial = try #require(s1.recordings.first)
        #expect(partial.audioState == .incomplete)
        let partURL = lib.paths.absolute(partial.rawPath)
        #expect(partURL.pathExtension == "part")

        let script: [FakeDevice.Step] = [.send(Data(hex: "2a 42 00 02 00 00 00 00 42 23")!)]
            + psA.map { .send($0) } + [.send(statusReplyMidSync)]
            + packets(fileId: 2, b, version: 2).map { .send($0) } + [.send(SyncNotification.endOfRecordsMarker)]
        let second = FakeDevice(status: status(files: 2, bytes: a.count + b.count, version: 2), script: script)
        let s2 = try await SyncEngine(device: second, importer: importer, idleTimeout: 5).sync()
        #expect(s2.result == .success)
        #expect(s2.rawFiles.map(\.lastPathComponent) == ["00001.bin", "00002.bin"])
        #expect(s2.recordings.map(\.audioState) == [.ok, .ok])
        #expect(s2.recordings.map(\.frameCount) == [framesA, framesB])

        // The library shows the two complete recordings; the partial copy is
        // in Recently Deleted, and emptying that removes its `.part`.
        let shown = try lib.recordings()
        #expect(shown.count == 2)
        #expect(!shown.contains { $0.id == partial.id })
        #expect(try lib.recording(id: partial.id)?.deletedAt != nil)
        #expect(FileManager.default.fileExists(atPath: partURL.path))
        #expect(try lib.purgeTrash(deletedBefore: .distantFuture).map(\.id) == [partial.id])
        #expect(!FileManager.default.fileExists(atPath: partURL.path))
        #expect(try importer.recoverUnimported().isEmpty)
    }

    @Test func partialRecoveredAfterCompleteCopyGoesStraightToRecentlyDeleted() throws {
        let root = tempRoot()
        let lib = try LibraryStore(paths: LibraryPaths(root: root))
        let importer = RecordingImporter(library: lib, transcriptionModel: "m")
        let (a, _) = try makeDeviceFile(seconds: 2, recordingId: 10)
        let newer = lib.paths.rawDirectory(syncID: "20261031T150603Z-c11b")
        let older = lib.paths.rawDirectory(syncID: "20261031T150549Z-4972")
        for d in [newer, older] { try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) }
        try a.write(to: newer.appendingPathComponent("00001.bin"))
        try a.prefix(a.count / 2).write(to: older.appendingPathComponent("00001.part"))

        let complete = try importer.importRaw(newer.appendingPathComponent("00001.bin"), syncId: "20261031T150603Z-c11b",
                                              deviceFileId: 1, incomplete: false, syncTime: Date())
        let recovered = try importer.recoverUnimported()
        #expect(recovered.count == 1)
        #expect(recovered[0].audioState == .incomplete)
        #expect(recovered[0].deletedAt != nil)
        #expect(try lib.recordings().map(\.id) == [complete.id])
        #expect(try lib.jobs().map(\.recordingId) == [complete.id])
    }

    @Test func differentRecordingsAreLeftAlone() throws {
        let root = tempRoot()
        let lib = try LibraryStore(paths: LibraryPaths(root: root))
        let importer = RecordingImporter(library: lib, transcriptionModel: nil)
        let dir = lib.paths.rawDirectory(syncID: "s")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let (a, _) = try makeDeviceFile(seconds: 2, recordedAt: 1_793_391_123, recordingId: 10)
        let (b, _) = try makeDeviceFile(seconds: 2, recordedAt: 1_793_391_999, recordingId: 10)
        try a.prefix(a.count / 2).write(to: dir.appendingPathComponent("00001.part"))
        try b.write(to: dir.appendingPathComponent("00002.bin"))
        let rows = try importer.recoverUnimported()
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.deletedAt == nil })
        #expect(try lib.recordings().count == 2)
    }
}
