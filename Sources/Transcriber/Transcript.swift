import Foundation

/// The two choices offered in Settings.
public enum TranscriptionModel: String, CaseIterable, Sendable, Codable {
    /// "More accurate" (default).
    case accurate = "openai_whisper-small.en"
    /// "Faster".
    case faster = "openai_whisper-base.en"

    public static let `default`: TranscriptionModel = .accurate

    public var displayName: String {
        switch self {
        case .accurate: "More accurate"
        case .faster: "Faster"
        }
    }

    /// Approximate download size in megabytes (Core ML weights + tokenizer),
    /// shown before the user agrees to download. Measured sizes are logged by
    /// the CLI after a download.
    public var approximateDownloadMB: Int {
        switch self {
        case .accurate: 490
        case .faster: 150
        }
    }

    public init?(variant: String) {
        guard let m = TranscriptionModel(rawValue: variant) else { return nil }
        self = m
    }
}

/// A segment as produced by the recognizer, before filtering.
public struct RecognizedSegment: Sendable, Equatable {
    public var start: Double
    public var end: Double
    public var text: String
    /// Whisper's probability that the window contains no speech.
    public var noSpeechProbability: Double

    public init(start: Double, end: Double, text: String, noSpeechProbability: Double) {
        self.start = start
        self.end = end
        self.text = text
        self.noSpeechProbability = noSpeechProbability
    }
}

/// A transcript segment kept for the library.
public struct TranscriptSegment: Sendable, Equatable {
    public var start: Double
    public var end: Double
    public var text: String

    public init(start: Double, end: Double, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

public enum TranscriptFilter {
    /// Segments above this no-speech probability are dropped.
    public static let defaultNoSpeechThreshold = 0.6

    /// Shown for a transcript with no segments.
    public static let noSpeechText = "No speech detected"

    /// Drops no-speech segments, special tokens and non-speech annotations
    /// ("[BLANK_AUDIO]", "(silence)"), and empty text.
    public static func clean(_ raw: [RecognizedSegment], noSpeechThreshold: Double = defaultNoSpeechThreshold) -> [TranscriptSegment] {
        raw.compactMap { s in
            guard s.noSpeechProbability <= noSpeechThreshold else { return nil }
            let text = stripAnnotations(s.text)
            guard !text.isEmpty else { return nil }
            return TranscriptSegment(start: s.start, end: max(s.start, s.end), text: text)
        }
    }

    static func stripAnnotations(_ text: String) -> String {
        var t = text.replacingOccurrences(of: #"<\|[^|]*\|>"#, with: "", options: .regularExpression)
        // Whole-segment bracketed/parenthesized annotations such as [BLANK_AUDIO], (silence), [Music].
        t = t.replacingOccurrences(of: #"\[[^\]]*\]|\([^)]*\)|\*[^*]*\*"#, with: "", options: .regularExpression)
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        // Nothing but punctuation left is not speech.
        if t.unicodeScalars.allSatisfy({ CharacterSet.punctuationCharacters.union(.symbols).union(.whitespaces).contains($0) }) {
            return ""
        }
        return t
    }

    /// `[mm:ss] text` lines, or "No speech detected".
    public static func plainText(_ segments: [TranscriptSegment]) -> String {
        guard !segments.isEmpty else { return noSpeechText }
        return segments.map { "[\(timestamp($0.start))] \($0.text)" }.joined(separator: "\n")
    }

    public static func timestamp(_ seconds: Double) -> String {
        let s = Int(seconds.rounded(.down))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%02d:%02d", s / 60, s % 60)
    }
}

/// Anything that turns 16 kHz mono Float samples into raw segments.
public protocol SpeechRecognizer: Sendable {
    func recognize(samples: [Float]) async throws -> [RecognizedSegment]
}
