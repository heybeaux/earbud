import FieldyDevice
import FieldyProtocol
import Foundation
import Library

/// Adapts EarBudKit's `FieldyDevice` (CoreBluetooth actor) to `DeviceProviding`.
///
/// Remembers the paired device's CoreBluetooth identifier in the library's
/// `setting` table (`SettingKey.deviceIdentifier`/`deviceName`) so EarBud can
/// reconnect to the right Fieldy without scanning every launch.
final class RealDeviceProvider: DeviceProviding, Sendable {
    let device: FieldyDevice
    private let store: LibraryStore?
    private let now: @Sendable () -> Date

    init(device: FieldyDevice = FieldyDevice(), store: LibraryStore? = nil, now: @escaping @Sendable () -> Date = Date.init) {
        self.device = device
        self.store = store
        self.now = now
    }

    /// Reconnects to the remembered device, if any, without blocking callers who just want a snapshot.
    static func makeRemembering(store: LibraryStore?) -> RealDeviceProvider {
        var configuration = FieldyDevice.Configuration()
        configuration.idleDisconnectAfter = 30
        let remembered = (try? store?.setting(SettingKey.deviceIdentifier)).flatMap { $0 }.flatMap(UUID.init(uuidString:))
        let device = FieldyDevice(configuration: configuration, rememberedIdentifier: remembered)
        return RealDeviceProvider(device: device, store: store)
    }

    private func remember(_ info: ConnectionInfo) {
        try? store?.setSetting(SettingKey.deviceIdentifier, info.identifier.uuidString)
        try? store?.setSetting(SettingKey.deviceName, info.name)
    }

    // MARK: DeviceProviding

    func snapshot() async -> DeviceSnapshot {
        if let connection = await device.connection {
            return await buildSnapshot(connection: connection, checkedAt: now())
        }
        return await emptySnapshot()
    }

    func refresh() async throws -> DeviceSnapshot {
        let info = try await device.connect(now: now)
        remember(info)
        return await buildSnapshot(connection: info, checkedAt: now())
    }

    func setRecordingMode(_ mode: RecordingMode) async throws -> RecordingMode {
        let confirmed = try await device.setRecordingMode(Self.map(mode))
        return Self.map(confirmed)
    }

    func setLight(_ on: Bool) async throws -> Bool {
        try await device.setLED(on)
    }

    func setMuted(_ muted: Bool) async throws -> Bool {
        try await device.setMuted(muted)
    }

    func buzz() async throws {
        try await device.buzz()
    }

    func startRecording() async throws -> Date {
        let status = try await device.startRecording()
        if status.errorReason == .muted { throw DeviceError.muted }
        guard status.state != .error else { throw DeviceError.notConfirmed }
        return now()
    }

    func stopRecording() async throws {
        _ = try await device.stopRecording()
    }

    // MARK: Snapshot building

    private func emptySnapshot() async -> DeviceSnapshot {
        let state = await device.state
        return DeviceSnapshot(
            name: "Fieldy", model: "", firmware: "", connection: Self.map(state),
            batteryPercent: nil, waitingCount: 0, waitingBytes: 0, lastSynced: lastSynced(), pairedAt: nil,
            checkedAt: nil, recordingMode: .manual, lightOn: true, muted: false, recordingStartedAt: nil)
    }

    private func buildSnapshot(connection: ConnectionInfo, checkedAt: Date) async -> DeviceSnapshot {
        async let battery = try? device.battery()
        async let recordingStatus = try? device.recordingStatus()
        async let mode = try? device.recordingMode()
        async let led = try? device.ledOn()
        async let muted = try? device.muted()
        async let storage = try? device.pair()

        let batteryInfo = await battery
        let recording = await recordingStatus
        let storageStatus = await storage
        let state = await device.state

        return DeviceSnapshot(
            name: connection.name,
            model: connection.deviceInfo.model ?? "Fieldy",
            firmware: connection.deviceInfo.firmware ?? "",
            connection: Self.map(state),
            batteryPercent: batteryInfo?.percent,
            waitingCount: storageStatus?.totalFileCount ?? 0,
            waitingBytes: storageStatus?.totalFileSize ?? 0,
            lastSynced: lastSynced(),
            pairedAt: nil,
            checkedAt: checkedAt,
            recordingMode: (await mode).map(Self.map) ?? .manual,
            lightOn: (await led) ?? true,
            muted: (await muted) ?? false,
            recordingStartedAt: recording?.isRecording == true ? checkedAt : nil)
    }

    private func lastSynced() -> Date? {
        (try? store?.lastSuccessfulSync()).flatMap { $0 }?.finishedAt
    }

    // MARK: Mapping

    static func map(_ mode: RecordingMode) -> FieldyProtocol.RecordingMode {
        switch mode {
        case .manual: .manual
        case .automatic: .automatic
        }
    }

    static func map(_ mode: FieldyProtocol.RecordingMode) -> RecordingMode {
        switch mode {
        case .manual: .manual
        case .automatic: .automatic
        }
    }

    static func map(_ state: ConnectionState) -> DeviceConnection {
        switch state {
        case .connected: .connected
        case .connecting: .connecting
        case .searching: .searching
        case .idle, .notNearby: .notNearby
        case .bluetoothOff, .bluetoothUnauthorized, .bluetoothUnsupported: .bluetoothOff
        case .pairedElsewhere: .pairedElsewhere
        }
    }
}
