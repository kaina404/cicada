import AppKit
import SystemConfiguration

/// Cicada owns the receiver, its floating window and playback. No helper process or AX/IPC bridge.
@MainActor
public final class CicadaWatchReceiver {
    private let pairingURL: URL?
    private let phonePairingFile: PhonePairingFile?
    private let getWindow: () -> NSWindow?
    private let setHeld: (Bool) -> Void
    private let selectSentence: (Int) -> Void
    private let phoneState: (() -> FloatingAnswerState)?
    private let refreshAnswer: (() -> Bool)?
    private var refreshRequests: [UUID] = []
    private var phoneWindowID: UUID?
    private var phoneScreen: PhoneScreenCapture?
    private let log: (String) -> Void
    private let controller = WindowController()
    private var lan: LANServer?
    private var bluetooth: BluetoothServer?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var suspended = false
    private var remotePressed = false
    public private(set) var status = "not started"

    public init(pairingURL: URL?, phonePairingDirectory: URL? = nil, window: @escaping () -> NSWindow?,
                setHeld: @escaping (Bool) -> Void, selectSentence: @escaping (Int) -> Void,
                playSentence: ((Int) -> Void)? = nil,
                phoneState: (() -> FloatingAnswerState)? = nil,
                refreshAnswer: (() -> Bool)? = nil,
                log: @escaping (String) -> Void = { _ in }) {
        self.pairingURL = pairingURL
        self.phonePairingFile = phonePairingDirectory.map { PhonePairingFile(directory: $0) }
        self.getWindow = window
        self.setHeld = setHeld
        self.selectSentence = selectSentence
        self.phoneState = phoneState
        self.refreshAnswer = refreshAnswer
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
        let pairing = pairingURL.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(WatchPairing.self, from: $0) }
        let watchPairing = pairing.flatMap { $0.isValid ? $0 : nil }
        guard watchPairing != nil || phoneState != nil else {
            status = "disabled: missing local pairing"
            log("watch: \(status)")
            return
        }
        let lan = LANServer(token: watchPairing?.token, port: watchPairing?.effectivePort ?? 8765) {
            [weak self] in self?.receive($0)
        }
        self.lan = lan
        lan.phoneState = { [weak self] in self?.readPhoneState() ?? FloatingAnswerState() }
        lan.phoneScreen = { [weak self] in
            guard let self else { return .off }
            self.refreshTarget()
            guard let capture = self.phoneScreen else { return .off }
            let frame = await capture.nextFrame()
            self.refreshTarget()
            return self.phoneScreen === capture ? frame : .off
        }
        lan.receivePhonePacket = { [weak self] packet, windowID in
            self?.receivePhone(packet, windowID: windowID) == true
        }
        lan.refreshPhoneAnswer = { [weak self] window, request in
            self?.refreshPhoneAnswer(windowID: window, requestID: request) == true
        }
        lan.onStatus = { [weak self] in self?.log("watch LAN: \($0)") }
        if phoneState != nil, let token = phonePairingFile?.read(), FloatingAnswerPairing.isValidToken(token) {
            refreshRequests.removeAll()
        lan.phoneToken = token
        }
        if watchPairing != nil || lan.phoneToken != nil { lan.start() }
        if let watchPairing {
            let bluetooth = BluetoothServer(serviceID: watchPairing.bluetoothService) { [weak self] in self?.receive($0) }
            self.bluetooth = bluetooth
            bluetooth.onStatus = { [weak self] in self?.log("watch BLE: \($0)") }
            bluetooth.start()
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.suspended = true
                    self?.refreshTarget()
                }
            })
        }
        observers.append(center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopPhoneScreen() }
        })
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
        stopPhoneScreen()
        controller.allowed = false
        controller.select(nil)
        phoneWindowID = nil
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

    public func windowVisibilityChanged() { refreshTarget() }

    /// Also checked before each packet, so a hidden/replaced float cannot receive stale input.
    func refreshTarget() {
        guard !suspended, let window = getWindow(), window.isVisible, !window.isMiniaturized,
              window.identifier?.rawValue == "cicada.assistant" else {
            stopPhoneScreen()
            controller.allowed = false
            phoneWindowID = nil
            if controller.target != nil { controller.select(nil) }
            status = suspended ? "suspended" : "waiting for floating answer"
            return
        }
        if (controller.target as? FloatingAnswerWindow)?.window !== window {
            stopPhoneScreen()
            controller.allowed = false
            guard controller.select(FloatingAnswerWindow(window)) else { return }
            phoneWindowID = UUID()
            log("watch: connected to floating answer")
        }
        controller.allowed = true
        status = "floating answer ready"
    }

    public var hasPhonePairing: Bool { lan?.phoneToken != nil }

    /// Replace the previous credential only after the new one has been saved.
    public func pairPhone() -> URL? {
        guard let lan, phoneState != nil, let localName = SCDynamicStoreCopyLocalHostName(nil) as String?, !localName.isEmpty else { return nil }
        let token = (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "").lowercased()
        guard let url = FloatingAnswerPairing(host: localName + ".local", port: lan.port.rawValue, token: token).webLink else { return nil }
        do { try phonePairingFile?.save(token) }
        catch { return nil }
        controller.cancelPhoneInput()
        stopPhoneScreen()
        refreshRequests.removeAll()
        lan.phoneToken = token
        lan.start()
        return url
    }

    @discardableResult
    public func disconnectPhone() -> Bool {
        do { try phonePairingFile?.remove() }
        catch { return false }
        stopPhoneScreen()
        lan?.phoneToken = nil
        refreshRequests.removeAll()
        controller.cancelPhoneInput()
        return true
    }

    public func startPhoneScreen() -> Bool {
        refreshTarget()
        guard lan?.phoneToken != nil, phoneWindowID != nil,
              CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else { return false }
        stopPhoneScreen()
        phoneScreen = PhoneScreenCapture()
        return true
    }

    public func stopPhoneScreen() {
        phoneScreen?.stop()
        phoneScreen = nil
    }

    public var isPhoneScreenEnabled: Bool { phoneScreen != nil }

    func readPhoneState() -> FloatingAnswerState {
        refreshTarget()
        guard let phoneWindowID, let phoneState else { return FloatingAnswerState() }
        return phoneState().scoped(to: phoneWindowID)
    }

    func refreshPhoneAnswer(windowID: UUID, requestID: UUID) -> Bool {
        refreshTarget()
        guard phoneWindowID == windowID else { return false }
        if refreshRequests.contains(requestID) { return true }
        guard phoneState?().canRefreshAnswer == true else { return false }
        controller.cancelPhoneInput()
        updateHold(false)
        guard refreshAnswer?() == true else { return false }
        refreshRequests.append(requestID)
        if refreshRequests.count > 64 { refreshRequests.removeFirst() }
        return true
    }

    func receivePhone(_ packet: ControlPacket, windowID: UUID) -> Bool {
        refreshTarget()
        guard phoneWindowID == windowID else { return false }
        apply(packet, source: .phone)
        return true
    }

    func receive(_ packet: ControlPacket) {
        refreshTarget()
        apply(packet, source: .watch)
    }

    private func apply(_ packet: ControlPacket, source: WindowController.InputSource) {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let screens = NSScreen.screens.map {
            CGRect(x: $0.frame.minX, y: top - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height)
        }
        controller.receive(packet, screens: screens, at: ProcessInfo.processInfo.systemUptime, source: source)
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
