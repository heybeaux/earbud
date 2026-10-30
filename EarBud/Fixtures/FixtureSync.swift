import Foundation

/// Simulates the Sync action: connect, copy each waiting file with byte progress,
/// hand it to the library (which queues the transcript), then record the sync.
actor FixtureSync: SyncProviding {
    private let library: FixtureLibrary
    private let device: FixtureDevice
    private let now: @Sendable () -> Date
    private let pace: Duration
    private var running = false
    private var counter = 0

    init(library: FixtureLibrary, device: FixtureDevice, now: @escaping @Sendable () -> Date = Date.init, pace: Duration = .milliseconds(120)) {
        self.library = library
        self.device = device
        self.now = now
        self.pace = pace
    }

    func startSync() -> AsyncStream<SyncEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: SyncEvent.self)
        guard !running else {
            continuation.finish()
            return stream
        }
        running = true
        Task { await self.run(continuation) }
        return stream
    }

    private func run(_ continuation: AsyncStream<SyncEvent>.Continuation) async {
        // Cleared before the actor is released, so a sync started right after this one ends isn't refused.
        defer { running = false }
        let startedAt = now()
        counter += 1
        let syncID = "fixture-sync-\(counter)"

        var progress = SyncProgressSnapshot(phase: .connecting, fileIndex: 0, fileCount: 0, bytesReceived: 0, bytesExpected: 0,
                                            currentRecordingStart: nil, currentFileFraction: 0)
        continuation.yield(.progress(progress))
        try? await Task.sleep(for: pace * 5)

        let files = await device.waitingFiles()
        progress.phase = .checking
        progress.fileCount = files.count
        progress.bytesExpected = files.reduce(0) { $0 + Int($1.script.duration) * FixtureData.bytesPerSecond }
        continuation.yield(.progress(progress))
        try? await Task.sleep(for: pace * 2)

        if files.isEmpty {
            await device.markSynced(at: now())
            await library.addHistory(SyncHistoryItem(id: syncID, startedAt: startedAt, finishedAt: now(), result: .nothingNew,
                                                     recordingCount: 0, totalSeconds: 0, bytes: 0, message: nil))
            continuation.yield(.finished(.nothingNew))
            continuation.finish()
            return
        }

        progress.phase = .copying
        var totalSeconds: TimeInterval = 0
        for (index, file) in files.enumerated() {
            let bytes = Int(file.script.duration) * FixtureData.bytesPerSecond
            let chunks = max(6, bytes / 40_000)
            progress.fileIndex = index + 1
            progress.currentRecordingStart = file.recordedAt
            let base = progress.bytesReceived
            for chunk in 1...chunks {
                progress.currentFileFraction = Double(chunk) / Double(chunks)
                progress.bytesReceived = base + bytes * chunk / chunks
                continuation.yield(.progress(progress))
                try? await Task.sleep(for: pace)
            }
            await device.didSend(file.recordedAt)
            await library.importCopied(id: "\(syncID)-\(index + 1)", recordedAt: file.recordedAt, script: file.script)
            totalSeconds += file.script.duration
        }

        progress.phase = .finishing
        progress.currentRecordingStart = nil
        continuation.yield(.progress(progress))
        let finishedAt = now()
        await device.markSynced(at: finishedAt)
        await library.addHistory(SyncHistoryItem(id: syncID, startedAt: startedAt, finishedAt: finishedAt, result: .success,
                                                 recordingCount: files.count, totalSeconds: totalSeconds,
                                                 bytes: progress.bytesExpected, message: nil))
        continuation.yield(.finished(.copied(count: files.count)))
        continuation.finish()
    }
}

/// The two WhisperKit models from the spec. "More accurate" is installed; "Faster" can be downloaded.
actor FixtureSpeechModels: SpeechModelProviding {
    private var installed: Set<String> = ["openai_whisper-small.en"]
    private let pace: Duration

    init(pace: Duration = .milliseconds(80)) {
        self.pace = pace
    }

    func models() -> [SpeechModel] {
        [
            SpeechModel(id: "openai_whisper-base.en", name: "Faster",
                        detail: "Transcripts are ready sooner, with a few more mistakes. Good for older Macs.",
                        sizeBytes: 75_000_000, installed: installed.contains("openai_whisper-base.en"), recommended: false),
            SpeechModel(id: "openai_whisper-small.en", name: "More accurate",
                        detail: "Better with names, accents and quiet voices. Takes a little longer.",
                        sizeBytes: 250_000_000, installed: installed.contains("openai_whisper-small.en"), recommended: true),
        ]
    }

    func download(_ modelID: String) -> AsyncStream<Double> {
        let (stream, continuation) = AsyncStream.makeStream(of: Double.self)
        Task {
            for step in 1...30 {
                continuation.yield(Double(step) / 30)
                try? await Task.sleep(for: pace)
            }
            self.markInstalled(modelID)
            continuation.finish()
        }
        return stream
    }

    private func markInstalled(_ id: String) {
        installed.insert(id)
    }
}
