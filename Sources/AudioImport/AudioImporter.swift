import AudioIngest
import Foundation
import Library

/// Copy-first import of audio files (and whole folders) into the library
/// (design.md "Import copies the file, then keeps only the compressed audio";
/// specs/audio-import/spec.md). Public entry point for OpenSpec task 2.2.
///
/// For each file: hash it, skip a duplicate (including Recently Deleted);
/// otherwise copy it to `imported/<id>.<ext>.part`, rename to `.<ext>` once the
/// copy is complete, run `AudioIngest` to produce the playback M4A and
/// recognizer audio, verify the M4A, delete the full-size copy and mark
/// `rawDeletedAt`, insert a `Recording` (source `.imported`), and queue
/// transcription. A file the system cannot decode is rejected and nothing is
/// left behind; the user's original is never modified, moved, or deleted.
///
/// `importPaths` accepts files and folders (searched recursively, skipping
/// hidden files and directories) and returns one `ImportSummary` covering
/// every file found. `cleanupAfterLaunch()` removes partial copies left by a
/// crash or quit during a previous import; call it once at app launch before
/// importing anything new.
public struct AudioImporter: Sendable {
    public let library: LibraryStore
    /// Model to queue new recordings with; nil means do not queue transcription.
    public var transcriptionModel: String?
    public var now: @Sendable () -> Date

    public static let supportedExtensions: Set<String> = ["wav", "aiff", "aif", "caf", "m4a", "mp3", "flac"]

    public init(library: LibraryStore, transcriptionModel: String?, now: @escaping @Sendable () -> Date = Date.init) {
        self.library = library
        self.transcriptionModel = transcriptionModel
        self.now = now
    }

    var paths: LibraryPaths { library.paths }

    /// Imports every audio file at or under `urls`. Folders are searched
    /// recursively; hidden files and directories (dot-prefixed names) are
    /// skipped. Each file is handled independently: one failure does not stop
    /// the rest.
    public func importPaths(_ urls: [URL]) async -> ImportSummary {
        var summary = ImportSummary()
        for url in urls {
            for file in Self.collectFiles(url) {
                await importOne(file, into: &summary)
            }
        }
        return summary
    }

    private func importOne(_ url: URL, into summary: inout ImportSummary) async {
        let name = url.lastPathComponent
        guard Self.supportedExtensions.contains(url.pathExtension.lowercased()) else {
            summary.rejected.append(RejectedFile(fileName: name, reason: "EarBud can't read this kind of file."))
            return
        }
        do {
            if let imported = try await importFile(url) {
                summary.imported.append(imported.id)
            } else if let title = try duplicateTitle(of: url) {
                summary.duplicates.append(DuplicateFile(fileName: name, existingTitle: title))
            }
        } catch {
            summary.rejected.append(RejectedFile(fileName: name, reason: "EarBud can't read this kind of file."))
        }
    }

    /// Hashes `url`; if a live or trashed recording already has that hash,
    /// returns its display title (file name when there is no title).
    private func duplicateTitle(of url: URL) throws -> String? {
        let hash = try ContentHash.sha256(of: url)
        guard let existing = try library.recording(contentHash: hash) else { return nil }
        return existing.title ?? existing.sourceName ?? existing.id
    }

    /// Imports one file that is not a duplicate. Returns nil if a duplicate is
    /// found after hashing (checked again here so a race with another import
    /// cannot double-insert). Throws `AudioIngestError` for an unreadable file;
    /// nothing is left on disk when this throws.
    @discardableResult
    func importFile(_ source: URL) async throws -> Recording? {
        let hash = try ContentHash.sha256(of: source)
        if try library.recording(contentHash: hash) != nil { return nil }
        guard AudioIngest.isSupported(source) else {
            throw AudioIngestError.unreadable(fileName: source.lastPathComponent)
        }

        let id = UUID().uuidString
        let ext = source.pathExtension
        try FileManager.default.createDirectory(at: paths.imported, withIntermediateDirectories: true)
        let partURL = paths.imported.appendingPathComponent("\(id).\(ext).part")
        let copyURL = paths.imported.appendingPathComponent("\(id).\(ext)")
        var leftovers = [partURL, copyURL]

        do {
            try FileManager.default.copyItem(at: source, to: partURL)
            try FileManager.default.moveItem(at: partURL, to: copyURL)

            let time = try await AudioIngest.recordingTime(of: copyURL)
            let dir = paths.audioDirectory(for: time.date)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let playbackURL = dir.appendingPathComponent("\(id).m4a")
            let recognizerURL = dir.appendingPathComponent("\(id).f32")
            leftovers += [playbackURL, recognizerURL]

            let now = now()
            let result: IngestResult
            do {
                result = try AudioIngest.ingest(copyURL, playback: playbackURL, recognizer: recognizerURL)
            } catch {
                try? FileManager.default.removeItem(at: copyURL)
                try? FileManager.default.removeItem(at: playbackURL)
                try? FileManager.default.removeItem(at: recognizerURL)
                throw error
            }

            var rec = Recording(
                id: id,
                recordedAt: time.date,
                timeUnknown: false,
                durationSeconds: result.duration,
                frameCount: 0,
                title: source.deletingPathExtension().lastPathComponent,
                audioState: .ok,
                rawPath: paths.relative(copyURL),
                audioPath: paths.relative(playbackURL),
                verifiedAt: now,
                createdAt: now,
                source: .imported,
                sourceName: source.lastPathComponent,
                contentHash: hash,
                timeFromFileDate: time.timeFromFileDate)

            // Only the compressed copy is kept once it is verified (design.md).
            try? FileManager.default.removeItem(at: copyURL)
            rec.rawDeletedAt = now

            try library.insert(rec)
            try? FileManager.default.removeItem(at: recognizerURL)
            if let model = transcriptionModel {
                try library.enqueueTranscription(recordingId: rec.id, model: model, at: now)
                rec = try library.recording(id: rec.id) ?? rec
            }
            return rec
        } catch {
            for url in leftovers where FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }
            throw error
        }
    }

    /// Removes `.part` files left in `imported/` by a crash or quit during a
    /// previous import, and any recognizer leftovers. Library rows are never
    /// half-made (the row is inserted only after the M4A is verified and the
    /// raw copy removed), so nothing here can point at a missing file.
    @discardableResult
    public func cleanupAfterLaunch() -> Int {
        let fm = FileManager.default
        var n = 0
        if let files = try? fm.contentsOfDirectory(at: paths.imported, includingPropertiesForKeys: nil) {
            for url in files where url.lastPathComponent.hasSuffix(".part") {
                try? fm.removeItem(at: url)
                n += 1
            }
        }
        if let years = try? fm.contentsOfDirectory(at: paths.audio, includingPropertiesForKeys: nil) {
            for year in years {
                guard let months = try? fm.contentsOfDirectory(at: year, includingPropertiesForKeys: nil) else { continue }
                for month in months {
                    guard let files = try? fm.contentsOfDirectory(at: month, includingPropertiesForKeys: nil) else { continue }
                    for url in files where url.pathExtension == "f32" {
                        let id = url.deletingPathExtension().lastPathComponent
                        let row = try? library.recording(id: id)
                        if row == nil || row! == nil {
                            try? fm.removeItem(at: url)
                            n += 1
                        }
                    }
                }
            }
        }
        return n
    }

    /// `url` itself if it is a file; every non-hidden file under it,
    /// recursively, if it is a folder. Public so the app can count the files
    /// up front and show progress while it imports them one at a time.
    public static func collectFiles(_ url: URL) -> [URL] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return [] }
        guard isDir.boolValue else { return isHidden(url) ? [] : [url] }
        guard let enumerator = fm.enumerator(
            at: url, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles], errorHandler: nil
        ) else { return [] }
        var out: [URL] = []
        for case let item as URL in enumerator {
            guard !isHidden(item) else { continue }
            let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if !isDirectory { out.append(item) }
        }
        return out.sorted { $0.path < $1.path }
    }

    private static func isHidden(_ url: URL) -> Bool {
        url.pathComponents.contains { $0.hasPrefix(".") && $0 != "." && $0 != ".." }
    }
}

/// How an import went: file names and ids, for the summary sheet
/// (specs/audio-import/spec.md "Import summary").
public struct ImportSummary: Sendable, Equatable {
    public var imported: [String] = []
    public var duplicates: [DuplicateFile] = []
    public var rejected: [RejectedFile] = []

    public init() {}
}

public struct DuplicateFile: Sendable, Equatable {
    public var fileName: String
    public var existingTitle: String

    public init(fileName: String, existingTitle: String) {
        self.fileName = fileName
        self.existingTitle = existingTitle
    }
}

public struct RejectedFile: Sendable, Equatable {
    public var fileName: String
    public var reason: String

    public init(fileName: String, reason: String) {
        self.fileName = fileName
        self.reason = reason
    }
}
