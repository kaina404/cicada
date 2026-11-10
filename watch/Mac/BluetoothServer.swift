import CoreBluetooth
import Foundation

/// Mac advertises; watchOS supports the central role. All callbacks use main.
@MainActor
final class BluetoothServer: NSObject, @preconcurrency CBPeripheralManagerDelegate {
  private var manager: CBPeripheralManager?
  private let serviceID: CBUUID
  private let receive: (ControlPacket) -> Void
  var onStatus: ((String) -> Void)?

  init(serviceID: String, receive: @escaping (ControlPacket) -> Void) {
    self.serviceID = CBUUID(string: serviceID)
    self.receive = receive
    super.init()
  }

  func start() { manager = CBPeripheralManager(delegate: self, queue: .main) }

  func stop() {
    manager?.stopAdvertising()
    manager?.removeAllServices()
    manager?.delegate = nil
    manager = nil
  }

  func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
    guard peripheral.state == .poweredOn else {
      onStatus?("蓝牙不可用（\(peripheral.state.rawValue)）")
      return
    }
    peripheral.removeAllServices()
    let service = CBMutableService(type: serviceID, primary: true)
    service.characteristics = [CBMutableCharacteristic(
      type: CBUUID(string: "F1A10002-4782-4AE8-BB3F-C35A88F0A128"),
      properties: [.write], value: nil, permissions: [.writeable])]
    peripheral.add(service)
  }

  func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
    if let error { onStatus?("蓝牙服务失败：\(error.localizedDescription)"); return }
    peripheral.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [serviceID]])
  }

  func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
    onStatus?(error.map { "蓝牙广播失败：\($0.localizedDescription)" } ?? "蓝牙备用服务就绪")
  }

  func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
    // Validate the entire batch before applying anything.
    guard requests.allSatisfy({ $0.characteristic.uuid == CBUUID(string: "F1A10002-4782-4AE8-BB3F-C35A88F0A128") && $0.offset == 0 &&
      ($0.value == Data([0x7f]) || $0.value.flatMap(ControlPacket.init(data:)) != nil) }) else {
      if let first = requests.first { peripheral.respond(to: first, withResult: .invalidAttributeValueLength) }
      return
    }
    for request in requests {
      if let value = request.value, let packet = ControlPacket(data: value) {
        NSLog("WatchControl received BLE kind=%u gesture=%u seq=%u", packet.kind.rawValue, packet.gesture, packet.sequence)
        receive(packet)
      }
    }
    if let first = requests.first { peripheral.respond(to: first, withResult: .success) }
  }
}
