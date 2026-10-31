@preconcurrency import CoreBluetooth
import FieldyProtocol
import Foundation

/// A Fieldy seen while scanning.
public struct DiscoveredFieldy: Sendable, Equatable, Identifiable {
    public var id: UUID { identifier }
    public var identifier: UUID
    public var name: String
    public var rssi: Int

    public init(identifier: UUID, name: String, rssi: Int) {
        self.identifier = identifier
        self.name = name
        self.rssi = rssi
    }
}

public enum FieldyDeviceError: Error, Equatable, Sendable, CustomStringConvertible {
    /// Bluetooth is off, unsupported, or EarBud is not allowed to use it.
    case bluetoothUnavailable(BluetoothAvailability)
    case notFound
    case notConnected
    case disconnected(String?)
    case timeout(String)
    case characteristicMissing(String)
    /// ATT error from the device (CBATTErrorDomain code).
    case att(code: Int, operation: String)
    /// CoreBluetooth error (CBErrorDomain code).
    case coreBluetooth(code: Int, message: String)
    /// Protected reads keep failing with an encryption/authentication error.
    case pairedElsewhere
    case invalidResponse(String)
    /// A read of a characteristic whose notifications are on was refused:
    /// CoreBluetooth reports read replies and notifications through the same
    /// callback, so the two cannot be told apart.
    case readWhileNotifying(String)

    public var description: String {
        switch self {
        case .bluetoothUnavailable(let a): "Bluetooth unavailable: \(a)"
        case .notFound: "Fieldy not found"
        case .notConnected: "not connected"
        case .disconnected(let m): "disconnected\(m.map { ": \($0)" } ?? "")"
        case .timeout(let what): "timed out: \(what)"
        case .characteristicMissing(let u): "characteristic \(u) not found"
        case .att(let code, let op): String(format: "ATT error 0x%02X during %@", code, op)
        case .coreBluetooth(let code, let m): "CoreBluetooth error \(code): \(m)"
        case .pairedElsewhere: "This Fieldy is paired with another device"
        case .invalidResponse(let m): "invalid response: \(m)"
        case .readWhileNotifying(let u): "cannot read \(u) while its notifications are on"
        }
    }

    /// ATT 0x0F insufficient encryption, 0x05 insufficient authentication,
    /// 0x0C insufficient encryption key size, or the CoreBluetooth errors macOS
    /// reports when the peer refuses to (re)bond.
    public var isPairingFailure: Bool {
        switch self {
        case .att(let code, _): [0x05, 0x0C, 0x0F].contains(code)
        case .coreBluetooth(let code, _):
            code == CBError.Code.peerRemovedPairingInformation.rawValue || code == CBError.Code.encryptionTimedOut.rawValue
        default: false
        }
    }

    static func from(_ error: Error, operation: String) -> FieldyDeviceError {
        if let e = error as? FieldyDeviceError { return e }
        let ns = error as NSError
        if ns.domain == CBATTErrorDomain { return .att(code: ns.code, operation: operation) }
        if ns.domain == CBErrorDomain { return .coreBluetooth(code: ns.code, message: ns.localizedDescription) }
        return .coreBluetooth(code: ns.code, message: "\(ns.domain): \(ns.localizedDescription)")
    }
}

public enum BluetoothAvailability: String, Sendable, Equatable {
    case unknown, resetting, unsupported, unauthorized, poweredOff, poweredOn

    init(_ s: CBManagerState) {
        switch s {
        case .unknown: self = .unknown
        case .resetting: self = .resetting
        case .unsupported: self = .unsupported
        case .unauthorized: self = .unauthorized
        case .poweredOff: self = .poweredOff
        case .poweredOn: self = .poweredOn
        @unknown default: self = .unknown
        }
    }
}

/// FIFO waiters keyed by an operation key (e.g. a characteristic UUID), each
/// with an id so a timeout can remove exactly one.
private struct Waiters<T: Sendable> {
    private var items: [(id: Int, key: String, cont: CheckedContinuation<T, Error>)] = []

    mutating func add(id: Int, key: String, _ cont: CheckedContinuation<T, Error>) { items.append((id, key, cont)) }

    mutating func popFirst(key: String) -> CheckedContinuation<T, Error>? {
        guard let i = items.firstIndex(where: { $0.key == key }) else { return nil }
        return items.remove(at: i).cont
    }

    mutating func remove(id: Int) -> CheckedContinuation<T, Error>? {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return nil }
        return items.remove(at: i).cont
    }

    mutating func removeAll() -> [CheckedContinuation<T, Error>] {
        defer { items.removeAll() }
        return items.map(\.cont)
    }

    func has(key: String) -> Bool { items.contains { $0.key == key } }
}

/// CoreBluetooth wrapper. All mutable state is confined to `queue`, which is
/// also the CBCentralManager delegate queue, so delegate callbacks run
/// synchronously against that state. Notification handlers are called
/// synchronously inside `didUpdateValueFor`, which lets the sync engine make
/// each packet durable before the next one is delivered.
final class BluetoothCentral: NSObject, @unchecked Sendable {
    let queue = DispatchQueue(label: "dev.earbud.fieldy.bluetooth", qos: .userInitiated)
    private var central: CBCentralManager!

    // Queue-confined state.
    private var nextID = 0
    private var stateWaiters = Waiters<BluetoothAvailability>()
    private var scanHandler: (@Sendable (DiscoveredFieldy) -> Void)?
    private var rawScanHandler: (@Sendable (UUID, String?, Int, [String]) -> Void)?
    private var namePrefix = FieldyGATT.namePrefix
    private var known: [UUID: CBPeripheral] = [:]
    private var peripheral: CBPeripheral?
    private var userDisconnect = false
    private var connectWaiters = Waiters<Void>()
    private var discoverWaiters = Waiters<Void>()
    private var servicesPendingCharacteristics = 0
    private var readWaiters = Waiters<Data>()
    private var writeWaiters = Waiters<Void>()
    private var notifyWaiters = Waiters<Void>()
    private var notifyHandlers: [String: @Sendable (Data) -> Void] = [:]

    /// Called on `queue` when the link drops. The error is nil for a requested disconnect.
    var onDisconnect: (@Sendable (FieldyDeviceError?) -> Void)?
    var onAvailabilityChange: (@Sendable (BluetoothAvailability) -> Void)?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: queue, options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }

    private func makeID() -> Int { nextID += 1; return nextID }

    private func key(_ uuid: CBUUID) -> String { uuid.uuidString.uppercased() }
    private func key(_ uuid: String) -> String { CBUUID(string: uuid).uuidString.uppercased() }

    private func timeout(after seconds: TimeInterval, _ body: @escaping @Sendable () -> Void) {
        queue.asyncAfter(deadline: .now() + seconds, execute: body)
    }

    // MARK: State

    func availability(timeout seconds: TimeInterval = 5) async throws -> BluetoothAvailability {
        if CBManager.authorization == .denied || CBManager.authorization == .restricted {
            return .unauthorized
        }
        return try await withCheckedThrowingContinuation { cont in
            queue.async { [self] in
                let s = BluetoothAvailability(central.state)
                if s != .unknown && s != .resetting { cont.resume(returning: s); return }
                let id = makeID()
                stateWaiters.add(id: id, key: "state", cont)
                timeout(after: seconds) { [self] in
                    stateWaiters.remove(id: id)?.resume(returning: BluetoothAvailability(central.state))
                }
            }
        }
    }

    // MARK: Scan

    func startScan(namePrefix: String, handler: @escaping @Sendable (DiscoveredFieldy) -> Void) {
        queue.async { [self] in
            self.namePrefix = namePrefix
            scanHandler = handler
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        }
    }

    /// Fieldy devices already connected to this Mac (by the system or another
    /// app). A connected peripheral stops advertising, so a scan misses it.
    func connectedFieldys(namePrefix: String) -> [DiscoveredFieldy] {
        queue.sync {
            let services = [CBUUID(string: FieldyGATT.serviceA)]
            return central.retrieveConnectedPeripherals(withServices: services).compactMap { p in
                guard let name = p.name, name.hasPrefix(namePrefix) else { return nil }
                known[p.identifier] = p
                return DiscoveredFieldy(identifier: p.identifier, name: name, rssi: 0)
            }
        }
    }

    /// Diagnostic: every advertiser, regardless of name.
    func startRawScan(handler: @escaping @Sendable (UUID, String?, Int, [String]) -> Void) {
        queue.async { [self] in
            rawScanHandler = handler
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        }
    }

    func stopScan() {
        queue.async { [self] in
            scanHandler = nil
            rawScanHandler = nil
            if central.isScanning { central.stopScan() }
        }
    }

    // MARK: Connect

    var isConnected: Bool {
        queue.sync { peripheral?.state == .connected }
    }

    /// Connects to a peripheral seen in a scan or known to the system, then
    /// discovers all services and characteristics.
    func connect(identifier: UUID, timeout seconds: TimeInterval) async throws -> String {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                let p = known[identifier] ?? central.retrievePeripherals(withIdentifiers: [identifier]).first
                guard let p else { cont.resume(throwing: FieldyDeviceError.notFound); return }
                if let current = peripheral, current.identifier != identifier {
                    central.cancelPeripheralConnection(current)
                }
                peripheral = p
                p.delegate = self
                userDisconnect = false
                if p.state == .connected { cont.resume(); return }
                let id = makeID()
                connectWaiters.add(id: id, key: "connect", cont)
                central.connect(p, options: nil)
                timeout(after: seconds) { [self] in
                    if let c = connectWaiters.remove(id: id) {
                        central.cancelPeripheralConnection(p)
                        c.resume(throwing: FieldyDeviceError.timeout("connect"))
                    }
                }
            }
        }
        try await discoverAll(timeout: seconds)
        return queue.sync { peripheral?.name ?? "Fieldy" }
    }

    private func discoverAll(timeout seconds: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                guard let p = peripheral, p.state == .connected else {
                    cont.resume(throwing: FieldyDeviceError.notConnected); return
                }
                let id = makeID()
                discoverWaiters.add(id: id, key: "discover", cont)
                p.discoverServices(nil)
                timeout(after: seconds) { [self] in
                    discoverWaiters.remove(id: id)?.resume(throwing: FieldyDeviceError.timeout("service discovery"))
                }
            }
        }
    }

    func disconnect() {
        queue.async { [self] in
            guard let p = peripheral else { return }
            userDisconnect = true
            central.cancelPeripheralConnection(p)
        }
    }

    /// Notifications for `uuid` are on (or being turned on) with a handler.
    func isNotifying(_ uuid: String) -> Bool {
        let k = key(uuid)
        return queue.sync { notifyHandlers[k] != nil }
    }

    func maximumWriteLength() -> Int? {
        queue.sync { peripheral?.maximumWriteValueLength(for: .withResponse) }
    }

    // MARK: GATT

    private func characteristic(_ k: String) -> CBCharacteristic? {
        for s in peripheral?.services ?? [] {
            for c in s.characteristics ?? [] where key(c.uuid) == k { return c }
        }
        return nil
    }

    func read(_ uuid: String, timeout seconds: TimeInterval) async throws -> Data {
        let k = key(uuid)
        return try await withCheckedThrowingContinuation { cont in
            queue.async { [self] in
                guard let p = peripheral, p.state == .connected else {
                    cont.resume(throwing: FieldyDeviceError.notConnected); return
                }
                guard let ch = characteristic(k) else {
                    cont.resume(throwing: FieldyDeviceError.characteristicMissing(uuid)); return
                }
                // The reply would be indistinguishable from a notification in
                // didUpdateValueFor: the read would take a notification and the
                // reply would reach the notification handler.
                guard notifyHandlers[k] == nil else {
                    cont.resume(throwing: FieldyDeviceError.readWhileNotifying(uuid)); return
                }
                let id = makeID()
                readWaiters.add(id: id, key: k, cont)
                p.readValue(for: ch)
                timeout(after: seconds) { [self] in
                    readWaiters.remove(id: id)?.resume(throwing: FieldyDeviceError.timeout("read \(uuid)"))
                }
            }
        }
    }

    func write(_ data: Data, to uuid: String, timeout seconds: TimeInterval) async throws {
        let k = key(uuid)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                guard let p = peripheral, p.state == .connected else {
                    cont.resume(throwing: FieldyDeviceError.notConnected); return
                }
                guard let ch = characteristic(k) else {
                    cont.resume(throwing: FieldyDeviceError.characteristicMissing(uuid)); return
                }
                let id = makeID()
                writeWaiters.add(id: id, key: k, cont)
                p.writeValue(data, for: ch, type: .withResponse)
                timeout(after: seconds) { [self] in
                    writeWaiters.remove(id: id)?.resume(throwing: FieldyDeviceError.timeout("write \(uuid)"))
                }
            }
        }
    }

    /// Enables notifications. `handler` runs on the Bluetooth queue, in order,
    /// before the next notification is processed.
    func setNotify(_ enabled: Bool, for uuid: String, timeout seconds: TimeInterval,
                   handler: (@Sendable (Data) -> Void)?) async throws {
        let k = key(uuid)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                guard let p = peripheral, p.state == .connected else {
                    if !enabled { notifyHandlers[k] = nil; cont.resume(); return }
                    cont.resume(throwing: FieldyDeviceError.notConnected); return
                }
                guard let ch = characteristic(k) else {
                    cont.resume(throwing: FieldyDeviceError.characteristicMissing(uuid)); return
                }
                if enabled { notifyHandlers[k] = handler }
                let id = makeID()
                notifyWaiters.add(id: id, key: k, cont)
                p.setNotifyValue(enabled, for: ch)
                timeout(after: seconds) { [self] in
                    notifyWaiters.remove(id: id)?.resume(throwing: FieldyDeviceError.timeout("notify \(uuid)"))
                }
            }
        }
    }

    private func failAll(_ error: FieldyDeviceError) {
        for c in connectWaiters.removeAll() { c.resume(throwing: error) }
        for c in discoverWaiters.removeAll() { c.resume(throwing: error) }
        for c in readWaiters.removeAll() { c.resume(throwing: error) }
        for c in writeWaiters.removeAll() { c.resume(throwing: error) }
        for c in notifyWaiters.removeAll() { c.resume(throwing: error) }
        notifyHandlers.removeAll()
        servicesPendingCharacteristics = 0
    }
}

extension BluetoothCentral: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let s = BluetoothAvailability(central.state)
        if s != .unknown && s != .resetting {
            while let c = stateWaiters.popFirst(key: "state") { c.resume(returning: s) }
        }
        if s != .poweredOn, peripheral != nil {
            failAll(.bluetoothUnavailable(s))
        }
        onAvailabilityChange?(s)
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? ""
        if let raw = rawScanHandler {
            let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.map(\.uuidString) ?? []
            raw(peripheral.identifier, name.isEmpty ? nil : name, RSSI.intValue, services)
        }
        guard name.hasPrefix(namePrefix), let handler = scanHandler else { return }
        known[peripheral.identifier] = peripheral
        handler(DiscoveredFieldy(identifier: peripheral.identifier, name: name, rssi: RSSI.intValue))
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        while let c = connectWaiters.popFirst(key: "connect") { c.resume() }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let e = error.map { FieldyDeviceError.from($0, operation: "connect") } ?? .disconnected("failed to connect")
        while let c = connectWaiters.popFirst(key: "connect") { c.resume(throwing: e) }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral.identifier == self.peripheral?.identifier else { return }
        let requested = userDisconnect
        let reason: FieldyDeviceError = .disconnected(error?.localizedDescription)
        failAll(reason)
        userDisconnect = false
        onDisconnect?(requested ? nil : reason)
    }
}

extension BluetoothCentral: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            let e = FieldyDeviceError.from(error, operation: "discover services")
            while let c = discoverWaiters.popFirst(key: "discover") { c.resume(throwing: e) }
            return
        }
        let services = peripheral.services ?? []
        servicesPendingCharacteristics = services.count
        if services.isEmpty {
            while let c = discoverWaiters.popFirst(key: "discover") { c.resume() }
        }
        for s in services { peripheral.discoverCharacteristics(nil, for: s) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        servicesPendingCharacteristics -= 1
        if servicesPendingCharacteristics <= 0 {
            while let c = discoverWaiters.popFirst(key: "discover") { c.resume() }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let k = key(characteristic.uuid)
        if let read = readWaiters.popFirst(key: k) {
            if let error {
                read.resume(throwing: FieldyDeviceError.from(error, operation: "read \(k)"))
            } else {
                read.resume(returning: characteristic.value ?? Data())
            }
            return
        }
        guard error == nil, let value = characteristic.value, let handler = notifyHandlers[k] else { return }
        handler(value)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        let k = key(characteristic.uuid)
        guard let c = writeWaiters.popFirst(key: k) else { return }
        if let error { c.resume(throwing: FieldyDeviceError.from(error, operation: "write \(k)")) } else { c.resume() }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        let k = key(characteristic.uuid)
        if error != nil || !characteristic.isNotifying { notifyHandlers[k] = nil }
        guard let c = notifyWaiters.popFirst(key: k) else { return }
        if let error { c.resume(throwing: FieldyDeviceError.from(error, operation: "notify \(k)")) } else { c.resume() }
    }
}
