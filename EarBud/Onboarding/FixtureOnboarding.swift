import AppKit
import Foundation

/// Drives onboarding on the sample data: a Fieldy that starts out "paired with a phone", resets
/// on cue, then connects and makes a transcribed test recording. Mirrors `FixtureDevice`'s pacing.
actor FixtureOnboarding: OnboardingProviding {
    private var authorization: BluetoothAuthorization = .notDetermined
    private var resetDone = false
    private let pace: Duration
    private let now: @Sendable () -> Date
    /// When true, `requestBluetoothAuthorization` denies instead of granting, for the denied-path demo.
    private let denyBluetooth: Bool
    private let library: FixtureLibrary?

    nonisolated let hasNotch: Bool

    /// - Parameter hasNotch: whether to show the notch-dock step. Detected by the caller
    ///   (`NSScreen.main?.safeAreaInsets.top ?? 0 > 0`), since that read needs the main actor.
    init(pace: Duration = .milliseconds(150), now: @escaping @Sendable () -> Date = Date.init,
         denyBluetooth: Bool = false, hasNotch: Bool, library: FixtureLibrary? = nil) {
        self.pace = pace
        self.now = now
        self.denyBluetooth = denyBluetooth
        self.hasNotch = hasNotch
        self.library = library
    }

    func bluetoothAuthorization() -> BluetoothAuthorization { authorization }

    func requestBluetoothAuthorization() async -> BluetoothAuthorization {
        try? await Task.sleep(for: pace * 4)
        authorization = denyBluetooth ? .denied : .authorized
        return authorization
    }

    func openBluetoothSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") {
            NSWorkspace.shared.open(url)
        }
    }

    nonisolated func scanForFieldy() -> AsyncStream<[FoundFieldy]> {
        let (stream, continuation) = AsyncStream.makeStream(of: [FoundFieldy].self)
        Task {
            let pairedElsewhere = await !self.resetDone
            try? await Task.sleep(for: self.pace * 3)
            continuation.yield([FoundFieldy(id: "fieldy-3a7c", name: "Fieldy 3A7C", isVeryClose: true, isPairedElsewhere: pairedElsewhere)])
            continuation.finish()
        }
        return stream
    }

    nonisolated func resetFieldy(_ id: String) -> AsyncStream<ResetOutcome> {
        let (stream, continuation) = AsyncStream.makeStream(of: ResetOutcome.self)
        Task {
            continuation.yield(.waiting)
            try? await Task.sleep(for: self.pace * 6)
            await self.markResetDone()
            continuation.yield(.succeeded)
            continuation.finish()
        }
        return stream
    }

    private func markResetDone() {
        resetDone = true
    }

    func pairAndConnect(_ id: String) async throws -> DeviceSnapshot {
        try await Task.sleep(for: pace * 4)
        return DeviceSnapshot(
            name: "Fieldy 3A7C", model: FixtureData.deviceModel, firmware: FixtureData.firmware,
            connection: .connected, batteryPercent: 82, waitingCount: 0, waitingBytes: 0,
            lastSynced: nil, pairedAt: now(), checkedAt: now(),
            recordingMode: .manual, lightOn: true, muted: false, recordingStartedAt: nil)
    }

    func startTestRecording() async throws {
        try await Task.sleep(for: pace * 3)
    }

    func stopTestRecording() async throws {
        try await Task.sleep(for: pace * 3)
    }

    func syncTestRecording() async throws -> RecordingItem {
        try await Task.sleep(for: pace * 6)
        let recordedAt = now()
        let item = RecordingItem(
            id: "onboarding-test", recordedAt: recordedAt, duration: 6, title: nil, audio: .ok,
            transcript: .done, preview: "This is my first recording with EarBud. It's raining again, and I still need to buy coffee.",
            copiedAt: recordedAt, transcribedAt: recordedAt, deletedAt: nil, waveformSeed: 7)
        await library?.addTestRecording(item, segments: [
            TranscriptSegment(position: 0, start: 0, end: 6,
                              text: "This is my first recording with EarBud. It's raining again, and I still need to buy coffee."),
        ])
        return item
    }
}
