import Foundation
import Observation

/// Drives the onboarding flow (mockups 02-11): step order, Bluetooth permission, device discovery,
/// reset, pairing, speech model download, and the test recording.
@MainActor
@Observable
final class OnboardingModel {
    let provider: any OnboardingProviding
    /// Called once onboarding finishes or is skipped, so the host can close the window and show the library.
    var onFinished: (() -> Void)?

    private(set) var step: OnboardingStep = .welcome
    private(set) var isWorking = false
    private(set) var bluetoothAuthorization: BluetoothAuthorization = .notDetermined
    private(set) var foundFieldy: FoundFieldy?
    private(set) var searchSeconds: TimeInterval = 0
    private(set) var resetOutcome: ResetOutcome = .waiting
    var showResetHelp = false
    private(set) var connectedDevice: DeviceSnapshot?
    private(set) var speechModels: [SpeechModel] = []
    private(set) var modelDownloadFraction: Double?
    var speechModelDeferred = false
    private(set) var testRecordingPhase = TestRecordingPhase.idle
    private(set) var testRecording: RecordingItem?
    private(set) var testRecordingSegments: [TranscriptSegment] = []
    var openAtLogin = false

    @ObservationIgnored private var speech: (any SpeechModelProviding)?
    @ObservationIgnored private var resetTask: Task<Void, Never>?
    @ObservationIgnored private var scanTask: Task<Void, Never>?

    enum TestRecordingPhase: Equatable { case idle, recording, syncing, done }

    /// `path` lists only the steps actually visited, in order, for step-dot progress and Back.
    private(set) var path: [OnboardingStep] = [.welcome]

    init(provider: any OnboardingProviding, speech: (any SpeechModelProviding)? = nil) {
        self.provider = provider
        self.speech = speech
    }

    // MARK: Navigation

    func goBack() {
        guard path.count > 1 else { return }
        path.removeLast()
        step = path.last ?? .welcome
    }

    private func advance(to next: OnboardingStep) {
        step = next
        path.append(next)
    }

    func skipToFinish() {
        onFinished?()
    }

    // MARK: Welcome

    func getStarted() {
        advance(to: .bluetoothPermission)
    }

    // MARK: Bluetooth

    func allowBluetooth() async {
        isWorking = true
        bluetoothAuthorization = await provider.requestBluetoothAuthorization()
        isWorking = false
        if bluetoothAuthorization == .authorized {
            advance(to: .findFieldy)
            startScan()
        } else {
            advance(to: .bluetoothDenied)
        }
    }

    func openBluetoothSettings() async {
        await provider.openBluetoothSettings()
    }

    /// Call when the app regains focus after System Settings, to re-check authorization.
    func recheckBluetoothAuthorization() async {
        guard step == .bluetoothDenied else { return }
        bluetoothAuthorization = await provider.bluetoothAuthorization()
        if bluetoothAuthorization == .authorized {
            advance(to: .findFieldy)
            startScan()
        }
    }

    // MARK: Find Fieldy

    private func startScan() {
        scanTask?.cancel()
        searchSeconds = 0
        foundFieldy = nil
        scanTask = Task {
            for await found in provider.scanForFieldy() {
                guard !Task.isCancelled else { return }
                self.foundFieldy = found.first
            }
        }
    }

    func retryScan() {
        startScan()
    }

    /// Called by the view once `foundFieldy` is non-nil, to move to the right next step.
    func handleFoundFieldy() {
        guard let found = foundFieldy else { return }
        if found.isPairedElsewhere {
            advance(to: .pairedElsewhere)
        } else {
            Task { await connect(found.id) }
        }
    }

    // MARK: Paired elsewhere / reset

    func confirmReset() {
        guard let found = foundFieldy else { return }
        advance(to: .resetSteps)
        resetOutcome = .waiting
        resetTask?.cancel()
        resetTask = Task {
            for await outcome in provider.resetFieldy(found.id) {
                guard !Task.isCancelled else { return }
                self.resetOutcome = outcome
                if outcome == .succeeded {
                    await connect(found.id)
                }
            }
        }
    }

    func itDidntWork() {
        showResetHelp = true
    }

    func tryResetAgain() {
        showResetHelp = false
        confirmReset()
    }

    private func connect(_ id: String) async {
        isWorking = true
        defer { isWorking = false }
        if let device = try? await provider.pairAndConnect(id) {
            connectedDevice = device
            advance(to: .connected)
        }
    }

    // MARK: Connected -> speech model

    func continueFromConnected() async {
        speechModels = await (speech?.models() ?? [])
        advance(to: .speechModel)
    }

    func downloadSpeechModel() async {
        guard let model = speechModels.first(where: { !$0.installed }) ?? speechModels.first else {
            advance(to: .testRecording)
            return
        }
        modelDownloadFraction = 0
        if let speech {
            for await fraction in await speech.download(model.id) {
                modelDownloadFraction = fraction
            }
        }
        modelDownloadFraction = nil
        speechModels = await (speech?.models() ?? [])
        advance(to: .testRecording)
    }

    func deferSpeechModel() {
        speechModelDeferred = true
        advance(to: .testRecording)
    }

    // MARK: Test recording

    func makeTestRecording() async {
        testRecordingPhase = .recording
        try? await provider.startTestRecording()
        try? await provider.stopTestRecording()
        testRecordingPhase = .syncing
        if let recording = try? await provider.syncTestRecording() {
            testRecording = recording
            testRecordingSegments = [TranscriptSegment(position: 0, start: 0, end: recording.duration, text: recording.preview ?? "")]
            testRecordingPhase = .done
        } else {
            testRecordingPhase = .idle
        }
    }

    /// "Finish setup" / "Continue" on the test-recording-done pane.
    func finishTestRecording() {
        advance(to: provider.hasNotch ? .notchDock : .finished)
    }

    // MARK: Notch dock

    func chooseNotchDock(_ turnOn: Bool) {
        UserDefaults.standard.set(turnOn, forKey: SettingsKey.showInNotch)
        advance(to: .finished)
    }

    // MARK: Finish

    func finish() {
        OnboardingState.markCompleted()
        onFinished?()
    }
}

/// Persistence for "has onboarding run" and the debug force-flag.
enum OnboardingState {
    static let completedKey = "onboarding.completed"
    static let forceArgument = "-EarBudForceOnboarding"

    static var isNeeded: Bool {
        if CommandLine.arguments.contains(forceArgument) { return true }
        return !UserDefaults.standard.bool(forKey: completedKey)
    }

    static func markCompleted() {
        UserDefaults.standard.set(true, forKey: completedKey)
    }
}
