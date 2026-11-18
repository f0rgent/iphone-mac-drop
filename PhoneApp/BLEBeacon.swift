import CoreBluetooth

/// Advertises a BLE service so the Mac can read our RSSI and tell when the phone touches it.
final class BLEBeacon: NSObject, ObservableObject, CBPeripheralManagerDelegate {
    @Published var state: String = "starting"
    private var manager: CBPeripheralManager!

    override init() {
        super.init()
        manager = CBPeripheralManager(delegate: self, queue: nil)
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        guard peripheral.state == .poweredOn else {
            state = "bluetooth off (\(peripheral.state.rawValue))"
            return
        }
        let uuid = CBUUID(string: F0Drop.bleServiceUUID)
        peripheral.removeAllServices()
        peripheral.add(CBMutableService(type: uuid, primary: true))
        peripheral.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [uuid],
            CBAdvertisementDataLocalNameKey: "f0drop",
        ])
        state = "beacon on"
    }
}
