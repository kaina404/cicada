import Foundation
import CoreGraphics

/// Packet arrival changes the target, never the rendering clock. No extrapolation.
/// Button transitions first finish the pending path at its exact endpoint.
struct CursorRenderer {
  private(set) var position: CGPoint
  private(set) var target: CGPoint
  private(set) var moving = false
  private var pressed = false
  private var lastTime: TimeInterval?
  static let responseTime: TimeInterval = 0.030

  init(position: CGPoint) { self.position = position; target = position }

  mutating func receive(_ actions: [CursorState.Action], at time: TimeInterval) -> [CursorState.Action] {
    var output: [CursorState.Action] = []
    for action in actions {
      switch action {
      case .move(let point, _):
        if !moving { lastTime = time }
        target = point
        moving = position != target
      case .down(let point):
        output += finish(at: point)
        output.append(action)
        pressed = true
      case .up(let point):
        output += finish(at: point)
        output.append(action)
        pressed = false
      case .click(let point, _):
        output += finish(at: point)
        output.append(action)
      }
    }
    return output
  }

  mutating func frame(at time: TimeInterval) -> CursorState.Action? {
    guard moving, let previous = lastTime, time > previous else { return nil }
    lastTime = time
    let distance = hypot(target.x - position.x, target.y - position.y)
    // Tiny corrections settle quickly; large strokes retain packet-jitter smoothing.
    let response = distance < 8 ? 0.010 : Self.responseTime
    let alpha = -expm1(-(time - previous) / response)
    position.x += (target.x - position.x) * alpha
    position.y += (target.y - position.y) * alpha
    if hypot(target.x - position.x, target.y - position.y) < 0.15 {
      position = target
      moving = false
    }
    return .move(position, dragging: pressed)
  }

  /// Freeze at the actual cursor for cancellation, pause and external repositioning.
  mutating func synchronize(to point: CGPoint) {
    position = point
    target = point
    moving = false
    lastTime = nil
  }

  mutating func finish() -> [CursorState.Action] { finish(at: target) }

  private mutating func finish(at point: CGPoint) -> [CursorState.Action] {
    let actions: [CursorState.Action] = position != point ? [.move(point, dragging: pressed)] : []
    synchronize(to: point)
    return actions
  }
}
