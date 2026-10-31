import AudioImport
import Foundation
import Library
import Transcriber

/// Adapts EarBudKit's `AudioImport.AudioImporter` (copy-first import, duplicate check by content,
/// playback M4A, transcription queueing) to `ImportProviding`.
///
/// New recordings are queued with the same model as synced ones; the app then calls
/// `LibraryProviding.transcribeWaiting()` so the queue runs them without a relaunch.
actor RealImportProvider: ImportProviding {
    private let importer: AudioImporter
    private var cleanup: Task<Int, Never>?

    init(store: LibraryStore, transcriptionModel: String? = TranscriptionModel.default.rawValue) {
        importer = AudioImporter(library: store, transcriptionModel: transcriptionModel)
    }

    nonisolated func files(in urls: [URL]) async -> [URL] {
        urls.flatMap(AudioImporter.collectFiles)
    }

    func importFile(_ url: URL) async -> ImportReport {
        // A partial copy from a crash must be gone before a new one can be written.
        await cleanupAfterLaunch()
        return Self.map(await importer.importPaths([url]))
    }

    /// Runs `AudioImporter.cleanupAfterLaunch()` once, off the main thread; later calls wait for that run.
    @discardableResult
    func cleanupAfterLaunch() async -> Int {
        if let cleanup { return await cleanup.value }
        let importer = importer
        let task = Task.detached { importer.cleanupAfterLaunch() }
        cleanup = task
        return await task.value
    }

    static func map(_ summary: AudioImport.ImportSummary) -> ImportReport {
        ImportReport(
            importedIDs: summary.imported,
            duplicates: summary.duplicates.map { .init(fileName: $0.fileName, existingTitle: $0.existingTitle) },
            // The sheet shows reasons without a full stop (mockup 24).
            rejected: summary.rejected.map { .init(fileName: $0.fileName, reason: Self.trimmingFullStop($0.reason)) })
    }

    private static func trimmingFullStop(_ text: String) -> String {
        text.hasSuffix(".") ? String(text.dropLast()) : text
    }
}
