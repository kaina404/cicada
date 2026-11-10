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
