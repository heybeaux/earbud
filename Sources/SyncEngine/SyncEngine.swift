import FieldyDevice
import FieldyProtocol
import Foundation
import Library

/// The device operations a sync needs. `FieldyDevice` conforms; tests use a fake.
public protocol SyncDevice: Actor {
    /// Connects (clock + reset report handled by the device layer); returns the device name.
    func connectForSync() async throws -> String
    /// Protected storage-status read (bonds on first use).
    func pair() async throws -> StorageStatus
    func subscribe(_ uuid: String, handler: @escaping @Sendable (Data) -> Void) async throws
    func unsubscribe(_ uuid: String) async
    func write(_ data: Data, to uuid: String) async throws
    func beginActivity()
    func endActivity()
    func states() -> AsyncStream<ConnectionState>
}

extension FieldyDevice: SyncDevice {
    public func connectForSync() async throws -> String {
        try await connect().name
    }
}

public struct SyncProgress: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case connecting
        case checking
        case copying
        case importing
        case finished
    }

    public var phase: Phase
    public var filesExpected: Int
    public var filesCompleted: Int
    public var bytesReceived: Int
    /// From the storage status; payload bytes include file headers and trailers.
    public var bytesExpected: Int

    /// 0...1 by bytes.
    public var fraction: Double {
        guard bytesExpected > 0 else { return phase == .finished ? 1 : 0 }
        return min(1, Double(bytesReceived) / Double(bytesExpected))
    }
}

public struct SyncSummary: Sendable {
    public var syncId: String
    public var result: SyncResult
    public var recordings: [Recording]
    /// Raw files written this sync (`.bin` complete, `.part` interrupted).
    public var rawFiles: [URL]
    public var bytesReceived: Int
    public var droppedFiles: Int
    public var transportVersion: Int
    public var storageStatus: StorageStatus?
    public var message: String?
    public var history: SyncHistoryEntry

    /// Adds an imported recording, or replaces it: a file appended to the
    /// previous file's recording returns that recording again, longer.
    mutating func add(_ r: Recording) {
        if let i = recordings.firstIndex(where: { $0.id == r.id }) {
            recordings[i] = r
        } else {
            recordings.append(r)
        }
    }
}

/// Downloads every stored recording with durable per-packet writes, then
/// imports them. See design.md "Durable download".
public actor SyncEngine {
    public let device: any SyncDevice
    public let importer: RecordingImporter
    /// Stop when no packet arrives for this long.
    public var idleTimeout: TimeInterval
    public var log: @Sendable (String) -> Void

    private var progressObservers: [UUID: AsyncStream<SyncProgress>.Continuation] = [:]
    private var running = false

    public init(device: any SyncDevice, importer: RecordingImporter, idleTimeout: TimeInterval = 30,
                log: @escaping @Sendable (String) -> Void = { _ in }) {
        self.device = device
        self.importer = importer
        self.idleTimeout = idleTimeout
        self.log = log
    }

    var library: LibraryStore { importer.library }

    public func progressUpdates() -> AsyncStream<SyncProgress> {
        let (stream, cont) = AsyncStream<SyncProgress>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        progressObservers[id] = cont
        cont.onTermination = { [weak self] _ in Task { await self?.dropObserver(id) } }
        return stream
    }

    private func dropObserver(_ id: UUID) { progressObservers[id] = nil }
    private func publish(_ p: SyncProgress) { for c in progressObservers.values { c.yield(p) } }

    /// Launch-time housekeeping: recover `.part`/`.bin` files left by a crash
    /// or quit, then delete raw files verified more than 7 days ago.
    @discardableResult
    public func recoverAndCleanUp(now: Date = Date()) throws -> [Recording] {
        let recovered = try importer.recoverUnimported(now: now)
        try importer.cleanupRaw(now: now)
        return recovered
    }

    private enum LoopEvent: Sendable {
        case writer(SyncWriterEvent)
        case idle
        case disconnected
    }

    public func sync(now: @Sendable () -> Date = Date.init) async throws -> SyncSummary {
        guard !running else { throw SyncError.alreadyRunning }
        running = true
        defer { running = false }

        let startedAt = now()
        let syncId = Self.makeSyncId(startedAt)
        // Recorded as interrupted until it finishes, so a crash leaves an honest entry.
        var history = try library.insert(SyncHistoryEntry(syncId: syncId, startedAt: startedAt, result: .interrupted))
        var progress = SyncProgress(phase: .connecting, filesExpected: 0, filesCompleted: 0, bytesReceived: 0, bytesExpected: 0)
        publish(progress)

        await device.beginActivity()
        var writer: DurableSyncWriter?
        var subscribed = false
        var summary = SyncSummary(syncId: syncId, result: .interrupted, recordings: [], rawFiles: [], bytesReceived: 0,
                                  droppedFiles: 0, transportVersion: 0, storageStatus: nil, message: nil, history: history)
        do {
            let name = try await device.connectForSync()
            history.deviceName = name
            progress.phase = .checking
            publish(progress)
            let status = try await device.pair()
            summary.storageStatus = status
            log("device holds \(status.totalFileCount) file(s), \(status.totalFileSize) bytes; transport v\(status.maxTransportVersion)")
            if status.isEmpty {
                await device.endActivity()
                return try finish(&summary, &history, result: .nothingNew, message: "No new recordings", now: now)
            }

            let version = status.negotiatedTransportVersion
            summary.transportVersion = version
            progress.phase = .copying
            progress.filesExpected = status.totalFileCount
            progress.bytesExpected = status.remainingSyncSize > 0 ? status.remainingSyncSize : status.totalFileSize
            publish(progress)

            let (events, cont) = AsyncStream<LoopEvent>.makeStream(bufferingPolicy: .unbounded)
            let w = try DurableSyncWriter(directory: importer.library.paths.rawDirectory(syncID: syncId),
                                          transportVersion: version) { cont.yield(.writer($0)) }
            writer = w
            try await device.subscribe(FieldyGATT.storage) { data in w.handle(data) }
            subscribed = true

            let timeout = idleTimeout
            let watchdog = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    if Date().timeIntervalSince(w.lastPacketAt) > timeout { cont.yield(.idle); return }
                }
            }
            let stateWatch = Task { [device] in
                for await s in await device.states() {
                    if s == .notNearby || s == .idle || s == .bluetoothOff { cont.yield(.disconnected); return }
                }
            }
            defer { watchdog.cancel(); stateWatch.cancel() }

            try await device.write(StorageCommand.syncStart(transportVersion: version).bytes, to: FieldyGATT.storage)
            log("sync started (transport v\(version))")

            var retried = Set<UInt16>()
            var outcome: SyncResult = .interrupted
            var message: String?
            loop: for await event in events {
                switch event {
                case .idle:
                    message = "No data for \(Int(timeout)) s"
                    break loop
                case .disconnected:
                    message = "Connection lost"
                    break loop
                case .writer(let e):
                    switch e {
                    case .transferHeader(let n):
                        log("device will send \(n) file(s)")
                        progress.filesExpected = n
                    case .fileStarted(let fid, _):
                        log("receiving file \(fid)")
                    case .bytes(_, _, let total):
                        progress.bytesReceived = total
                        publish(progress)
                    case .fileCompleted(let fid, let url, let count):
                        log("file \(fid) complete: \(count) bytes")
                        summary.rawFiles.append(url)
                        progress.filesCompleted += 1
                        publish(progress)
                        // Durable already; only now may the device be told.
                        if version >= 3 {
                            try await device.write(StorageCommand.ack(fileId: fid, byteCount: UInt32(count)).bytes, to: FieldyGATT.storage)
                        }
                    case .fileFailed(let f):
                        if retried.contains(f.fileId) {
                            log("file \(f.fileId) failed again; dropping")
                            try await device.write(StorageCommand.drop(fileId: f.fileId, byteCount: f.fileSize).bytes, to: FieldyGATT.storage)
                            summary.droppedFiles += 1
                        } else {
                            log("file \(f.fileId) failed at \(f.failureOffset)/\(f.fileSize); asking for a retry")
                            retried.insert(f.fileId)
                            try await device.write(StorageCommand.retry(fileId: f.fileId, byteCount: f.fileSize).bytes, to: FieldyGATT.storage)
                        }
                    case .endOfRecords, .noFiles:
                        outcome = .success
                        break loop
                    case .storageStatus(let s):
                        log("ignored storage status in sync stream (\(s.totalFileCount) file(s), \(s.totalFileSize) bytes)")
                    case .packetGap(let fid, let expected, let received):
                        log("file \(fid): expected packet \(expected), got \(received); packets missing")
                    case .unrecognized(let d):
                        log("ignored notification: \(d.hexString)")
                    case .writeFailed(let fid, let m):
                        message = "Could not save file \(fid): \(m)"
                        outcome = .failed
                        break loop
                    }
                }
            }
            cont.finish()

            let partials = w.closeOpenFiles()
            summary.rawFiles += partials.map(\.url)
            summary.bytesReceived = w.sessionBytes
            await device.unsubscribe(FieldyGATT.storage)
            subscribed = false
            await device.endActivity()

            // Import from disk only.
            progress.phase = .importing
            publish(progress)
            let syncTime = startedAt
            for (fid, url, _) in w.completedFiles {
                summary.add(try importer.importRaw(url, syncId: syncId, deviceFileId: Int(fid),
                                                                  incomplete: false, syncTime: syncTime, now: now()))
            }
            for p in partials {
                let fid = Int(p.url.deletingPathExtension().lastPathComponent.prefix(5))
                summary.add(try importer.importRaw(p.url, syncId: syncId, deviceFileId: fid,
                                                                  incomplete: true, syncTime: syncTime, now: now()))
            }
            if outcome == .success, summary.droppedFiles > 0 {
                let n = summary.droppedFiles
                message = "\(n) recording\(n == 1 ? "" : "s") on your Fieldy \(n == 1 ? "was" : "were") damaged and couldn't be copied"
            }
            if outcome == .success, summary.recordings.isEmpty, summary.droppedFiles == 0 {
                outcome = .nothingNew
            }
            return try finish(&summary, &history, result: outcome, message: message, now: now)
        } catch {
            writer.map { w in
                let partials = w.closeOpenFiles()
                summary.rawFiles += partials.map(\.url)
                summary.bytesReceived = w.sessionBytes
            }
            if subscribed { await device.unsubscribe(FieldyGATT.storage) }
            await device.endActivity()
            // Whatever reached disk is recovered now rather than at next launch.
            if let w = writer {
                for (fid, url, _) in w.completedFiles {
                    if let r = try? importer.importRaw(url, syncId: syncId, deviceFileId: Int(fid), incomplete: false,
                                                       syncTime: startedAt, now: now()) {
                        summary.add(r)
                    }
                }
                for url in summary.rawFiles where url.pathExtension == "part" {
                    if let r = try? importer.importRaw(url, syncId: syncId, deviceFileId: nil, incomplete: true,
                                                       syncTime: startedAt, now: now()) {
                        summary.add(r)
                    }
                }
            }
            let result: SyncResult = summary.bytesReceived > 0 ? .interrupted : .failed
            _ = try? finish(&summary, &history, result: result, message: "\(error)", now: now)
            throw error
        }
    }

    private func finish(_ summary: inout SyncSummary, _ history: inout SyncHistoryEntry, result: SyncResult,
                        message: String?, now: () -> Date) throws -> SyncSummary {
        summary.result = result
        summary.message = message
        history.finishedAt = now()
        history.result = result
        history.recordingCount = summary.recordings.count
        history.totalSeconds = summary.recordings.reduce(0) { $0 + $1.durationSeconds }
        history.bytesReceived = summary.bytesReceived
        history.droppedFiles = summary.droppedFiles
        history.message = message
        try library.update(history)
        summary.history = history
        publish(SyncProgress(phase: .finished, filesExpected: summary.storageStatus?.totalFileCount ?? 0,
                             filesCompleted: summary.recordings.count, bytesReceived: summary.bytesReceived,
                             bytesExpected: summary.storageStatus?.remainingSyncSize ?? 0))
        return summary
    }

    static func makeSyncId(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return "\(f.string(from: date))-\(UUID().uuidString.prefix(4).lowercased())"
    }
}

public enum SyncError: Error, Sendable {
    case alreadyRunning
}
