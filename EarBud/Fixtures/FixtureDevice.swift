import Foundation

/// A Fieldy that is always nearby, with the values from mockup 16.
/// Every write waits a moment and then "reads back" the value, like the real device.
actor FixtureDevice: DeviceProviding {
    struct WaitingFile: Sendable {
        var recordedAt: Date
        var script: FixtureData.WaitingScript
    }

    private var state: DeviceSnapshot
    private var waiting: [WaitingFile]
    private let now: @Sendable () -> Date
    private let pace: Duration

    init(reference: Date = Date(), calendar: Calendar = .autoupdatingCurrent, now: @escaping @Sendable () -> Date = Date.init,
         pace: Duration = .milliseconds(120)) {
        self.now = now
        self.pace = pace
        waiting = FixtureData.waiting.map {
            WaitingFile(recordedAt: reference.addingTimeInterval(-Double($0.minutesAgo) * 60), script: $0)
        }
        let lastSynced = FixtureData.date(dayOffset: 0, hour: FixtureData.lastSyncedTime.hour, minute: FixtureData.lastSyncedTime.minute,
                                          reference: reference, calendar: calendar)
        let paired = FixtureData.date(dayOffset: -FixtureData.pairedDaysAgo, hour: 16, minute: 0, reference: reference, calendar: calendar)
        state = DeviceSnapshot(
            name: FixtureData.deviceName, model: FixtureData.deviceModel, firmware: FixtureData.firmware,
            connection: .connected, batteryPercent: FixtureData.batteryPercent,
            waitingCount: 0, waitingBytes: 0, lastSynced: lastSynced, pairedAt: paired, checkedAt: reference,
            recordingMode: .manual, lightOn: true, muted: false, recordingStartedAt: nil)
        Self.updateWaitingTotals(&state, waiting)
    }

    func snapshot() -> DeviceSnapshot { state }

    func refresh() async throws -> DeviceSnapshot {
        try await Task.sleep(for: pace)
        state.checkedAt = now()
        return state
    }

    func setRecordingMode(_ mode: RecordingMode) async throws -> RecordingMode {
        try await Task.sleep(for: pace * 4)
        state.recordingMode = mode
        state.checkedAt = now()
        return state.recordingMode
    }

    func setLight(_ on: Bool) async throws -> Bool {
        try await Task.sleep(for: pace * 4)
        state.lightOn = on
        state.checkedAt = now()
        return state.lightOn
    }

    func setMuted(_ muted: Bool) async throws -> Bool {
        try await Task.sleep(for: pace * 4)
        state.muted = muted
        state.checkedAt = now()
        return state.muted
    }

    func buzz() async throws {
        try await Task.sleep(for: pace * 3)
    }

    func startRecording() async throws -> Date {
        if state.muted { throw DeviceError.muted }
        try await Task.sleep(for: pace * 3)
        let started = now()
        state.recordingStartedAt = started
        return started
    }

    func stopRecording() async throws {
        try await Task.sleep(for: pace * 3)
        guard let started = state.recordingStartedAt else { return }
        let duration = max(1, now().timeIntervalSince(started))
        // Silence from the Mac fixture: the transcriber reports "No speech detected".
        waiting.append(WaitingFile(recordedAt: started, script: FixtureData.WaitingScript(
            minutesAgo: 0, duration: duration.rounded(), seed: 40 + waiting.count, lines: [], noSpeech: true)))
        state.recordingStartedAt = nil
        Self.updateWaitingTotals(&state, waiting)
    }

    // MARK: Fixture sync hooks

    func waitingFiles() -> [WaitingFile] {
        waiting.sorted { $0.recordedAt < $1.recordedAt }
    }

    /// The device deletes each file once it has been sent.
    func didSend(_ recordedAt: Date) {
        waiting.removeAll { $0.recordedAt == recordedAt }
        Self.updateWaitingTotals(&state, waiting)
    }

    func markSynced(at date: Date) {
        state.lastSynced = date
        state.checkedAt = date
    }

    private static func updateWaitingTotals(_ state: inout DeviceSnapshot, _ waiting: [WaitingFile]) {
        state.waitingCount = waiting.count
        state.waitingBytes = waiting.reduce(0) { $0 + Int($1.script.duration) * FixtureData.bytesPerSecond }
    }
}
