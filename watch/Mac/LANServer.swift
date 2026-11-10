import Foundation
import Network

/// All Network callbacks run on the main queue selected by start(queue:).
/// assumeIsolated bridges that queue guarantee to MainActor.
@MainActor
final class LANServer {
  var onStatus: ((String) -> Void)?
  /// Optional local fault injection for the explicit --connection-test mode.
  var acceptsRequests: () -> Bool = { true }
  private var connectionExpiry: DispatchWorkItem?
  private var listener: NWListener?
  private var connections: [UUID: NWConnection] = [:]
  private var deadlines: [UUID: DispatchWorkItem] = [:]
  private var lastActivity: TimeInterval = 0
  private var connected = false
  private let port: NWEndpoint.Port
  private let token: String
  private let receivePacket: (ControlPacket) -> Void

  init(token: String, port: UInt16 = 8765, receivePacket: @escaping (ControlPacket) -> Void) {
    self.port = NWEndpoint.Port(rawValue: port) ?? 8765
    self.token = token
    self.receivePacket = receivePacket
  }

  func start() {
    do {
      let tcp = NWProtocolTCP.Options()
      tcp.noDelay = true
      let listener = try NWListener(using: NWParameters(tls: nil, tcp: tcp), on: port)
      self.listener = listener
      listener.stateUpdateHandler = { [weak self] state in
        MainActor.assumeIsolated {
          guard let self else { return }
          switch state {
          case .ready: self.onStatus?("等待 Apple Watch 连接")
          case .failed(let error): self.onStatus?("局域网服务失败：\(error.localizedDescription)")
          default: break
          }
        }
      }
      listener.newConnectionHandler = { [weak self] connection in
        MainActor.assumeIsolated { self?.accept(connection) }
      }
      listener.start(queue: .main)
    } catch { onStatus?("无法启动服务：\(error.localizedDescription)") }
  }

  func stop() {
    listener?.stateUpdateHandler = nil
    listener?.newConnectionHandler = nil
    listener?.cancel()
    listener = nil
    connectionExpiry?.cancel()
    connectionExpiry = nil
    for deadline in deadlines.values { deadline.cancel() }
    deadlines.removeAll()
    let active = Array(connections.values)
    connections.removeAll()
    for connection in active { connection.stateUpdateHandler = nil; connection.cancel() }
    connected = false
  }

  private func accept(_ connection: NWConnection) {
    guard connections.count < 8 else {
      connection.cancel()
      return
    }
    let id = UUID()
    connections[id] = connection
    connection.stateUpdateHandler = { [weak self] state in
      MainActor.assumeIsolated {
        if case .failed = state { self?.close(id) }
        if case .cancelled = state { self?.connections.removeValue(forKey: id) }
      }
    }
    connection.start(queue: .main)
    awaitRequest(connection, id: id)
  }

  private func awaitRequest(_ connection: NWConnection, id: UUID) {
    deadlines.removeValue(forKey: id)?.cancel()
    let timeout = DispatchWorkItem { [weak self] in self?.close(id) }
    deadlines[id] = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeout)
    read(connection, id: id, buffer: Data())
  }

  private func close(_ id: UUID) {
    deadlines.removeValue(forKey: id)?.cancel()
    connections.removeValue(forKey: id)?.cancel()
  }

  private func reply(_ connection: NWConnection, id: UUID, status: String, reuse: Bool = false) {
    let policy = reuse ? "keep-alive" : "close"
    let data = Data("HTTP/1.1 \(status)\r\nContent-Length: 0\r\nConnection: \(policy)\r\n\r\n".utf8)
    connection.send(
      content: data,
      completion: .contentProcessed { [weak self] error in
        MainActor.assumeIsolated {
          guard let self, self.connections[id] != nil else { return }
          if reuse && error == nil { self.awaitRequest(connection, id: id) }
          else { self.close(id) }
        }
      })
  }

  private func read(_ connection: NWConnection, id: UUID, buffer: Data) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) {
      [weak self] data, _, done, error in
      MainActor.assumeIsolated {
        guard let self, self.connections[id] != nil else { return }
        var buffer = buffer
        if let data { buffer.append(data) }
        guard error == nil, buffer.count <= 4096 else {
          self.close(id)
          return
        }
        guard let split = buffer.range(of: Data("\r\n\r\n".utf8)) else {
          if done { self.close(id) } else { self.read(connection, id: id, buffer: buffer) }
          return
        }
        guard let header = String(data: buffer[..<split.lowerBound], encoding: .utf8) else {
          self.reply(connection, id: id, status: "400 Bad Request")
          return
        }
        let lines = header.components(separatedBy: "\r\n")
        let connecting = lines.first == "POST /connect HTTP/1.1"
        guard connecting || lines.first == "POST /control HTTP/1.1" else {
          self.reply(connection, id: id, status: "404 Not Found")
          return
        }
        guard self.acceptsRequests() else {
          self.reply(connection, id: id, status: "503 Service Unavailable")
          return
        }
        var fields: [String: String] = [:]
        for line in lines.dropFirst() {
          let parts = line.split(separator: ":", maxSplits: 1)
          guard parts.count == 2 else {
            self.reply(connection, id: id, status: "400 Bad Request")
            return
          }
          let key = parts[0].lowercased()
          guard fields[key] == nil else {
            self.reply(connection, id: id, status: "400 Bad Request")
            return
          }
          fields[key] = parts[1].trimmingCharacters(in: .whitespaces)
        }
        guard fields["x-watchcontrol-token"] == self.token else {
          self.reply(connection, id: id, status: "403 Forbidden")
          return
        }
        let reuse = fields["connection"]?.lowercased() != "close" && !done
        if connecting {
          guard (fields["content-length"] ?? "0") == "0", fields["transfer-encoding"] == nil,
            buffer.count == split.upperBound else {
            self.reply(connection, id: id, status: "400 Bad Request")
            return
          }
          self.markConnected()
          self.reply(connection, id: id, status: "204 No Content", reuse: reuse)
          return
        }
        guard fields["content-length"] == String(ControlPacket.byteCount), fields["transfer-encoding"] == nil else {
          self.reply(connection, id: id, status: "400 Bad Request")
          return
        }
        let body = Data(buffer[split.upperBound...])
        if body.count < ControlPacket.byteCount, !done {
          self.read(connection, id: id, buffer: buffer)
          return
        }
        guard let packet = ControlPacket(data: body) else {
          self.reply(connection, id: id, status: "400 Bad Request")
          return
        }
        self.markConnected()
        NSLog("WatchControl received LAN kind=%u gesture=%u seq=%u", packet.kind.rawValue, packet.gesture, packet.sequence)
        self.receivePacket(packet)
        self.reply(connection, id: id, status: "204 No Content", reuse: reuse)
      }
    }
  }

  private func markConnected() {
    lastActivity = ProcessInfo.processInfo.systemUptime
    if !connected {
      connected = true
      onStatus?("当前已连接")
    }
    guard connectionExpiry == nil else { return }
    checkActivity()
  }

  private func checkActivity() {
    let expiry = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.connectionExpiry = nil
      if ProcessInfo.processInfo.systemUptime - self.lastActivity >= 8 {
        self.connected = false
        self.onStatus?("等待 Apple Watch 连接")
      } else { self.checkActivity() }
    }
    connectionExpiry = expiry
    let remaining = max(0, 8 - (ProcessInfo.processInfo.systemUptime - lastActivity))
    DispatchQueue.main.asyncAfter(deadline: .now() + remaining, execute: expiry)
  }

  static func localAddresses() -> [String] {
    var interfaces: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&interfaces) == 0 else { return ["查看 Wi-Fi 设置中的 IP"] }
    defer { freeifaddrs(interfaces) }
    var addresses: [String] = []
    var cursor = interfaces
    while let entry = cursor {
      defer { cursor = entry.pointee.ifa_next }
      guard let address = entry.pointee.ifa_addr,
        address.pointee.sa_family == UInt8(AF_INET),
        entry.pointee.ifa_flags & UInt32(IFF_LOOPBACK) == 0
      else { continue }
      var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
      if getnameinfo(
        address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0,
        NI_NUMERICHOST) == 0
      {
        addresses.append(String(cString: host))
      }
    }
    return addresses.isEmpty ? ["请连接 Wi-Fi"] : addresses
  }
}
