import AppKit
import Foundation
import Testing
@testable import CicadaWatchControl

@Test func pairingValidation() throws {
    let service = UUID().uuidString
    #expect(WatchPairing(host: "mac.local", bluetoothService: service, token: "local-test").isValid)
    #expect(!WatchPairing(host: "", bluetoothService: service, token: "local-test").isValid)
    #expect(!WatchPairing(host: "mac.local", bluetoothService: "bad", token: "local-test").isValid)
    #expect(!WatchPairing(host: "mac.local", bluetoothService: service, token: "").isValid)
    var custom = WatchPairing(host: "mac.local", bluetoothService: service, token: "test")
    #expect(custom.effectivePort == 8765)
    custom.port = "8876"
    #expect(custom.isValid && custom.effectivePort == 8876)
    for invalid in ["0", "65536", "bad"] {
        custom.port = invalid
        #expect(!custom.isValid)
    }
    let decoded = try JSONDecoder().decode(WatchPairing.self, from: JSONSerialization.data(withJSONObject:
        ["host": "mac.local", "bluetoothService": service, "token": "test", "port": "8876"]))
    #expect(decoded.isValid && decoded.effectivePort == 8876)
    #expect(throws: (any Error).self) { try JSONDecoder().decode(WatchPairing.self, from: Data("{}".utf8)) }
}

@Test @MainActor func receiverOnlyControlsVisibleOwnedFloat() {
    _ = NSApplication.shared
    let window = NSPanel(contentRect: CGRect(x: 300, y: 300, width: 520, height: 300),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.identifier = NSUserInterfaceItemIdentifier("cicada.assistant")
    var held = false
    var holds: [Bool] = []
    var sentences: [Int] = []
    let receiver = CicadaWatchReceiver(pairingURL: nil, window: { window },
        setHeld: { held = $0; holds.append($0) }, selectSentence: { sentences.append($0) })
    defer { receiver.stop(); window.close() }
    receiver.start()
    #expect(receiver.status == "disabled: missing local pairing")
    var sequence: UInt32 = 0
    func send(_ kind: ControlPacket.Kind, _ gesture: UInt16, x: Float = 0, y: Float = 0) {
        sequence += 1
        receiver.receive(ControlPacket(kind: kind, session: 123, sequence: sequence, gesture: gesture, x: x, y: y))
    }
    let original = window.frame.origin
    send(.begin, 1)
    send(.end, 1, x: 0.1)
    #expect(window.frame.origin == original)
    #expect(receiver.status == "waiting for floating answer")
    #expect(holds.isEmpty, "Idle receiver does not interfere with local playback")
    window.orderFrontRegardless()
    send(.begin, 2)
    send(.end, 2, x: 0.1, y: 0.05)
    #expect(abs(window.frame.minX - original.x - 90) < 0.01)
    #expect(abs(window.frame.minY - original.y + 45) < 0.01)
    #expect(!window.isKeyWindow)
    send(.begin, 3)
    send(.hold, 3)
    #expect(held)
    window.orderOut(nil)
    receiver.refreshTarget()
    #expect(!held)
    window.orderFrontRegardless()
    send(.hold, 3)
    #expect(!held, "A hidden float discards the old gesture")
    send(.begin, 4)
    send(.hold, 4)
    #expect(held)
    send(.end, 4)
    #expect(!held)
    send(.begin, 5)
    send(.sentence, 5, y: -1)
    send(.end, 5)
    #expect(sentences == [-1])
    window.identifier = NSUserInterfaceItemIdentifier("cicada.notes")
    let stopped = window.frame.origin
    send(.begin, 6)
    send(.end, 6, x: 0.2)
    send(.begin, 7)
    send(.hold, 7)
    #expect(window.frame.origin == stopped && !held)
    #expect(receiver.status == "waiting for floating answer")
    window.identifier = NSUserInterfaceItemIdentifier("cicada.assistant")
    send(.hold, 7)
    #expect(!held, "Reconnecting requires a new begin")
    send(.begin, 8)
    send(.hold, 8)
    #expect(held)
    receiver.stop()
    #expect(!held && receiver.status == "stopped")
}

@Test @MainActor func tapPlaybackStopsOnTargetLossAndFreshTouch() async throws {
    _ = NSApplication.shared
    let window = NSPanel(contentRect: CGRect(x: 300, y: 300, width: 520, height: 300),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.identifier = NSUserInterfaceItemIdentifier("cicada.assistant")
    window.orderFrontRegardless()
    var playing = false
    var selections: [Int] = []
    let receiver = CicadaWatchReceiver(pairingURL: nil, window: { window },
        setHeld: { playing = $0 }, selectSentence: { _ in playing = false },
        playSentence: { selections.append($0); playing = true })
    defer { receiver.stop(); window.close() }
    var sequence: UInt32 = 0
    func send(_ kind: ControlPacket.Kind, _ gesture: UInt16) {
        sequence += 1
        receiver.receive(ControlPacket(kind: kind, session: 234, sequence: sequence, gesture: gesture))
    }
    send(.begin, 1); send(.click, 1)
    try await Task.sleep(for: .seconds(NSEvent.doubleClickInterval + 0.15))
    #expect(selections == [1] && playing)
    receiver.refreshTarget()
    #expect(playing, "Idle target polling does not pause tap playback")
    send(.begin, 2)
    #expect(!playing, "New touch pauses tap playback")
    send(.click, 2)
    send(.begin, 3); send(.click, 3)
    #expect(selections == [1, -1] && playing)
    window.orderOut(nil); receiver.refreshTarget()
    #expect(!playing)
}

@Test @MainActor func phoneStateFollowsWindowVisibilityAndRejectsOldGestures() throws {
    _ = NSApplication.shared
    let window = NSPanel(contentRect: CGRect(x: 300, y: 300, width: 520, height: 300),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.identifier = NSUserInterfaceItemIdentifier("cicada.assistant")
    var held = false
    var selected = 0
    let receiver = CicadaWatchReceiver(pairingURL: nil, window: { window }, setHeld: { held = $0 },
        selectSentence: { selected += $0 },
        phoneState: { FloatingAnswerState(answerID: "answer", sentences: ["First.", "Second."],
                                         currentSentence: selected, canSelectSentence: true) })
    defer { receiver.stop(); window.close() }
    #expect(receiver.readPhoneState() == FloatingAnswerState())
    window.orderFrontRegardless()
    let initial = receiver.readPhoneState()
    let windowID = try #require(initial.windowID)
    #expect(initial.sentences == ["First.", "Second."])
    #expect(receiver.receivePhone(ControlPacket(kind: .begin, sequence: 1), windowID: windowID))
    #expect(receiver.receivePhone(ControlPacket(kind: .sentence, sequence: 2, y: 1), windowID: windowID))
    #expect(receiver.readPhoneState().currentSentence == 1)
    #expect(!held)
    #expect(receiver.receivePhone(ControlPacket(kind: .hold, sequence: 3), windowID: windowID))
    #expect(held)
    receiver.receive(ControlPacket(kind: .begin, sequence: 1))
    #expect(!held, "A new Watch gesture takes control")
    receiver.receive(ControlPacket(kind: .hold, sequence: 2))
    receiver.disconnectPhone()
    #expect(held, "Disconnecting the iPhone leaves Watch playback alone")
    #expect(receiver.receivePhone(ControlPacket(kind: .hold, sequence: 4), windowID: windowID))
    #expect(held, "A delayed hold cannot take control back from the Watch")
    #expect(receiver.receivePhone(ControlPacket(kind: .begin, sequence: 5), windowID: windowID))
    #expect(!held)
    #expect(receiver.receivePhone(ControlPacket(kind: .hold, sequence: 6), windowID: windowID))
    #expect(held, "The iPhone can start a fresh gesture in the same session")
    window.orderOut(nil)
    receiver.windowVisibilityChanged()
    #expect(receiver.readPhoneState() == FloatingAnswerState())
    #expect(!held)
    window.orderFrontRegardless()
    #expect(receiver.readPhoneState().windowID != windowID)
    #expect(!receiver.receivePhone(ControlPacket(kind: .hold, sequence: 7), windowID: windowID))
    #expect(!held)
}

@Test func phonePairingRoundTripsAndRestrictsEndpoints() throws {
    let pairing = FloatingAnswerPairing(host: "mac.local", port: 8876, token: String(repeating: "a", count: 64))
    let link = try #require(pairing.link)
    let decoded = try #require(FloatingAnswerPairing(link: link))
    #expect(decoded.endpoint(FloatingAnswerPairing.statePath)?.absoluteString == "http://mac.local:8876/floating-answer")
    #expect(decoded.token == pairing.token)
    let outsideLAN = FloatingAnswerPairing(host: "example.com", port: 8876, token: pairing.token)
    #expect(outsideLAN.link.flatMap(FloatingAnswerPairing.init(link:)) == nil)
}

@Test @MainActor func phonePairingSurvivesReceiverRestartAndCanBeRevoked() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = PhonePairingFile(directory: directory)
    func makeReceiver() -> CicadaWatchReceiver {
        CicadaWatchReceiver(pairingURL: nil, phonePairingDirectory: directory, window: { nil },
                            setHeld: { _ in }, selectSentence: { _ in }, phoneState: { FloatingAnswerState() })
    }
    let first = makeReceiver()
    first.start()
    defer { first.stop() }
    #expect(!first.hasPhonePairing)
    let firstLink = try #require(first.pairPhone())
    #expect(file.read() == URLComponents(url: firstLink, resolvingAgainstBaseURL: false)?.fragment?.replacingOccurrences(of: "token=", with: ""))
    let privateFile = directory.appendingPathComponent("pairing")
    let attributes = try FileManager.default.attributesOfItem(atPath: privateFile.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    first.stop()

    let restarted = makeReceiver()
    restarted.start()
    defer { restarted.stop() }
    #expect(restarted.hasPhonePairing)
    let newLink = try #require(restarted.pairPhone())
    #expect(firstLink != newLink)
    #expect(file.read() == URLComponents(url: newLink, resolvingAgainstBaseURL: false)?.fragment?.replacingOccurrences(of: "token=", with: ""))
    #expect(restarted.disconnectPhone())
    #expect(!restarted.hasPhonePairing && file.read() == nil)
    restarted.stop()
    restarted.start()
    #expect(!restarted.hasPhonePairing)
}
