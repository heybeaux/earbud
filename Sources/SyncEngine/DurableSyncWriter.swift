import FieldyProtocol
import Foundation

/// What the writer reports while a sync runs. Emitted after the bytes
/// concerned are on disk.
public enum SyncWriterEvent: Sendable, Equatable {
    case transferHeader(fileCount: Int)
    case fileStarted(fileId: UInt16, url: URL)
    /// Bytes of payload made durable so far: this file and the whole session.
    case bytes(fileId: UInt16, fileBytes: Int, sessionBytes: Int)
    /// `.part` renamed to `.bin` after a full flush. Safe to ACK.
    case fileCompleted(fileId: UInt16, url: URL, byteCount: Int)
    case fileFailed(FileFailure)
    /// A storage status record reached the sync handler (the reply to a
    /// status read made during the sync). Not file data; nothing is written.
    case storageStatus(StorageStatus)
    /// A packet index was not the one expected: packets `expected..<received`
    /// of this file never arrived, so the file has a hole.
    case packetGap(fileId: UInt16, expected: UInt32, received: UInt32)
    case endOfRecords
    case noFiles
    case unrecognized(Data)
    /// Writing to disk failed. The sync must stop.
    case writeFailed(fileId: UInt16, message: String)
}

/// Writes each synced packet to `raw/<syncID>/<fileID>.part` and flushes it
/// (`FileHandle.synchronize()`) before returning, so the bytes are on disk
/// before the next notification is processed. The device deletes a file once
/// it has sent it, so nothing else may come first.
///
/// `handle(_:)` is called synchronously from the Bluetooth notification
/// callback. A lock makes the class safe to touch from other threads
/// (`closeOpenFiles`, `lastPacketAt`).
public final class DurableSyncWriter: @unchecked Sendable {
    public let directory: URL
    public let transportVersion: Int
    private let onEvent: @Sendable (SyncWriterEvent) -> Void

    private let lock = NSLock()
    private var open: [UInt16: OpenFile] = [:]
    private var _sessionBytes = 0
    private var _lastPacketAt = Date()
    private var _completed: [(fileId: UInt16, url: URL, bytes: Int)] = []
    private var superseded: [UInt16: [URL]] = [:]

    private struct OpenFile {
        var handle: FileHandle
        var url: URL
        var bytes: Int
        var lastIndex: UInt32
    }

    public init(directory: URL, transportVersion: Int, onEvent: @escaping @Sendable (SyncWriterEvent) -> Void) throws {
        self.directory = directory
        self.transportVersion = transportVersion
        self.onEvent = onEvent
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public var sessionBytes: Int { lock.withLock { _sessionBytes } }
    public var lastPacketAt: Date { lock.withLock { _lastPacketAt } }
    public var completedFiles: [(fileId: UInt16, url: URL, bytes: Int)] { lock.withLock { _completed } }

    /// Handles one notification from `...66E1`.
    public func handle(_ data: Data) {
        let events: [SyncWriterEvent] = lock.withLock {
            _lastPacketAt = Date()
            switch SyncNotification.parse(data, transportVersion: transportVersion) {
            case .endOfRecords: return [.endOfRecords]
            case .noFiles: return [.noFiles]
            case .transferHeader(let n): return [.transferHeader(fileCount: n)]
            case .fileFailed(let f): return [.fileFailed(f)]
            case .storageStatus(let s): return [.storageStatus(s)]
            case .unrecognized(let d): return [.unrecognized(d)]
            case .data(let packet): return write(packet)
            }
        }
        for e in events { onEvent(e) }
    }

    /// Called with the lock held.
    private func write(_ packet: DataPacket) -> [SyncWriterEvent] {
        var events: [SyncWriterEvent] = []
        let fid = packet.fileId
        do {
            // A packet index of 1 for a file that is already open means the
            // device restarted it (after a retry). Keep the old bytes aside.
            if packet.packetIndex <= 1, let existing = open[fid], existing.bytes > 0 {
                try existing.handle.synchronize()
                try existing.handle.close()
                open[fid] = nil
                superseded[fid, default: []].append(existing.url)
            }
            if open[fid] == nil {
                let url = nextPartURL(fileId: fid)
                guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                    throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
                }
                open[fid] = OpenFile(handle: try FileHandle(forWritingTo: url), url: url, bytes: 0, lastIndex: 0)
                try Self.syncDirectory(directory)
                events.append(.fileStarted(fileId: fid, url: url))
            }
            var file = open[fid]!
            // v2/v3 indexes are u16 on the air; compare in that width.
            let expected = file.lastIndex &+ 1
            let matches = transportVersion <= 1
                ? packet.packetIndex == expected
                : UInt16(truncatingIfNeeded: packet.packetIndex) == UInt16(truncatingIfNeeded: expected)
            if !matches {
                events.append(.packetGap(fileId: fid, expected: expected, received: packet.packetIndex))
            }
            if !packet.payload.isEmpty {
                try file.handle.write(contentsOf: packet.payload)
                try file.handle.synchronize()
            }
            file.bytes += packet.payload.count
            file.lastIndex = packet.packetIndex
            _sessionBytes += packet.payload.count
            open[fid] = file
            events.append(.bytes(fileId: fid, fileBytes: file.bytes, sessionBytes: _sessionBytes))
            if packet.isEndOfFile {
                events.append(try finish(fid))
            }
        } catch {
            events.append(.writeFailed(fileId: fid, message: error.localizedDescription))
        }
        return events
    }

    private func nextPartURL(fileId: UInt16) -> URL {
        let base = String(format: "%05d", fileId)
        var url = directory.appendingPathComponent("\(base).part")
        var n = 2
        let fm = FileManager.default
        while fm.fileExists(atPath: url.path) || fm.fileExists(atPath: url.deletingPathExtension().appendingPathExtension("bin").path) {
            url = directory.appendingPathComponent("\(base)-\(n).part")
            n += 1
        }
        return url
    }

    /// Full flush, close, rename `.part` -> `.bin`. Called with the lock held.
    private func finish(_ fid: UInt16) throws -> SyncWriterEvent {
        guard let file = open.removeValue(forKey: fid) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try file.handle.synchronize()
        Self.fullSync(file.handle)
        try file.handle.close()
        let final = file.url.deletingPathExtension().appendingPathExtension("bin")
        try FileManager.default.moveItem(at: file.url, to: final)
        try Self.syncDirectory(directory)
        // Earlier partial attempts of this file are now redundant; keep them
        // out of crash recovery without deleting received bytes.
        for old in superseded.removeValue(forKey: fid) ?? [] {
            try? FileManager.default.moveItem(at: old, to: old.appendingPathExtension("superseded"))
        }
        _completed.append((fid, final, file.bytes))
        return .fileCompleted(fileId: fid, url: final, byteCount: file.bytes)
    }

    /// Flushes and closes any file still open (interrupted sync). The `.part`
    /// files stay for crash recovery. Returns their URLs and byte counts.
    @discardableResult
    public func closeOpenFiles() -> [(url: URL, bytes: Int)] {
        lock.withLock {
            var out: [(URL, Int)] = []
            for (_, f) in open {
                try? f.handle.synchronize()
                Self.fullSync(f.handle)
                try? f.handle.close()
                out.append((f.url, f.bytes))
            }
            open.removeAll()
            return out
        }
    }

    /// F_FULLFSYNC asks the drive to flush its cache too (fsync alone does not on Apple platforms).
    static func fullSync(_ handle: FileHandle) {
        _ = fcntl(handle.fileDescriptor, F_FULLFSYNC)
    }

    /// Makes a create/rename in `dir` durable.
    static func syncDirectory(_ dir: URL) throws {
        let fd = Darwin.open(dir.path, O_RDONLY)
        guard fd >= 0 else { return }
        defer { Darwin.close(fd) }
        _ = fsync(fd)
    }
}
