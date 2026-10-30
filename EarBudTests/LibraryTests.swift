import XCTest
@testable import EarBud

final class LibraryTests: XCTestCase {
    func testFixtureLibraryMatchesMockups() async throws {
        let fx = Fixtures()
        let recordings = try await fx.store.recordings()
        let deleted = try await fx.store.recentlyDeleted()
        XCTAssertEqual(recordings.count, 24)
        XCTAssertEqual(deleted.count, 2)
        XCTAssertEqual(recordings.first?.title, "Run club planning")
        XCTAssertEqual(recordings.first?.duration, 402)

        let groups = LibraryGrouping.byDay(recordings, date: \.recordedAt, now: TestClock.reference, formatting: TestClock.formatting)
        XCTAssertEqual(groups.prefix(3).map(\.title), ["Today", "Yesterday", "Wednesday 28 October"])
        XCTAssertEqual(groups.prefix(3).map(\.items.count), [3, 2, 4])
        XCTAssertEqual(groups[0].items.map { $0.title ?? "untitled" }, ["Run club planning", "Groceries", "untitled"])
    }

    func testGroupingSortsNewestFirst() {
        struct Item: Identifiable { let id: Int; let at: Date }
        let items = [
            Item(id: 1, at: TestClock.date(10, 28, 7, 20)),
            Item(id: 2, at: TestClock.date(10, 30, 8, 47)),
            Item(id: 3, at: TestClock.date(10, 30, 13, 12)),
        ]
        let groups = LibraryGrouping.byDay(items, date: \.at, now: TestClock.reference, formatting: TestClock.formatting)
        XCTAssertEqual(groups.map(\.title), ["Today", "Wednesday 28 October"])
        XCTAssertEqual(groups[0].items.map(\.id), [3, 2])
    }

    func testNoSpeechRecording() async throws {
        let fx = Fixtures()
        let all = try await fx.store.recordings()
        let quiet = try XCTUnwrap(all.first { $0.title == nil && $0.duration == 12 })
        XCTAssertEqual(quiet.transcript, .noSpeech)
        let segments = try await fx.store.segments(for: quiet.id)
        XCTAssertEqual(segments, [])
    }

    func testSearchFindsPhraseWithCounts() async throws {
        let fx = Fixtures()
        let results = try await fx.store.search("Powell River")
        XCTAssertEqual(results.map(\.matchCount), [2, 1, 3])
        XCTAssertEqual(results.first?.recording.title, "Run club planning")
        XCTAssertEqual(results.first?.snippet, "Bigger thing: the Powell River trip in November. We need a head count by next Friday for the ferry booking.")
        XCTAssertEqual(results[1].recording.title, "Weekend ideas with Sam")
        XCTAssertTrue(results[2].snippet.hasPrefix("Ferry from Earls Cove"))

        let lower = try await fx.store.search("powell river")
        let blank = try await fx.store.search("   ")
        let none = try await fx.store.search("zeppelin")
        XCTAssertEqual(lower.count, 3)
        XCTAssertEqual(blank.count, 0)
        XCTAssertEqual(none.count, 0)
    }

    func testSearchMatchesTitles() async throws {
        let fx = Fixtures()
        let results = try await fx.store.search("groceries")
        XCTAssertEqual(results.map(\.recording.title), ["Groceries"])
    }

    func testTrashRestoreRename() async throws {
        let fx = Fixtures()
        let first = try await fx.store.recordings()[0]
        try await fx.store.moveToTrash(first.id)
        var count = try await fx.store.recordings().count
        XCTAssertEqual(count, 23)
        let trash = try await fx.store.recentlyDeleted()
        XCTAssertEqual(trash.count, 3)
        XCTAssertEqual(trash.first?.id, first.id)
        let hits = try await fx.store.search("Powell River")
        XCTAssertEqual(hits.count, 2, "Deleted recordings leave search")

        try await fx.store.restore(first.id)
        count = try await fx.store.recordings().count
        XCTAssertEqual(count, 24)

        try await fx.store.rename(first.id, to: "  Saturday run  ")
        var renamed = try await fx.store.recordings()[0]
        XCTAssertEqual(renamed.title, "Saturday run")
        try await fx.store.rename(first.id, to: "")
        renamed = try await fx.store.recordings()[0]
        XCTAssertTrue(renamed.isUntitled)
    }

    func testSyncHistoryNewestFirst() async throws {
        let fx = Fixtures()
        let history = try await fx.store.syncHistory()
        XCTAssertEqual(history.count, FixtureData.history.count)
        XCTAssertEqual(history.first?.startedAt, TestClock.date(10, 30, 13, 40))
        XCTAssertTrue(history.contains { $0.result == .interrupted && $0.message != nil })
    }

    func testAudioFileIsSilentWavOfRightLength() async throws {
        let fx = Fixtures()
        let first = try await fx.store.recordings()[0]
        let found = try await fx.store.audioURL(for: first.id)
        let url = try XCTUnwrap(found)
        let data = try Data(contentsOf: url)
        XCTAssertEqual(data.count, 44 + Int(first.duration) * SilentAudio.sampleRate)
        XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertEqual(data.last, 128)
    }
}

final class MatchingTests: XCTestCase {
    func testTextMatcherIgnoresCaseAndAccents() {
        let text = "Café at Powell river, then POWELL RIVER again."
        XCTAssertEqual(TextMatcher.count(of: "powell river", in: text), 2)
        XCTAssertEqual(TextMatcher.count(of: "cafe", in: text), 1)
        XCTAssertEqual(TextMatcher.count(of: "", in: text), 0)
    }

    func testTranscriptMatchesAndTiming() async throws {
        let fx = Fixtures()
        let run = try await fx.store.recordings()[0]
        let segments = try await fx.store.segments(for: run.id)
        let matches = TextMatcher.matches(of: "Powell River", in: segments)
        XCTAssertEqual(matches.map(\.segmentPosition), [5, 8])
        XCTAssertEqual(segments[5].start, 94)

        XCTAssertEqual(TranscriptTiming.currentSegment(at: 0, in: segments), 0)
        XCTAssertEqual(TranscriptTiming.currentSegment(at: 58, in: segments), 3)
        XCTAssertEqual(TranscriptTiming.currentSegment(at: 400, in: segments), segments.count - 1)
        XCTAssertNil(TranscriptTiming.currentSegment(at: 0, in: []))
    }

    func testWaveformIsStableAndBounded() {
        let a = WaveformShape.bars(count: 96, seed: 3)
        XCTAssertEqual(a, WaveformShape.bars(count: 96, seed: 3))
        XCTAssertNotEqual(a, WaveformShape.bars(count: 96, seed: 4))
        XCTAssertTrue(a.allSatisfy { (0.1...1).contains($0) })
    }

    func testHighlightingMarksEveryOccurrence() {
        let text = "Powell River, then powell river."
        let attributed = Highlighting.attributed(text, query: "Powell River", current: 1)
        let marked = attributed.runs.filter { $0.backgroundColor != nil }
        XCTAssertEqual(marked.count, 2)
    }
}
