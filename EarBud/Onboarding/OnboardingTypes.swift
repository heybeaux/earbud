import Foundation

// Value types and the provider seam for onboarding (mockups 02-11). Batch 2 ships a fixture
// implementation; the integration batch adapts this to EarBudKit's Bluetooth/pairing APIs.

/// One step in the onboarding flow, in order. The notch step is skipped on Macs without a notch.
enum OnboardingStep: Int, CaseIterable, Equatable, Sendable {
    case welcome
    case bluetoothPermission
    /// A dead end off `bluetoothPermission`, not counted in the step dots.
    case bluetoothDenied
    case findFieldy
    case pairedElsewhere
    case resetSteps
    case connected
    case speechModel
    case testRecording
    case notchDock
    case finished

    /// The happy-path steps shown as dots in the footer.
    static let dotted: [OnboardingStep] = [.welcome, .bluetoothPermission, .findFieldy, .connected, .speechModel, .testRecording, .notchDock, .finished]
}

/// A Fieldy seen while scanning.
struct FoundFieldy: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var isVeryClose: Bool
    var isPairedElsewhere: Bool
}

/// How the reset attempt went, for the "It didn't work" help screen.
enum ResetOutcome: Equatable, Sendable {
    case waiting
    case restartedOnly
    case succeeded
}

enum BluetoothAuthorization: Equatable, Sendable {
    case notDetermined, authorized, denied
}

/// The seam between onboarding UI and the pairing/setup engine. Batch 2 ships `FixtureOnboarding`.
/// The integration batch adapts this to EarBudKit (Bluetooth authorization, FieldyDevice discovery,
/// pairing and reset).
protocol OnboardingProviding: Sendable {
    func bluetoothAuthorization() async -> BluetoothAuthorization
    /// Triggers the macOS Bluetooth permission prompt and returns the result.
    func requestBluetoothAuthorization() async -> BluetoothAuthorization
    func openBluetoothSettings() async

    /// Scans for nearby Fieldys. Ends when the caller stops consuming it.
    func scanForFieldy() -> AsyncStream<[FoundFieldy]>
    func resetFieldy(_ id: String) -> AsyncStream<ResetOutcome>
    /// Pairs with a reset (or already-available) Fieldy, sets its clock, and returns its snapshot.
    func pairAndConnect(_ id: String) async throws -> DeviceSnapshot

    /// Starts a short test recording on the connected Fieldy; mirrors `DeviceProviding` but is
    /// kept separate so onboarding can run before the main `AppModel` is set up.
    func startTestRecording() async throws
    func stopTestRecording() async throws
    /// Syncs the test recording and waits for its transcript. Throws if nothing came through.
    func syncTestRecording() async throws -> RecordingItem

    nonisolated var hasNotch: Bool { get }
}
