import AppKit
import Foundation
import Observation

enum SidebarItem: Hashable, Sendable {
    case recordings, syncHistory, recentlyDeleted, device
}

/// The sync shown in the toolbar, list card, sidebar and menu.
enum SyncActivity: Equatable {
    case idle
    case running(SyncProgressSnapshot)
    /// Shown briefly after a sync ends.
    case finished(SyncOutcome, at: Date)

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

/// Something the device panel needs to tell the user.
enum DeviceNotice: Equatable {
    /// "Your Fieldy is muted" with an Unmute button.
    case muted
    case message(String)
}

/// A row in the recordings list.
enum ListEntry: Identifiable, Equatable {
    struct SearchInfo: Equatable {
        var snippet: String
        var matchCount: Int
    }

    case recording(RecordingItem, SearchInfo?)
    /// The file coming over from the Fieldy right now.
    case copying(recordedAt: Date, fraction: Double)

    var id: String {
        switch self {
        case .recording(let item, _): item.id
        case .copying: AppModel.copyingRowID
        }
    }

    var date: Date {
        switch self {
        case .recording(let item, _): item.recordedAt
        case .copying(let date, _): date
        }
    }
}

/// State shared by the main window, Settings and the menu-bar menu.
@MainActor
@Observable
final class AppModel {
    nonisolated static let copyingRowID = "copying"

    let library: any LibraryProviding
    let device: any DeviceProviding
    let syncProvider: any SyncProviding
    let speech: any SpeechModelProviding
    let player = PlaybackController()
    let formatting: Formatting
    @ObservationIgnored let now: () -> Date
    @ObservationIgnored private let noticeDuration: Duration

    var sidebar: SidebarItem = .recordings
    private(set) var recordings: [RecordingItem] = []
    private(set) var deleted: [RecordingItem] = []
    private(set) var history: [SyncHistoryItem] = []
    private(set) var selectedID: String?
    /// Transcript of the selected recording.
    private(set) var segments: [TranscriptSegment] = []

    var searchText = "" {
        didSet { if searchText != oldValue { searchTextChanged() } }
    }
    /// `nil` when not searching.
    private(set) var searchResults: [SearchResult]?
    /// The query `searchResults` belong to.
    private(set) var activeQuery = ""
    private(set) var matchIndex = 0

    private(set) var deviceState: DeviceSnapshot?
    private(set) var sync: SyncActivity = .idle
    private(set) var pendingSettings: Set<DeviceSetting> = []
    private(set) var savedSettings: Set<DeviceSetting> = []
    var deviceNotice: DeviceNotice?
    private(set) var isBuzzing = false
    private(set) var isChangingRecording = false

    private(set) var speechModels: [SpeechModel] = []
    private(set) var modelDownloads: [String: Double] = [:]
    private(set) var isLoaded = false

    @ObservationIgnored private var isStarting = false
    @ObservationIgnored private var changesTask: Task<Void, Never>?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var selectionTask: Task<Void, Never>?

    init(library: any LibraryProviding, device: any DeviceProviding, sync: any SyncProviding, speech: any SpeechModelProviding,
         formatting: Formatting = .standard, now: @escaping () -> Date = Date.init, noticeDuration: Duration = .seconds(3)) {
        self.library = library
        self.device = device
        self.syncProvider = sync
        self.speech = speech
        self.formatting = formatting
        self.now = now
        self.noticeDuration = noticeDuration
    }

    /// The app with the sample library, device and sync.
    static func fixture() -> AppModel {
        let library = FixtureLibrary()
        let device = FixtureDevice()
        return AppModel(library: library, device: device, sync: FixtureSync(library: library, device: device), speech: FixtureSpeechModels())
    }

    // MARK: Loading

    func start() async {
        guard !isLoaded, !isStarting else { return }
        isStarting = true
        let stream = await library.changes()
        changesTask = Task { [weak self] in
            for await change in stream {
                await self?.handle(change)
            }
        }
        await reloadLibrary()
        history = (try? await library.syncHistory()) ?? []
        deviceState = await device.snapshot()
        speechModels = await speech.models()
        if selectedID == nil, let first = recordings.first {
            await select(first.id)
        }
        isLoaded = true
    }

    private func reloadLibrary() async {
        recordings = (try? await library.recordings()) ?? []
        deleted = (try? await library.recentlyDeleted()) ?? []
        if !activeQuery.isEmpty {
            searchResults = try? await library.search(activeQuery)
        }
    }

    private func handle(_ change: LibraryChange) async {
        switch change {
        case .history:
            history = (try? await library.syncHistory()) ?? []
        case .recordings, .recording:
            await reloadLibrary()
            if let id = selectedID {
                segments = (try? await library.segments(for: id)) ?? []
                if let item = recording(id), player.loadedID == id, !player.isReady {
                    player.load(id: id, url: try? await library.audioURL(for: id), duration: item.duration)
                }
            }
        }
    }

    // MARK: Selection

    var selectedRecording: RecordingItem? {
        selectedID.flatMap(recording)
    }

    func recording(_ id: String) -> RecordingItem? {
        recordings.first { $0.id == id } ?? deleted.first { $0.id == id }
    }

    func select(_ id: String?) async {
        guard id != AppModel.copyingRowID else { return }
        selectedID = id
        guard let id, let item = recording(id) else {
            segments = []
            player.unload()
            return
        }
        segments = (try? await library.segments(for: id)) ?? []
        guard selectedID == id else { return }
        let url = try? await library.audioURL(for: id)
        guard selectedID == id else { return }
        player.load(id: id, url: url, duration: item.duration)
        if !activeQuery.isEmpty {
            matchIndex = 0
            seekToCurrentMatch()
        }
    }

    /// Selects without waiting; for views.
    func choose(_ id: String?) {
        selectionTask?.cancel()
        selectionTask = Task { await select(id) }
    }

    func selectAdjacent(_ offset: Int) {
        let ids = listGroups.flatMap(\.items).compactMap { entry -> String? in
            if case .recording(let item, _) = entry { return item.id }
            return nil
        }
        guard !ids.isEmpty else { return }
        let index = selectedID.flatMap { ids.firstIndex(of: $0) } ?? (offset > 0 ? -1 : ids.count)
        choose(ids[max(0, min(ids.count - 1, index + offset))])
    }

    // MARK: List

    var copyingEntry: ListEntry? {
        guard case .running(let p) = sync, p.phase == .copying, let start = p.currentRecordingStart else { return nil }
        return .copying(recordedAt: start, fraction: p.currentFileFraction)
    }

    var listGroups: [DayGroup<ListEntry>] {
        var entries: [ListEntry]
        if let searchResults {
            entries = searchResults.map { .recording($0.recording, .init(snippet: $0.snippet, matchCount: $0.matchCount)) }
        } else {
            entries = recordings.map { .recording($0, nil) }
            if let copyingEntry { entries.append(copyingEntry) }
        }
        return LibraryGrouping.byDay(entries, date: \.date, now: now(), formatting: formatting)
    }

    var isSearching: Bool { searchResults != nil }

    // MARK: Search

    private func searchTextChanged() {
        searchTask?.cancel()
        searchTask = Task { await runSearch() }
    }

    func runSearch() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = nil
            activeQuery = ""
            matchIndex = 0
            return
        }
        let results = (try? await library.search(query)) ?? []
        guard !Task.isCancelled, query == searchText.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        searchResults = results
        activeQuery = query
        matchIndex = 0
        if sidebar != .recordings { sidebar = .recordings }
        if let selectedID, results.contains(where: { $0.id == selectedID }) {
            seekToCurrentMatch()
        } else {
            await select(results.first?.id)
        }
    }

    /// Every occurrence of the search phrase in the selected transcript.
    var transcriptMatches: [TranscriptMatch] {
        activeQuery.isEmpty ? [] : TextMatcher.matches(of: activeQuery, in: segments)
    }

    var currentMatch: TranscriptMatch? {
        let matches = transcriptMatches
        return matches.indices.contains(matchIndex) ? matches[matchIndex] : nil
    }

    /// Moves to the next (+1) or previous (-1) match, wrapping round.
    func showMatch(offset: Int) {
        let count = transcriptMatches.count
        guard count > 0 else { return }
        matchIndex = ((matchIndex + offset) % count + count) % count
        seekToCurrentMatch()
    }

    private func seekToCurrentMatch() {
        guard let match = currentMatch, let segment = segments.first(where: { $0.position == match.segmentPosition }) else { return }
        player.seek(to: segment.start)
    }

    // MARK: Sync

    @discardableResult
    func syncNow() -> Task<Void, Never>? {
        guard !sync.isRunning else { return nil }
        sync = .running(SyncProgressSnapshot(phase: .connecting, fileIndex: 0, fileCount: 0, bytesReceived: 0, bytesExpected: 0,
                                             currentRecordingStart: nil, currentFileFraction: 0))
        return Task {
            let events = await syncProvider.startSync()
            var lastFile = 0
            var outcome: SyncOutcome = .failed(message: "The sync stopped unexpectedly.")
            for await event in events {
                switch event {
                case .progress(let progress):
                    sync = .running(progress)
                    if progress.fileIndex != lastFile {
                        lastFile = progress.fileIndex
                        deviceState = await device.snapshot()
                    }
                case .finished(let result):
                    outcome = result
                }
            }
            let finishedAt = now()
            sync = .finished(outcome, at: finishedAt)
            deviceState = await device.snapshot()
            history = (try? await library.syncHistory()) ?? history
            await reloadLibrary()
            try? await Task.sleep(for: noticeDuration * 1.5)
            if case .finished(_, let at) = sync, at == finishedAt { sync = .idle }
        }
    }

    func retryTranscription(_ id: String) {
        Task { try? await library.retryTranscription(id) }
    }

    // MARK: Library actions

    func rename(_ id: String, to title: String?) async {
        try? await library.rename(id, to: title)
        await reloadLibrary()
    }

    func moveToTrash(_ id: String) async {
        let ids = listGroups.flatMap(\.items).map(\.id)
        let next = ids.firstIndex(of: id).flatMap { index in
            ids.indices.contains(index + 1) ? ids[index + 1] : (index > 0 ? ids[index - 1] : nil)
        }
        try? await library.moveToTrash(id)
        await reloadLibrary()
        if selectedID == id { await select(next == AppModel.copyingRowID ? nil : next) }
    }

    func restore(_ id: String) async {
        try? await library.restore(id)
        await reloadLibrary()
    }

    func showInFinder(_ id: String) async {
        guard let url = try? await library.fileURL(for: id) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// The transcript as plain text, one line per segment.
    func transcriptText(timestamps: Bool = false) -> String {
        segments.map { timestamps ? "[\(formatting.timestamp($0.start))] \($0.text)" : $0.text }.joined(separator: "\n")
    }

    // MARK: Device

    var isRecordingOnDevice: Bool { deviceState?.isRecording ?? false }

    func setRecordingMode(_ mode: RecordingMode) async {
        guard deviceState?.recordingMode != mode, !pendingSettings.contains(.recordingMode) else { return }
        await change(.recordingMode) {
            let confirmed = try await self.device.setRecordingMode(mode)
            self.deviceState?.recordingMode = confirmed
        }
    }

    func setLight(_ on: Bool) async {
        guard deviceState?.lightOn != on, !pendingSettings.contains(.light) else { return }
        await change(.light) {
            let confirmed = try await self.device.setLight(on)
            self.deviceState?.lightOn = confirmed
        }
    }

    func setMuted(_ muted: Bool) async {
        guard deviceState?.muted != muted, !pendingSettings.contains(.mute) else { return }
        await change(.mute) {
            let confirmed = try await self.device.setMuted(muted)
            self.deviceState?.muted = confirmed
            if !confirmed, self.deviceNotice == .muted { self.deviceNotice = nil }
        }
    }

    /// Writes a setting, waits for the device to confirm it, then shows "Saved" for a moment.
    private func change(_ setting: DeviceSetting, _ write: @escaping () async throws -> Void) async {
        pendingSettings.insert(setting)
        savedSettings.remove(setting)
        do {
            try await write()
            pendingSettings.remove(setting)
            savedSettings.insert(setting)
            deviceState?.checkedAt = now()
            try? await Task.sleep(for: noticeDuration)
            savedSettings.remove(setting)
        } catch {
            pendingSettings.remove(setting)
            deviceNotice = .message("Your Fieldy didn't confirm the change. Keep it near this Mac and try again.")
        }
    }

    func toggleRecording() async {
        guard !isChangingRecording else { return }
        isChangingRecording = true
        defer { isChangingRecording = false }
        do {
            if isRecordingOnDevice {
                try await device.stopRecording()
            } else {
                _ = try await device.startRecording()
                if deviceNotice == .muted { deviceNotice = nil }
            }
        } catch DeviceError.muted {
            deviceNotice = .muted
        } catch {
            deviceNotice = .message("EarBud couldn't reach your Fieldy. Keep it near this Mac and try again.")
        }
        deviceState = await device.snapshot()
    }

    func buzz() async {
        guard !isBuzzing else { return }
        isBuzzing = true
        defer { isBuzzing = false }
        do {
            try await device.buzz()
        } catch {
            deviceNotice = .message("EarBud couldn't reach your Fieldy. Keep it near this Mac and try again.")
        }
    }

    // MARK: Speech models

    func downloadModel(_ id: String) async {
        guard modelDownloads[id] == nil else { return }
        modelDownloads[id] = 0
        for await fraction in await speech.download(id) {
            modelDownloads[id] = fraction
        }
        modelDownloads[id] = nil
        speechModels = await speech.models()
    }

    // MARK: Menu bar

    var menuBarState: MenuBarGlyphState {
        if isRecordingOnDevice { return .recording }
        if sync.isRunning { return .syncing }
        return deviceState?.connection == .connected ? .ready : .notNearby
    }
}
