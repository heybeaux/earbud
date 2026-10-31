import Foundation

/// On-disk layout (design.md "Storage"). The root is injectable for tests and
/// for the CLI's `--out`.
///
/// ```
/// <root>/library.sqlite
/// <root>/audio/YYYY/MM/<recordingID>.m4a   (+ .opus original frames)
/// <root>/raw/<syncID>/<fileID>.part|.bin   exact bytes from the device
/// <root>/imported/<recordingID>.<ext>      copy of an imported file until its M4A is verified
/// <root>/capture/<recordingID>.caf         microphone capture, kept 7 days after verification
/// <root>/trash/audio/<recordingID>/        audio in Recently Deleted (transcript kept)
/// <root>/models/                           WhisperKit models
/// ```
public struct LibraryPaths: Sendable, Equatable {
    public var root: URL

    public init(root: URL) { self.root = root.standardizedFileURL }

    /// `~/Library/Application Support/EarBud`.
    public static var defaultRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("EarBud", isDirectory: true)
    }

    public static var `default`: LibraryPaths { LibraryPaths(root: defaultRoot) }

    public var database: URL { root.appendingPathComponent("library.sqlite") }
    public var audio: URL { root.appendingPathComponent("audio", isDirectory: true) }
    public var raw: URL { root.appendingPathComponent("raw", isDirectory: true) }
    public var models: URL { root.appendingPathComponent("models", isDirectory: true) }
    public var imported: URL { root.appendingPathComponent("imported", isDirectory: true) }
    public var capture: URL { root.appendingPathComponent("capture", isDirectory: true) }
    public var trash: URL { root.appendingPathComponent("trash", isDirectory: true) }

    public func rawDirectory(syncID: String) -> URL { raw.appendingPathComponent(syncID, isDirectory: true) }

    /// `trash/audio/<id>/`: where Delete Audio moves a recording's M4A and `.opus`.
    public func trashedAudioDirectory(recordingID: String) -> URL {
        trash.appendingPathComponent("audio", isDirectory: true).appendingPathComponent(recordingID, isDirectory: true)
    }

    /// `audio/YYYY/MM/` for a recording date, in the given calendar (local by default).
    public func audioDirectory(for date: Date, calendar: Calendar = .current) -> URL {
        let c = calendar.dateComponents([.year, .month], from: date)
        return audio
            .appendingPathComponent(String(format: "%04d", c.year!), isDirectory: true)
            .appendingPathComponent(String(format: "%02d", c.month!), isDirectory: true)
    }

    public func createDirectories() throws {
        for dir in [root, audio, raw, models] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// Paths are stored relative to the root so the library can move.
    public func relative(_ url: URL) -> String {
        let r = root.path.hasSuffix("/") ? root.path : root.path + "/"
        let p = url.standardizedFileURL.path
        return p.hasPrefix(r) ? String(p.dropFirst(r.count)) : p
    }

    public func absolute(_ relative: String) -> URL {
        relative.hasPrefix("/") ? URL(fileURLWithPath: relative) : root.appendingPathComponent(relative)
    }
}
