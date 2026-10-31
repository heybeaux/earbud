import Foundation
@preconcurrency import WhisperKit

/// On-device Whisper via WhisperKit. Nothing leaves the Mac after the
/// one-time model download.
public actor WhisperKitRecognizer: SpeechRecognizer {
    public let model: TranscriptionModel
    public let modelsDirectory: URL
    private var kit: WhisperKit?

    public init(model: TranscriptionModel, modelsDirectory: URL) {
        self.model = model
        self.modelsDirectory = modelsDirectory
    }

    // MARK: Model files

    private static func markerURL(_ model: TranscriptionModel, in dir: URL) -> URL {
        dir.appendingPathComponent("\(model.rawValue).installed.json")
    }

    private struct Marker: Codable {
        var folder: String
        var installedAt: Date
    }

    /// The installed model folder, if the download completed.
    public static func installedFolder(_ model: TranscriptionModel, in dir: URL) -> URL? {
        guard let data = try? Data(contentsOf: markerURL(model, in: dir)),
              let m = try? JSONDecoder().decode(Marker.self, from: data) else { return nil }
        let url = URL(fileURLWithPath: m.folder)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    public static func isInstalled(_ model: TranscriptionModel, in dir: URL) -> Bool {
        installedFolder(model, in: dir) != nil
    }

    /// Downloads the model (and its tokenizer) into `dir`. Files already
    /// downloaded are not fetched again, so calling this after an interrupted
    /// download continues where it stopped at file granularity.
    @discardableResult
    public static func download(_ model: TranscriptionModel, to dir: URL,
                                progress: (@Sendable (Double) -> Void)? = nil) async throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let folder = try await WhisperKit.download(variant: model.rawValue, downloadBase: dir) { p in
            progress?(p.fractionCompleted)
        }
        // Loading once fetches and caches the tokenizer, so later runs work offline.
        let config = WhisperKitConfig(modelFolder: folder.path, tokenizerFolder: dir, verbose: false,
                                      logLevel: .error, prewarm: false, load: true, download: false)
        _ = try await WhisperKit(config)
        let marker = Marker(folder: folder.path, installedAt: Date())
        try JSONEncoder().encode(marker).write(to: markerURL(model, in: dir), options: .atomic)
        return folder
    }

    // MARK: Recognition

    /// Decoder prompt with product names Whisper otherwise mishears
    /// ("Fieldy" comes out as "Fility").
    static let vocabularyPrompt = "Fieldy, EarBud."

    public func load() async throws {
        guard kit == nil else { return }
        guard let folder = Self.installedFolder(model, in: modelsDirectory) else {
            throw TranscriberError.modelNotInstalled(model)
        }
        let config = WhisperKitConfig(modelFolder: folder.path, tokenizerFolder: modelsDirectory, verbose: false,
                                      logLevel: .error, prewarm: false, load: true, download: false)
        kit = try await WhisperKit(config)
    }

    public func recognize(samples: [Float]) async throws -> [RecognizedSegment] {
        try await load()
        guard let kit else { throw TranscriberError.modelNotInstalled(model) }
        var options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: "en",
            usePrefillPrompt: true,
            skipSpecialTokens: true,
            withoutTimestamps: false,
            noSpeechThreshold: Float(TranscriptFilter.defaultNoSpeechThreshold),
            chunkingStrategy: .vad)
        if let tokenizer = kit.tokenizer {
            // Same encoding as WhisperKit's CLI --prompt: leading space, no special tokens.
            options.promptTokens = tokenizer.encode(text: " " + Self.vocabularyPrompt)
                .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        }
        let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)
        return results.flatMap(\.segments).map {
            RecognizedSegment(start: Double($0.start), end: Double($0.end), text: $0.text,
                              noSpeechProbability: Double($0.noSpeechProb))
        }
    }
}

public enum TranscriberError: Error, Sendable, CustomStringConvertible {
    case modelNotInstalled(TranscriptionModel)
    case audioMissing(String)

    public var description: String {
        switch self {
        case .modelNotInstalled(let m): "The \(m.displayName) speech model (\(m.rawValue)) is not downloaded"
        case .audioMissing(let id): "No audio for recording \(id)"
        }
    }
}
