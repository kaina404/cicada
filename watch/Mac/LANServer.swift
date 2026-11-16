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
  let port: NWEndpoint.Port
  private let token: String?
  var remoteResourceDirectory = Bundle.main.resourceURL?.appendingPathComponent("remote")
  var phoneToken: String?
  var phoneState: (() -> FloatingAnswerState)?
  var phoneScreen: (() async -> ScreenFrame)?
  var receivePhonePacket: ((ControlPacket, UUID) -> Bool)?
  var refreshPhoneAnswer: ((UUID, UUID) -> Bool)?
  private let receivePacket: (ControlPacket) -> Void

  init(token: String?, port: UInt16 = 8765, receivePacket: @escaping (ControlPacket) -> Void) {
    self.port = NWEndpoint.Port(rawValue: port) ?? 8765
    self.token = token
    self.receivePacket = receivePacket
  }

  func start() {
    guard listener == nil else { return }
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
          case .failed(let error):
            self.stop()
            self.onStatus?("局域网服务失败：\(error.localizedDescription)")
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

  enum ScreenFrame {
    case off, waiting, unavailable, image(Data)
  }

  private func reply(_ connection: NWConnection, id: UUID, status: String, reuse: Bool = false,
                     body: Data = Data(), contentType: String = "application/json") {
    let policy = reuse ? "keep-alive" : "close"
    let type = body.isEmpty ? "" : "Content-Type: \(contentType)\r\nCache-Control: no-store\r\n"
    let security = "X-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nContent-Security-Policy: default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self' blob:; frame-ancestors 'none'; base-uri 'none'; form-action 'none'\r\n"
    var data = Data("HTTP/1.1 \(status)\r\n\(security)Content-Length: \(body.count)\r\nConnection: \(policy)\r\n\(type)\r\n".utf8)
    data.append(body)
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
        let reading = lines.first == "GET /\(FloatingAnswerPairing.statePath) HTTP/1.1"
        let viewing = lines.first == "GET /\(FloatingAnswerPairing.screenPath) HTTP/1.1"
        let refreshing = lines.first == "POST /\(FloatingAnswerPairing.refreshPath) HTTP/1.1"
        let phoneControl = lines.first == "POST /\(FloatingAnswerPairing.controlPath) HTTP/1.1"
        let assets = ["GET /remote HTTP/1.1": ("index.html", "text/html; charset=utf-8"),
                      "GET /remote.css HTTP/1.1": ("remote.css", "text/css; charset=utf-8"),
                      "GET /remote.js HTTP/1.1": ("remote.js", "text/javascript; charset=utf-8")]
        let asset = lines.first.flatMap { assets[$0] }
        let phone = reading || viewing || phoneControl || refreshing
        guard connecting || phone || asset != nil || lines.first == "POST /control HTTP/1.1" else {
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
        // Only public, fixed assets bypass pairing. No answers or credentials are embedded.
        if let asset {
          guard (fields["content-length"] ?? "0") == "0", fields["transfer-encoding"] == nil,
                buffer.count == split.upperBound else {
            self.reply(connection, id: id, status: "400 Bad Request")
            return
          }
          guard let directory = self.remoteResourceDirectory,
                let body = try? Data(contentsOf: directory.appendingPathComponent(asset.0)) else {
            self.reply(connection, id: id, status: "404 Not Found")
            return
          }
          self.reply(connection, id: id, status: "200 OK", body: body, contentType: asset.1)
          return
        }
        // Native clients omit Origin. Browser clients must come from this server.
        if phone, let origin = fields["origin"], origin != "http://" + (fields["host"] ?? "") {
          self.reply(connection, id: id, status: "403 Forbidden")
          return
        }
        let authorized = phone
          ? self.phoneToken.map { fields[FloatingAnswerPairing.tokenHeader.lowercased()] == $0 } == true
          : self.token.map { fields["x-watchcontrol-token"] == $0 } == true
        guard authorized else {
          self.reply(connection, id: id, status: "403 Forbidden")
          return
        }
        let reuse = fields["connection"]?.lowercased() != "close" && !done
        if connecting || reading || viewing || refreshing {
          guard (fields["content-length"] ?? "0") == "0", fields["transfer-encoding"] == nil,
            buffer.count == split.upperBound else {
            self.reply(connection, id: id, status: "400 Bad Request")
            return
          }
          if refreshing {
            guard let rawWindow = fields[FloatingAnswerPairing.windowHeader.lowercased()],
                  let window = UUID(uuidString: rawWindow),
                  let rawRequest = fields[FloatingAnswerPairing.requestHeader.lowercased()],
                  let request = UUID(uuidString: rawRequest) else {
              self.reply(connection, id: id, status: "400 Bad Request")
              return
            }
            let accepted = self.refreshPhoneAnswer?(window, request) == true
            self.reply(connection, id: id, status: accepted ? "204 No Content" : "409 Conflict", reuse: reuse)
          } else if viewing {
            self.readScreen(connection, id: id, reuse: reuse)
          } else if reading {
            guard let state = self.phoneState?(), let body = try? JSONEncoder().encode(state) else {
              self.reply(connection, id: id, status: "503 Service Unavailable")
              return
            }
            self.reply(connection, id: id, status: "200 OK", reuse: reuse, body: body)
          } else {
            self.markConnected()
            self.reply(connection, id: id, status: "204 No Content", reuse: reuse)
          }
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
        if phoneControl {
          guard let raw = fields[FloatingAnswerPairing.windowHeader.lowercased()],
                let windowID = UUID(uuidString: raw), self.receivePhonePacket?(packet, windowID) == true else {
            self.reply(connection, id: id, status: "409 Conflict", reuse: reuse)
            return
          }
          self.reply(connection, id: id, status: "204 No Content", reuse: reuse)
          return
        }
        self.markConnected()
        NSLog("WatchControl received LAN kind=%u gesture=%u seq=%u", packet.kind.rawValue, packet.gesture, packet.sequence)
        self.receivePacket(packet)
        self.reply(connection, id: id, status: "204 No Content", reuse: reuse)
      }
    }
  }

  private func readScreen(_ connection: NWConnection, id: UUID, reuse: Bool) {
    let token = phoneToken
    Task { [weak self] in
      guard let self, self.connections[id] != nil else { return }
      let frame = await self.phoneScreen?() ?? .off
      guard self.connections[id] != nil else { return }
      guard token == self.phoneToken else {
        self.reply(connection, id: id, status: "403 Forbidden")
        return
      }
      switch frame {
      case .off: self.reply(connection, id: id, status: "409 Conflict", reuse: reuse)
      case .waiting: self.reply(connection, id: id, status: "204 No Content", reuse: reuse)
      case .unavailable: self.reply(connection, id: id, status: "503 Service Unavailable", reuse: reuse)
      case .image(let jpeg):
        self.reply(connection, id: id, status: "200 OK", reuse: reuse, body: jpeg, contentType: "image/jpeg")
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
