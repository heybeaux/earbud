import XCTest
@testable import EarBud

final class FormattingTests: XCTestCase {
    let f = TestClock.formatting
    let now = TestClock.reference

    func testClockDurations() {
        XCTAssertEqual(f.clock(402), "6:42")
        XCTAssertEqual(f.clock(12), "0:12")
        XCTAssertEqual(f.clock(725), "12:05")
        XCTAssertEqual(f.clock(3723), "1:02:03")
        XCTAssertEqual(f.clock(-3), "0:00")
    }

    func testTranscriptTimestamps() {
        XCTAssertEqual(f.timestamp(52), "00:52")
        XCTAssertEqual(f.timestamp(94), "01:34")
        XCTAssertEqual(f.timestamp(3723), "1:02:03")
    }

    func testSpokenDuration() {
        XCTAssertEqual(f.spokenDuration(402), "6 min 42 s")
        XCTAssertEqual(f.spokenDuration(468), "7 min 48 s")
        XCTAssertEqual(f.spokenDuration(12), "12 s")
        XCTAssertEqual(f.spokenDuration(120), "2 min")
        XCTAssertEqual(f.spokenDuration(3900), "1 h 5 min")
    }

    func testTimeLeft() {
        XCTAssertEqual(f.timeLeft(116), "about 2 minutes left")
        XCTAssertEqual(f.timeLeft(70), "about 1 minute left")
        XCTAssertEqual(f.timeLeft(20), "less than a minute left")
    }

    func testDayHeadings() {
        XCTAssertEqual(f.dayHeading(TestClock.date(10, 30, 13, 12), now: now), "Today")
        XCTAssertEqual(f.dayHeading(TestClock.date(10, 29, 16, 30), now: now), "Yesterday")
        XCTAssertEqual(f.dayHeading(TestClock.date(10, 28, 18, 2), now: now), "Wednesday 28 October")
        XCTAssertEqual(f.day(TestClock.date(10, 30, 13, 12), now: now), "Friday 30 October")
        let lastYear = TestClock.calendar.date(from: DateComponents(year: 2025, month: 12, day: 24, hour: 9))!
        XCTAssertEqual(f.dayHeading(lastYear, now: now), "Wednesday 24 December 2025")
    }

    func testTimesAndMoments() {
        let lastSync = TestClock.date(10, 30, 13, 40)
        XCTAssertEqual(f.time(lastSync).plainSpaces, "1:40 PM")
        XCTAssertEqual(f.relativeMoment(lastSync, now: now).plainSpaces, "today at 1:40 PM")
        XCTAssertEqual(f.statDate(lastSync, now: now).plainSpaces, "Today, 1:40 PM")
        XCTAssertEqual(f.untitledHeading(TestClock.date(10, 30, 14, 15), now: now).plainSpaces, "Today at 2:15 PM")
        XCTAssertEqual(f.shortDay(TestClock.date(10, 12, 16, 0), now: now), "12 October")
        XCTAssertEqual(f.ago(now.addingTimeInterval(-20), now: now), "just now")
        XCTAssertEqual(f.ago(now.addingTimeInterval(-300), now: now), "5 min ago")
    }

    func testSizesAndCounts() {
        XCTAssertEqual(f.bytes(1_100_000), "1.1 MB")
        XCTAssertEqual(f.bytes(250_000_000), "250 MB")
        XCTAssertEqual(f.recordings(1), "1 recording")
        XCTAssertEqual(f.recordings(24), "24 recordings")
    }
}
