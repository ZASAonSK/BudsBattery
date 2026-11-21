import Foundation
import CoreBluetooth

struct Level: Codable, Equatable {
    var value: Int
    var date: Date
}

/// A Buds set heard nearby that the user can choose during setup.
struct Candidate: Identifiable {
    let token: Data
    var name: String
    var rssi: Int
    var caseLevel: Int?
    var left: Int?
    var right: Int?
    var lastSeen: Date
    var id: Data { token }
}

/// Two battery sources, merged per channel:
/// - GATT Battery Service, while the earbuds are connected to this phone (preferred);
/// - the Bluetooth broadcast (foreground scan), which needs no connection.
final class BudsStore: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    enum Channel: String { case left = "l", right = "r", box = "c" }

    @Published private(set) var left: Level?
    @Published private(set) var right: Level?
    @Published private(set) var caseLevel: Level?
    @Published private(set) var history: [Sample] = []
    @Published private(set) var rssi: Int?
    @Published private(set) var bluetoothReady = false
    @Published private(set) var denied = false
    @Published private(set) var gattChannels: Set<Channel> = []
    @Published private(set) var lastBroadcast: Date?
    @Published private(set) var candidates: [Candidate] = []
    @Published private(set) var deviceName = "Galaxy Buds"

    private var central: CBCentralManager!
    private var active = true
    private var token: Data? = UserDefaults.standard.data(forKey: "token")

    private let batteryService = CBUUID(string: "180F")
    private let infoService = CBUUID(string: "180A")
    private let vendorService = CBUUID(string: "A7A473E9-19C6-491B-AEA6-7EA92B8F043A")
    private let batteryChar = CBUUID(string: "2A19")
    private let modelChar = CBUUID(string: "2A24")
    private let formatDescriptor = CBUUID(string: "2904")
    private var gatt: CBPeripheral?
    private var gattKinds: [ObjectIdentifier: UInt16] = [:]
    private var gattValues: [ObjectIdentifier: Int] = [:]
    private var model: String?
    private var savedGattID = UserDefaults.standard.string(forKey: "gatt-id").flatMap(UUID.init)

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: "levels"),
           let saved = try? JSONDecoder().decode([String: Level].self, from: data) {
            left = saved["l"]; right = saved["r"]; caseLevel = saved["c"]
        }
        if let data = UserDefaults.standard.data(forKey: "history"),
           let saved = try? JSONDecoder().decode([Sample].self, from: data) { history = saved }
        deviceName = UserDefaults.standard.string(forKey: "name") ?? "Galaxy Buds"
        central = CBCentralManager(delegate: self, queue: .main)
    }

    var isSetUp: Bool { token != nil }
    var hasData: Bool { left != nil || right != nil || caseLevel != nil }

    func setActive(_ value: Bool) {
        active = value
        updateScan()
        if value { connectGatt() }
    }

    /// Locks onto the chosen set; broadcasts of other sets are ignored from now on.
    func choose(_ c: Candidate) {
        token = c.token
        deviceName = c.name
        UserDefaults.standard.set(c.token, forKey: "token")
        UserDefaults.standard.set(c.name, forKey: "name")
        candidates = []
        update([.left: c.left, .right: c.right, .box: c.caseLevel].compactMapValues { $0 }, gatt: false)
        connectGatt()
    }

    func forget() {
        if let p = gatt { resetGatt(); central.cancelPeripheralConnection(p) }
        token = nil; savedGattID = nil; left = nil; right = nil; caseLevel = nil
        history = []; rssi = nil; lastBroadcast = nil; deviceName = "Galaxy Buds"
        for key in ["token", "levels", "history", "gatt-id", "name"] { UserDefaults.standard.removeObject(forKey: key) }
    }

    // MARK: Merging

    private func level(_ c: Channel) -> Level? {
        switch c { case .left: left; case .right: right; case .box: caseLevel }
    }

    private func set(_ level: Level, _ c: Channel) {
        switch c { case .left: left = level; case .right: right = level; case .box: caseLevel = level }
    }

    /// GATT wins: a broadcast never overwrites a channel GATT currently supplies.
    private func update(_ values: [Channel: Int], gatt: Bool) {
        let now = Date()
        var changed = false
        for (channel, value) in values where gatt || !gattChannels.contains(channel) {
            if level(channel)?.value != value { changed = true }
            set(Level(value: value, date: now), channel)
        }
        // Timestamps refresh on every update; record and persist only on change.
        guard changed else { return }
        history.append(Sample(date: now, l: left?.value, r: right?.value, c: caseLevel?.value))
        if history.count > 1500 { history.removeFirst(history.count - 1500) }
        var saved: [String: Level] = [:]
        saved["l"] = left; saved["r"] = right; saved["c"] = caseLevel
        if let data = try? JSONEncoder().encode(saved) { UserDefaults.standard.set(data, forKey: "levels") }
        if let data = try? JSONEncoder().encode(history) { UserDefaults.standard.set(data, forKey: "history") }
    }

    // MARK: Central

    private func updateScan() {
        central.stopScan()
        if active, central.state == .poweredOn {
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothReady = central.state == .poweredOn
        denied = central.state == .unauthorized
        if bluetoothReady { connectGatt() } else { resetGatt(); gatt = nil }
        updateScan()
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
              let reading = BudsDecoder.decode(data) else { return }
        guard let token else {
            track(reading, name: advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name, rssi: RSSI.intValue)
            return
        }
        guard reading.token == token else { return }
        lastBroadcast = Date()
        if abs((rssi ?? 0) - RSSI.intValue) >= 3 { rssi = RSSI.intValue }
        update([.left: reading.left, .right: reading.right, .box: reading.caseLevel].compactMapValues { $0 }, gatt: false)
    }

    // MARK: Setup candidates

    private func track(_ reading: BudsBattery, name: String?, rssi: Int) {
        let now = Date()
        candidates.removeAll { now.timeIntervalSince($0.lastSeen) > 30 }
        // "Galaxy Buds3 Pro (1A2B) LE" -> "Galaxy Buds3 Pro"
        let clean = name?.replacingOccurrences(of: #"\s*\([0-9A-Fa-f]{4}\)|\s+LE$"#, with: "", options: .regularExpression)
        let title = clean.flatMap { $0.lowercased().contains("buds") ? $0 : nil }
        guard let i = candidates.firstIndex(where: { $0.token == reading.token }) else {
            candidates.append(Candidate(token: reading.token, name: title ?? "Galaxy Buds", rssi: rssi,
                                        caseLevel: reading.caseLevel, left: reading.left, right: reading.right, lastSeen: now))
            candidates.sort { $0.rssi > $1.rssi }
            return
        }
        var c = candidates[i]
        let changed = abs(c.rssi - rssi) >= 4 || (reading.left != nil && reading.left != c.left)
            || (reading.right != nil && reading.right != c.right) || (reading.caseLevel != nil && reading.caseLevel != c.caseLevel)
        // Frames arrive many times a second; publish a change or a keep-alive every 3 s.
        guard changed || now.timeIntervalSince(c.lastSeen) >= 3 else { return }
        c.rssi = rssi; c.lastSeen = now
        c.left = reading.left ?? c.left; c.right = reading.right ?? c.right; c.caseLevel = reading.caseLevel ?? c.caseLevel
        if let title { c.name = title }
        candidates[i] = c
        candidates.sort { $0.rssi > $1.rssi }
    }

    // MARK: GATT

    /// Samsung earbuds already connected to iOS are found by their vendor service,
    /// so a renamed device ("My buds") is still recognised.
    private func connectGatt() {
        guard central.state == .poweredOn, gatt == nil, isSetUp else { return }
        let vendor = central.retrieveConnectedPeripherals(withServices: [vendorService])
        let named = central.retrieveConnectedPeripherals(withServices: [batteryService])
            .filter { ($0.name ?? "").lowercased().contains("buds") }
        let candidate = vendor.first ?? named.first
            ?? savedGattID.flatMap { central.retrievePeripherals(withIdentifiers: [$0]).first }
        guard let p = candidate else { return }
        gatt = p
        p.delegate = self
        central.connect(p)   // pends until the earbuds are reachable
    }

    private func resetGatt() {
        gattChannels = []
        gattKinds.removeAll(); gattValues.removeAll(); model = nil
    }

    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        guard p === gatt else { return }
        savedGattID = p.identifier
        UserDefaults.standard.set(p.identifier.uuidString, forKey: "gatt-id")
        p.discoverServices([batteryService, infoService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        if p === gatt { gatt = nil }   // retried the next time the app becomes active
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        guard p === gatt else { return }
        resetGatt()
        if central.state == .poweredOn { central.connect(p) }   // pends until it is back
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for s in p.services ?? [] {
            p.discoverCharacteristics(s.uuid == batteryService ? [batteryChar] : [modelChar], for: s)
        }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for c in s.characteristics ?? [] {
            if c.uuid == modelChar { p.readValue(for: c) }
            if c.uuid == batteryChar {
                p.discoverDescriptors(for: c)
                p.readValue(for: c)
                if c.properties.contains(.notify) { p.setNotifyValue(true, for: c) }
            }
        }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverDescriptorsFor c: CBCharacteristic, error: Error?) {
        for d in c.descriptors ?? [] where d.uuid == formatDescriptor { p.readValue(for: d) }
    }

    /// 2904 Characteristic Presentation Format: namespace 1 + description id.
    func peripheral(_ p: CBPeripheral, didUpdateValueFor d: CBDescriptor, error: Error?) {
        guard let c = d.characteristic, let data = d.value as? Data, data.count >= 7 else { return }
        let b = [UInt8](data)
        guard b[4] == 1 else { return }
        gattKinds[ObjectIdentifier(c)] = UInt16(b[5]) | UInt16(b[6]) << 8
        publishGatt()
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        guard let data = c.value, let first = data.first else { return }
        if c.uuid == modelChar {
            model = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters)
        } else if c.uuid == batteryChar, first <= 100 {
            gattValues[ObjectIdentifier(c)] = Int(first)
        }
        publishGatt()
    }

    /// Description ids 0x010D / 0x010E label left / right. 0x0110 ("external")
    /// is the case on SM-R630 (Buds3 Pro), confirmed on hardware against the Windows reading;
    /// for other models it is not mapped rather than guessed.
    private func publishGatt() {
        var out: [Channel: Int] = [:]
        for (id, value) in gattValues {
            switch gattKinds[id] {
            case 0x010D: out[.left] = value
            case 0x010E: out[.right] = value
            case 0x0110 where model == "SM-R630": out[.box] = value
            default: break
            }
        }
        gattChannels = Set(out.keys)
        update(out, gatt: true)
    }
}
