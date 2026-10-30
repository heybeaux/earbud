import Foundation
@testable import EarBud

enum TestClock {
    static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Vancouver")!
        cal.locale = Locale(identifier: "en_US")
        return cal
    }()

    static let formatting = Formatting(calendar: calendar, locale: Locale(identifier: "en_US"))

    /// Friday 30 October 2026, 2:03 PM: the moment in the mockups.
    static let reference: Date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 14, minute: 3))!

    static func date(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    static var audioDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("EarBudTests-\(UUID().uuidString)", isDirectory: true)
    }
}

extension String {
    /// ICU puts a narrow no-break space before AM/PM; compare with plain spaces.
    var plainSpaces: String { replacingOccurrences(of: "\u{202F}", with: " ") }
}

struct Fixtures {
    let library: FixtureLibrary
    let device: FixtureDevice
    let sync: FixtureSync
    let speech: FixtureSpeechModels
    /// The library through its protocol, as the app sees it.
    var store: any LibraryProviding { library }

    init() {
        let now: @Sendable () -> Date = { TestClock.reference }
        library = FixtureLibrary(reference: TestClock.reference, calendar: TestClock.calendar, now: now, pace: .zero,
                                 audioDirectory: TestClock.audioDirectory)
        device = FixtureDevice(reference: TestClock.reference, calendar: TestClock.calendar, now: now, pace: .zero)
        sync = FixtureSync(library: library, device: device, now: now, pace: .zero)
        speech = FixtureSpeechModels(pace: .zero)
    }

    @MainActor
    func model() -> AppModel {
        AppModel(library: library, device: device, sync: sync, speech: speech, formatting: TestClock.formatting,
                 now: { TestClock.reference }, noticeDuration: .zero)
    }
}
