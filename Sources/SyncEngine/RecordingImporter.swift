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
    /// raw bytes are kept. A file that continues the previous file of the same
    /// sync (see `continuationTarget`) is appended to that recording, which is
    /// returned. A `.part` whose complete copy is already in is deleted and the
    /// complete recording returned.
    @discardableResult
    public func importRaw(_ rawURL: URL, syncId: String?, deviceFileId: Int?, incomplete: Bool,
                          syncTime: Date, now: Date = Date()) throws -> Recording {
        let rawRel = paths.relative(rawURL)
        if let existing = try library.recording(rawPath: rawRel) { return existing }

        let data = try Data(contentsOf: rawURL)
        let file = RecordingFile(parsing: data)
        // A file whose header was lost still has its trailer, which holds the
        // device's wall-clock end time; see `RecordingFile.startFromTrailer`.
        let recordedAt = file.header?.recordedAt ?? file.startFromTrailer
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

        if incomplete, let complete = try partialCopies(of: rec).complete.first {
            // Recovered after the complete copy is already in: nothing to keep.
            try? FileManager.default.removeItem(at: rawURL)
            return complete
        }
        if !incomplete, let target = try continuationTarget(for: file, syncId: syncId, deviceFileId: deviceFileId),
           let merged = try? append(file, rawPath: rawRel, deviceFileId: deviceFileId, to: target, now: now) {
            return merged
        }

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
            try verifyM4A(m4aURL, against: audio)
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
        for old in try partialCopies(of: rec).incomplete {
            try library.deleteRecording(id: old.id)
        }
        return rec
    }

    private func verifyM4A(_ url: URL, against audio: DecodedAudio) throws {
        let m4aSeconds = try AudioFileInfo.duration(of: url)
        guard abs(m4aSeconds - audio.durationSeconds) <= durationTolerance else {
            throw ImportError.verificationFailed(String(format: "M4A is %.2f s, decoded %.2f s", m4aSeconds, audio.durationSeconds))
        }
    }

    /// Other library rows of the same device recording: same header recording
    /// ID and start time. The device keeps a file after an interrupted sync and
    /// sends it again whole next time (seen 2026-10-31), so an "Incomplete"
    /// row from the first attempt is a shorter copy of the complete one.
    /// `incomplete` lists such rows to delete when `rec` is the complete copy
    /// (row, transcript, audio and `.part` go); `complete` lists complete
    /// copies when `rec` is itself incomplete.
    private func partialCopies(of rec: Recording) throws -> (incomplete: [Recording], complete: [Recording]) {
        guard rec.source == .fieldy, rec.audioState != .unreadable, !rec.timeUnknown,
              let rid = rec.deviceRecordingId else { return ([], []) }
        let same = try library.recordings().filter {
            $0.id != rec.id && $0.source == .fieldy && $0.deviceRecordingId == rid
                && !$0.timeUnknown && $0.recordedAt == rec.recordedAt
        }
        if rec.audioState == .ok {
            return (same.filter { $0.audioState == .incomplete && $0.frameCount <= rec.frameCount }, [])
        }
        return ([], same.filter { $0.audioState == .ok && $0.frameCount >= rec.frameCount })
    }

    // MARK: One recording over several files

    /// Stop reason in a file trailer when the device closed the file itself
    /// at its length limit (about 610 s) and went on recording in a new file.
    static let fileLimitStopReason: UInt8 = 4

    /// Allowed difference between the end time in the previous file's trailer
    /// and this file's start: 2 s, plus 1 % of this file's length for the
    /// device clock running slow against the audio (0.7 % seen on device).
    static func continuationTolerance(seconds: Double) -> TimeInterval { 2 + 0.01 * seconds }

    /// The recording `file` continues, if any. The device splits a long
    /// recording into files (device test 2026-10-31: 610 s, trailer stop
    /// reason 4, then the rest in the next file). The candidate is the
    /// recording that holds the previous file of the same sync (highest
    /// device file ID below this one): it must be a complete, headered Fieldy
    /// recording with its audio and raw file still present, and the end time
    /// in that file's trailer must equal this file's start within
    /// `continuationTolerance`.
    /// - Headerless file: start is its trailer time minus its length. Its
    ///   header was lost (on device, to a status read mid-sync), so time is
    ///   the only link to the previous file.
    /// - Headered file: also needs the previous trailer's stop reason 4
    ///   (file limit); a manual stop always ends the recording.
    func continuationTarget(for file: RecordingFile, syncId: String?, deviceFileId: Int?) throws -> Recording? {
        guard let syncId, let fid = deviceFileId, file.frameCount > 0, file.trailer != nil else { return nil }
        let start: Date
        if let header = file.header {
            guard let t = header.recordedAt else { return nil }
            start = t
        } else {
            guard let t = file.startFromTrailer else { return nil }
            start = t
        }
        // Previous file of this sync, as a recording or an appended part.
        var previous: (fid: Int, rawPath: String, recordingId: String)?
        for r in try library.recordings(syncId: syncId) where r.source == .fieldy {
            var files = [(r.deviceFileId, r.rawPath)]
            files += try library.parts(recordingId: r.id).map { ($0.deviceFileId, $0.rawPath) }
            for case let (f?, raw) in files where f < fid && f > (previous?.fid ?? Int.min) {
                previous = (f, raw, r.id)
            }
        }
        guard let previous, let target = try library.recording(id: previous.recordingId),
              target.deletedAt == nil, target.audioState == .ok, !target.isTranscriptOnly,
              target.deviceRecordingId != nil, !target.timeUnknown,
              target.opusPath != nil, target.audioPath != nil, target.rawDeletedAt == nil,
              let prevData = try? Data(contentsOf: paths.absolute(previous.rawPath)),
              let prevTrailer = RecordingFile(parsing: prevData).trailer,
              let prevEnd = prevTrailer.endedAt else { return nil }
        if file.header != nil, prevTrailer.stopReason != Self.fileLimitStopReason { return nil }
        let gap = abs(start.timeIntervalSince(prevEnd))
        return gap <= Self.continuationTolerance(seconds: file.durationSeconds) ? target : nil
    }

    /// Appends the frames of `file` to `target`: rewrites its `.opus` and M4A,
    /// records the file as a part, updates the length, and queues the whole
    /// recording for transcription again (the old transcript stays until the
    /// new one is done). Throws, changing nothing, if the result fails to
    /// decode or verify.
    func append(_ file: RecordingFile, rawPath: String, deviceFileId: Int?, to target: Recording,
                now: Date) throws -> Recording {
        guard let opusRel = target.opusPath, let m4aRel = target.audioPath else {
            throw ImportError.verificationFailed("recording \(target.id) has no audio to append to")
        }
        let fm = FileManager.default
        let opusURL = paths.absolute(opusRel)
        let m4aURL = paths.absolute(m4aRel)
        let frames = try Data(contentsOf: opusURL) + file.opusFrames
        let frameCount = frames.count / FieldyAudioFormat.frameBytes
        let audio = try FieldyOpusDecoder.decode(frames: frames)
        guard audio.frameCount == frameCount, audio.samples.count == frameCount * FieldyAudioFormat.samplesPerFrame else {
            throw ImportError.verificationFailed("decoded \(audio.frameCount) of \(frameCount) frames")
        }
        let dir = opusURL.deletingLastPathComponent()
        let newOpus = dir.appendingPathComponent("\(target.id).appending.opus")
        let newM4A = dir.appendingPathComponent("\(target.id).appending.m4a")
        defer { for u in [newOpus, newM4A] { try? fm.removeItem(at: u) } }
        try frames.write(to: newOpus, options: .atomic)
        try M4AFile.write(audio, to: newM4A)
        try verifyM4A(newM4A, against: audio)

        var rec = target
        rec.frameCount = frameCount
        rec.durationSeconds = audio.durationSeconds
        let part = RecordingPart(rawPath: rawPath, recordingId: rec.id, deviceFileId: deviceFileId,
                                 frameCount: file.frameCount, appendedAt: now)
        // Swap the files in, then commit; on failure put the old files back so
        // the raw file stays unimported and is tried again.
        let backups = [opusURL, m4aURL].map { $0.appendingPathExtension("bak") }
        defer { for b in backups { try? fm.removeItem(at: b) } }
        for (u, b) in zip([opusURL, m4aURL], backups) {
            try? fm.removeItem(at: b)
            try fm.copyItem(at: u, to: b)
        }
        do {
            _ = try fm.replaceItemAt(opusURL, withItemAt: newOpus)
            _ = try fm.replaceItemAt(m4aURL, withItemAt: newM4A)
            try library.append(part, updating: rec)
        } catch {
            for (u, b) in zip([opusURL, m4aURL], backups) {
                try? fm.removeItem(at: u)
                try? fm.copyItem(at: b, to: u)
            }
            throw error
        }
        if let model = rec.transcriptModel ?? transcriptionModel {
            try library.enqueueTranscription(recordingId: rec.id, model: model, at: now)
        }
        return try library.recording(id: rec.id) ?? rec
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
            for part in try library.parts(recordingId: rec.id) {
                let p = paths.absolute(part.rawPath)
                if fm.fileExists(atPath: p.path) { try fm.removeItem(at: p) }
            }
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
