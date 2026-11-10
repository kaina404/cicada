import AppKit

/// Cicada owns the receiver, its floating window and playback. No helper process or AX/IPC bridge.
@MainActor
public final class CicadaWatchReceiver {
    private let pairingURL: URL?
    private let getWindow: () -> NSWindow?
    private let setHeld: (Bool) -> Void
    private let selectSentence: (Int) -> Void
    private let log: (String) -> Void
    private let controller = WindowController()
    private var lan: LANServer?
    private var bluetooth: BluetoothServer?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var suspended = false
    private var remotePressed = false
    public private(set) var status = "not started"

    public init(pairingURL: URL?, window: @escaping () -> NSWindow?,
                setHeld: @escaping (Bool) -> Void, selectSentence: @escaping (Int) -> Void,
                playSentence: ((Int) -> Void)? = nil,
                log: @escaping (String) -> Void = { _ in }) {
        self.pairingURL = pairingURL
        self.getWindow = window
        self.setHeld = setHeld
        self.selectSentence = selectSentence
        self.log = log
        controller.onHold = { [weak self] in self?.updateHold($0) }
        controller.onSentence = { [weak self] offset in
            guard let self else { return }
            self.remotePressed = false
            self.setHeld(false)
            self.selectSentence(offset)
        }
        controller.onPlaySentence = { [weak self] offset in
            guard let self else { return }
            self.updateHold(false)
            if let playSentence {
                playSentence(offset)
                // Target loss, sleep and the next touch must also stop tap playback.
                self.remotePressed = true
            } else { self.selectSentence(offset) }
        }
        controller.onFailure = { [weak self] in
            self?.controller.allowed = false
            self?.controller.select(nil)
        }
    }

    public func start() {
        guard lan == nil else { return }
        guard let pairingURL, let data = try? Data(contentsOf: pairingURL),
              let pairing = try? JSONDecoder().decode(WatchPairing.self, from: data), pairing.isValid else {
            status = "disabled: missing local pairing"
            log("watch: \(status)")
            return
        }
        let lan = LANServer(token: pairing.token, port: pairing.effectivePort) { [weak self] in self?.receive($0) }
        self.lan = lan
        lan.onStatus = { [weak self] in self?.log("watch LAN: \($0)") }
        lan.start()
        let bluetooth = BluetoothServer(serviceID: pairing.bluetoothService) { [weak self] in self?.receive($0) }
        self.bluetooth = bluetooth
        bluetooth.onStatus = { [weak self] in self?.log("watch BLE: \($0)") }
        bluetooth.start()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.suspended = true
                    self?.controller.allowed = false
                }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.suspended = false }
            })
        }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshTarget() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        refreshTarget()
        log("watch: receiver started")
    }

    public func stop() {
        controller.allowed = false
        controller.select(nil)
        updateHold(false)
        timer?.invalidate()
        timer = nil
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
        lan?.stop()
        lan = nil
        bluetooth?.stop()
        bluetooth = nil
        status = "stopped"
    }

    private func updateHold(_ pressed: Bool) {
        // Repeated true values renew the audio lease. Idle polling must not pause local controls.
        guard pressed || remotePressed else { return }
        remotePressed = pressed
        setHeld(pressed)
    }

    /// Also checked before each packet, so a hidden/replaced float cannot receive stale input.
    func refreshTarget() {
        guard !suspended, let window = getWindow(), window.isVisible, !window.isMiniaturized,
              window.identifier?.rawValue == "cicada.assistant" else {
            controller.allowed = false
            if controller.target != nil { controller.select(nil) }
            status = suspended ? "suspended" : "waiting for floating answer"
            return
        }
        if (controller.target as? FloatingAnswerWindow)?.window !== window {
            controller.allowed = false
            guard controller.select(FloatingAnswerWindow(window)) else { return }
            log("watch: connected to floating answer")
        }
        controller.allowed = true
        status = "floating answer ready"
    }

    func receive(_ packet: ControlPacket) {
        refreshTarget()
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let screens = NSScreen.screens.map {
            CGRect(x: $0.frame.minX, y: top - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height)
        }
        controller.receive(packet, screens: screens, at: ProcessInfo.processInfo.systemUptime)
    }
}

struct WatchPairing: Decodable {
    let host: String
    let bluetoothService: String
    let token: String
    var port: String? = nil
    var effectivePort: UInt16 { UInt16(port ?? "8765") ?? 8765 }
    var isValid: Bool {
        !host.isEmpty && UUID(uuidString: bluetoothService) != nil && !token.isEmpty &&
        (port == nil || (UInt16(port ?? "") ?? 0) > 0)
    }
}
