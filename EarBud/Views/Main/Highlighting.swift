import SwiftUI

/// Marks every occurrence of the search phrase, as `mark` / `mark.cur` in the mockups.
enum Highlighting {
    /// - Parameters:
    ///   - current: index of the occurrence to show as the current match.
    ///   - onAccent: the text sits on the selected (accent) row.
    static func attributed(_ text: String, query: String, current: Int? = nil, onAccent: Bool = false) -> AttributedString {
        var result = AttributedString(text)
        guard !query.isEmpty else { return result }
        for (index, range) in TextMatcher.ranges(of: query, in: text).enumerated() {
            guard let lower = AttributedString.Index(range.lowerBound, within: result),
                  let upper = AttributedString.Index(range.upperBound, within: result) else { continue }
            let r = lower..<upper
            if index == current {
                result[r].backgroundColor = Palette.highlightCurrent
                result[r].foregroundColor = Color(red: 0.16, green: 0.13, blue: 0)
            } else if onAccent {
                result[r].backgroundColor = Palette.highlightOnAccent
                result[r].foregroundColor = Color(red: 0.16, green: 0.13, blue: 0)
            } else {
                result[r].backgroundColor = Palette.highlight
            }
        }
        return result
    }
}
