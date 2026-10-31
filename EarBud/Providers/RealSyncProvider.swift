import FieldyDevice
import Foundation
import Library
import SyncEngine
import Transcriber

/// Adapts EarBudKit's `SyncEngine` (durable per-packet download + import) to `SyncProviding`.
/// Progress is reported by bytes, same as `SyncEngine.SyncProgress.fraction`.
final class RealSyncProvider: SyncProviding, Sendable {
    private let engine: SyncEngine
    private let device: FieldyDevice

    init(device: FieldyDevice, store: LibraryStore, transcriptionModel: String? = TranscriptionModel.default.rawValue) {
        self.device = device
        let importer = RecordingImporter(library: store, transcriptionModel: transcriptionModel)
        self.engine = SyncEngine(device: device, importer: importer)
    }

    func startSync() async -> AsyncStream<SyncEvent> {
        let (stream, continuation) = AsyncStream<SyncEvent>.makeStream(bufferingPolicy: .bufferingNewest(64))
        let engine = engine
        Task.detached {
            _ = try? await engine.recoverAndCleanUp()
            let progressTask = Task {
                for await progress in await engine.progressUpdates() where progress.phase != .finished {
                    continuation.yield(.progress(Self.map(progress)))
                }
            }
            defer { progressTask.cancel() }
            do {
                let summary = try await engine.sync()
                continuation.yield(.finished(Self.map(summary)))
            } catch {
                continuation.yield(.finished(.failed(message: "\(error)")))
            }
            continuation.finish()
        }
        return stream
    }

    // MARK: Mapping

    private static func map(_ progress: SyncProgress) -> SyncProgressSnapshot {
        SyncProgressSnapshot(
            phase: map(progress.phase),
            fileIndex: progress.filesCompleted + (progress.phase == .copying ? 1 : 0),
            fileCount: progress.filesExpected,
            bytesReceived: progress.bytesReceived,
            bytesExpected: progress.bytesExpected,
            currentRecordingStart: nil,
            currentFileFraction: progress.fraction)
    }

    private static func map(_ phase: SyncProgress.Phase) -> SyncProgressSnapshot.Phase {
        switch phase {
        case .connecting: .connecting
        case .checking: .checking
        case .copying: .copying
        case .importing, .finished: .finishing
        }
    }

    private static func map(_ summary: SyncSummary) -> SyncOutcome {
        switch summary.result {
        case .success: .copied(count: summary.recordings.count)
        case .nothingNew: .nothingNew
        case .interrupted: .interrupted(saved: summary.recordings.count)
        case .failed: .failed(message: summary.message ?? "The sync failed.")
        }
    }
}
