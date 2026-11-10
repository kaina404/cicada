import CoreBluetooth
import Foundation

@MainActor
final class BluetoothLink: NSObject, BluetoothTransport, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
  var onReady: ((Bool) -> Void)?
  var onWrite: ((Bool) -> Void)?
  private var central: CBCentralManager?
  private var peripheral: CBPeripheral?
  private var characteristic: CBCharacteristic?
  private var serviceID: CBUUID?
  private var active = false
  private var deadline: TimeInterval = 0
  private var writing = false
  private let characteristicID = CBUUID(string: "F1A10002-4782-4AE8-BB3F-C35A88F0A128")

  func start(serviceID: String) {
    self.serviceID = CBUUID(string: serviceID)
    active = true
    if central == nil { central = CBCentralManager(delegate: self, queue: .main) }
    else { tick() }
  }

  func stop() {
    active = false
    central?.stopScan()
    drop()
  }

  func tick() {
    guard active, central?.state == .poweredOn else { return }
    if peripheral != nil, deadline > 0, ProcessInfo.processInfo.systemUptime >= deadline { drop() }
    if peripheral == nil, let serviceID, central?.isScanning == false {
      central?.scanForPeripherals(withServices: [serviceID])
    }
  }

  func write(_ data: Data) -> Bool {
    guard active, !writing, let peripheral, let characteristic else { return false }
    writing = true
    deadline = ProcessInfo.processInfo.systemUptime + 4
    peripheral.writeValue(data, for: characteristic, type: .withResponse)
    return true
  }

  private func drop() {
    let old = peripheral
    peripheral = nil
    characteristic = nil
    deadline = 0
    let wasWriting = writing
    writing = false
    if let old { central?.cancelPeripheralConnection(old) }
    onReady?(false)
    if wasWriting { onWrite?(false) }
  }

  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    if central.state != .poweredOn { drop() }
    tick()
  }

  func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any], rssi RSSI: NSNumber) {
    guard active, self.peripheral == nil else { return }
    self.peripheral = peripheral
    peripheral.delegate = self
    deadline = ProcessInfo.processInfo.systemUptime + 8
    central.stopScan()
    central.connect(peripheral)
  }

  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    guard active, peripheral === self.peripheral, let serviceID else { return }
    peripheral.discoverServices([serviceID])
  }

  func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
    guard peripheral === self.peripheral else { return }
    drop()
  }

  func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
    guard peripheral === self.peripheral else { return }
    drop()
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    guard peripheral === self.peripheral else { return }
    guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == serviceID }) else { drop(); return }
    peripheral.discoverCharacteristics([characteristicID], for: service)
  }

  func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
    guard peripheral === self.peripheral else { return }
    guard error == nil, let characteristic = service.characteristics?.first(where: {
      $0.uuid == characteristicID && $0.properties.contains(.write)
    }) else { drop(); return }
    self.characteristic = characteristic
    // A successful acknowledged ping, rather than discovery alone, marks BLE ready.
    _ = write(Data([0x7f]))
  }

  func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
    guard peripheral === self.peripheral, writing else { return }
    writing = false
    deadline = 0
    if error != nil { drop(); onWrite?(false); return }
    onReady?(true)
    onWrite?(true)
  }
}
