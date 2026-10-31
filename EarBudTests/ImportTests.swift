import AudioImport
import XCTest
@testable import EarBud

/// 2.4: importing files and folders, the summary sheet (mockup 24), and transcription afterwards.
@MainActor
final class ImportTests: XCTestCase {
    // MARK: Summary text

    func testSummaryTextMatchesMockup() {
        var origin = ImportOrigin()
        origin.add([URL(fileURLWithPath: "/Fixtures/October interviews", isDirectory: true)])
        let report = ImportReport(
            importedIDs: ["a", "b", "c", "d"],
            duplicates: [.init(fileName: "Lena interview copy.wav", existingTitle: "Interview with Lena Okafor")],
            rejected: [.init(fileName: "Release form.pdf", reason: ImportFormats.unreadableReason)])
        let summary = ImportSummaryContent(report: report, origin: origin)
        XCTAssertEqual(summary.title, "4 imported, 1 already in EarBud")
        XCTAssertEqual(summary.subtitle, "From the folder \u{201C}October interviews\u{201D}. 1 file was not imported.")
    }

    func testSummaryTitleVariants() {
        let origin = ImportOrigin(folderNames: [], fileNames: ["Talk.wav"])
        XCTAssertEqual(ImportSummaryContent(report: ImportReport(importedIDs: ["a", "b", "c"]), origin: origin).title, "3 imported")
        XCTAssertEqual(ImportSummaryContent(report: ImportReport(duplicates: [.init(fileName: "x.wav", existingTitle: "X")]), origin: origin).title,
                       "0 imported, 1 already in EarBud")
        let rejectedOnly = ImportReport(rejected: [.init(fileName: "a.pdf", reason: "r"), .init(fileName: "b.pdf", reason: "r")])
        let summary = ImportSummaryContent(report: rejectedOnly, origin: origin)
        XCTAssertEqual(summary.title, "Nothing imported")
        XCTAssertEqual(summary.subtitle, "From \u{201C}Talk.wav\u{201D}. 2 files were not imported.")
    }

    func testEmptyFolderSummary() {
        let summary = ImportSummaryContent(report: ImportReport(), origin: ImportOrigin(folderNames: ["Empty"], fileNames: []))
        XCTAssertEqual(summary.title, "Nothing imported")
        XCTAssertEqual(summary.subtitle, "From the folder \u{201C}Empty\u{201D}. There were no files to import.")
    }

    func testOriginSentences() {
        XCTAssertEqual(ImportOrigin(folderNames: ["A", "B"], fileNames: []).sentence, "From 2 folders.")
        XCTAssertEqual(ImportOrigin(folderNames: [], fileNames: ["a", "b", "c"]).sentence, "From 3 files.")
        XCTAssertEqual(ImportOrigin(folderNames: ["A"], fileNames: ["a", "b"]).sentence, "From 1 folder and 2 files.")
        XCTAssertEqual(ImportOrigin(folderNames: ["A", "B"], fileNames: ["a"]).sentence, "From 2 folders and 1 file.")
    }

    func testOriginTellsFoldersFromFilesOnDisk() throws {
        let dir = TestClock.audioDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("Talk.wav")
        try Data().write(to: file)
        var origin = ImportOrigin()
        // A folder URL without a trailing slash is still a folder.
        origin.add([URL(fileURLWithPath: dir.path), file])
        XCTAssertEqual(origin.folderNames, [dir.lastPathComponent])
        XCTAssertEqual(origin.fileNames, ["Talk.wav"])
    }

    func testProgressTitle() {
        XCTAssertEqual(ImportProgress(completed: 0, total: 0).title, "Looking for audio files\u{2026}")
        XCTAssertEqual(ImportProgress(completed: 1, total: 6).title, "Importing 2 of 6\u{2026}")
        XCTAssertEqual(ImportProgress(completed: 3, total: 6).fraction, 0.5)
    }

    // MARK: Importing through the model

    func testImportFolderShowsMockupSummaryAndListsNewRecordings() async throws {
        let fx = Fixtures()
        let model = fx.model()
        await model.start()
        let before = model.recordings.count

        let task = model.importAudio([FixtureImport.octoberInterviews])
        XCTAssertTrue(model.isImporting)
        guard case .importing = model.importSheet else { return XCTFail("expected the progress sheet") }
        await task?.value

        XCTAssertFalse(model.isImporting)
        guard case .finished(let summary) = model.importSheet else { return XCTFail("expected the summary sheet") }
        XCTAssertEqual(summary.title, "4 imported, 1 already in EarBud")
        XCTAssertEqual(summary.subtitle, "From the folder \u{201C}October interviews\u{201D}. 1 file was not imported.")
        XCTAssertEqual(summary.report.duplicates, [.init(fileName: "Lena interview copy.wav", existingTitle: "Interview with Lena Okafor")])
        XCTAssertEqual(summary.report.rejected, [.init(fileName: "Release form.pdf", reason: "EarBud can't read this kind of file")])

        XCTAssertEqual(model.recordings.count, before + 4)
        let imported = summary.report.importedIDs.compactMap(model.recording)
        XCTAssertEqual(imported.map(\.source), [
            .imported(name: "Panel discussion.m4a"), .imported(name: "Lena Okafor follow-up.wav"),
            .imported(name: "REC_0043.WAV"), .imported(name: "Site walk.mp3"),
        ])
        XCTAssertEqual(model.selectedID, summary.report.importedIDs.first)
        XCTAssertEqual(model.sidebar, .recordings)

        model.dismissImportSummary()
        XCTAssertNil(model.importSheet)
    }

    func testImportedRecordingsGetTranscribed() async throws {
        let fx = Fixtures()
        let model = fx.model()
        await model.start()

        await model.importAudio([FixtureImport.octoberInterviews])?.value
        guard case .finished(let summary) = model.importSheet else { return XCTFail("expected the summary sheet") }

        // The importer only queues; the model must start the transcriber.
        let transcribe = try XCTUnwrap(model.transcribeTask)
        await transcribe.value
        let waiting = await fx.library.waitingCount
        XCTAssertEqual(waiting, 0)
        let all = await fx.library.recordings()
        for id in summary.report.importedIDs {
            let item = try XCTUnwrap(all.first { $0.id == id })
            XCTAssertTrue(item.transcript.isFinished, "\(item.title ?? id) is \(item.transcript)")
        }
    }

    /// Guards the test above: without the model's nudge, imported recordings stay Waiting
    /// (the bug where synced recordings sat as Waiting until relaunch).
    func testFixtureImporterOnlyQueuesTranscription() async throws {
        let fx = Fixtures()
        let report = await fx.importer.importFile(URL(fileURLWithPath: "/tmp/Interview.wav"))
        let id = try XCTUnwrap(report.importedIDs.first)
        await fx.library.waitForTranscriptions()
        let item = await fx.library.recordings().first { $0.id == id }
        XCTAssertEqual(item?.transcript, .waiting(position: 1))
        XCTAssertEqual(item?.title, "Interview")
        let waiting = await fx.library.waitingCount
        XCTAssertEqual(waiting, 1)
    }

    func testSameFileTwiceIsSkippedAsDuplicate() async throws {
        let fx = Fixtures()
        let model = fx.model()
        await model.start()
        let file = URL(fileURLWithPath: "/tmp/Board meeting.wav")

        await model.importAudio([file])?.value
        model.dismissImportSummary()
        await model.importAudio([file])?.value

        guard case .finished(let summary) = model.importSheet else { return XCTFail("expected the summary sheet") }
        XCTAssertEqual(summary.title, "0 imported, 1 already in EarBud")
        XCTAssertEqual(summary.report.duplicates, [.init(fileName: "Board meeting.wav", existingTitle: "Board meeting")])
    }

    func testDropDuringImportJoinsTheSameSummary() async throws {
        let fx = Fixtures()
        let model = fx.model()
        await model.start()

        let first = model.importAudio([FixtureImport.octoberInterviews])
        let second = model.importAudio([URL(fileURLWithPath: "/tmp/Extra.flac"), URL(fileURLWithPath: "/tmp/notes.txt")])
        await first?.value
        await second?.value

        guard case .finished(let summary) = model.importSheet else { return XCTFail("expected the summary sheet") }
        XCTAssertEqual(summary.report.importedIDs.count, 5)
        XCTAssertEqual(summary.report.rejected.map(\.fileName), ["Release form.pdf", "notes.txt"])
        XCTAssertEqual(summary.origin, ImportOrigin(folderNames: ["October interviews"], fileNames: ["Extra.flac", "notes.txt"]))
        XCTAssertEqual(summary.subtitle, "From 1 folder and 2 files. 2 files were not imported.")
    }

    func testProgressSheetCannotBeDismissed() async {
        let fx = Fixtures()
        let model = fx.model()
        await model.start()
        let task = model.importAudio([URL(fileURLWithPath: "/tmp/One.wav")])
        model.dismissImportSummary()
        guard case .importing = model.importSheet else { return XCTFail("the progress sheet should stay up") }
        await task?.value
    }

    func testNonFileURLsAreIgnored() async {
        let fx = Fixtures()
        let model = fx.model()
        await model.start()
        XCTAssertNil(model.importAudio([URL(string: "https://example.com/a.wav")!]))
        XCTAssertNil(model.importSheet)
        XCTAssertFalse(model.isImporting)
    }

    func testStartRunsLaunchCleanupOnce() async throws {
        let fx = Fixtures()
        let model = fx.model()
        await model.start()
        await model.start()
        for _ in 0..<100 where await fx.importer.cleanupCount == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        let count = await fx.importer.cleanupCount
        XCTAssertEqual(count, 1)
    }

    func testFixtureFindsFilesInRealFoldersRecursively() async throws {
        let dir = TestClock.audioDirectory
        let sub = dir.appendingPathComponent("Day 2", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        for url in [dir.appendingPathComponent("a.wav"), sub.appendingPathComponent("b.m4a"), dir.appendingPathComponent(".hidden.wav")] {
            try Data().write(to: url)
        }
        let files = await Fixtures().importer.files(in: [dir])
        XCTAssertEqual(Set(files.map(\.lastPathComponent)), ["a.wav", "b.m4a"])
    }

    // MARK: Real provider mapping

    func testRealProviderMapsSummaryWithoutFullStops() {
        var summary = AudioImport.ImportSummary()
        summary.imported = ["id-1"]
        summary.duplicates = [DuplicateFile(fileName: "copy.wav", existingTitle: "Original")]
        summary.rejected = [RejectedFile(fileName: "form.pdf", reason: "EarBud can't read this kind of file.")]
        let report = RealImportProvider.map(summary)
        XCTAssertEqual(report.importedIDs, ["id-1"])
        XCTAssertEqual(report.duplicates, [.init(fileName: "copy.wav", existingTitle: "Original")])
        XCTAssertEqual(report.rejected, [.init(fileName: "form.pdf", reason: ImportFormats.unreadableReason)])
    }
}
