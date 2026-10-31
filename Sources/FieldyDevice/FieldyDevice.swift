import FieldyProtocol
import Foundation

/// Device state shown in the main window and menu bar.
public enum ConnectionState: Equatable, Sendable {
    case bluetoothOff
    case bluetoothUnauthorized
    case bluetoothUnsupported
    /// Bluetooth is on; EarBud is not connected and not looking.
    case idle
    case searching
    case connecting
    case connected(name: String)
    /// The device was not found or the connection dropped.
    case notNearby
    case pairedElsewhere
}

/// Facts gathered by `connect()`.
public struct ConnectionInfo: Sendable, Equatable {
    public var identifier: UUID
    public var name: String
    public var deviceInfo: DeviceInfo
    /// When the clock was written (UTC).
    public var clockSetAt: Date
    /// The reset report was pending and has been acknowledged: the device was
    /// reset since the last connection and its clock had to be fixed.
    public var acknowledgedResetReport: ResetReport?
}

public struct BatteryInfo: Sendable, Equatable, Codable {
    public var percent: Int?
    public var millivolts: Int?
}

/// The Fieldy 3 as an async/await actor over CoreBluetooth.
///
/// On every connection it writes the clock first, then acknowledges a pending
/// reset report, then reads Device Information. It disconnects after
/// `idleDisconnectAfter` seconds with no activity.
public actor FieldyDevice {
    public struct Configuration: Sendable {
        public var namePrefix = FieldyGATT.namePrefix
        public var scanTimeout: TimeInterval = 20
        public var connectTimeout: TimeInterval = 20
        public var gattTimeout: TimeInterval = 10
        /// How long protected reads may fail before "paired elsewhere".
        public var pairingWindow: TimeInterval = 15
        public var pairingAttempts = 3
        /// Disconnect after this long without activity. Nil keeps the link.
        public var idleDisconnectAfter: TimeInterval? = 30

        public init() {}
    }

    public let configuration: Configuration
    public private(set) var state: ConnectionState = .idle
    /// The paired device (CoreBluetooth peripheral identifier).
    public private(set) var rememberedIdentifier: UUID?
    public private(set) var connection: ConnectionInfo?

    private let ble = BluetoothCentral()
    private var observers: [UUID: AsyncStream<ConnectionState>.Continuation] = [:]
    private var activities = 0
    private var idleTask: Task<Void, Never>?
    private var hooksInstalled = false

    public init(configuration: Configuration = Configuration(), rememberedIdentifier: UUID? = nil) {
        self.configuration = configuration
        self.rememberedIdentifier = rememberedIdentifier
    }

    // MARK: State stream

    /// A stream of connection states, starting with the current one.
    public func states() -> AsyncStream<ConnectionState> {
        let (stream, cont) = AsyncStream<ConnectionState>.makeStream(bufferingPolicy: .bufferingNewest(16))
        let id = UUID()
        observers[id] = cont
        cont.yield(state)
        cont.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(id) }
        }
        return stream
    }

    private func removeObserver(_ id: UUID) { observers[id] = nil }

    private func setState(_ s: ConnectionState) {
        guard s != state else { return }
        state = s
        for c in observers.values { c.yield(s) }
    }

    private func installHooks() {
        guard !hooksInstalled else { return }
        hooksInstalled = true
        ble.onDisconnect = { [weak self] error in
            Task { await self?.handleDisconnect(error) }
        }
        ble.onAvailabilityChange = { [weak self] a in
            Task { await self?.handleAvailability(a) }
        }
    }

    private func handleDisconnect(_ error: FieldyDeviceError?) {
        connection = nil
        idleTask?.cancel()
        if state == .pairedElsewhere { return }
        setState(error == nil ? .idle : .notNearby)
    }

    private func handleAvailability(_ a: BluetoothAvailability) {
        switch a {
        case .poweredOff: setState(.bluetoothOff)
        case .unauthorized: setState(.bluetoothUnauthorized)
        case .unsupported: setState(.bluetoothUnsupported)
        case .poweredOn:
            if [.bluetoothOff, .bluetoothUnauthorized, .bluetoothUnsupported].contains(state) { setState(.idle) }
        default: break
        }
    }

    private func requirePoweredOn() async throws {
        installHooks()
        let a = try await ble.availability()
        handleAvailability(a)
        guard a == .poweredOn else { throw FieldyDeviceError.bluetoothUnavailable(a) }
    }

    // MARK: Scan and connect

    /// Lists nearby Fieldy devices by name and signal strength.
    public func scan(timeout: TimeInterval? = nil, stopAfterFirst: Bool = false) async throws -> [DiscoveredFieldy] {
        try await requirePoweredOn()
        let previous = state
        setState(.searching)
        let found = FoundList()
        // Already connected to this Mac: not advertising, but usable.
        let connected = ble.connectedFieldys(namePrefix: configuration.namePrefix)
        for d in connected { found.add(d) }
        if stopAfterFirst, !connected.isEmpty {
            setState(previous == .searching ? .idle : previous)
            return connected
        }
        let (signal, signalCont) = AsyncStream<Void>.makeStream()
        ble.startScan(namePrefix: configuration.namePrefix) { d in
            found.add(d)
            if stopAfterFirst { signalCont.yield() }
        }
        let wait = timeout ?? configuration.scanTimeout
        let timer = Task {
            try? await Task.sleep(for: .seconds(wait))
            signalCont.finish()
        }
        for await _ in signal { break }
        timer.cancel()
        signalCont.finish()
        ble.stopScan()
        let result = found.all.sorted { $0.rssi > $1.rssi }
        setState(result.isEmpty ? .notNearby : (previous == .searching ? .idle : previous))
        return result
    }

    /// Diagnostic scan of every advertiser (name, RSSI, advertised services).
    public func scanAll(seconds: TimeInterval) async throws -> [(identifier: UUID, name: String?, rssi: Int, services: [String])] {
        try await requirePoweredOn()
        let box = RawList()
        ble.startRawScan { id, name, rssi, services in box.add((id, name, rssi, services)) }
        try await Task.sleep(for: .seconds(seconds))
        ble.stopScan()
        return box.all
    }

    /// Connects to `identifier`, the remembered device, or the first Fieldy
    /// found. Then writes the clock, acknowledges a pending reset report and
    /// reads Device Information.
    @discardableResult
    public func connect(to identifier: UUID? = nil, now: @Sendable () -> Date = Date.init) async throws -> ConnectionInfo {
        try await requirePoweredOn()
        if let c = connection, ble.isConnected, identifier == nil || identifier == c.identifier {
            touch()
            return c
        }
        beginActivity()
        defer { endActivity() }
        var target = identifier ?? rememberedIdentifier
        if target == nil {
            guard let first = try await scan(stopAfterFirst: true).first else {
                setState(.notNearby)
                throw FieldyDeviceError.notFound
            }
            target = first.identifier
        }
        setState(.connecting)
        let name: String
        do {
            name = try await ble.connect(identifier: target!, timeout: configuration.connectTimeout)
        } catch FieldyDeviceError.notFound {
            // Not known to the system yet: scan for it once.
            setState(.searching)
            let seen = try await scan()
            guard seen.contains(where: { $0.identifier == target }) else {
                setState(.notNearby)
                throw FieldyDeviceError.notFound
            }
            setState(.connecting)
            name = try await ble.connect(identifier: target!, timeout: configuration.connectTimeout)
        } catch {
            setState(.notNearby)
            throw error
        }
        rememberedIdentifier = target
        // Clock first, before anything else.
        let clockAt = now()
        try await ble.write(ClockPayload.make(clockAt), to: FieldyGATT.currentTime, timeout: configuration.gattTimeout)
        let acked = try await acknowledgeResetReportIfPending()
        let info = await readDeviceInfo()
        let c = ConnectionInfo(identifier: target!, name: name, deviceInfo: info, clockSetAt: clockAt,
                               acknowledgedResetReport: acked)
        connection = c
        setState(.connected(name: name))
        return c
    }

    public func disconnect() {
        idleTask?.cancel()
        ble.disconnect()
        connection = nil
        if case .connected = state { setState(.idle) }
    }

    /// Forgets the remembered device.
    public func forget() {
        rememberedIdentifier = nil
        disconnect()
    }

    // MARK: Activity and idle disconnect

    /// Marks the start of a sync or device action; prevents idle disconnect.
    public func beginActivity() {
        activities += 1
        idleTask?.cancel()
    }

    public func endActivity() {
        activities = max(0, activities - 1)
        touch()
    }

    private func touch() {
        idleTask?.cancel()
        guard activities == 0, let after = configuration.idleDisconnectAfter else { return }
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(after))
            guard !Task.isCancelled else { return }
            await self?.idleExpired()
        }
    }

    private func idleExpired() {
        guard activities == 0, connection != nil else { return }
        disconnect()
    }

    private func op<T: Sendable>(_ body: () async throws -> T) async throws -> T {
        guard connection != nil else { throw FieldyDeviceError.notConnected }
        beginActivity()
        defer { endActivity() }
        return try await body()
    }

    // MARK: Pairing

    /// Bonds by reading protected storage status; macOS bonds silently on the
    /// first encrypted read. If protected reads keep failing with an
    /// encryption/authentication error for `pairingWindow` seconds while an
    /// unprotected read works, reports `.pairedElsewhere`.
    public func pair() async throws -> StorageStatus {
        try await op {
            let attempts = max(1, configuration.pairingAttempts)
            let pause = configuration.pairingWindow / Double(attempts)
            var lastError: FieldyDeviceError = .pairedElsewhere
            for attempt in 1...attempts {
                do {
                    let data = try await ble.read(FieldyGATT.storage, timeout: max(configuration.gattTimeout, pause))
                    return try StorageStatus(parsing: data)
                } catch let e as FieldyDeviceError where e.isPairingFailure {
                    lastError = e
                    if attempt < attempts { try await Task.sleep(for: .seconds(pause)) }
                }
            }
            // Protected reads failed throughout. Is the link itself fine?
            if (try? await ble.read(FieldyGATT.batteryLevel, timeout: configuration.gattTimeout)) != nil {
                setState(.pairedElsewhere)
                throw FieldyDeviceError.pairedElsewhere
            }
            throw lastError
        }
    }

    // MARK: Clock and reset report

    /// Writes the current UTC time. Done automatically on connect; the app
    /// repeats it every 30 minutes while connected.
    public func setClock(_ date: Date = Date()) async throws {
        try await op { try await ble.write(ClockPayload.make(date), to: FieldyGATT.currentTime, timeout: configuration.gattTimeout) }
    }

    public func readClock() async throws -> Date? {
        try await op { ClockPayload.parse(try await ble.read(FieldyGATT.currentTime, timeout: configuration.gattTimeout)) }
    }

    /// Reads `...66EE` and writes `01` if a reset event is pending.
    /// Returns the report that was acknowledged, or nil.
    private func acknowledgeResetReportIfPending() async throws -> ResetReport? {
        let data: Data
        do {
            data = try await ble.read(FieldyGATT.resetReport, timeout: configuration.gattTimeout)
        } catch FieldyDeviceError.characteristicMissing {
            return nil // older firmware
        }
        guard let report = try? ResetReport(parsing: data), report.needsAcknowledgement else { return nil }
        try await ble.write(ResetReport.acknowledgement, to: FieldyGATT.resetReport, timeout: configuration.gattTimeout)
        return report
    }

    public func resetReport() async throws -> ResetReport {
        try await op { try ResetReport(parsing: try await ble.read(FieldyGATT.resetReport, timeout: configuration.gattTimeout)) }
    }

    // MARK: Status

    public func storageStatus() async throws -> StorageStatus {
        try await op { try StorageStatus(parsing: try await ble.read(FieldyGATT.storage, timeout: configuration.gattTimeout)) }
    }

    public func recordingStatus() async throws -> RecordingStatus {
        try await op { try RecordingStatus(parsing: try await ble.read(FieldyGATT.recordingControl, timeout: configuration.gattTimeout)) }
    }

    public func battery() async throws -> BatteryInfo {
        try await op {
            let pct = try await ble.read(FieldyGATT.batteryLevel, timeout: configuration.gattTimeout)
            let mv = try? await ble.read(FieldyGATT.batteryVoltage, timeout: configuration.gattTimeout)
            return BatteryInfo(percent: DeviceValues.batteryPercent(pct), millivolts: mv.flatMap(DeviceValues.batteryMillivolts))
        }
    }

    public func temperature() async throws -> Double? {
        try await op { DeviceValues.temperatureCelsius(try await ble.read(FieldyGATT.temperature, timeout: configuration.gattTimeout)) }
    }

    public func deviceInfo() async throws -> DeviceInfo {
        try await op { await readDeviceInfo() }
    }

    private func readDeviceInfo() async -> DeviceInfo {
        func s(_ uuid: String) async -> String? {
            guard let d = try? await ble.read(uuid, timeout: configuration.gattTimeout) else { return nil }
            return DeviceInfo.string(d)
        }
        return DeviceInfo(
            model: await s(FieldyGATT.modelNumber),
            manufacturer: await s(FieldyGATT.manufacturerName),
            serialNumber: await s(FieldyGATT.serialNumber),
            firmware: await s(FieldyGATT.firmwareRevision),
            hardware: await s(FieldyGATT.hardwareRevision),
            software: await s(FieldyGATT.softwareRevision))
    }

    // MARK: Controls (each change is read back)

    public func recordingMode() async throws -> RecordingMode {
        try await op {
            let d = try await ble.read(FieldyGATT.recordingMode, timeout: configuration.gattTimeout)
            guard let m = RecordingMode(data: d) else { throw FieldyDeviceError.invalidResponse("recording mode \(d.hexString)") }
            return m
        }
    }

    /// Writes the mode and returns the value read back from the device.
    @discardableResult
    public func setRecordingMode(_ mode: RecordingMode) async throws -> RecordingMode {
        try await op {
            try await ble.write(mode.payload, to: FieldyGATT.recordingMode, timeout: configuration.gattTimeout)
            let d = try await ble.read(FieldyGATT.recordingMode, timeout: configuration.gattTimeout)
            guard let m = RecordingMode(data: d) else { throw FieldyDeviceError.invalidResponse("recording mode \(d.hexString)") }
            return m
        }
    }

    public func ledOn() async throws -> Bool { try await readFlag(FieldyGATT.led) }
    @discardableResult
    public func setLED(_ on: Bool) async throws -> Bool { try await writeFlag(on, FieldyGATT.led) }

    public func muted() async throws -> Bool { try await readFlag(FieldyGATT.mute) }
    @discardableResult
    public func setMuted(_ on: Bool) async throws -> Bool { try await writeFlag(on, FieldyGATT.mute) }

    private func readFlag(_ uuid: String) async throws -> Bool {
        try await op {
            let d = try await ble.read(uuid, timeout: configuration.gattTimeout)
            guard let v = DeviceValues.flag(d) else { throw FieldyDeviceError.invalidResponse("empty value for \(uuid)") }
            return v
        }
    }

    private func writeFlag(_ on: Bool, _ uuid: String) async throws -> Bool {
        try await op {
            try await ble.write(DeviceValues.flag(on), to: uuid, timeout: configuration.gattTimeout)
            let d = try await ble.read(uuid, timeout: configuration.gattTimeout)
            guard let v = DeviceValues.flag(d) else { throw FieldyDeviceError.invalidResponse("empty value for \(uuid)") }
            return v
        }
    }

    /// "Buzz my Fieldy".
    public func buzz() async throws {
        try await op { try await ble.write(ControlCommand.buzz, to: FieldyGATT.haptics, timeout: configuration.gattTimeout) }
    }

    /// Starts a recording to the device's own storage. Returns the status
    /// read afterwards (check `errorReason` for `.muted`, `.timeNotSet`).
    public func startRecording() async throws -> RecordingStatus {
        try await op {
            try await ble.write(ControlCommand.startRecording, to: FieldyGATT.recordingControl, timeout: configuration.gattTimeout)
            return try RecordingStatus(parsing: try await ble.read(FieldyGATT.recordingControl, timeout: configuration.gattTimeout))
        }
    }

    public func stopRecording() async throws -> RecordingStatus {
        try await op {
            try await ble.write(ControlCommand.stopRecording, to: FieldyGATT.recordingControl, timeout: configuration.gattTimeout)
            return try RecordingStatus(parsing: try await ble.read(FieldyGATT.recordingControl, timeout: configuration.gattTimeout))
        }
    }

    // MARK: Raw GATT (used by SyncEngine)

    public func read(_ uuid: String) async throws -> Data {
        try await op { try await ble.read(uuid, timeout: configuration.gattTimeout) }
    }

    public func write(_ data: Data, to uuid: String) async throws {
        try await op { try await ble.write(data, to: uuid, timeout: configuration.gattTimeout) }
    }

    /// Subscribes to notifications. `handler` runs synchronously on the
    /// Bluetooth queue, in arrival order, before the next notification.
    public func subscribe(_ uuid: String, handler: @escaping @Sendable (Data) -> Void) async throws {
        try await op { try await ble.setNotify(true, for: uuid, timeout: configuration.gattTimeout, handler: handler) }
    }

    public func unsubscribe(_ uuid: String) async {
        try? await ble.setNotify(false, for: uuid, timeout: configuration.gattTimeout, handler: nil)
    }

    public var maximumWriteLength: Int? { ble.maximumWriteLength() }
}

private final class RawList: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [UUID: (identifier: UUID, name: String?, rssi: Int, services: [String])] = [:]

    func add(_ d: (identifier: UUID, name: String?, rssi: Int, services: [String])) {
        lock.lock(); defer { lock.unlock() }
        items[d.identifier] = d
    }

    var all: [(identifier: UUID, name: String?, rssi: Int, services: [String])] {
        lock.lock(); defer { lock.unlock() }
        return items.values.sorted { $0.rssi > $1.rssi }
    }
}

/// Thread-safe accumulator for scan results.
private final class FoundList: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [UUID: DiscoveredFieldy] = [:]

    func add(_ d: DiscoveredFieldy) {
        lock.lock(); defer { lock.unlock() }
        if let old = items[d.identifier], old.rssi > d.rssi { return }
        items[d.identifier] = d
    }

    var all: [DiscoveredFieldy] {
        lock.lock(); defer { lock.unlock() }
        return Array(items.values)
    }
}
