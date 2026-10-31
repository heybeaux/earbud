import FieldyProtocol
import Foundation
import Library

/// One-off repair of a library damaged by the sync bugs found on
/// 2026-10-31 (docs/device-tests/interrupted-sync-20261031.md), run with
/// `earbud-cli repair`. Each step is safe to run again.
///
/// 1. Phantom file 10818: a status reply (`*B` = 0x2A42) saved as file data.
///    The row and its raw file are deleted.
/// 2. "Incomplete" rows whose complete copy is in (same device recording ID
///    and start time), Recently Deleted included: row, transcript, audio and
///    `.part` are deleted.
/// 3. Headerless Fieldy files that have their own row: imported again. One
///    that continues the previous file of its sync is appended to that
///    recording; an unreadable one that does not becomes its own recording,
///    timed from its trailer. A readable one that does not is left alone.
public struct LibraryRepair: Sendable {
    public let importer: RecordingImporter

    public init(importer: RecordingImporter) {
        self.importer = importer
    }

    public enum Action: Sendable, Equatable, CustomStringConvertible {
        case deletePhantom(recordingId: String, rawPath: String)
        case deleteSuperseded(recordingId: String, rawPath: String, completeId: String)
        /// `appendTo` is the recording it continues; nil: it stays its own recording.
        case reimport(recordingId: String, rawPath: String, appendTo: String?)

        public var description: String {
            switch self {
            case let .deletePhantom(id, raw): "delete phantom recording \(id) (\(raw))"
            case let .deleteSuperseded(id, raw, by): "delete incomplete recording \(id) (\(raw)): complete copy is \(by)"
            case let .reimport(id, raw, to?): "re-import \(raw) (recording \(id)): append to recording \(to)"
            case let .reimport(id, raw, nil): "re-import \(raw) (recording \(id)) as its own recording"
            }
        }
    }

    /// "*B": first bytes of a storage status record, read as a file ID.
    static let phantomFileId = 0x2A42

    /// What `run` would do, in order.
    public func plan() throws -> [Action] {
        let lib = importer.library
        let all = try lib.allRecordings().filter { $0.source == .fieldy }
        var actions: [Action] = []

        let phantoms = all.filter { $0.deviceFileId == Self.phantomFileId && $0.frameCount == 0 }
        actions += phantoms.map { .deletePhantom(recordingId: $0.id, rawPath: $0.rawPath) }

        let complete = all.filter { $0.audioState == .ok && $0.deletedAt == nil && !$0.timeUnknown && $0.deviceRecordingId != nil }
        for r in all where r.audioState == .incomplete && !r.timeUnknown && r.deviceRecordingId != nil {
            if let c = complete.first(where: {
                $0.deviceRecordingId == r.deviceRecordingId && $0.recordedAt == r.recordedAt && $0.frameCount >= r.frameCount
            }) {
                actions.append(.deleteSuperseded(recordingId: r.id, rawPath: r.rawPath, completeId: c.id))
            }
        }

        let phantomIds = Set(phantoms.map(\.id))
        let candidates = all.filter {
            !phantomIds.contains($0.id) && $0.deletedAt == nil && $0.deviceRecordingId == nil
                && $0.rawDeletedAt == nil && $0.rawPath.hasSuffix(".bin")
        }
        for r in candidates.sorted(by: { ($0.syncId ?? "", $0.deviceFileId ?? 0) < ($1.syncId ?? "", $1.deviceFileId ?? 0) }) {
            guard let data = try? Data(contentsOf: lib.paths.absolute(r.rawPath)) else { continue }
            let file = RecordingFile(parsing: data)
            guard file.header == nil, file.trailer != nil else { continue }
            let target = try importer.continuationTarget(for: file, syncId: r.syncId, deviceFileId: r.deviceFileId)
            if target != nil || r.audioState == .unreadable {
                actions.append(.reimport(recordingId: r.id, rawPath: r.rawPath, appendTo: target?.id))
            }
        }
        return actions
    }

    /// Carries out `plan()`. Returns one line per action with its outcome.
    @discardableResult
    public func run(now: Date = Date()) throws -> [String] {
        let lib = importer.library
        var out: [String] = []
        for action in try plan() {
            switch action {
            case let .deletePhantom(id, _), let .deleteSuperseded(id, _, _):
                try lib.deleteRecording(id: id)
                out.append("done: \(action)")
            case let .reimport(id, raw, _):
                guard let old = try lib.recording(id: id) else { continue }
                try lib.deleteRecording(id: id, keepRaw: true)
                // A time-unknown row holds the sync time in `recordedAt`.
                let r = try importer.importRaw(lib.paths.absolute(raw), syncId: old.syncId, deviceFileId: old.deviceFileId,
                                               incomplete: false, syncTime: old.recordedAt, now: now)
                let result = r.rawPath == raw ? "own recording \(r.id)" : "appended to recording \(r.id)"
                out.append("done: \(action) -> \(result), \(r.audioState.rawValue), \(String(format: "%.2f", r.durationSeconds)) s")
            }
        }
        return out
    }
}
