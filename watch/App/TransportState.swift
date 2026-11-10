import Foundation

/// A successful application-level probe establishes LAN health. Never change
/// lanes while a BLE write awaits its acknowledgement.
struct TransportState {
  enum Route: String { case offline, network, bluetooth }
  var networkReady = false
  var bluetoothReady = false
  var bluetoothBusy = false
  var route: Route {
    if bluetoothBusy { return .bluetooth }
    if networkReady { return .network }
    return bluetoothReady ? .bluetooth : .offline
  }
}
