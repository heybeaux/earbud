import Foundation

/// How an import went (EarBudKit `AudioImport.ImportSummary`), for the summary sheet (mockup 24).
struct ImportReport: Equatable, Sendable {
    /// A file skipped because the same audio is already in EarBud (or in Recently Deleted).
    struct Duplicate: Equatable, Hashable, Sendable {
        var fileName: String
        /// The title the existing recording is listed under.
        var existingTitle: String
    }

    /// A file EarBud couldn't import.
    struct Rejected: Equatable, Hashable, Sendable {
        var fileName: String
        /// Shown under the file name, e.g. "EarBud can't read this kind of file".
        var reason: String
    }

    var importedIDs: [String] = []
    var duplicates: [Duplicate] = []
    var rejected: [Rejected] = []

    var fileCount: Int { importedIDs.count + duplicates.count + rejected.count }

    mutating func merge(_ other: ImportReport) {
        importedIDs += other.importedIDs
        duplicates += other.duplicates
        rejected += other.rejected
    }
}

/// What the user dropped or chose, for "From the folder "October interviews"."
struct ImportOrigin: Equatable, Sendable {
    var folderNames: [String] = []
    var fileNames: [String] = []

    mutating func add(_ urls: [URL]) {
        for url in urls {
            let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? url.hasDirectoryPath
            if isFolder { folderNames.append(url.lastPathComponent) } else { fileNames.append(url.lastPathComponent) }
        }
    }

    /// "From the folder "October interviews".", "From "Panel.m4a".", or "From 2 folders and 3 files."
    var sentence: String {
        switch (folderNames.count, fileNames.count) {
        case (0, 0): return ""
        case (1, 0): return "From the folder \u{201C}\(folderNames[0])\u{201D}."
        case (0, 1): return "From \u{201C}\(fileNames[0])\u{201D}."
        case (let folders, 0): return "From \(folders) folders."
        case (0, let files): return "From \(files) files."
        case (let folders, let files):
            return "From \(Self.count(folders, "folder")) and \(Self.count(files, "file"))."
        }
    }

    private static func count(_ n: Int, _ noun: String) -> String {
        n == 1 ? "1 \(noun)" : "\(n) \(noun)s"
    }
}

/// The import running now: "Importing 2 of 5".
struct ImportProgress: Equatable, Sendable {
    var completed: Int
    var total: Int
    /// The file being imported, once the file list is known.
    var currentFileName: String?

    var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }

    var title: String {
        total > 0 ? "Importing \(min(completed + 1, total)) of \(total)\u{2026}" : "Looking for audio files\u{2026}"
    }
}

/// The finished import as the summary sheet shows it (mockup 24).
struct ImportSummaryContent: Equatable, Sendable {
    var report: ImportReport
    var origin: ImportOrigin

    /// "4 imported, 1 already in EarBud" (specs/audio-import "Import summary").
    var title: String {
        let imported = report.importedIDs.count
        let duplicates = report.duplicates.count
        if imported == 0 && duplicates == 0 { return "Nothing imported" }
        var parts = ["\(imported) imported"]
        if duplicates > 0 { parts.append("\(duplicates) already in EarBud") }
        return parts.joined(separator: ", ")
    }

    /// "From the folder "October interviews". 1 file was not imported."
    var subtitle: String {
        var sentences = [origin.sentence]
        if report.fileCount == 0 {
            sentences.append("There were no files to import.")
        } else if report.rejected.count == 1 {
            sentences.append("1 file was not imported.")
        } else if report.rejected.count > 1 {
            sentences.append("\(report.rejected.count) files were not imported.")
        }
        return sentences.filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// The import sheet on the main window: progress while files are imported, then the summary.
enum ImportSheet: Equatable, Sendable {
    case importing(ImportProgress)
    case finished(ImportSummaryContent)
}

/// File types EarBud imports (specs/audio-import "Import audio files"), as shown on the drop target.
enum ImportFormats {
    static let names = ["WAV", "AIFF", "CAF", "M4A", "MP3", "FLAC"]
    static let extensions: Set<String> = ["wav", "aiff", "aif", "caf", "m4a", "mp3", "flac"]
    static let unreadableReason = "EarBud can't read this kind of file"
}
