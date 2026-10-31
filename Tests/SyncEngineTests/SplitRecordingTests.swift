import AudioCodec
import FieldyProtocol
import Foundation
import Library
import SyncEngine
import Testing

// Device test 2026-10-31: one 11-minute recording came off the device as two
// files. File 1 (610 s) ends with trailer stop reason 4 (file limit) at
// 14:57:02; file 2 (44 s) lost its first packet, header included, and ends at
// 14:57:46. See docs/device-tests/interrupted-sync-20261031.md.

/// Start of the owner's recording, 14:46:56Z (header of file 1).
let splitStart: UInt32 = 0x6AE5_FF60

/// A device file: v2 header unless `recordingId` is nil, `lead` bytes (the
/// tail of a frame whose start was lost), frames, trailer, padding.
func makeSplitFile(seconds: Double, start: UInt32? = nil, recordingId: UInt16? = nil, lead: Data = Data(),
                   stopReason: UInt8, endedAt: UInt32, tone: Double = 300) throws -> (file: Data, frames: Int) {
    let n = Int(seconds * 16_000)
    let pcm = (0..<n).map { Int16(9000 * sin(2 * .pi * tone * Double($0) / 16_000)) }
    let frames = try FieldyOpusEncoder().encode(pcm)
    var file = Data()
    if let recordingId { file += FileHeader.makeV2(recordedAt: start ?? 0, recordingId: recordingId) }
    file += lead
    file += frames
    file += Data([0x2A, 0x45, stopReason, UInt8(endedAt >> 24), UInt8(endedAt >> 16 & 0xFF),
                  UInt8(endedAt >> 8 & 0xFF), UInt8(endedAt & 0xFF), 0, 0, 0x23])
    file += Data(repeating: 0, count: 6)
    return (file, frames.count / 40)
}

/// The 8 bytes that start the real `00002.bin`: the end of a frame.
let lostPacketLead = Data(hex: "e4 df 8d ac 46 36 86 f2")!

/// File 1: 2 s, closed at the file limit. Its device-clock end is 2 s on.
func fileLimitHead(recordingId: UInt16 = 10, stopReason: UInt8 = 4) throws -> (file: Data, frames: Int) {
    try makeSplitFile(seconds: 2, start: splitStart, recordingId: recordingId, stopReason: stopReason, endedAt: splitStart + 2)
}

func writeRaw(_ data: Data, _ lib: LibraryStore, sync: String, _ name: String) throws -> URL {
    let dir = lib.paths.rawDirectory(syncID: sync)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent(name)
    try data.write(to: url)
    return url
}

@Suite("One recording over several files")
struct SplitRecordingTests {
    @Test func headerlessTailIsAppendedInOneSync() async throws {
        let root = tempRoot()
        let lib = try LibraryStore(paths: LibraryPaths(root: root))
        let importer = RecordingImporter(library: lib, transcriptionModel: "m")
        let (a, framesA) = try fileLimitHead()
        let (b, framesB) = try makeSplitFile(seconds: 1, lead: lostPacketLead, stopReason: 1, endedAt: splitStart + 3, tone: 500)
        let script: [FakeDevice.Step] = [.send(Data(hex: "2a 42 00 02 00 00 00 00 42 23")!)]
            + packets(fileId: 1, a, version: 2).map { .send($0) }
            + packets(fileId: 2, b, version: 2).map { .send($0) } + [.send(SyncNotification.endOfRecordsMarker)]
        let dev = FakeDevice(status: status(files: 2, bytes: a.count + b.count, version: 2), script: script)
        let s = try await SyncEngine(device: dev, importer: importer, idleTimeout: 5).sync()

        #expect(s.result == .success)
        #expect(s.rawFiles.map(\.lastPathComponent) == ["00001.bin", "00002.bin"])
        let r = try #require(s.recordings.first)
        #expect(s.recordings.count == 1)
        #expect(r.frameCount == framesA + framesB)
        #expect(abs(r.durationSeconds - 3) < 0.05)
        #expect(r.deviceRecordingId == 10)
        #expect(r.recordedAt == Date(timeIntervalSince1970: TimeInterval(splitStart)))
        #expect(try lib.recordings().map(\.id) == [r.id])
        #expect(try lib.parts(recordingId: r.id).map(\.rawPath) == ["raw/\(s.syncId)/00002.bin"])
        #expect(try lib.parts(recordingId: r.id).map(\.frameCount) == [framesB])

        let opus = try Data(contentsOf: lib.paths.absolute(try #require(r.opusPath)))
        #expect(opus.count == (framesA + framesB) * 40)
        #expect(abs(try AudioFileInfo.duration(of: lib.paths.absolute(try #require(r.audioPath))) - 3) < 0.25)
        #expect(try lib.jobs().map(\.recordingId) == [r.id])
        #expect(s.history.recordingCount == 1)
        // Both raw files count as imported.
        #expect(try importer.recoverUnimported().isEmpty)
        #expect(try lib.recordings().count == 1)
    }

    @Test func headerlessFileWithATimeGapIsItsOwnRecording() throws {
        let lib = try LibraryStore(paths: LibraryPaths(root: tempRoot()))
        let importer = RecordingImporter(library: lib, transcriptionModel: nil)
        let (a, _) = try fileLimitHead()
        // Starts 30 s after file 1 ended.
        let (b, framesB) = try makeSplitFile(seconds: 1, lead: lostPacketLead, stopReason: 1, endedAt: splitStart + 33)
        let ra = try importer.importRaw(try writeRaw(a, lib, sync: "s", "00001.bin"), syncId: "s", deviceFileId: 1,
                                        incomplete: false, syncTime: Date())
        let rb = try importer.importRaw(try writeRaw(b, lib, sync: "s", "00002.bin"), syncId: "s", deviceFileId: 2,
                                        incomplete: false, syncTime: Date())
        #expect(rb.id != ra.id)
        #expect(rb.audioState == .ok)
        #expect(rb.frameCount == framesB)
        #expect(rb.recordedAt.timeIntervalSince1970 == Double(splitStart + 33) - Double(framesB) * 0.02)
        #expect(try lib.recordings().count == 2)
        #expect(try lib.parts(recordingId: ra.id).isEmpty)
    }

    @Test func headerlessFileFromAnotherSyncIsItsOwnRecording() throws {
        let lib = try LibraryStore(paths: LibraryPaths(root: tempRoot()))
        let importer = RecordingImporter(library: lib, transcriptionModel: nil)
        let (a, _) = try fileLimitHead()
        let (b, _) = try makeSplitFile(seconds: 1, lead: lostPacketLead, stopReason: 1, endedAt: splitStart + 3)
        _ = try importer.importRaw(try writeRaw(a, lib, sync: "s1", "00001.bin"), syncId: "s1", deviceFileId: 1,
                                   incomplete: false, syncTime: Date())
        _ = try importer.importRaw(try writeRaw(b, lib, sync: "s2", "00002.bin"), syncId: "s2", deviceFileId: 2,
                                   incomplete: false, syncTime: Date())
        #expect(try lib.recordings().count == 2)
    }

    @Test func headeredFileContinuesOnlyAfterTheFileLimit() throws {
        for (reason, merged) in [(UInt8(4), true), (UInt8(1), false)] {
            let lib = try LibraryStore(paths: LibraryPaths(root: tempRoot()))
            let importer = RecordingImporter(library: lib, transcriptionModel: nil)
            let (a, framesA) = try fileLimitHead(stopReason: reason)
            let (b, framesB) = try makeSplitFile(seconds: 1, start: splitStart + 2, recordingId: 11, stopReason: 1,
                                                 endedAt: splitStart + 3)
            let ra = try importer.importRaw(try writeRaw(a, lib, sync: "s", "00001.bin"), syncId: "s", deviceFileId: 1,
                                            incomplete: false, syncTime: Date())
            let rb = try importer.importRaw(try writeRaw(b, lib, sync: "s", "00002.bin"), syncId: "s", deviceFileId: 2,
                                            incomplete: false, syncTime: Date())
            #expect((rb.id == ra.id) == merged)
            #expect(try lib.recordings().count == (merged ? 1 : 2))
            if merged { #expect(rb.frameCount == framesA + framesB) }
        }
    }

    @Test func jobQueuedAgainDuringTranscriptionStays() throws {
        let lib = try LibraryStore(paths: LibraryPaths(root: tempRoot()))
        let importer = RecordingImporter(library: lib, transcriptionModel: "faster")
        let (a, _) = try fileLimitHead()
        let (b, _) = try makeSplitFile(seconds: 1, lead: lostPacketLead, stopReason: 1, endedAt: splitStart + 3)
        let ra = try importer.importRaw(try writeRaw(a, lib, sync: "s", "00001.bin"), syncId: "s", deviceFileId: 1,
                                        incomplete: false, syncTime: Date())
        let job = try #require(try lib.jobs().first)
        try lib.markTranscribing(recordingId: ra.id)
        let later = job.enqueuedAt.addingTimeInterval(5)
        _ = try importer.importRaw(try writeRaw(b, lib, sync: "s", "00002.bin"), syncId: "s", deviceFileId: 2,
                                   incomplete: false, syncTime: Date(), now: later)
        // The 2 s transcript finishes after the append: the job for 3 s stays.
        try lib.completeTranscription(recordingId: ra.id, segments: [Segment(recordingId: ra.id, position: 0, start: 0, end: 1, text: "hi")],
                                      model: "accurate", jobEnqueuedAt: job.enqueuedAt)
        let jobs = try lib.jobs()
        #expect(jobs.map(\.recordingId) == [ra.id])
        #expect(jobs.first?.state == .waiting)
        #expect(jobs.first?.model == "faster")
        #expect(try lib.nextWaitingJob()?.recordingId == ra.id)
    }

    @Test func deletingAMergedRecordingRemovesEveryRawFile() throws {
        let lib = try LibraryStore(paths: LibraryPaths(root: tempRoot()))
        let importer = RecordingImporter(library: lib, transcriptionModel: nil)
        let (a, _) = try fileLimitHead()
        let (b, _) = try makeSplitFile(seconds: 1, lead: lostPacketLead, stopReason: 1, endedAt: splitStart + 3)
        let ua = try writeRaw(a, lib, sync: "s", "00001.bin")
        let ub = try writeRaw(b, lib, sync: "s", "00002.bin")
        let r = try importer.importRaw(ua, syncId: "s", deviceFileId: 1, incomplete: false, syncTime: Date())
        _ = try importer.importRaw(ub, syncId: "s", deviceFileId: 2, incomplete: false, syncTime: Date())
        try lib.moveToTrash(recordingId: r.id)
        #expect(try lib.purgeTrash(deletedBefore: .distantFuture).map(\.id) == [r.id])
        #expect(!FileManager.default.fileExists(atPath: ua.path))
        #expect(!FileManager.default.fileExists(atPath: ub.path))
        #expect(!FileManager.default.fileExists(atPath: ua.deletingLastPathComponent().path))
    }

    @Test func rawCleanupRemovesPartsToo() throws {
        let lib = try LibraryStore(paths: LibraryPaths(root: tempRoot()))
        let importer = RecordingImporter(library: lib, transcriptionModel: nil)
        let (a, _) = try fileLimitHead()
        let (b, _) = try makeSplitFile(seconds: 1, lead: lostPacketLead, stopReason: 1, endedAt: splitStart + 3)
        let ua = try writeRaw(a, lib, sync: "s", "00001.bin")
        let ub = try writeRaw(b, lib, sync: "s", "00002.bin")
        let t0 = Date()
        _ = try importer.importRaw(ua, syncId: "s", deviceFileId: 1, incomplete: false, syncTime: t0, now: t0)
        _ = try importer.importRaw(ub, syncId: "s", deviceFileId: 2, incomplete: false, syncTime: t0, now: t0)
        #expect(try importer.cleanupRaw(now: t0.addingTimeInterval(8 * 86_400)) == 1)
        #expect(!FileManager.default.fileExists(atPath: ub.path))
        #expect(try importer.recoverUnimported().isEmpty)
    }

    /// The owner's library after sync 8, rebuilt: the "Incomplete" copy from
    /// sync 7, file 1 complete, phantom file 10818, and file 2 unreadable (as
    /// imported before the frame-alignment fix).
    @Test func repairFixesTheLibraryLeftBySync8() throws {
        let lib = try LibraryStore(paths: LibraryPaths(root: tempRoot()))
        let importer = RecordingImporter(library: lib, transcriptionModel: "m")
        let sync7 = "20261031T150549Z-4972"
        let sync8 = "20261031T150603Z-c11b"
        let syncTime = Date(timeIntervalSince1970: 1_793_463_963)
        let (a, framesA) = try fileLimitHead()
        let (b, framesB) = try makeSplitFile(seconds: 1, lead: lostPacketLead, stopReason: 1, endedAt: splitStart + 3)

        let full = try importer.importRaw(try writeRaw(a, lib, sync: sync8, "00001.bin"), syncId: sync8, deviceFileId: 1,
                                          incomplete: false, syncTime: syncTime)
        let partURL = try writeRaw(a.prefix(a.count / 2), lib, sync: sync7, "00001.part")
        let partial = Recording(recordedAt: full.recordedAt, durationSeconds: 1, frameCount: framesA / 2, audioState: .incomplete,
                                rawPath: lib.paths.relative(partURL), syncId: sync7, deviceFileId: 1, deviceRecordingId: 10)
        let phantomURL = try writeRaw(Data(hex: "54 00 00 00 13 f9 54 00 00 00 00 00 02")!, lib, sync: sync8, "10818.bin")
        let phantom = Recording(recordedAt: syncTime, timeUnknown: true, durationSeconds: 0, frameCount: 0, audioState: .unreadable,
                                rawPath: lib.paths.relative(phantomURL), syncId: sync8, deviceFileId: 10818)
        let tailURL = try writeRaw(b, lib, sync: sync8, "00002.bin")
        let tail = Recording(recordedAt: syncTime, timeUnknown: true, durationSeconds: Double(framesB) * 0.02, frameCount: framesB,
                             audioState: .unreadable, rawPath: lib.paths.relative(tailURL), syncId: sync8, deviceFileId: 2,
                             transcriptError: "decode failed")
        for r in [partial, phantom, tail] { try lib.insert(r) }
        #expect(try lib.recordings().count == 4)

        let repair = LibraryRepair(importer: importer)
        #expect(try repair.plan() == [
            .deletePhantom(recordingId: phantom.id, rawPath: phantom.rawPath),
            .deleteSuperseded(recordingId: partial.id, rawPath: partial.rawPath, completeId: full.id),
            .reimport(recordingId: tail.id, rawPath: tail.rawPath, appendTo: full.id),
        ])
        #expect(try repair.run().count == 3)

        let left = try lib.allRecordings()
        #expect(left.map(\.id) == [full.id])
        #expect(left.first?.frameCount == framesA + framesB)
        #expect(try lib.parts(recordingId: full.id).map(\.rawPath) == [tail.rawPath])
        #expect(!FileManager.default.fileExists(atPath: partURL.path))
        #expect(!FileManager.default.fileExists(atPath: partURL.deletingLastPathComponent().path))
        #expect(!FileManager.default.fileExists(atPath: phantomURL.path))
        #expect(FileManager.default.fileExists(atPath: tailURL.path))
        #expect(try importer.recoverUnimported().isEmpty)
        #expect(try repair.plan().isEmpty)
    }
}
