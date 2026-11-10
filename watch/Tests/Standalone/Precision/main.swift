import Foundation
import CoreGraphics

func expect(_ value: @autoclosure () -> Bool, _ label: String) { precondition(value(), label) }
func stroke(speed: Double, points: Double) -> CGSize {
  var motion = TouchMotion(at: 0)
  let steps = 60
  for step in 1...steps {
    let point = points * Double(step) / Double(steps)
    _ = motion.update(CGSize(width: point, height: 0), at: point / speed)
  }
  return motion.translation
}
let slow = stroke(speed: 20, points: 100)
let fast = stroke(speed: 400, points: 100)
expect(abs(slow.width - 15) < 0.001, "Slow movement has precision gain")
expect(fast.width > 85 && fast.width <= 100, "Quick stroke preserves travel")
var motion = TouchMotion(at: 0)
_ = motion.update(CGSize(width: 100, height: 0), at: 0.25)
let before = motion.translation.width
_ = motion.update(CGSize(width: 100.5, height: 0), at: 0.3)
expect(abs(motion.translation.width - before - 0.075) < 0.001, "Fast stroke does not inflate the next tiny correction")
let stopped = motion.translation
_ = motion.update(CGSize(width: 100.5, height: 0), at: 0.5)
expect(motion.translation == stopped, "Stationary finger produces no drift")
_ = motion.update(CGSize(width: 100, height: 0), at: 0.55)
expect(abs(motion.translation.width - before) < 0.001, "Fine reverse movement is symmetric")
var vertical = TouchMotion(at: 0)
let up = vertical.update(CGSize(width: 0, height: -1), at: 0.1)
expect(abs(up.height + 0.15) < 0.001 && up.width == 0, "Vertical direction and low gain preserved")
var diagonal = TouchMotion(at: 0)
let d = diagonal.update(CGSize(width: 1, height: 1), at: 0.1)
expect(abs(d.width - d.height) < 0.001, "Diagonal has no axis-dependent acceleration")
var sparse = TouchMotion(at: 0)
for i in 1...10 { _ = sparse.update(CGSize(width: Double(i) * 10, height: 0), at: Double(i) * 0.5) }
expect(abs(sparse.translation.width - slow.width) < 0.001, "Slow precision is stable across sample rates")
var touch = TouchState()
touch.begin(at: 0)
expect(touch.update(translation: CGSize(width: 1, height: 0)) == nil, "Small tap jitter ignored")
expect(touch.update(translation: CGSize(width: 2.1, height: 0)) == .move, "Fine movement starts without old five-point jump")
print("PASS: local velocity acceleration, fine reversal, fast-to-slow transition, zero drift, direction, sample-rate stability, smaller start threshold")
print("100 watch-point stroke: slow=\(slow.width), fast=\(fast.width); standard 170-point area: slow 1-point correction ≈ \(900 / 170 * TouchMotion.precisionGain) Mac points")
