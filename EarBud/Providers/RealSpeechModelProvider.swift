import Foundation
import Library
import Transcriber

/// Adapts EarBudKit's `WhisperKitRecognizer` model download to `SpeechModelProviding`.
/// Mirrors the two choices from the spec ("Faster" / "More accurate"); "Later" in onboarding
/// just means `download` is never called, so nothing downloads until the user asks for it.
final class RealSpeechModelProvider: SpeechModelProviding, Sendable {
    private let modelsDirectory: URL

    init(modelsDirectory: URL) {
        self.modelsDirectory = modelsDirectory
    }

    convenience init(paths: LibraryPaths = .default) {
        self.init(modelsDirectory: paths.models)
    }

    func models() async -> [SpeechModel] {
        TranscriptionModel.allCases.map { map($0) }
    }

    func download(_ modelID: String) async -> AsyncStream<Double> {
        let (stream, continuation) = AsyncStream<Double>.makeStream(bufferingPolicy: .bufferingNewest(1))
        guard let model = TranscriptionModel(rawValue: modelID) else {
            continuation.finish()
            return stream
        }
        let dir = modelsDirectory
        Task.detached {
            if WhisperKitRecognizer.isInstalled(model, in: dir) {
                continuation.yield(1)
                continuation.finish()
                return
            }
            do {
                _ = try await WhisperKitRecognizer.download(model, to: dir) { fraction in
                    continuation.yield(fraction)
                }
            } catch {
                // The UI treats a stream that ends without reaching 1.0 as "didn't finish";
                // `models()` afterwards still reports `installed: false` for this model.
            }
            continuation.finish()
        }
        return stream
    }

    private func map(_ model: TranscriptionModel) -> SpeechModel {
        SpeechModel(
            id: model.rawValue,
            name: model.displayName,
            detail: Self.detail(for: model),
            sizeBytes: model.approximateDownloadMB * 1_000_000,
            installed: WhisperKitRecognizer.isInstalled(model, in: modelsDirectory),
            recommended: model == .default)
    }

    private static func detail(for model: TranscriptionModel) -> String {
        switch model {
        case .accurate: "Better with names, accents and quiet voices. Takes a little longer."
        case .faster: "Transcripts are ready sooner, with a few more mistakes. Good for older Macs."
        }
    }
}
