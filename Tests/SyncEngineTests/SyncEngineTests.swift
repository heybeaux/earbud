import AudioCodec
import FieldyDevice
import FieldyProtocol
import Foundation
import Library
import SyncEngine
import Testing

// MARK: Fixtures

func tempRoot() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("earbudkit-sync-\(UUID().uuidString)", isDirectory: true)
}

/// A synthetic device file: v2 header, real CELT frames, trailer, zero padding.
func makeDeviceFile(seconds: Double, recordedAt: UInt32 = 1_793_391_123, recordingId: UInt16 = 5) throws -> (file: Data, frames: Int) {
    let n = Int(seconds * 16_000)
    let pcm = (0..<n).map { Int16(9000 * sin(2 * .pi * 300 * Double($0) / 16_000)) }
    let frames = try FieldyOpusEncoder().encode(pcm)
    var file = FileHeader.makeV2(recordedAt: recordedAt, recordingId: recordingId)
    file += frames
    file += Data([0x2A, 0x45, 0, 0, 0, 0, 0, 0, 0, 0x23])
    file += Data(repeating: 0, count: 6)
    return (file, frames.count / 40)
}

func packets(fileId: UInt16, _ file: Data, chunk: Int = 490, version: Int) -> [Data] {
    let size = version == 1 ? 240 : chunk
    var out: [Data] = []
    var idx: UInt32 = 1
    var off = 0
    while off < file.count {
        let end = min(file.count, off + size)
        out.append(DataPacket(fileId: fileId, packetIndex: idx, payload: file[off..<end], isEndOfFile: end == file.count)
            .encoded(transportVersion: version))
        idx += 1
        off = end
    }
    return out
}

/// Scripted device. On SYNC_START it plays the script through the handler.
actor FakeDevice: SyncDevice {
    enum Step: Sendable {
        case send(Data)
        /// Wait for the engine to write this opcode, then continue.
        case awaitCommand(UInt8)
        case disconnect
    }

    var status: StorageStatus
    var script: [Step]
    var writes: [Data] = []
    /// Checked at ACK time: was the .bin already on disk with the right size?
    var ackSawDurableFile: [Bool] = []
    var rawDirectory: URL?
    private var handler: (@Sendable (Data) -> Void)?
    private var stateConts: [AsyncStream<ConnectionState>.Continuation] = []
    private var commandWaiters: [(UInt8, CheckedContinuation<Void, Never>)] = []
    var subscribeCount = 0
    var activity = 0

    init(status: StorageStatus, script: [Step]) {
        self.status = status
        self.script = script
    }

    func setRawRoot(_ url: URL) { rawDirectory = url }

    func connectForSync() async throws -> String { "Fieldy-TEST" }
    func pair() async throws -> StorageStatus { status }
    func subscribe(_ uuid: String, handler: @escaping @Sendable (Data) -> Void) async throws {
        subscribeCount += 1
        self.handler = handler
    }
    func unsubscribe(_ uuid: String) async { handler = nil }
    func beginActivity() { activity += 1 }
    func endActivity() { activity -= 1 }

    func states() -> AsyncStream<ConnectionState> {
        let (s, c) = AsyncStream<ConnectionState>.makeStream()
        c.yield(.connected(name: "Fieldy-TEST"))
        stateConts.append(c)
        return s
    }

    func write(_ data: Data, to uuid: String) async throws {
        writes.append(data)
        let op = data[data.startIndex + 2]
        if op == 0x41, let root = rawDirectory {
            let r = ByteReader(data)
            let fid = r.u16(3), count = Int(r.u32(5))
            let bin = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                .flatMap { try FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil) }
                .first { $0.lastPathComponent == String(format: "%05d.bin", fid) }
            let size = bin.flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }
            ackSawDurableFile.append(size == count)
        }
        if op == 0x53 {
            Task { await self.play() }
        }
        if let i = commandWaiters.firstIndex(where: { $0.0 == op }) {
            commandWaiters.remove(at: i).1.resume()
        } else {
            unclaimed[op, default: 0] += 1
        }
    }

    private var unclaimed: [UInt8: Int] = [:]

    private func play() async {
        while !script.isEmpty {
            let step = script.removeFirst()
            switch step {
            case .send(let d):
                handler?(d)
                await Task.yield()
            case .awaitCommand(let op):
                if let n = unclaimed[op], n > 0 {
                    unclaimed[op] = n - 1
                    continue
                }
                await withCheckedContinuation { c in commandWaiters.append((op, c)) }
            case .disconnect:
                for c in stateConts { c.yield(.notNearby) }
                return
            }
        }
    }

    var opcodes: [UInt8] { writes.map { $0[$0.startIndex + 2] } }
}

struct ByteReader {
    let b: [UInt8]
    init(_ d: Data) { b = [UInt8](d) }
    func u16(_ i: Int) -> UInt16 { UInt16(b[i]) << 8 | UInt16(b[i + 1]) }
    func u32(_ i: Int) -> UInt32 { UInt32(b[i]) << 24 | UInt32(b[i + 1]) << 16 | UInt32(b[i + 2]) << 8 | UInt32(b[i + 3]) }
}

func status(files: Int, bytes: Int, version: Int) -> StorageStatus {
    StorageStatus(totalFileCount: files, totalFileSize: bytes, syncedFileCount: 0, remainingSyncSize: bytes, maxTransportVersion: version)
}

func makeEngine(_ device: FakeDevice, root: URL, idle: TimeInterval = 5) throws -> (SyncEngine, LibraryStore) {
    let lib = try LibraryStore(paths: LibraryPaths(root: root))
    let engine = SyncEngine(device: device, importer: RecordingImporter(library: lib, transcriptionModel: "m"), idleTimeout: idle)
    return (engine, lib)
}

// MARK: Tests

@Suite("Durable writer")
struct DurableWriterTests {
    @Test func eachPacketIsOnDiskWhenHandleReturns() throws {
        let dir = tempRoot()
        let w = try DurableSyncWriter(directory: dir, transportVersion: 2) { _ in }
        let (file, _) = try makeDeviceFile(seconds: 1)
        let ps = packets(fileId: 1, file, version: 2)
        var expected = 0
        for (i, p) in ps.enumerated() {
            w.handle(p)
            if i < ps.count - 1 {
                expected += SyncNotificationPayloadLength(p)
                let part = dir.appendingPathComponent("00001.part")
                #expect(try Data(contentsOf: part).count == expected)
            }
        }
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("00001.part").path))
        #expect(try Data(contentsOf: dir.appendingPathComponent("00001.bin")) == file)
        #expect(w.completedFiles.map(\.bytes) == [file.count])
    }

    @Test func restartedFileKeepsEarlierBytesAside() throws {
        let dir = tempRoot()
        let w = try DurableSyncWriter(directory: dir, transportVersion: 3) { _ in }
        let (file, _) = try makeDeviceFile(seconds: 1)
        let ps = packets(fileId: 2, file, version: 3)
        w.handle(ps[0]); w.handle(ps[1])
        for p in ps { w.handle(p) } // device resends from packet 1
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        #expect(names == ["00002-2.bin", "00002.part.superseded"])
        #expect(try Data(contentsOf: dir.appendingPathComponent("00002-2.bin")) == file)
    }

    @Test func v1Packets() throws {
        let dir = tempRoot()
        let events = EventBox()
        let w = try DurableSyncWriter(directory: dir, transportVersion: 1) { events.add($0) }
        let (file, _) = try makeDeviceFile(seconds: 0.5)
        for p in packets(fileId: 3, file, version: 1) { w.handle(p) }
        w.handle(SyncNotification.endOfRecordsMarker)
        let bin = try Data(contentsOf: dir.appendingPathComponent("00003.bin"))
        // v1 pads the last packet to 240 bytes.
        #expect(bin.prefix(file.count) == file)
        #expect(bin.count % 240 == 0)
        #expect(events.all.last == .endOfRecords)
        #expect(RecordingFile(parsing: bin).frameCount == 25)
    }
}

func SyncNotificationPayloadLength(_ packet: Data) -> Int {
    if case .data(let p) = SyncNotification.parse(packet, transportVersion: 2) { return p.payload.count }
    return 0
}

final class EventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [SyncWriterEvent] = []
    func add(_ e: SyncWriterEvent) { lock.lock(); items.append(e); lock.unlock() }
    var all: [SyncWriterEvent] { lock.lock(); defer { lock.unlock() }; return items }
}

@Suite("Sync engine")
struct SyncEngineTests {
    @Test func v2SyncDownloadsImportsAndDoesNotAck() async throws {
        let root = tempRoot()
        let (file, frames) = try makeDeviceFile(seconds: 2)
        let script: [FakeDevice.Step] = [.send(Data([0x2A, 0x42, 0, 1, 0, 0, 0, 0, 0x42, 0x23]))]
            + packets(fileId: 1, file, version: 2).map { .send($0) } + [.send(SyncNotification.endOfRecordsMarker)]
        let dev = FakeDevice(status: status(files: 1, bytes: file.count, version: 2), script: script)
        let (engine, lib) = try makeEngine(dev, root: root)
        let summary = try await engine.sync()

        #expect(summary.result == .success)
        #expect(summary.transportVersion == 2)
        #expect(summary.bytesReceived == file.count)
        #expect(await dev.opcodes == [0x53]) // start only: no ACK on v2
        #expect(await dev.writes.first == Data(hex: "2a 42 53 02 00 00 00 00 00 23"))
        #expect(await dev.activity == 0)
        #expect(summary.rawFiles.count == 1)
        #expect(try Data(contentsOf: summary.rawFiles[0]) == file)

        let r = try #require(summary.recordings.first)
        #expect(r.audioState == .ok)
        #expect(r.frameCount == frames)
        #expect(abs(r.durationSeconds - 2.0) < 1e-9)
        #expect(r.recordedAt == Date(timeIntervalSince1970: 1_793_391_123))
        #expect(!r.timeUnknown)
        #expect(r.deviceRecordingId == 5)
        #expect(r.verifiedAt != nil)
        #expect(r.transcriptState == .waiting)
        let m4a = lib.paths.absolute(try #require(r.audioPath))
        #expect(abs(try AudioFileInfo.duration(of: m4a) - 2.0) < 0.1)
        #expect(try Data(contentsOf: lib.paths.absolute(try #require(r.opusPath))).count == frames * 40)

        let h = try #require(try lib.syncHistory().first)
        #expect(h.result == .success)
        #expect(h.recordingCount == 1)
        #expect(h.bytesReceived == file.count)
        #expect(h.deviceName == "Fieldy-TEST")
        #expect(try lib.jobs().count == 1)
    }

    @Test func v3AcksOnlyAfterFileIsDurable() async throws {
        let root = tempRoot()
        let (a, _) = try makeDeviceFile(seconds: 1, recordingId: 1)
        let (b, _) = try makeDeviceFile(seconds: 1.5, recordingId: 2)
        var script: [FakeDevice.Step] = packets(fileId: 10, a, version: 3).map { .send($0) }
        script += [.awaitCommand(0x41)]
        script += packets(fileId: 11, b, version: 3).map { .send($0) }
        script += [.awaitCommand(0x41), .send(SyncNotification.endOfRecordsMarker)]
        let dev = FakeDevice(status: status(files: 2, bytes: a.count + b.count, version: 3), script: script)
        await dev.setRawRoot(root.appendingPathComponent("raw"))
        let (engine, _) = try makeEngine(dev, root: root)
        let summary = try await engine.sync()
        #expect(summary.result == .success)
        #expect(summary.recordings.count == 2)
        #expect(await dev.opcodes == [0x53, 0x41, 0x41])
        let w = await dev.writes
        #expect(w[0] == Data(hex: "2a 42 53 03 00 00 00 00 00 23"))
        #expect(w[1] == StorageCommand.ack(fileId: 10, byteCount: UInt32(a.count)).bytes)
        #expect(w[2] == StorageCommand.ack(fileId: 11, byteCount: UInt32(b.count)).bytes)
        #expect(await dev.ackSawDurableFile == [true, true])
    }

    @Test func failedFileRetriedOnceThenDropped() async throws {
        let root = tempRoot()
        let (a, _) = try makeDeviceFile(seconds: 1)
        let failure = FileFailure(flags: 0, fsResult: 1, fileId: 4, fileSize: 9999, failureOffset: 100)
        let ps = packets(fileId: 3, a, version: 3)
        let script: [FakeDevice.Step] = [
            .send(failure.encoded), .awaitCommand(0x52),
            .send(failure.encoded), .awaitCommand(0x44),
        ] + ps.map { .send($0) } + [.awaitCommand(0x41), .send(SyncNotification.endOfRecordsMarker)]
        let dev = FakeDevice(status: status(files: 2, bytes: a.count + 9999, version: 3), script: script)
        let (engine, lib) = try makeEngine(dev, root: root)
        let summary = try await engine.sync()
        #expect(await dev.opcodes == [0x53, 0x52, 0x44, 0x41])
        let w = await dev.writes
        #expect(w[1] == StorageCommand.retry(fileId: 4, byteCount: 9999).bytes)
        #expect(w[2] == StorageCommand.drop(fileId: 4, byteCount: 9999).bytes)
        #expect(summary.droppedFiles == 1)
        #expect(summary.recordings.count == 1)
        #expect(summary.message == "1 recording on your Fieldy was damaged and couldn't be copied")
        #expect(try lib.syncHistory().first?.droppedFiles == 1)
    }

    @Test func disconnectMidFileKeepsPartAsIncomplete() async throws {
        let root = tempRoot()
        let (a, _) = try makeDeviceFile(seconds: 3)
        let ps = packets(fileId: 7, a, version: 2)
        let sent = ps.prefix(ps.count / 2)
        let dev = FakeDevice(status: status(files: 1, bytes: a.count, version: 2),
                             script: sent.map { .send($0) } + [.disconnect])
        let (engine, lib) = try makeEngine(dev, root: root)
        let summary = try await engine.sync()
        #expect(summary.result == .interrupted)
        #expect(summary.message == "Connection lost")
        #expect(summary.rawFiles.count == 1)
        #expect(summary.rawFiles[0].pathExtension == "part")
        let r = try #require(summary.recordings.first)
        #expect(r.audioState == .incomplete)
        #expect(r.durationSeconds > 1 && r.durationSeconds < 2)
        #expect(r.verifiedAt == nil)
        #expect(try lib.syncHistory().first?.result == .interrupted)
        // Recovery on the next launch does not import it twice.
        #expect(try await engine.recoverAndCleanUp().isEmpty)
    }

    @Test func silenceFromDeviceTimesOut() async throws {
        let root = tempRoot()
        let (a, _) = try makeDeviceFile(seconds: 1)
        let ps = packets(fileId: 7, a, version: 2)
        let dev = FakeDevice(status: status(files: 1, bytes: a.count, version: 2),
                             script: [.send(ps[0]), .awaitCommand(0xFF)])
        let (engine, _) = try makeEngine(dev, root: root, idle: 1.5)
        let summary = try await engine.sync()
        #expect(summary.result == .interrupted)
        #expect(summary.message?.hasPrefix("No data") == true)
        #expect(summary.recordings.first?.audioState == .incomplete)
    }

    @Test func emptyDeviceRecordsNothingNew() async throws {
        let root = tempRoot()
        let dev = FakeDevice(status: status(files: 0, bytes: 0, version: 2), script: [])
        let (engine, lib) = try makeEngine(dev, root: root)
        let summary = try await engine.sync()
        #expect(summary.result == .nothingNew)
        #expect(await dev.subscribeCount == 0)
        #expect(await dev.writes.isEmpty)
        #expect(try lib.syncHistory().first?.result == .nothingNew)
        #expect(try lib.lastSuccessfulSync() != nil)
    }

    @Test func noFilesMarkerIsNothingNew() async throws {
        let root = tempRoot()
        let dev = FakeDevice(status: status(files: 1, bytes: 10, version: 2), script: [.send(SyncNotification.noFilesMarker)])
        let (engine, _) = try makeEngine(dev, root: root)
        #expect(try await engine.sync().result == .nothingNew)
    }
}

@Suite("Import and recovery")
struct ImportTests {
    @Test func recoversPartAndUnimportedBin() throws {
        let root = tempRoot()
        let lib = try LibraryStore(paths: LibraryPaths(root: root))
        let importer = RecordingImporter(library: lib, transcriptionModel: "m")
        let dir = lib.paths.rawDirectory(syncID: "20261030T200000Z-abcd")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let (a, framesA) = try makeDeviceFile(seconds: 2)
        try a.prefix(a.count / 2 + 7).write(to: dir.appendingPathComponent("00001.part"))
        let (b, framesB) = try makeDeviceFile(seconds: 1)
        try b.write(to: dir.appendingPathComponent("00002.bin"))
        try Data([1, 2, 3]).write(to: dir.appendingPathComponent("00003.part.superseded"))

        let recovered = try importer.recoverUnimported()
        #expect(recovered.count == 2)
        let part = try #require(recovered.first { $0.rawPath.hasSuffix("00001.part") })
        #expect(part.audioState == .incomplete)
        #expect(part.frameCount < framesA && part.frameCount > framesA / 2 - 2)
        #expect(part.deviceFileId == 1)
        #expect(part.syncId == "20261030T200000Z-abcd")
        let bin = try #require(recovered.first { $0.rawPath.hasSuffix("00002.bin") })
        #expect(bin.audioState == .ok)
        #expect(bin.frameCount == framesB)
        #expect(try importer.recoverUnimported().isEmpty)
    }

    @Test func undecodableFileIsKeptAndMarkedUnreadable() throws {
        let root = tempRoot()
        let lib = try LibraryStore(paths: LibraryPaths(root: root))
        let importer = RecordingImporter(library: lib, transcriptionModel: "m")
        let url = root.appendingPathComponent("raw/s/00009.bin")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (FileHeader.makeV2(recordedAt: 1_793_391_123, recordingId: 1) + Data([0xB8, 1, 2])).write(to: url)
        let r = try importer.importRaw(url, syncId: "s", deviceFileId: 9, incomplete: false, syncTime: Date())
        #expect(r.audioState == .unreadable)
        #expect(r.audioPath == nil)
        #expect(r.transcriptState == .none)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(try lib.jobs().isEmpty)
    }

    @Test func headerWithoutTimeUsesSyncTime() throws {
        let root = tempRoot()
        let lib = try LibraryStore(paths: LibraryPaths(root: root))
        let importer = RecordingImporter(library: lib, transcriptionModel: nil)
        let (file, _) = try makeDeviceFile(seconds: 1, recordedAt: 0)
        let url = root.appendingPathComponent("raw/s/00001.bin")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try file.write(to: url)
        let syncTime = Date(timeIntervalSince1970: 1_800_000_000)
        let r = try importer.importRaw(url, syncId: "s", deviceFileId: 1, incomplete: false, syncTime: syncTime)
        #expect(r.timeUnknown)
        #expect(r.recordedAt == syncTime)
        #expect(r.transcriptState == .none) // no model: not queued
    }

    @Test func rawCleanupAfterSevenDays() throws {
        let root = tempRoot()
        let lib = try LibraryStore(paths: LibraryPaths(root: root))
        let importer = RecordingImporter(library: lib, transcriptionModel: nil)
        let (file, _) = try makeDeviceFile(seconds: 1)
        let url = root.appendingPathComponent("raw/s/00001.bin")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try file.write(to: url)
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let r = try importer.importRaw(url, syncId: "s", deviceFileId: 1, incomplete: false, syncTime: t0, now: t0)
        #expect(try importer.cleanupRaw(now: t0.addingTimeInterval(6 * 86_400)) == 0)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(try importer.cleanupRaw(now: t0.addingTimeInterval(7 * 86_400 + 1)) == 1)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(!FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
        #expect(try lib.recording(id: r.id)?.rawDeletedAt != nil)
        // The decoded audio is untouched.
        #expect(FileManager.default.fileExists(atPath: lib.paths.absolute(r.audioPath!).path))
    }
}
