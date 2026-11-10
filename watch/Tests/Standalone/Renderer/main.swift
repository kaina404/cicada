import Foundation
import CoreGraphics

func expect(_ condition: @autoclosure () -> Bool, _ message: String) { precondition(condition(), message) }
var render = CursorRenderer(position: .zero)
expect(render.receive([.move(CGPoint(x: 100, y: 0), dragging: false)], at: 0).isEmpty, "Packet must not jump the cursor")
_ = render.frame(at: 1.0 / 120)
expect(render.position.x > 0 && render.position.x < 100, "Display frame advances smoothly")
let down = render.receive([.down(CGPoint(x: 100, y: 0))], at: 0.01)
expect(down == [.move(CGPoint(x: 100, y: 0), dragging: false), .down(CGPoint(x: 100, y: 0))], "Down is at the exact target")
_ = render.receive([.move(CGPoint(x: 200, y: 0), dragging: true)], at: 0.02)
if case .move(_, let dragging) = render.frame(at: 0.03) { expect(dragging, "Frames during hold are dragged events") }
else { preconditionFailure("Expected drag frame") }
let up = render.receive([.move(CGPoint(x: 220, y: 0), dragging: true), .up(CGPoint(x: 220, y: 0))], at: 0.04)
expect(up == [.move(CGPoint(x: 220, y: 0), dragging: true), .up(CGPoint(x: 220, y: 0))], "Finish drag before up")
expect(render.frame(at: 0.05) == nil, "No movement after up")
_ = render.receive([.move(CGPoint(x: 300, y: 0), dragging: false)], at: 0.06)
let clicks = render.receive([.click(CGPoint(x: 300, y: 0), count: 2)], at: 0.07)
expect(clicks.last == .click(CGPoint(x: 300, y: 0), count: 2), "Double click preserved after settling")
_ = render.receive([.down(CGPoint(x: 300, y: 0)), .move(CGPoint(x: 400, y: 0), dragging: true)], at: 0.08)
_ = render.frame(at: 0.09)
let frozen = render.position
render.synchronize(to: frozen)
expect(render.receive([.up(frozen)], at: 0.10) == [.up(frozen)], "Cancel releases at actual position")
expect(render.frame(at: 0.2) == nil, "Cancel does not drift")
for hz in [60, 120] {
  var model = CursorRenderer(position: .zero)
  _ = model.receive([.move(CGPoint(x: 100, y: -100), dragging: false)], at: 0)
  for i in 1...hz {
    _ = model.frame(at: Double(i) / Double(hz))
    expect(model.position.x <= 100 && model.position.y >= -100, "Never extrapolate past target")
  }
  expect(model.position == CGPoint(x: 100, y: -100) && !model.moving, "Converges and pauses at either refresh rate")
}
var small = CursorRenderer(position: .zero)
_ = small.receive([.move(CGPoint(x: 3, y: 0), dragging: false)], at: 0)
_ = small.frame(at: 0.03)
expect(small.position.x > 2.8, "Small corrections respond in 30ms rather than trailing a large stroke")
let finalPointing = small.finish()
expect(finalPointing.isEmpty || finalPointing == [.move(CGPoint(x: 3, y: 0), dragging: false)], "Finger lift finishes pointing endpoint")
expect(small.frame(at: 0.05) == nil, "No pointing drift after lift")
// Replay a deterministic irregular ~20 Hz input on a 120 Hz rendering clock.
let intervals = [0.025, 0.055, 0.049, 0.140, 0.033, 0.248, 0.05]
var inputs: [(Double, CGPoint)] = []
var inputTime = 0.0
for index in 0..<45 {
  inputTime += intervals[index % intervals.count]
  inputs.append((inputTime, CGPoint(x: 140 * sin(inputTime * 2), y: 0)))
}
var model = CursorRenderer(position: .zero)
var direct = CGPoint.zero
var input = 0
var previousSmooth = CGPoint.zero, previousDirect = CGPoint.zero
var smoothSteps: [Double] = [], directSteps: [Double] = []
for frame in 1...Int((inputTime + 0.3) * 120) {
  let time = Double(frame) / 120
  while input < inputs.count && inputs[input].0 <= time {
    let (at, target) = inputs[input]
    direct = target
    _ = model.receive([.move(target, dragging: false)], at: at)
    input += 1
  }
  _ = model.frame(at: time)
  smoothSteps.append(abs(model.position.x - previousSmooth.x))
  directSteps.append(abs(direct.x - previousDirect.x))
  previousSmooth = model.position
  previousDirect = direct
}
func stats(_ steps: [Double]) -> [String: Double] {
  let sorted = steps.sorted()
  return ["maxStep": sorted.last ?? 0, "p95Step": sorted[Int(Double(sorted.count) * 0.95)],
          "stationaryFraction": Double(steps.filter { $0 < 0.01 }.count) / Double(steps.count)]
}
let directStats = stats(directSteps), smoothStats = stats(smoothSteps)
expect((smoothStats["maxStep"] ?? 0) < (directStats["maxStep"] ?? 0) * 0.5, "Irregular packet steps spread across frames")
expect((smoothStats["stationaryFraction"] ?? 0) < (directStats["stationaryFraction"] ?? 0), "Fewer motionless frames")
let data = try JSONSerialization.data(withJSONObject: ["direct": directStats, "smooth": smoothStats], options: [.prettyPrinted, .sortedKeys])
try data.write(to: URL(fileURLWithPath: "build/cursor-render-comparison.json"))
print("PASS: display smoothing, no overshoot, exact down/up/click positions, drag ordering, freeze on cancel, 60/120 Hz convergence")
print(String(decoding: data, as: UTF8.self))
