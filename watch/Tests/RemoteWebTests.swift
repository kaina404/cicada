import AppKit
import Foundation
import Testing
@testable import CicadaWatchControl

@Test func browserPairingKeepsCredentialInFragment() throws {
    let pairing = FloatingAnswerPairing(host: "mac.local", port: 8765, token: String(repeating: "a", count: 64))
    let url = try #require(pairing.webLink)
    #expect(url.scheme == "http" && url.host == "mac.local" && url.path == "/remote")
    #expect(url.query == nil)
    #expect(url.fragment == "token=" + pairing.token)
    #expect(FloatingAnswerPairing(link: url)?.token == pairing.token)
    #expect(try FloatingAnswerPairing(link: #require(pairing.link))?.token == pairing.token)
    #expect(FloatingAnswerPairing(link: try #require(URL(string: "http://public.example:8765/remote#token=" + pairing.token))) == nil)
    #expect(FloatingAnswerPairing(link: try #require(URL(string: url.absoluteString + "&extra=1"))) == nil)
}

@Test @MainActor func remoteWebServesAssetsAndRequiresAuthorizedControls() async throws {
    let server = LANServer(token: nil, port: UInt16.random(in: 20000...45000), receivePacket: { _ in })
    server.remoteResourceDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/remote")
    let token = String(repeating: "a", count: 64)
    server.phoneToken = token
    let windowID = UUID()
    server.phoneState = { FloatingAnswerState(windowID: windowID, answerID: "test", sentences: ["Test answer."]) }
    var received: [ControlPacket] = []
    server.receivePhonePacket = { packet, window in
        guard window == windowID else { return false }
        received.append(packet); return true
    }
    var refreshes = 0
    server.refreshPhoneAnswer = { window, _ in
        guard window == windowID else { return false }
        refreshes += 1; return true
    }
    var ready = false
    server.onStatus = { if $0 == "等待 Apple Watch 连接" { ready = true } }
    server.start()
    defer { server.stop() }
    for _ in 0..<100 where !ready { try await Task.sleep(for: .milliseconds(20)) }
    #expect(ready)
    let base = "http://127.0.0.1:\(server.port.rawValue)"
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 3
    let network = URLSession(configuration: configuration)
    defer { network.invalidateAndCancel() }
    func get(_ path: String, credential: String? = nil) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: try #require(URL(string: base + path)))
        request.setValue(credential, forHTTPHeaderField: FloatingAnswerPairing.tokenHeader)
        let (data, response) = try await network.data(for: request)
        return (data, try #require(response as? HTTPURLResponse))
    }
    for (path, type) in [("/remote", "text/html"), ("/remote.css", "text/css"), ("/remote.js", "text/javascript")] {
        let (data, response) = try await get(path)
        #expect(response.statusCode == 200 && !data.isEmpty)
        #expect(response.value(forHTTPHeaderField: "Content-Type")?.hasPrefix(type) == true)
        #expect(response.value(forHTTPHeaderField: "Cache-Control") == "no-store")
        #expect(response.value(forHTTPHeaderField: "Content-Security-Policy")?.contains("frame-ancestors 'none'") == true)
        #expect(!String(decoding: data, as: UTF8.self).contains(token))
    }
    for path in ["/floating-answer", "/mac-screen"] {
        let (_, response) = try await get(path)
        #expect(response.statusCode == 403)
    }
    let (state, response) = try await get("/floating-answer", credential: token)
    #expect(response.statusCode == 200)
    #expect(try JSONDecoder().decode(FloatingAnswerState.self, from: state).sentences == ["Test answer."])
    let (_, missing) = try await get("/remote/../pairing")
    #expect(missing.statusCode == 404)
    func send(window: UUID, origin: String) async throws -> Int {
        var request = URLRequest(url: try #require(URL(string: base + "/floating-control")))
        request.httpMethod = "POST"
        request.setValue(token, forHTTPHeaderField: FloatingAnswerPairing.tokenHeader)
        request.setValue(window.uuidString, forHTTPHeaderField: FloatingAnswerPairing.windowHeader)
        request.setValue(origin, forHTTPHeaderField: "Origin")
        request.httpBody = ControlPacket(kind: .begin, sequence: 1).data
        let (_, response) = try await network.data(for: request)
        return try #require(response as? HTTPURLResponse).statusCode
    }
    #expect(try await send(window: windowID, origin: "http://other.local") == 403)
    #expect(received.isEmpty)
    #expect(try await send(window: UUID(), origin: base) == 409)
    #expect(try await send(window: windowID, origin: base) == 204)
    #expect(received.count == 1)
    func refresh(window: UUID, credential: String?, origin: String = "") async throws -> Int {
        var request = URLRequest(url: try #require(URL(string: base + "/floating-refresh")))
        request.httpMethod = "POST"
        request.setValue(credential, forHTTPHeaderField: FloatingAnswerPairing.tokenHeader)
        request.setValue(window.uuidString, forHTTPHeaderField: FloatingAnswerPairing.windowHeader)
        request.setValue(UUID().uuidString, forHTTPHeaderField: FloatingAnswerPairing.requestHeader)
        if !origin.isEmpty { request.setValue(origin, forHTTPHeaderField: "Origin") }
        let (_, response) = try await network.data(for: request)
        return try #require(response as? HTTPURLResponse).statusCode
    }
    #expect(try await refresh(window: windowID, credential: nil) == 403)
    #expect(try await refresh(window: windowID, credential: token, origin: "http://other.local") == 403)
    #expect(try await refresh(window: UUID(), credential: token) == 409)
    #expect(refreshes == 0)
    #expect(try await refresh(window: windowID, credential: token) == 204)
    #expect(refreshes == 1)
    server.phoneToken = nil
    #expect(try await refresh(window: windowID, credential: token) == 403)
    #expect(refreshes == 1)
    let (_, revoked) = try await get("/floating-answer", credential: token)
    #expect(revoked.statusCode == 403)
}

@Test func legacyAnswerStateWithoutRefreshCapabilityStillDecodes() throws {
    let data = Data(#"{"answerID":"old","sentences":[],"canSelectSentence":false,"playback":"off"}"#.utf8)
    let state = try JSONDecoder().decode(FloatingAnswerState.self, from: data)
    #expect(state.canRefreshAnswer == nil)
}

@Test @MainActor func phoneRefreshStopsHoldDeduplicatesAndRejectsHiddenWindow() throws {
    _ = NSApplication.shared
    let window = NSPanel(contentRect: NSRect(x: 20, y: 20, width: 500, height: 300),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    window.identifier = NSUserInterfaceItemIdentifier("cicada.assistant")
    window.orderFrontRegardless()
    var held = false, refreshes = 0, available = true
    let receiver = CicadaWatchReceiver(pairingURL: nil, window: { window }, setHeld: { held = $0 },
        selectSentence: { _ in }, phoneState: { FloatingAnswerState(canRefreshAnswer: available) },
        refreshAnswer: { refreshes += 1; return true })
    defer { receiver.stop(); window.orderOut(nil) }
    let id = try #require(receiver.readPhoneState().windowID)
    #expect(receiver.receivePhone(ControlPacket(kind: .begin, sequence: 1, gesture: 1), windowID: id))
    #expect(receiver.receivePhone(ControlPacket(kind: .hold, sequence: 2, gesture: 1), windowID: id))
    #expect(held)
    let request = UUID()
    #expect(receiver.refreshPhoneAnswer(windowID: id, requestID: request))
    #expect(!held)
    #expect(receiver.refreshPhoneAnswer(windowID: id, requestID: request))
    #expect(refreshes == 1)
    #expect(receiver.refreshPhoneAnswer(windowID: id, requestID: UUID()))
    #expect(refreshes == 2)
    available = false
    #expect(!receiver.refreshPhoneAnswer(windowID: id, requestID: UUID()))
    window.orderOut(nil)
    #expect(!receiver.refreshPhoneAnswer(windowID: id, requestID: UUID()))
    #expect(refreshes == 2)
}
