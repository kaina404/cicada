import Foundation
import CoreGraphics

var checks = 0
func check(_ value: @autoclosure () -> Bool, _ label: String) {
  checks += 1
  precondition(value(), label)
}
let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
var state = CursorState()
var point = CGPoint(x: 500, y: 400)
var time: TimeInterval = 0
var seq: UInt32 = 0
func send(_ kind: ControlPacket.Kind, session: UInt32 = 1, gesture: UInt16 = 1,
          x: Float = 0, y: Float = 0) -> [CursorState.Action] {
  seq &+= 1
  let actions = state.receive(ControlPacket(kind: kind, session: session, sequence: seq,
      gesture: gesture, x: x, y: y), at: time, cursor: point, screens: [screen])
  for action in actions { if case .move(let p, _) = action { point = p } }
  return actions
}
check(send(.hold).isEmpty, "Unbegun hold ignored")
check(send(.begin).isEmpty, "Begin does not click or move")
_ = send(.move, x: 0.1, y: -0.1)
check(abs(point.x - 590) < 0.001 && abs(point.y - 310) < 0.001, "Direction uses Quartz coordinates")
_ = send(.move, x: 0.2, y: -0.1)
check(abs(point.x - 680) < 0.001, "Cumulative displacement is not added twice")
_ = send(.end, x: 0.2, y: -0.1)
let lifted = point
_ = send(.begin, gesture: 2)
check(point == lifted, "Relanding does not jump")
_ = send(.move, gesture: 2, x: -0.1)
check(abs(point.x - 590) < 0.001, "New gesture starts from current cursor")
check(send(.hold, gesture: 2, x: -0.1) == [.down(point)], "Hold presses once")
check(send(.hold, gesture: 2, x: -0.1).isEmpty, "Held heartbeat is idempotent")
let drag = send(.hold, gesture: 2, x: 0.1)
check(drag == [.move(point, dragging: true)], "Movement while held generates drag")
let finish = send(.end, gesture: 2, x: 0.2)
check(finish == [.move(point, dragging: true), .up(point)], "Final drag precedes release")
check(!state.isDown, "End releases")
check(send(.hold, gesture: 2).isEmpty, "Late hold cannot reopen ended gesture")
_ = send(.begin, gesture: 3)
_ = send(.hold, gesture: 3)
time = 1.6
check(state.expire(at: time, cursor: point) == [.up(point)], "Watchdog releases an abandoned hold")
check(send(.hold, gesture: 3).isEmpty, "Late heartbeat cannot reacquire expired hold")
_ = send(.begin, gesture: 4)
_ = send(.hold, gesture: 4)
time = 3.2
check(send(.hold, gesture: 4) == [.up(point)], "Lease expiry checked on receive, before timer")
_ = send(.begin, gesture: 5)
_ = send(.hold, gesture: 5)
let p = ControlPacket(kind: .end, session: 1, sequence: seq + 2, gesture: 5)
check(state.receive(p, at: time, cursor: point, screens: [screen]) == [.up(point)], "End accepted")
check(state.receive(ControlPacket(kind: .hold, session: 1, sequence: seq + 1, gesture: 5),
  at: time, cursor: point, screens: [screen]).isEmpty, "Out-of-order hold ignored")
seq += 2
_ = send(.begin, session: 2, gesture: 6)
check(send(.hold, session: 2, gesture: 6) == [.down(point)], "New foreground session accepted")
check(send(.begin, session: 1, gesture: 9).isEmpty && state.isDown, "Retired session cannot interrupt new session")
check(send(.cancel, session: 2, gesture: 6) == [.up(point)], "Explicit cancel releases")
check(send(.cancel, session: 2, gesture: 6).isEmpty, "Duplicate cancellation harmless")
_ = send(.begin, session: 2, gesture: 7)
check(send(.click, session: 2, gesture: 7) == [.click(point, count: 1)], "Tap clicks")
time += 0.2
_ = send(.begin, session: 2, gesture: 8)
check(send(.click, session: 2, gesture: 8) == [.click(point, count: 2)], "Second tap carries native double-click count")
time += 0.8
_ = send(.begin, session: 2, gesture: 9)
check(send(.click, session: 2, gesture: 9) == [.click(point, count: 1)], "Slow tap starts new click sequence")
let displays = [screen, CGRect(x: -1280, y: -200, width: 1280, height: 1024), CGRect(x: 1920, y: 300, width: 900, height: 600)]
check(CursorState.clamp(CGPoint(x: -500, y: 0), to: displays) == CGPoint(x: -500, y: 0), "Left display supported")
check(CursorState.clamp(CGPoint(x: -500, y: -100), to: displays).y == -100, "Display above primary supported")
check(displays.contains { $0.contains(CursorState.clamp(CGPoint(x: 2000, y: 100), to: displays)) }, "Display gaps cannot strand cursor")
// Edge reversal should respond immediately, with no accumulated off-screen debt.
_ = send(.begin, session: 2, gesture: 10)
_ = send(.move, session: 2, gesture: 10, x: 4)
check(point.x == 1919, "Right edge clamped")
_ = send(.move, session: 2, gesture: 10, x: 3.9)
check(point.x < 1830, "Reverse at edge responds immediately")
_ = send(.hold, session: 2, gesture: 10, x: 3.9)
check(state.cancel(cursor: point) == [.up(point)], "Pause/termination releases")
var wrapped = CursorState()
_ = wrapped.receive(ControlPacket(kind: .begin, sequence: .max), at: 0, cursor: point, screens: [screen])
check(wrapped.receive(ControlPacket(kind: .hold, sequence: 0), at: 0.1, cursor: point, screens: [screen]) == [.down(point)], "Sequence wrap accepted")

var touch = TouchState()
touch.begin(at: 0)
check(touch.update(translation: CGSize(width: 1, height: 0.5)) == nil, "Tap jitter suppressed")
check(touch.tick(at: 0.39) == .move && !touch.holding, "Before long-press threshold no down")
check(touch.tick(at: 0.41) == .hold && touch.holding, "Stationary long press enters hold")
check(touch.update(translation: CGSize(width: 20, height: 0)) == .hold, "Hold then move remains drag")
check(touch.end(translation: CGSize(width: 20, height: 0)) == .end, "Drag lifts without click")
touch.begin(at: 1)
check(touch.update(translation: CGSize(width: 6, height: 0)) == .move, "Early movement selects pointing")
check(touch.tick(at: 2) == .move && !touch.holding, "Pause during pointing never becomes hold")
check(touch.end(translation: .zero) == .end, "Returning to start is not a click")
touch.begin(at: 3)
check(touch.end(translation: .zero) == .click, "Stationary brief touch is click")
touch.begin(at: 4)
touch.cancel()
check(touch.tick(at: 5) == nil && touch.end(translation: .zero) == nil, "Cancelled touch produces no hold or click")
print("PASS: \(checks) cursor/gesture checks: movement, drag ordering, double click, lease, stale sessions, screens, edge reversal, cancellation")
