import Foundation
import Combine

// Deterministic BLE acknowledgements plus URLSession's real completion path.
@MainActor
final class BluetoothLink: BluetoothTransport {
  var onReady: ((Bool) -> Void)?
  var onWrite: ((Bool) -> Void)?
  var writes: [Data] = []
  var busy = false
  var available = true
  func start(serviceID: String) { onReady?(available) }
  func stop() { busy = false; onReady?(false) }
  func tick() {}
  func write(_ data: Data) -> Bool {
    guard available, !busy else { return false }
    busy = true
    if data == Data([0x7f]) {
      Task { @MainActor in self.acknowledge() }
      return true
    }
    writes.append(data)
    return true
  }
  func acknowledge() { busy = false; onWrite?(true) }
  func disconnect() { available = false; busy = false; onReady?(false); onWrite?(false) }
}

final class StubNetwork: URLProtocol, @unchecked Sendable {
  static let lock = NSLock()
  nonisolated(unsafe) static var reachable = true
  nonisolated(unsafe) static var requests: [URLRequest] = []
  static func setReachable(_ value: Bool) { lock.lock(); reachable = value; lock.unlock() }
  static func count(_ path: String) -> Int {
    lock.lock(); defer { lock.unlock() }
    return requests.filter { $0.url?.path == path }.count
  }
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    Self.lock.lock()
    Self.requests.append(request)
    let reachable = Self.reachable
    Self.lock.unlock()
    if reachable, let url = request.url,
      let response = HTTPURLResponse(url: url, statusCode: 204, httpVersion: nil, headerFields: nil) {
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocolDidFinishLoading(self)
    } else { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
  }
  override func stopLoading() {}
}

@main
struct TransportTests {
  @MainActor static func wait(_ predicate: () -> Bool, seconds: Double = 7) async {
    let until = Date().addingTimeInterval(seconds)
    while !predicate(), Date() < until { try? await Task.sleep(for: .milliseconds(20)) }
    precondition(predicate(), "Timed out waiting for transport transition")
  }

  @MainActor static func main() async {
    var state = TransportState()
    precondition(state.route == .offline)
    state.bluetoothReady = true
    precondition(state.route == .bluetooth)
    state.networkReady = true
    precondition(state.route == .network)
    state.bluetoothBusy = true
    precondition(state.route == .bluetooth)
    state.bluetoothBusy = false
    precondition(state.route == .network)

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubNetwork.self]
    let session = URLSession(configuration: config)
    let ble = BluetoothLink()
    let link = WatchLink(session: session, bluetooth: ble)
    link.start(host: "test.local", serviceID: UUID().uuidString, port: 8876)
    await wait { link.status == "网络已连接" }
    precondition(StubNetwork.lock.withLock { StubNetwork.requests.last?.url?.port == 8876 },
                 "Pairing port must be used for LAN probes")
    let first = ControlPacket(gesture: 1, x: 0.1)
    link.send(first)
    await wait { StubNetwork.count("/control") == 1 }
    precondition(ble.writes.isEmpty, "Healthy LAN must have priority")
    precondition(StubNetwork.lock.withLock { StubNetwork.requests.last?.url?.port == 8876 },
                 "Pairing port must also be used for controls")

    StubNetwork.setReachable(false)
    link.send(ControlPacket(gesture: 1, x: 0.2))
    await wait { link.status.contains("蓝牙已连接") }
    let second = ControlPacket(gesture: 1, x: 0.3)
    link.send(second)
    precondition(ble.writes.last == second.data)
    // Movement can coalesce, but button transitions and gesture boundaries cannot.
    let move = ControlPacket(gesture: 10, x: 0.2)
    let hold = ControlPacket(kind: .hold, gesture: 10, x: 0.3)
    let end = ControlPacket(kind: .end, gesture: 10, x: 0.3)
    let begin = ControlPacket(kind: .begin, gesture: 11)
    let click = ControlPacket(kind: .click, gesture: 11)
    for packet in [ControlPacket(gesture: 10, x: 0.1), move,
                   ControlPacket(kind: .hold, gesture: 10, x: 0.2), hold, end, begin, click] {
      link.send(packet)
    }
    for expected in [move, hold, end, begin, click] {
      ble.acknowledge()
      precondition(ble.writes.last == expected.data, "Button transition lost or reordered")
    }
    let failedProbeCount = StubNetwork.count("/connect")
    await wait { StubNetwork.count("/connect") > failedProbeCount }
    precondition(link.connected, "Failed LAN probes must not disconnect BLE")

    // Recovery arrives while a BLE command is unacknowledged.
    StubNetwork.setReachable(true)
    let probes = StubNetwork.count("/connect")
    await wait { StubNetwork.count("/connect") > probes }
    try? await Task.sleep(for: .milliseconds(100))
    precondition(link.status.contains("蓝牙已连接"), "Wait for BLE acknowledgement before returning to LAN")
    let controls = StubNetwork.count("/control")
    link.send(ControlPacket(gesture: 2, x: 0.1))
    link.send(ControlPacket(gesture: 2, x: 0.2))
    precondition(StubNetwork.count("/control") == controls)
    ble.acknowledge()
    await wait { link.status == "网络已连接" && StubNetwork.count("/control") == controls + 1 }

    ble.disconnect()
    precondition(link.connected, "Standby BLE loss must not disconnect healthy LAN")
    link.stop()
    precondition(!link.connected)
    // Returning to foreground starts a fresh connection generation.
    link.start(host: "test.local", serviceID: UUID().uuidString, port: 8876)
    await wait { link.status == "网络已连接" }
    StubNetwork.setReachable(false)
    link.send(ControlPacket(gesture: 3, x: 0.1))
    await wait { !link.connected }
    precondition(link.interruption >= 2, "Failed controls must interrupt live touches")
    let allAuthenticated = StubNetwork.lock.withLock {
      StubNetwork.requests.allSatisfy {
        $0.value(forHTTPHeaderField: "X-WatchControl-Token") == "test-token"
      }
    }
    precondition(allAuthenticated, "Every probe and control must carry its token")
    link.stop()
    session.invalidateAndCancel()
    print("PASS: LAN priority, BLE failover, continued LAN probes, acknowledgement barrier, coalescing, standby loss, foreground reconnect, both offline, button barriers, interruption, token headers")
  }
}
