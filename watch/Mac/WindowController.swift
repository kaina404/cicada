import AppKit
import QuartzCore

@MainActor
protocol ControlledWindow: AnyObject {
  var title: String { get }
  var isAssistant: Bool { get }
  func frame() -> CGRect?
  func move(to point: CGPoint) -> Bool
}

extension ControlledWindow { var isAssistant: Bool { false } }

/// Own-process windows need neither Accessibility permission nor localized title matching.
@MainActor
final class FloatingAnswerWindow: ControlledWindow {
  weak var window: NSWindow?
  init(_ window: NSWindow) { self.window = window }
  var title: String { window?.title ?? "" }
  var isAssistant: Bool { true }
  func frame() -> CGRect? {
    guard let window, window.isVisible, !window.isMiniaturized else { return nil }
    let top = NSScreen.screens.first?.frame.maxY ?? 0
    return CGRect(x: window.frame.minX, y: top - window.frame.maxY,
                  width: window.frame.width, height: window.frame.height)
  }
  func move(to point: CGPoint) -> Bool {
    guard let window, frame() != nil else { return false }
    let top = NSScreen.screens.first?.frame.maxY ?? 0
    window.setFrameOrigin(CGPoint(x: point.x, y: top - point.y - window.frame.height))
    return true
  }
}

/// Moves the target window with ordered packets and display smoothing; never posts mouse events.
@MainActor
final class WindowController: NSObject {
  private(set) var target: ControlledWindow?
  private(set) var original = CGPoint.zero
  private var unavailable = false
  private var state = CursorState()
  private var renderer = CursorRenderer(position: .zero)
  private var link: CADisplayLink?
  private var timer: Timer?
  var onFrame: ((CGRect?) -> Void)?
  var onFailure: (() -> Void)?
  private var pendingTap: Task<Void, Never>?
  var onSentence: ((Int) -> Void)?
  var onPlaySentence: ((Int) -> Void)?
  var onHold: ((Bool) -> Void)?
  var allowed = false { didSet { if !allowed { cancel() } } }
  var sensitivity: CGFloat = 1 { didSet { cancel(); state.sensitivity = sensitivity } }

  override init() {
    super.init()
    timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, self.target != nil else { return }
        if self.state.activeGesture != nil {
          _ = self.state.expire(at: ProcessInfo.processInfo.systemUptime, cursor: self.renderer.position)
          if self.state.activeGesture == nil { self.cancel() }
        }
        self.onFrame?(self.allowed && !self.unavailable ? self.target?.frame() : nil)
      }
    }
    if let timer { RunLoop.main.add(timer, forMode: .common) }
  }

  @discardableResult func select(_ window: ControlledWindow?) -> Bool {
    guard window == nil || window?.frame() != nil else { return false }
    cancel()
    target = window
    unavailable = false
    original = window?.frame()?.origin ?? .zero
    // A mode switch must also discard the previous mode's click count.
    state = CursorState()
    state.sensitivity = sensitivity
    renderer.synchronize(to: original)
    onFrame?(allowed ? window?.frame() : nil)
    return true
  }

  func receive(_ packet: ControlPacket, screens: [CGRect], at time: TimeInterval) {
    guard allowed, let target else { return }
    guard let frame = target.frame() else { fail(); return }
    if !renderer.moving { renderer.synchronize(to: frame.origin) }
    // Keep the title bar reachable while allowing large windows and multiple displays.
    let bounds = screens.map { CGRect(x: $0.minX - max(0, frame.width - 80), y: $0.minY,
                                     width: $0.width + max(0, frame.width - 80) - 79,
                                     height: max(1, $0.height - 27)) }
    let active = state.activeGesture
    let inputRevision = state.inputRevision
    let wasDown = state.isDown
    let actions = state.receive(packet, at: time, cursor: renderer.target, screens: bounds,
                                doubleClickInterval: NSEvent.doubleClickInterval)
    if state.inputRevision != inputRevision, state.isDown { pendingTap?.cancel(); pendingTap = nil; onHold?(true) }
    else if wasDown && !state.isDown || packet.kind == .begin { onHold?(false) }
    if state.inputRevision != inputRevision, packet.kind == .sentence, target.isAssistant {
      pendingTap?.cancel(); pendingTap = nil
      if packet.y == 1 || packet.y == -1 { onSentence?(Int(packet.y)) }
    }
    if packet.kind == .cancel, active != nil, state.activeGesture == nil { cancel(); return }
    // A hold owns playback until lift, including its first and final coordinates.
    // Freeze any queued smoothing so finger jitter cannot move the answer while reading.
    let playbackGesture = wasDown || state.isDown
    if playbackGesture {
      renderer.synchronize(to: frame.origin)
      link?.isPaused = true
    }
    for action in actions {
      switch action {
      case .move where !playbackGesture: _ = renderer.receive([action], at: time)
      case .click(_, let count) where target.isAssistant:
        pendingTap?.cancel()
        if count % 2 == 0 { (onPlaySentence ?? onSentence)?(-1) }
        else {
          pendingTap = Task { [weak self] in
            try? await Task.sleep(for: .seconds(NSEvent.doubleClickInterval))
            guard !Task.isCancelled, let self, self.allowed, self.target?.isAssistant == true,
                  self.target?.frame() != nil else { return }
            (self.onPlaySentence ?? self.onSentence)?(1)
          }
        }
      case .click(_, let count) where count % 2 == 0:
        renderer.synchronize(to: original)
        guard target.move(to: original) else { fail(); return }
        onFrame?(target.frame())
      default: break // Single taps and holds never click or press inside the selected window.
      }
    }
    if packet.kind == .end, active != nil, state.activeGesture == nil { apply(renderer.finish()) }
    if renderer.moving { startLink() }
  }

  func cancel() {
    pendingTap?.cancel(); pendingTap = nil
    onHold?(false)
    _ = state.cancel(cursor: renderer.position)
    renderer.synchronize(to: target?.frame()?.origin ?? renderer.position)
    link?.isPaused = true
    if !allowed { onFrame?(nil) }
  }

  private func fail() {
    unavailable = true
    cancel()
    onFrame?(nil)
    onFailure?()
  }

  private func apply(_ actions: [CursorState.Action]) {
    for action in actions {
      if case .move(let point, _) = action, target?.move(to: point) != true { fail(); return }
    }
    unavailable = false
    onFrame?(target?.frame())
  }

  private func startLink() {
    if link == nil, let screen = NSScreen.main {
      let display = screen.displayLink(target: self, selector: #selector(render(_:)))
      display.add(to: .main, forMode: .common)
      link = display
    }
    link?.isPaused = false
  }

  @objc private func render(_ display: CADisplayLink) {
    if let action = renderer.frame(at: ProcessInfo.processInfo.systemUptime) { apply([action]) }
    display.isPaused = !renderer.moving
  }

  func stop() { cancel(); timer?.invalidate(); link?.invalidate() }
}

