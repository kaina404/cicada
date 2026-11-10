import Foundation

/// A stationary touch becomes a hold; movement beyond the slop permanently selects pointing.
struct TouchState {
  static let holdDelay: TimeInterval = 0.4
  static let slop: CGFloat = 2
  private(set) var active = false
  private(set) var holding = false
  private(set) var moving = false
  private var started: TimeInterval = 0

  mutating func begin(at time: TimeInterval) {
    self = TouchState()
    active = true
    started = time
  }

  mutating func update(translation: CGSize) -> ControlPacket.Kind? {
    guard active else { return nil }
    if hypot(translation.width, translation.height) >= Self.slop { moving = true }
    return holding ? .hold : (moving ? .move : nil)
  }

  mutating func tick(at time: TimeInterval) -> ControlPacket.Kind? {
    guard active else { return nil }
    if !moving, !holding, time - started >= Self.holdDelay { holding = true }
    // Generic transport pings never renew a press; the live touch must do so.
    return holding ? .hold : .move
  }

  mutating func end(translation: CGSize) -> ControlPacket.Kind? {
    guard active else { return nil }
    _ = update(translation: translation)
    active = false
    return holding || moving ? .end : .click
  }

  mutating func cancel() { self = TouchState() }
}
