import Foundation
import Combine
import WatchKit

@MainActor
final class TouchController: ObservableObject {
  @Published private(set) var state = TouchState()
  @Published private(set) var location: CGPoint?
  private var timer: Timer?
  private var session = UInt32.random(in: 1 ... .max)
  private var sequence: UInt32 = 0
  private var gesture: UInt16 = 0
  private var translation = CGSize.zero
  private var motion = TouchMotion(at: 0)
  private var pointerTranslation = CGSize.zero
  private var size = CGSize(width: 1, height: 1)
  private var blocked = false
  private weak var link: WatchLink?

  func changed(location: CGPoint, translation: CGSize, size: CGSize, link: WatchLink) {
    guard !blocked else { return }
    if !state.active {
      guard link.connected else { blocked = true; return }
      self.link = link
      gesture &+= 1
      self.size = size
      self.translation = .zero
      let now = ProcessInfo.processInfo.systemUptime
      state.begin(at: now)
      motion = TouchMotion(at: now)
      pointerTranslation = .zero
      send(.begin)
      timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
        MainActor.assumeIsolated { self?.tick() }
      }
      if let timer { RunLoop.main.add(timer, forMode: .common) }
    }
    self.location = location
    self.translation = translation
    pointerTranslation = motion.update(translation, at: ProcessInfo.processInfo.systemUptime)
    if let kind = state.update(translation: translation) { send(kind) }
  }

  func selectSentence(_ offset: Int, link: WatchLink) {
    guard link.connected, !state.active, !blocked, offset != 0 else { return }
    self.link = link
    gesture &+= 1
    send(.begin)
    sequence &+= 1
    link.send(ControlPacket(kind: .sentence, session: session, sequence: sequence,
                            gesture: gesture, y: offset > 0 ? 1 : -1))
    send(.end)
  }

  func ended(translation: CGSize) {
    defer { reset(); blocked = false }
    self.translation = translation
    pointerTranslation = motion.update(translation, at: ProcessInfo.processInfo.systemUptime)
    if let kind = state.end(translation: translation) { send(kind) }
  }

  /// Called for gesture cancellation, foreground loss, and transport interruptions.
  func cancel() {
    if state.active { send(.cancel); blocked = true }
    reset()
  }

  func gestureDidFinish() {
    cancel()
    blocked = false
  }

  func restartSession() {
    cancel()
    session = UInt32.random(in: 1 ... .max)
    sequence = 0
    blocked = false
  }

  private func tick() {
    guard link?.connected == true else { cancel(); return }
    let wasHolding = state.holding
    if let kind = state.tick(at: ProcessInfo.processInfo.systemUptime) { send(kind) }
    if !wasHolding, state.holding { WKInterfaceDevice.current().play(.click) }
  }

  private func send(_ kind: ControlPacket.Kind) {
    sequence &+= 1
    // Ignore pre-recognition jitter and tap displacement.
    let moving = state.moving || state.holding
    link?.send(ControlPacket(kind: kind, session: session, sequence: sequence, gesture: gesture,
      x: moving ? Float(pointerTranslation.width / max(size.width, 1)) : 0,
      y: moving ? Float(pointerTranslation.height / max(size.height, 1)) : 0))
  }

  private func reset() {
    timer?.invalidate()
    timer = nil
    state.cancel()
    location = nil
    translation = .zero
    pointerTranslation = .zero
  }
}
