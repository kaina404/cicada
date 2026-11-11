import AppKit
import Testing
@testable import CicadaWatchControl

@MainActor
final class FakeWindow: ControlledWindow {
  let title = "Test window"
  var isAssistant = false
  var rect: CGRect? = CGRect(x: 300, y: 200, width: 600, height: 400)
  var writable = true
  var moves: [CGPoint] = []
  func frame() -> CGRect? { rect }
  func move(to point: CGPoint) -> Bool {
    guard writable, rect != nil else { return false }
    rect?.origin = point
    moves.append(point)
    return true
  }
}
func expect(_ condition: @autoclosure () -> Bool, _ message: String) { #expect(condition(), "\(message)") }

@Test @MainActor func windowGesturesAndPlayback() async throws {
  let controller = WindowController()
  let window = FakeWindow()
  let screens = [CGRect(x: 0, y: 0, width: 1920, height: 1080)]
  var holds: [Bool] = []
  controller.onHold = { holds.append($0) }
  var sequence: UInt32 = 0
  @MainActor func send(_ kind: ControlPacket.Kind, _ gesture: UInt16, _ time: Double, x: Float = 0, y: Float = 0) {
    sequence += 1
    controller.receive(ControlPacket(kind: kind, session: 7, sequence: sequence, gesture: gesture, x: x, y: y), screens: screens, at: time)
  }
  controller.allowed = true
  send(.begin, 99, -2)
  send(.end, 99, -1.9, x: 0.2)
  expect(window.moves.isEmpty, "No target means incoming gestures do nothing")
  expect(controller.select(window), "Select available window")
  let original = controller.original
  send(.begin, 1, 0)
  send(.move, 1, 0.1, x: 0.1, y: 0.05)
  send(.end, 1, 0.2, x: 0.1, y: 0.05)
  expect(abs((window.rect?.minX ?? 0) - 390) < 0.001, "Moving without hold moves the whole window")
  expect(abs((window.rect?.minY ?? 0) - 245) < 0.001, "Vertical displacement")
  send(.begin, 2, 0.3)
  send(.click, 2, 0.31)
  expect(window.rect?.origin != original, "Single tap does not reset")
  send(.begin, 3, 0.4)
  send(.click, 3, 0.41)
  expect(window.rect?.origin == original, "Double tap restores selection origin")
  send(.begin, 4, 0.5)
  send(.end, 4, 0.6, x: -0.05)
  expect(abs((window.rect?.minX ?? 0) - 255) < 0.001, "Continue from restored origin")
  let moved = window.rect?.origin
  send(.end, 4, 0.7, x: -0.1)
  expect(window.rect?.origin == moved, "Ended gesture cannot move again")
  send(.begin, 5, 0.8)
  send(.move, 5, 0.9, x: 0.2)
  controller.allowed = false
  let paused = window.rect?.origin
  send(.end, 5, 1.0, x: 0.2)
  expect(window.rect?.origin == paused, "Pause cancels motion")
  controller.allowed = true
  send(.end, 5, 1.1, x: 0.3)
  expect(window.rect?.origin == paused, "Resume requires new touch")
  send(.begin, 6, 1.2)
  send(.move, 6, 3, x: 0.2)
  expect(window.rect?.origin == paused, "Expired gesture cannot move")
  var failures = 0
  controller.onFailure = { failures += 1 }
  window.writable = false
  send(.begin, 7, 4)
  send(.end, 7, 4.1, x: 0.1)
  expect(failures == 1 && controller.target != nil, "Failed movement reports error and never falls back to mouse")
  window.rect = nil
  send(.begin, 8, 5)
  expect(failures == 2, "Closed window reports failure")
  expect(!controller.select(window), "Cannot select closed window")
  expect(controller.select(nil) && controller.target == nil, "Clear unavailable target")
  // Holds are usable as audio control without posting mouse buttons; duplicate/late packets cannot renew them.
  window.rect = CGRect(x: 300, y: 200, width: 600, height: 400)
  window.writable = true
  expect(controller.select(window), "Select playback window")
  send(.begin, 20, 10)
  send(.hold, 20, 10.4)
  expect(holds.last == true, "Validated hold starts private playback")
  let count = holds.count
  controller.receive(ControlPacket(kind: .hold, session: 7, sequence: sequence, gesture: 20), screens: screens, at: 10.5)
  expect(holds.count == count, "Duplicate hold does not renew playback lease")
  send(.hold, 20, 10.6)
  expect(holds.count == count + 1 && holds.last == true, "Live touch renews playback")
  send(.end, 20, 10.7)
  expect(holds.last == false, "Lift pauses playback")
  send(.hold, 20, 10.8)
  expect(holds.last == false, "Late hold cannot restart ended gesture")
  send(.begin, 21, 11)
  send(.hold, 21, 11.4)
  controller.allowed = false
  expect(holds.last == false, "Suspend releases playback")
  controller.allowed = true
  send(.begin, 22, 12)
  send(.hold, 22, 12.4)
  _ = controller.select(nil)
  expect(holds.last == false, "Clearing target stops playback")
  window.isAssistant = true
  expect(controller.select(window), "Select Assistant")
  var selections: [Int] = []
  controller.onSentence = { selections.append($0) }
  let moveCount = window.moves.count
  send(.begin, 30, 13)
  send(.click, 30, 13.05)
  expect(selections.isEmpty, "Single waits for double tap decision")
  send(.begin, 31, 13.1)
  send(.click, 31, 13.15)
  expect(selections == [-1], "Double tap selects previous without advancing first")
  expect(window.moves.count == moveCount, "Assistant double tap never resets window")
  send(.begin, 32, 14)
  send(.sentence, 32, 14.01, y: 1)
  expect(selections == [-1, 1], "Crown down immediately selects next")
  controller.receive(ControlPacket(kind: .sentence, session: 7, sequence: sequence, gesture: 32, y: 1), screens: screens, at: 14.02)
  expect(selections == [-1, 1], "Duplicate crown event ignored")
  send(.end, 32, 14.03)
  send(.begin, 33, 14.1)
  send(.sentence, 33, 14.11, y: -1)
  send(.end, 33, 14.12)
  expect(selections == [-1, 1, -1], "Crown up selects previous")
  expect(window.moves.count == moveCount, "Crown never moves window")
  send(.begin, 35, 16)
  send(.click, 35, 16.01)
  try await Task.sleep(for: .seconds(NSEvent.doubleClickInterval + 0.15))
  expect(selections == [-1, 1, -1, 1], "Single tap selects next exactly once after decision interval")
  send(.begin, 36, 17)
  send(.click, 36, 17.01)
  controller.select(nil)
  try await Task.sleep(for: .seconds(NSEvent.doubleClickInterval + 0.15))
  expect(selections == [-1, 1, -1, 1], "Switching targets cancels pending single tap")
  controller.select(window)
  window.isAssistant = false
  send(.begin, 34, 15)
  send(.sentence, 34, 15.01, y: 1)
  send(.end, 34, 15.02)
  expect(selections == [-1, 1, -1, 1], "Other windows do not navigate audio")
  controller.stop()
}

@Test @MainActor func holdPlaybackNeverMovesFloatingAnswer() async throws {
  let controller = WindowController()
  defer { controller.stop() }
  let window = FakeWindow()
  window.isAssistant = true
  controller.allowed = true
  #expect(controller.select(window))
  let origin = window.rect?.origin
  var holds: [Bool] = []
  controller.onHold = { holds.append($0) }
  let screens = [CGRect(x: 0, y: 0, width: 1920, height: 1080)]
  var sequence: UInt32 = 0
  @MainActor func send(_ kind: ControlPacket.Kind, _ gesture: UInt16, _ time: Double, x: Float = 0) {
    sequence += 1
    controller.receive(ControlPacket(kind: kind, session: 8, sequence: sequence,
                                      gesture: gesture, x: x), screens: screens, at: time)
  }
  send(.begin, 1, 0)
  send(.hold, 1, 0.4, x: 0.02)
  #expect(holds.last == true)
  send(.hold, 1, 0.5, x: 0.2)
  send(.move, 1, 0.6, x: -0.1)
  // Let the real display link run: no smoothing frames may move the window either.
  try await Task.sleep(for: .milliseconds(80))
  #expect(window.moves.isEmpty)
  send(.end, 1, 0.7, x: 0.3)
  #expect(holds.last == false)
  #expect(window.moves.isEmpty)
  #expect(window.rect?.origin == origin)
  send(.begin, 2, 1)
  send(.move, 2, 1.1, x: 0.05)
  send(.end, 2, 1.2, x: 0.1)
  #expect(abs((window.rect?.minX ?? 0) - 390) < 0.001,
          "A fresh direct slide still moves from the unchanged position")
}
