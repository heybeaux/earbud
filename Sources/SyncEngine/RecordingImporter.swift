import AudioCodec
import FieldyProtocol
import Foundation
import Library

/// Turns raw files from the device into library recordings: split header and
/// frames, decode, verify, write `.opus` and `.m4a`, insert, queue for
/// transcription. Works only from files already on disk.
public struct RecordingImporter: Sendable {
    public let library: LibraryStore
    /// Model to queue new recordings with; nil means do not queue.
    public var transcriptionModel: String?
    /// Allowed difference between the decoded length and the M4A length.
    public var durationTolerance: Double = 0.25

    public init(library: LibraryStore, transcriptionModel: String?) {
        self.library = library
        self.transcriptionModel = transcriptionModel
    }

    var paths: LibraryPaths { library.paths }

    /// Imports one raw file. `incomplete` marks a recovered `.part`.
    /// A file that cannot be decoded becomes an `.unreadable` recording and its
    /// raw bytes are kept.
    @discardableResult
    public func importRaw(_ rawURL: URL, syncId: String?, deviceFileId: Int?, incomplete: Bool,
                          syncTime: Date, now: Date = Date()) throws -> Recording {
        let rawRel = paths.relative(rawURL)
        if let existing = try library.recording(rawPath: rawRel) { return existing }

        let data = try Data(contentsOf: rawURL)
        let file = RecordingFile(parsing: data)
        let recordedAt = file.header?.recordedAt
        var rec = Recording(
            recordedAt: recordedAt ?? syncTime,
            timeUnknown: recordedAt == nil,
            durationSeconds: file.durationSeconds,
            frameCount: file.frameCount,
            audioState: incomplete ? .incomplete : .ok,
            rawPath: rawRel,
            syncId: syncId,
            deviceFileId: deviceFileId,
            deviceRecordingId: file.header?.recordingId.map(Int.init),
            createdAt: now)

        do {
            let audio = try FieldyOpusDecoder.decode(frames: file.opusFrames)
            let expectedSamples = file.frameCount * FieldyAudioFormat.samplesPerFrame
            guard audio.frameCount == file.frameCount, audio.samples.count == expectedSamples else {
                throw ImportError.verificationFailed("decoded \(audio.frameCount) of \(file.frameCount) frames")
            }
            let dir = paths.audioDirectory(for: rec.recordedAt)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let opusURL = dir.appendingPathComponent("\(rec.id).opus")
            let m4aURL = dir.appendingPathComponent("\(rec.id).m4a")
            try file.opusFrames.write(to: opusURL, options: .atomic)
            try M4AFile.write(audio, to: m4aURL)
            let m4aSeconds = try AudioFileInfo.duration(of: m4aURL)
            guard abs(m4aSeconds - audio.durationSeconds) <= durationTolerance else {
                throw ImportError.verificationFailed(String(format: "M4A is %.2f s, decoded %.2f s", m4aSeconds, audio.durationSeconds))
            }
            rec.durationSeconds = audio.durationSeconds
            rec.opusPath = paths.relative(opusURL)
            rec.audioPath = paths.relative(m4aURL)
            // Raw cleanup counts from verification; incomplete files keep their raw bytes.
            rec.verifiedAt = incomplete ? nil : now
        } catch {
            rec.audioState = .unreadable
            rec.transcriptError = "\(error)"
        }

        try library.insert(rec)
        if rec.audioState != .unreadable, let model = transcriptionModel {
            try library.enqueueTranscription(recordingId: rec.id, model: model, at: now)
            rec = try library.recording(id: rec.id) ?? rec
        }
        return rec
    }

    /// Crash recovery on launch: imports every `.bin` and `.part` under
    /// `raw/` that is not in the library yet. `.part` files become
    /// "Incomplete" recordings with their playable length.
    @discardableResult
    public func recoverUnimported(now: Date = Date()) throws -> [Recording] {
        let fm = FileManager.default
        guard let syncDirs = try? fm.contentsOfDirectory(at: paths.raw, includingPropertiesForKeys: nil) else { return [] }
        let imported = try library.importedRawPaths()
        var out: [Recording] = []
        for dir in syncDirs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for url in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let ext = url.pathExtension
                guard ext == "bin" || ext == "part", !imported.contains(paths.relative(url)) else { continue }
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                if size == 0 { continue }
                let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? now
                let fid = Int(url.deletingPathExtension().lastPathComponent.prefix(5))
                out.append(try importRaw(url, syncId: dir.lastPathComponent, deviceFileId: fid,
                                         incomplete: ext == "part", syncTime: mtime, now: now))
            }
        }
        return out
    }

    /// Deletes raw bytes of recordings verified more than `age` ago (7 days by default).
    @discardableResult
    public func cleanupRaw(olderThan age: TimeInterval = 7 * 86_400, now: Date = Date()) throws -> Int {
        var n = 0
        for rec in try library.rawCleanupCandidates(verifiedBefore: now.addingTimeInterval(-age)) {
            let url = paths.absolute(rec.rawPath)
            let fm = FileManager.default
            if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
            try library.markRawDeleted(recordingId: rec.id, at: now)
            let dir = url.deletingLastPathComponent()
            if let left = try? fm.contentsOfDirectory(atPath: dir.path),
               left.allSatisfy({ $0.hasSuffix(".superseded") || $0 == ".DS_Store" }) {
                try? fm.removeItem(at: dir)
            }
            n += 1
        }
        return n
    }
}

public enum ImportError: Error, Sendable, CustomStringConvertible {
    case verificationFailed(String)

    public var description: String {
        switch self {
        case .verificationFailed(let m): "verification failed: \(m)"
        }
    }
}
