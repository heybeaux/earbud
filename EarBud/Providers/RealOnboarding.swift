import AppKit
import CoreBluetooth
import FieldyDevice
import FieldyProtocol
import Foundation
import Library
import SyncEngine
import Transcriber

/// Adapts EarBudKit's `FieldyDevice` (scan, pair, reset-report, record) to `OnboardingProviding`.
/// CoreBluetooth has no explicit "request authorization" API: creating `CBCentralManager`
/// (done by `FieldyDevice.init`) triggers the system prompt the first time it is used, and
/// `CBManager.authorization` reflects the answer afterwards.
actor RealOnboarding: OnboardingProviding {
    private let device: FieldyDevice
    private let store: LibraryStore?
    private let library: RealLibraryProvider?
    nonisolated let hasNotch: Bool

    init(device: FieldyDevice, store: LibraryStore?, library: RealLibraryProvider?, hasNotch: Bool) {
        self.device = device
        self.store = store
        self.library = library
        self.hasNotch = hasNotch
    }

    func bluetoothAuthorization() async -> BluetoothAuthorization {
        Self.map(CBManager.authorization)
    }

    func requestBluetoothAuthorization() async -> BluetoothAuthorization {
        // Any Bluetooth call on `device` instantiates CoreBluetooth and triggers the
        // system prompt on first use (there is no separate "request" call).
        _ = try? await device.scan(timeout: 1)
        return Self.map(CBManager.authorization)
    }

    func openBluetoothSettings() async {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") {
            NSWorkspace.shared.open(url)
        }
    }

    nonisolated func scanForFieldy() -> AsyncStream<[FoundFieldy]> {
        let (stream, continuation) = AsyncStream.makeStream(of: [FoundFieldy].self)
        let device = device
        Task {
            do {
                let found = try await device.scan(stopAfterFirst: true)
                let mapped = found.map { FoundFieldy(id: $0.identifier.uuidString, name: $0.name, isVeryClose: $0.rssi > -60, isPairedElsewhere: false) }
                continuation.yield(mapped)
            } catch {
                continuation.yield([])
            }
            continuation.finish()
        }
        return stream
    }

    nonisolated func resetFieldy(_ id: String) -> AsyncStream<ResetOutcome> {
        // EarBudKit has no remote-reset command: the Fieldy is reset by its physical button
        // (short click, then hold 10 s). This stream just reflects "still waiting"; the
        // onboarding screen's own retry/"it didn't work" path covers the rest.
        let (stream, continuation) = AsyncStream.makeStream(of: ResetOutcome.self)
        continuation.yield(.waiting)
        continuation.finish()
        return stream
    }

    func pairAndConnect(_ id: String) async throws -> DeviceSnapshot {
        guard let uuid = UUID(uuidString: id) else { throw FieldyDeviceError.notFound }
        let info = try await device.connect(to: uuid)
        try? store?.setSetting(SettingKey.deviceIdentifier, info.identifier.uuidString)
        try? store?.setSetting(SettingKey.deviceName, info.name)
        let storage = try await device.pair()
        let battery = try? await device.battery()
        let mode = try? await device.recordingMode()
        let led = try? await device.ledOn()
        let muted = try? await device.muted()
        return DeviceSnapshot(
            name: info.name, model: info.deviceInfo.model ?? "Fieldy", firmware: info.deviceInfo.firmware ?? "",
            connection: .connected, batteryPercent: battery?.percent,
            waitingCount: storage.totalFileCount, waitingBytes: storage.totalFileSize,
            lastSynced: nil, pairedAt: Date(), checkedAt: Date(),
            recordingMode: mode.map(RealDeviceProvider.map) ?? .manual, lightOn: led ?? true, muted: muted ?? false,
            recordingStartedAt: nil)
    }

    func startTestRecording() async throws {
        let status = try await device.startRecording()
        if status.errorReason == .muted { throw DeviceError.muted }
    }

    func stopTestRecording() async throws {
        _ = try await device.stopRecording()
    }

    func syncTestRecording() async throws -> RecordingItem {
        guard let store, let library else { throw FieldyDeviceError.notConnected }
        let importer = RecordingImporter(library: store, transcriptionModel: Transcriber.TranscriptionModel.default.rawValue)
        let engine = SyncEngine(device: device, importer: importer)
        let summary = try await engine.sync()
        guard let recording = summary.recordings.first else { throw FieldyDeviceError.notFound }
        return RealLibraryProvider.map(recording)
    }

    private static func map(_ authorization: CBManagerAuthorization) -> BluetoothAuthorization {
        switch authorization {
        case .notDetermined: .notDetermined
        case .allowedAlways: .authorized
        case .restricted, .denied: .denied
        @unknown default: .notDetermined
        }
    }
}
