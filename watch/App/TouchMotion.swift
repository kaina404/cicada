import Foundation
import CoreGraphics

/// Acceleration is computed from local touch timestamps, never jittery network arrival times.
/// Slow corrections use low gain; quick strokes retain the full travel range.
struct TouchMotion {
  private(set) var translation = CGSize.zero
  private var previous = CGSize.zero
  private var previousTime: TimeInterval
  private var speed: CGFloat = 0
  static let precisionGain: CGFloat = 0.15

  init(at time: TimeInterval) { previousTime = time }

  mutating func update(_ raw: CGSize, at time: TimeInterval) -> CGSize {
    let dx = raw.width - previous.width, dy = raw.height - previous.height
    let dt = max(time - previousTime, 1.0 / 240)
    let measured = hypot(dx, dy) / dt
    let alpha = -expm1(-dt / 0.025)
    // Decelerate immediately when the finger slows; never carry fast-swipe gain into aiming.
    speed = min(measured, speed + (measured - speed) * alpha)
    let fraction = min(max((speed - 35) / (240 - 35), 0), 1)
    let curve = fraction * fraction * (3 - 2 * fraction)
    let gain = Self.precisionGain + (1 - Self.precisionGain) * curve
    translation.width += dx * gain
    translation.height += dy * gain
    previous = raw
    previousTime = time
    return translation
  }
}
