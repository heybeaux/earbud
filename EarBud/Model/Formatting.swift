import Foundation

/// Plain-English dates, durations and sizes as written in the mockups
/// ("Wednesday 28 October", "6 min 42 s", "Last synced today at 1:40 PM").
struct Formatting: Sendable {
    var calendar: Calendar
    var locale: Locale

    init(calendar: Calendar = .autoupdatingCurrent, locale: Locale = .autoupdatingCurrent) {
        var cal = calendar
        cal.locale = locale
        self.calendar = cal
        self.locale = locale
    }

    static let standard = Formatting()

    // MARK: Durations

    /// "6:42", "0:12", "1:02:03".
    func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// Transcript timestamps: "00:52", "1:02:03".
    func timestamp(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    /// "6 min 42 s", "12 s", "1 h 5 min".
    func spokenDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return m > 0 ? "\(h) h \(m) min" : "\(h) h" }
        if m > 0 { return s > 0 ? "\(m) min \(s) s" : "\(m) min" }
        return "\(s) s"
    }

    /// "about 2 minutes left", "less than a minute left".
    func timeLeft(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 1 { return "less than a minute left" }
        return minutes == 1 ? "about 1 minute left" : "about \(minutes) minutes left"
    }

    // MARK: Dates

    /// "1:12 PM" (or "13:12" where the locale uses a 24-hour clock).
    func time(_ date: Date) -> String {
        formatter(template: "jmm").string(from: date)
    }

    /// "Friday 30 October", with the year added when it isn't this year.
    func day(_ date: Date, now: Date) -> String {
        let sameYear = calendar.isDate(date, equalTo: now, toGranularity: .year)
        return formatter(format: sameYear ? "EEEE d MMMM" : "EEEE d MMMM yyyy").string(from: date)
    }

    /// "12 October" (or "12 October 2025").
    func shortDay(_ date: Date, now: Date) -> String {
        let sameYear = calendar.isDate(date, equalTo: now, toGranularity: .year)
        return formatter(format: sameYear ? "d MMMM" : "d MMMM yyyy").string(from: date)
    }

    /// Day headings in the recording list: "Today", "Yesterday", "Wednesday 28 October".
    func dayHeading(_ date: Date, now: Date) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        return day(date, now: now)
    }

    /// "today at 1:40 PM", "yesterday at 9:02 PM", "on Wednesday 28 October".
    func relativeMoment(_ date: Date, now: Date) -> String {
        let heading = dayHeading(date, now: now)
        switch heading {
        case "Today": return "today at \(time(date))"
        case "Yesterday": return "yesterday at \(time(date))"
        default: return "on \(heading)"
        }
    }

    /// "Today, 1:40 PM", "Yesterday, 9:02 PM", "28 October, 6:40 PM".
    func statDate(_ date: Date, now: Date) -> String {
        let heading = dayHeading(date, now: now)
        switch heading {
        case "Today", "Yesterday": return "\(heading), \(time(date))"
        default: return "\(shortDay(date, now: now)), \(time(date))"
        }
    }

    /// The heading for an untitled recording: "Today at 2:15 PM".
    func untitledHeading(_ date: Date, now: Date) -> String {
        "\(dayHeading(date, now: now)) at \(time(date))"
    }

    /// "just now", "4 min ago", "2 h ago", or a day.
    func ago(_ date: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        if seconds < 6 * 3600 { return "\(Int(seconds / 3600)) h ago" }
        return relativeMoment(date, now: now)
    }

    // MARK: Sizes

    /// "1.1 MB", "250 MB".
    func bytes(_ count: Int) -> String {
        let style = ByteCountFormatStyle(style: .file, allowedUnits: [.kb, .mb, .gb], spellsOutZero: false, includesActualByteCount: false, locale: locale)
        return style.format(Int64(count))
    }

    // MARK: Counts

    /// "1 recording", "24 recordings".
    func recordings(_ n: Int) -> String {
        n == 1 ? "1 recording" : "\(n) recordings"
    }

    // MARK: Private

    private func formatter(template: String) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = locale
        f.timeZone = calendar.timeZone
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }

    private func formatter(format: String) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = locale
        f.timeZone = calendar.timeZone
        f.dateFormat = format
        return f
    }
}
