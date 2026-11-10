import Foundation
import Combine

/// Main-actor coordinator: independent LAN probes, one ordered control lane.
@MainActor
final class WatchLink: ObservableObject {
  @Published var status = "正在连接 Mac"
  @Published var connected = false
  @Published private(set) var interruption = 0
  private var token = ""
  private var lastControl: ControlPacket?
  private var heartbeat: Timer?
  private var host = ""
  private var port = 8765
  private var active = false
  private var pending: [ControlPacket] = []
  private var task: URLSessionDataTask?
  private var generation = UUID()
  private var transport = TransportState()
  private let bluetooth: BluetoothTransport
  private var nextProbe: TimeInterval = 0
  private var lastRoute: TransportState.Route = .offline
  private static func makeSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 2
    config.timeoutIntervalForResource = 3
    config.requestCachePolicy = .reloadIgnoringLocalCacheData
    return URLSession(configuration: config)
  }

  init(session: URLSession? = nil, bluetooth: BluetoothTransport? = nil) {
    self.session = session ?? Self.makeSession()
    self.bluetooth = bluetooth ?? BluetoothLink()
  }
  private let session: URLSession

  func start() {
    guard !active else { return }
    guard let url = Bundle.main.url(forResource: "LocalPairing", withExtension: "json"),
      let data = try? Data(contentsOf: url),
      let pair = try? JSONDecoder().decode([String: String].self, from: data),
      let host = pair["host"], !host.isEmpty,
      let serviceID = pair["bluetoothService"], UUID(uuidString: serviceID) != nil,
      let token = pair["token"], !token.isEmpty else {
      status = "请从 Mac 重新构建并安装"
      return
    }
    guard let port = UInt16(pair["port"] ?? "8765"), port > 0 else {
      status = "配对端口无效，请重新构建"
      return
    }
    start(host: host, serviceID: serviceID, token: token, port: Int(port))
  }

  func start(host: String, serviceID: String, token: String = "test-token", port: Int = 8765) {
    guard !active else { return }
    self.port = port
    self.host = host
    self.token = token
    active = true
    nextProbe = 0
    bluetooth.onReady = { [weak self] ready in
      guard let self, self.active else { return }
      self.transport.bluetoothReady = ready
      self.updateStatus()
    }
    bluetooth.onWrite = { [weak self] success in
      guard let self, self.active else { return }
      self.transport.bluetoothBusy = false
      if !success { self.pending.removeAll(); self.interruption &+= 1 }
      self.updateStatus()
      self.flush()
    }
    bluetooth.start(serviceID: serviceID)
    heartbeat = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.tick() }
    }
    tick()
  }

  func stop() {
    // Foreground exit cannot wait for the control lane. Send an idempotent, ordered
    // cancellation best-effort; the Mac's lease remains the independent fallback.
    if active, let last = lastControl {
      let cancel = ControlPacket(kind: .cancel, session: last.session,
        sequence: last.sequence &+ 1, gesture: last.gesture)
      if transport.route == .network, let url = URL(string: "http://\(host):\(port)/control") {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(token, forHTTPHeaderField: "X-WatchControl-Token")
        request.httpBody = cancel.data
        request.timeoutInterval = 1
        session.dataTask(with: request).resume()
      } else if !transport.bluetoothBusy { _ = bluetooth.write(cancel.data) }
    }
    lastControl = nil
    active = false
    heartbeat?.invalidate()
    heartbeat = nil
    generation = UUID()
    task?.cancel()
    task = nil
    bluetooth.stop()
    transport = TransportState()
    pending.removeAll()
    updateStatus()
  }

  private func tick() {
    guard active else { return }
    bluetooth.tick()
    // A healthy interface is insufficient; only a 204 from this Mac restores LAN.
    if task == nil, ProcessInfo.processInfo.systemUptime >= nextProbe { requestNetwork(packet: nil) }
    if transport.route == .bluetooth, !transport.bluetoothBusy, pending.isEmpty,
      bluetooth.write(Data([0x7f])) { transport.bluetoothBusy = true }
    updateStatus()
    flush()
  }

  func send(_ packet: ControlPacket) {
    guard active, connected else { return }
    lastControl = packet
    if let last = pending.last, packet.canReplace(last) {
      pending[pending.count - 1] = packet
    } else { pending.append(packet) }
    flush()
  }

  private func updateStatus() {
    let route = transport.route
    connected = active && route != .offline
    switch route {
    case .network: status = "网络已连接"
    case .bluetooth: status = "蓝牙已连接 · 检测网络中"
    case .offline: status = "正在寻找 Mac…"
    }
    if route != lastRoute {
      NSLog("WatchControl route: %@ -> %@", lastRoute.rawValue, route.rawValue)
      lastRoute = route
    }
  }

  private func flush() {
    guard active, !pending.isEmpty, !transport.bluetoothBusy else { return }
    switch transport.route {
    case .network:
      guard task == nil else { return }
      requestNetwork(packet: pending.removeFirst())
    case .bluetooth:
      // A network probe may proceed concurrently, but a LAN control never does.
      if bluetooth.write(pending[0].data) {
        pending.removeFirst()
        transport.bluetoothBusy = true
      }
    case .offline: break
    }
  }

  private func requestNetwork(packet: ControlPacket?) {
    guard active, task == nil else { return }
    var components = URLComponents()
    components.scheme = "http"
    components.host = host
    components.port = port
    components.path = packet == nil ? "/connect" : "/control"
    guard let url = components.url else { return }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
    request.setValue(token, forHTTPHeaderField: "X-WatchControl-Token")
    request.httpBody = packet?.data ?? Data()
    let generation = generation
    task = session.dataTask(with: request) { [weak self] _, response, error in
      DispatchQueue.main.async {
        guard let self, self.active, self.generation == generation else { return }
        self.task = nil
        let success = error == nil && (response as? HTTPURLResponse)?.statusCode == 204
        self.transport.networkReady = success
        let now = ProcessInfo.processInfo.systemUptime
        self.nextProbe = now + (success ? 3 : 2)
        // A timed-out command may already have reached the Mac. Do not replay it
        // on BLE. Interrupt the touch; a fresh finger-down starts a new gesture.
        if !success, packet != nil {
          self.pending.removeAll()
          self.interruption &+= 1
        }
        self.updateStatus()
        self.flush()
      }
    }
    task?.resume()
  }
}
