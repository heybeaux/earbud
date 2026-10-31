import AudioIngest
import AVFoundation
import Foundation
@testable import AudioImport
import Library
import Testing

private func tempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("earbud-import-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func makeImportStore() throws -> LibraryStore {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("earbudkit-import-\(UUID().uuidString)", isDirectory: true)
    return try LibraryStore(paths: LibraryPaths(root: root))
}

/// A short 16-bit mono WAV, silent except for a quiet 440 Hz tone so AudioIngest has real samples.
private func writeToneWAV(to url: URL, seconds: Double = 1, rate: Double = 16_000) throws {
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: rate,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ]
    let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    let n = Int(seconds * rate)
    let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n))!
    buf.frameLength = AVAudioFrameCount(n)
    let ch = buf.floatChannelData![0]
    for i in 0..<n { ch[i] = 0.2 * Float(sin(2 * .pi * 440 * Double(i) / rate)) }
    try file.write(from: buf)
    if #available(macOS 15, *) { file.close() }
}

@Suite("AudioImporter")
struct AudioImporterTests {
    @Test func importsASupportedFile() async throws {
        let s = try makeImportStore()
        let importer = AudioImporter(library: s, transcriptionModel: "small")
        let dir = try tempDir()
        let src = dir.appendingPathComponent("Interview.wav")
        try writeToneWAV(to: src)
        let originalData = try Data(contentsOf: src)

        let summary = await importer.importPaths([src])
        #expect(summary.imported.count == 1)
        #expect(summary.duplicates.isEmpty && summary.rejected.isEmpty)

        let rec = try #require(try s.recording(id: summary.imported[0]))
        #expect(rec.source == .imported)
        #expect(rec.sourceName == "Interview.wav")
        #expect(rec.title == "Interview")
        #expect(rec.contentHash == (try ContentHash.sha256(of: src)))
        #expect(rec.audioPath != nil)
        #expect(FileManager.default.fileExists(atPath: s.paths.absolute(rec.audioPath!).path))
        // Only the compressed copy is kept: the full-size import copy is gone.
        #expect(!FileManager.default.fileExists(atPath: s.paths.absolute(rec.rawPath).path))
        #expect(rec.rawDeletedAt != nil)
        // Transcription was queued.
        #expect(try s.jobs().map(\.recordingId) == [rec.id])
        // The original file is untouched.
        #expect(try Data(contentsOf: src) == originalData)
    }

    @Test func duplicateIncludingTrashedIsSkipped() async throws {
        let s = try makeImportStore()
        let importer = AudioImporter(library: s, transcriptionModel: nil)
        let dir = try tempDir()
        let src = dir.appendingPathComponent("Meeting.wav")
        try writeToneWAV(to: src)

        let first = await importer.importPaths([src])
        #expect(first.imported.count == 1)
        try s.rename(recordingId: first.imported[0], title: "Team Meeting")
        try s.moveToTrash(recordingId: first.imported[0])

        // Same bytes under a different name: still detected as a duplicate.
        let dir2 = try tempDir()
        let copy = dir2.appendingPathComponent("Renamed.wav")
        try FileManager.default.copyItem(at: src, to: copy)
        let second = await importer.importPaths([copy])
        #expect(second.imported.isEmpty)
        #expect(second.duplicates == [DuplicateFile(fileName: "Renamed.wav", existingTitle: "Team Meeting")])
        // No second recording was created.
        #expect(try await s.db.read { try Recording.fetchCount($0) } == 1)
    }

    @Test func folderRecursionSkipsHiddenFiles() async throws {
        let s = try makeImportStore()
        let importer = AudioImporter(library: s, transcriptionModel: nil)
        let root = try tempDir()
        let sub = root.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let hiddenDir = root.appendingPathComponent(".trashed", isDirectory: true)
        try FileManager.default.createDirectory(at: hiddenDir, withIntermediateDirectories: true)

        try writeToneWAV(to: root.appendingPathComponent("top.wav"), seconds: 0.5)
        try writeToneWAV(to: sub.appendingPathComponent("nested.wav"), seconds: 0.5, rate: 22_050)
        try writeToneWAV(to: root.appendingPathComponent(".hidden.wav"), seconds: 0.5)
        try writeToneWAV(to: hiddenDir.appendingPathComponent("skip-me.wav"), seconds: 0.5)

        let summary = await importer.importPaths([root])
        #expect(summary.imported.count == 2)
        var names = Set<String?>()
        for id in summary.imported { names.insert(try s.recording(id: id)?.sourceName) }
        #expect(names == ["top.wav", "nested.wav"])
    }

    @Test func rejectedFileReportsReason() async throws {
        let s = try makeImportStore()
        let importer = AudioImporter(library: s, transcriptionModel: nil)
        let dir = try tempDir()
        let pdf = dir.appendingPathComponent("notes.pdf")
        try Data("%PDF-1.4 not audio".utf8).write(to: pdf)
        let wav = dir.appendingPathComponent("good.wav")
        try writeToneWAV(to: wav, seconds: 0.5)

        let summary = await importer.importPaths([pdf, wav])
        #expect(summary.imported.count == 1)
        #expect(summary.rejected == [RejectedFile(fileName: "notes.pdf", reason: "EarBud can't read this kind of file.")])
    }

    @Test func rejectedAudioExtensionThatFailsToDecodeLeavesNothingBehind() async throws {
        let s = try makeImportStore()
        let importer = AudioImporter(library: s, transcriptionModel: nil)
        let dir = try tempDir()
        // A .wav extension but not real audio: AVAudioFile should fail to open it.
        let fake = dir.appendingPathComponent("broken.wav")
        try Data("not actually a wav file, just bytes".utf8).write(to: fake)

        let summary = await importer.importPaths([fake])
        #expect(summary.imported.isEmpty)
        #expect(summary.rejected == [RejectedFile(fileName: "broken.wav", reason: "EarBud can't read this kind of file.")])
        #expect(try await s.db.read { try Recording.fetchCount($0) } == 0)
        // No partial copy left in imported/.
        let leftovers = (try? FileManager.default.contentsOfDirectory(at: s.paths.imported, includingPropertiesForKeys: nil)) ?? []
        #expect(leftovers.isEmpty)
    }

    @Test func launchCleanupRemovesLeftoverPartFiles() async throws {
        let s = try makeImportStore()
        let importer = AudioImporter(library: s, transcriptionModel: nil)
        try FileManager.default.createDirectory(at: s.paths.imported, withIntermediateDirectories: true)
        let leftoverPart = s.paths.imported.appendingPathComponent("abc.wav.part")
        try Data("partial".utf8).write(to: leftoverPart)
        // A finished copy that was never cleaned up (simulates a crash after
        // ingest but before the raw-copy delete step) should be left alone by
        // cleanup; only .part files are swept.
        let finishedCopy = s.paths.imported.appendingPathComponent("finished.wav")
        try Data("finished".utf8).write(to: finishedCopy)

        let removed = importer.cleanupAfterLaunch()
        #expect(removed == 1)
        #expect(!FileManager.default.fileExists(atPath: leftoverPart.path))
        #expect(FileManager.default.fileExists(atPath: finishedCopy.path))

        // After cleanup, importing the same source file again succeeds normally.
        let dir = try tempDir()
        let src = dir.appendingPathComponent("retry.wav")
        try writeToneWAV(to: src, seconds: 0.5)
        let summary = await importer.importPaths([src])
        #expect(summary.imported.count == 1)
    }

    @Test func launchCleanupRemovesOrphanedRecognizerFiles() async throws {
        let s = try makeImportStore()
        let importer = AudioImporter(library: s, transcriptionModel: nil)
        let dir = s.paths.audioDirectory(for: Date(timeIntervalSince1970: 1_700_000_000))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let orphan = dir.appendingPathComponent("no-such-id.f32")
        try Data("orphan".utf8).write(to: orphan)

        let removed = importer.cleanupAfterLaunch()
        #expect(removed >= 1)
        #expect(!FileManager.default.fileExists(atPath: orphan.path))
    }

    @Test func rowsNeverPointAtMissingFilesAfterFailureMidImport() async throws {
        let s = try makeImportStore()
        let importer = AudioImporter(library: s, transcriptionModel: nil)
        let dir = try tempDir()
        // A zero-length file with a supported extension: AVAudioFile opens it
        // but it has no audio, so AudioIngest.ingest throws partway through.
        let empty = dir.appendingPathComponent("empty.wav")
        FileManager.default.createFile(atPath: empty.path, contents: Data())

        let summary = await importer.importPaths([empty])
        #expect(summary.imported.isEmpty)
        #expect(summary.rejected.map(\.fileName) == ["empty.wav"])
        #expect(try await s.db.read { try Recording.fetchCount($0) } == 0)
        let leftovers = (try? FileManager.default.contentsOfDirectory(at: s.paths.imported, includingPropertiesForKeys: nil)) ?? []
        #expect(leftovers.isEmpty)
    }

    @Test func transcriptionQueuedOnlyWhenModelProvided() async throws {
        let s = try makeImportStore()
        let importer = AudioImporter(library: s, transcriptionModel: nil)
        let dir = try tempDir()
        let src = dir.appendingPathComponent("silent-queue.wav")
        try writeToneWAV(to: src, seconds: 0.5)
        let summary = await importer.importPaths([src])
        #expect(summary.imported.count == 1)
        #expect(try s.jobs().isEmpty)
        let got = try s.recording(id: summary.imported[0])
        #expect(got?.transcriptState == TranscriptState.none)
    }

    @Test func mixedFolderProducesFullSummary() async throws {
        let s = try makeImportStore()
        let importer = AudioImporter(library: s, transcriptionModel: "small")
        let dir = try tempDir()
        let a = dir.appendingPathComponent("a.wav")
        try writeToneWAV(to: a, seconds: 0.5)
        let b = dir.appendingPathComponent("b.wav")
        try writeToneWAV(to: b, seconds: 0.5, rate: 22_050)
        let dupe = dir.appendingPathComponent("a-again.wav")
        try FileManager.default.copyItem(at: a, to: dupe)
        let pdf = dir.appendingPathComponent("doc.pdf")
        try Data("pdf".utf8).write(to: pdf)

        let summary = await importer.importPaths([dir])
        #expect(summary.imported.count == 2)
        #expect(summary.duplicates.count == 1)
        #expect(summary.rejected == [RejectedFile(fileName: "doc.pdf", reason: "EarBud can't read this kind of file.")])
    }
}
