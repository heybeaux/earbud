import Foundation

/// In-memory library backed by `FixtureData`, with a simulated on-device transcription queue.
actor FixtureLibrary: LibraryProviding {
    private struct Entry {
        var item: RecordingItem
        /// Lines shown so far.
        var segments: [TranscriptSegment]
        /// The full transcript the simulated transcriber "finds".
        var script: [TranscriptSegment]
        var failNextAttempt = false
    }

    private var entries: [String: Entry] = [:]
    private var history: [SyncHistoryItem] = []
    private var queue: [String] = []
    private var worker: Task<Void, Never>?
    private var observers: [UUID: AsyncStream<LibraryChange>.Continuation] = [:]

    private let now: @Sendable () -> Date
    private let pace: Duration
    private let audioDirectory: URL

    /// - Parameters:
    ///   - reference: the moment the fixtures are laid out around ("now" at launch).
    ///   - pace: one transcription step. `.zero` in tests.
    init(reference: Date = Date(), calendar: Calendar = .autoupdatingCurrent, now: @escaping @Sendable () -> Date = Date.init,
         pace: Duration = .milliseconds(120), audioDirectory: URL = SilentAudio.defaultDirectory) {
        self.now = now
        self.pace = pace
        self.audioDirectory = audioDirectory

        func make(_ script: FixtureData.Script, index: Int, prefix: String) -> Entry {
            let recordedAt = FixtureData.date(dayOffset: script.dayOffset, hour: script.hour, minute: script.minute, reference: reference, calendar: calendar)
            let segments = FixtureData.segments(script.lines, duration: script.duration)
            let deletedAt = script.deletedDaysAgo.map { reference.addingTimeInterval(-Double($0) * 86_400) }
            let item = RecordingItem(
                id: "\(prefix)-\(index + 1)", recordedAt: recordedAt, duration: script.duration, title: script.title,
                audio: .ok, transcript: script.noSpeech ? .noSpeech : .done, preview: segments.first?.text,
                copiedAt: recordedAt.addingTimeInterval(3_600), transcribedAt: recordedAt.addingTimeInterval(3_700),
                deletedAt: deletedAt, waveformSeed: script.seed)
            return Entry(item: item, segments: segments, script: segments)
        }

        for (index, script) in FixtureData.recordings.enumerated() {
            let entry = make(script, index: index, prefix: "rec")
            entries[entry.item.id] = entry
        }
        for (index, script) in FixtureData.deleted.enumerated() {
            let entry = make(script, index: index, prefix: "del")
            entries[entry.item.id] = entry
        }
        history = FixtureData.history.enumerated().map { index, h in
            let start = FixtureData.date(dayOffset: h.dayOffset, hour: h.hour, minute: h.minute, reference: reference, calendar: calendar)
            return SyncHistoryItem(
                id: "sync-\(index + 1)", startedAt: start, finishedAt: start.addingTimeInterval(40 + h.seconds / 10),
                result: h.result, recordingCount: h.count, totalSeconds: h.seconds,
                bytes: Int(h.seconds) * FixtureData.bytesPerSecond, message: h.message)
        }
    }

    // MARK: LibraryProviding

    func recordings() -> [RecordingItem] {
        entries.values.map(\.item).filter { $0.deletedAt == nil }.sorted { $0.recordedAt > $1.recordedAt }
    }

    func segments(for recordingID: String) -> [TranscriptSegment] {
        entries[recordingID]?.segments ?? []
    }

    func search(_ query: String) -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return recordings().compactMap { item in
            guard let entry = entries[item.id] else { return nil }
            let lineMatches = entry.segments.filter { TextMatcher.count(of: trimmed, in: $0.text) > 0 }
            let titleCount = TextMatcher.count(of: trimmed, in: item.title ?? "")
            let count = titleCount + entry.segments.reduce(0) { $0 + TextMatcher.count(of: trimmed, in: $1.text) }
            guard count > 0 else { return nil }
            return SearchResult(recording: item, snippet: lineMatches.first?.text ?? item.preview ?? "", matchCount: count)
        }
    }

    func recentlyDeleted() -> [RecordingItem] {
        entries.values.map(\.item).filter { $0.deletedAt != nil }.sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    func syncHistory() -> [SyncHistoryItem] {
        // Newest first; syncs that started at the same moment keep the order they were added.
        history.enumerated()
            .sorted { ($0.element.startedAt, $0.offset) > ($1.element.startedAt, $1.offset) }
            .map(\.element)
    }

    func rename(_ recordingID: String, to title: String?) {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        entries[recordingID]?.item.title = (trimmed?.isEmpty ?? true) ? nil : trimmed
        broadcast(.recording(id: recordingID))
    }

    func moveToTrash(_ recordingID: String) {
        entries[recordingID]?.item.deletedAt = now()
        broadcast(.recordings)
    }

    func restore(_ recordingID: String) {
        entries[recordingID]?.item.deletedAt = nil
        broadcast(.recordings)
    }

    func retryTranscription(_ recordingID: String) {
        guard let entry = entries[recordingID], case .failed = entry.item.transcript else { return }
        enqueue(recordingID)
    }

    func audioURL(for recordingID: String) throws -> URL? {
        guard let item = entries[recordingID]?.item, item.audio != .unreadable else { return nil }
        return try SilentAudio.file(for: recordingID, duration: item.duration, in: audioDirectory)
    }

    func fileURL(for recordingID: String) throws -> URL? {
        try audioURL(for: recordingID)
    }

    func changes() -> AsyncStream<LibraryChange> {
        let (stream, continuation) = AsyncStream.makeStream(of: LibraryChange.self, bufferingPolicy: .bufferingNewest(64))
        let id = UUID()
        observers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(id) }
        }
        return stream
    }

    // MARK: Fixture sync hooks

    /// Adds a recording that has just been copied from the Fieldy and queues its transcript.
    func importCopied(id: String, recordedAt: Date, script: FixtureData.WaitingScript) {
        let segments = FixtureData.segments(script.lines, duration: script.duration)
        let item = RecordingItem(
            id: id, recordedAt: recordedAt, duration: script.duration, title: nil, audio: .ok,
            transcript: .waiting(position: queue.count + 1), preview: nil, copiedAt: now(), transcribedAt: nil,
            deletedAt: nil, waveformSeed: script.seed)
        entries[id] = Entry(item: item, segments: [], script: segments, failNextAttempt: script.failFirstAttempt)
        enqueue(id)
    }

    func addHistory(_ entry: SyncHistoryItem) {
        history.append(entry)
        broadcast(.history)
    }

    /// Adds a recording that already has its transcript, for the onboarding test recording.
    func addTestRecording(_ item: RecordingItem, segments: [TranscriptSegment]) {
        entries[item.id] = Entry(item: item, segments: segments, script: segments)
        broadcast(.recordings)
    }

    /// Resolves when the transcription queue is empty. For tests.
    func waitForTranscriptions() async {
        while let running = worker {
            await running.value
        }
    }

    // MARK: Transcription simulation

    private func enqueue(_ id: String) {
        if !queue.contains(id) { queue.append(id) }
        updateQueuePositions()
        broadcast(.recordings)
        if worker == nil {
            worker = Task { await self.runQueue() }
        }
    }

    private func runQueue() async {
        while let id = queue.first {
            await transcribe(id)
            queue.removeAll { $0 == id }
            updateQueuePositions()
            broadcast(.recordings)
        }
        worker = nil
    }

    private func transcribe(_ id: String) async {
        guard let entry = entries[id] else { return }
        let duration = entry.item.duration
        // Roughly one step per eight seconds of audio, so long recordings take visibly longer.
        let steps = max(10, Int(duration / 8))
        let failAt = entry.failNextAttempt ? steps * 2 / 5 : nil
        entries[id]?.segments = []
        for step in 1...steps {
            let progress = Double(step) / Double(steps)
            if let failAt, step >= failAt {
                entries[id]?.failNextAttempt = false
                entries[id]?.segments = []
                entries[id]?.item.preview = nil
                entries[id]?.item.transcript = .failed(message: "EarBud couldn't make a transcript for this recording.")
                broadcast(.recording(id: id))
                return
            }
            let heard = duration * progress
            let ready = entry.script.filter { $0.end <= heard || progress >= 1 }
            entries[id]?.segments = ready
            entries[id]?.item.transcript = .transcribing(progress: progress, secondsLeft: (1 - progress) * duration * 0.4)
            entries[id]?.item.preview = ready.first?.text
            broadcast(.recording(id: id))
            try? await Task.sleep(for: pace)
        }
        entries[id]?.segments = entry.script
        entries[id]?.item.preview = entry.script.first?.text
        entries[id]?.item.transcript = entry.script.isEmpty ? .noSpeech : .done
        entries[id]?.item.transcribedAt = now()
        broadcast(.recording(id: id))
    }

    private func updateQueuePositions() {
        // The first item is being transcribed; the rest wait in order.
        for (index, id) in queue.enumerated() where index > 0 || worker == nil {
            if case .transcribing = entries[id]?.item.transcript { continue }
            entries[id]?.item.transcript = .waiting(position: worker == nil ? index + 1 : index)
        }
    }

    private func broadcast(_ change: LibraryChange) {
        for continuation in observers.values { continuation.yield(change) }
    }

    private func removeObserver(_ id: UUID) {
        observers[id] = nil
    }
}
