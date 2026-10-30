import Foundation

/// Recordings under one day heading.
struct DayGroup<Item: Identifiable>: Identifiable {
    var id: Date { day }
    /// Start of the day.
    var day: Date
    var title: String
    var items: [Item]
}

enum LibraryGrouping {
    /// Groups items by calendar day, newest day first and newest item first within a day.
    static func byDay<Item: Identifiable>(_ items: [Item], date: (Item) -> Date, now: Date, formatting: Formatting) -> [DayGroup<Item>] {
        let calendar = formatting.calendar
        let sorted = items.sorted { date($0) > date($1) }
        var groups: [DayGroup<Item>] = []
        for item in sorted {
            let day = calendar.startOfDay(for: date(item))
            if let last = groups.indices.last, groups[last].day == day {
                groups[last].items.append(item)
            } else {
                groups.append(DayGroup(day: day, title: formatting.dayHeading(day, now: now), items: [item]))
            }
        }
        return groups
    }
}

/// Finds a search phrase in text, ignoring case and accents.
enum TextMatcher {
    static func ranges(of query: String, in text: String) -> [Range<String.Index>] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        var result: [Range<String.Index>] = []
        var searchRange = text.startIndex..<text.endIndex
        while let found = text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange) {
            result.append(found)
            searchRange = found.upperBound..<text.endIndex
        }
        return result
    }

    static func count(of query: String, in text: String) -> Int {
        ranges(of: query, in: text).count
    }
}

/// One occurrence of the search phrase in a transcript, for "Match 1 of 2".
struct TranscriptMatch: Equatable {
    var segmentPosition: Int
    /// Index of this occurrence within its segment.
    var occurrence: Int
}

extension TextMatcher {
    static func matches(of query: String, in segments: [TranscriptSegment]) -> [TranscriptMatch] {
        segments.flatMap { segment in
            ranges(of: query, in: segment.text).indices.map { TranscriptMatch(segmentPosition: segment.position, occurrence: $0) }
        }
    }
}

/// Which transcript line is playing.
enum TranscriptTiming {
    /// The last segment that has started by `time`, or `nil` before the first one.
    static func currentSegment(at time: TimeInterval, in segments: [TranscriptSegment]) -> Int? {
        segments.last { $0.start <= time + 0.05 }?.position
    }
}
