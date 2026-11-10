import Foundation

@MainActor
protocol BluetoothTransport: AnyObject {
  var onReady: ((Bool) -> Void)? { get set }
  var onWrite: ((Bool) -> Void)? { get set }
  func start(serviceID: String)
  func stop()
  func tick()
  func write(_ data: Data) -> Bool
}
