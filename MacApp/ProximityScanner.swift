import CoreBluetooth
import Foundation

/// Scans for the phone's BLE beacon and turns RSSI into "how close is the phone".
final class ProximityScanner: NSObject, ObservableObject, CBCentralManagerDelegate {
    @Published private(set) var rssi: Int?          // smoothed, nil = not seen recently
    @Published private(set) var touching = false
    @Published private(set) var state = "starting"

    private var central: CBCentralManager!
    private var smoothed: Double?
    private var lastSeen = Date.distantPast
    private var timer: Timer?
    private var lastLog = Date.distantPast

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
        // Drop the reading if the phone stops advertising (app closed / walked away).
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, Date().timeIntervalSince(self.lastSeen) > 2.5, self.rssi != nil else { return }
            self.smoothed = nil
            self.rssi = nil
            self.touching = false
        }
    }

    /// 0 = far / unseen, 1 = touching. Used for glow intensity.
    var nearness: Double {
        guard let rssi else { return 0 }
        return min(max(Double(rssi + 75) / Double(F0Drop.touchRSSI + 75), 0), 1)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        dlog("bluetooth state \(central.state.rawValue)")
        guard central.state == .poweredOn else {
            state = central.state == .unauthorized ? "Bluetooth not allowed" : "Bluetooth off"
            return
        }
        state = "scanning"
        central.scanForPeripherals(withServices: [CBUUID(string: F0Drop.bleServiceUUID)],
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let value = RSSI.doubleValue
        guard value < 0, value > -110 else { return }   // 127 = unavailable
        lastSeen = Date()
        let s = smoothed.map { $0 * 0.6 + value * 0.4 } ?? value
        smoothed = s
        rssi = Int(s.rounded())
        // Hysteresis so the glow doesn't flicker at the threshold.
        if touching { touching = s >= Double(F0Drop.touchRSSI - 8) }
        else { touching = s >= Double(F0Drop.touchRSSI) }
        state = "phone seen"
        if Date().timeIntervalSince(lastLog) > 1 { lastLog = Date(); dlog("rssi \(Int(value)) smoothed \(Int(s)) touching \(touching)") }
    }
}
