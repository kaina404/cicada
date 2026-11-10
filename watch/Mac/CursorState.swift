import Foundation
import CoreGraphics

/// Pure state machine. Coordinates use Quartz's global, top-left coordinate system.
struct CursorState {
  enum Action: Equatable {
    case move(CGPoint, dragging: Bool)
    case down(CGPoint)
    case up(CGPoint)
    case click(CGPoint, count: Int)
  }
  static let lease: TimeInterval = 1.5
  var sensitivity: CGFloat = 1
  private(set) var isDown = false
  private(set) var inputRevision: UInt64 = 0
  private(set) var activeGesture: UInt16?
  private var session: UInt32?
  private var retiredSessions: Set<UInt32> = []
  private var sequence: UInt32 = 0
  private var translation = CGPoint.zero
  private var lastActivity: TimeInterval = 0
  private var lastClickTime: TimeInterval = -.infinity
  private var lastClickPoint = CGPoint.zero
  private var lastClickCount = 0

  mutating func receive(_ packet: ControlPacket, at time: TimeInterval,
                        cursor: CGPoint, screens: [CGRect], doubleClickInterval: TimeInterval = 0.5) -> [Action] {
    guard !retiredSessions.contains(packet.session) else { return [] }
    if session != packet.session {
      guard packet.kind == .begin else { return [] }
      if let session { retiredSessions.insert(session) }
      session = packet.session
      sequence = packet.sequence
    } else {
      // Serial-number arithmetic also handles UInt32 wraparound.
      let distance = packet.sequence &- sequence
      guard distance > 0, distance < 0x8000_0000 else { return [] }
      sequence = packet.sequence
    }
    if packet.kind == .begin {
      let actions = cancel(cursor: cursor)
      activeGesture = packet.gesture
      translation = .zero
      lastActivity = time
      return actions
    }
    guard activeGesture == packet.gesture else { return [] }
    // A delayed packet must not renew an expired press, even before the timer runs.
    guard time - lastActivity < Self.lease else { return cancel(cursor: cursor) }
    lastActivity = time
    inputRevision &+= 1
    if packet.kind == .cancel { return cancel(cursor: cursor) }
    if packet.kind == .sentence { return [] } // Crown selection never moves the pointer or window.
    let next = CGPoint(x: CGFloat(packet.x), y: CGFloat(packet.y))
    let proposed = CGPoint(x: cursor.x + (next.x - translation.x) * 900 * sensitivity,
                           y: cursor.y + (next.y - translation.y) * 900 * sensitivity)
    translation = next
    let point = Self.clamp(proposed, to: screens)
    var actions: [Action] = []
    if point != cursor { actions.append(.move(point, dragging: isDown)) }
    switch packet.kind {
    case .hold:
      if !isDown {
        isDown = true
        lastClickCount = 0
        actions.append(.down(point))
      }
    case .end:
      actions += cancel(cursor: point)
    case .click:
      guard !isDown else { return actions + cancel(cursor: point) }
      let nearby = hypot(point.x - lastClickPoint.x, point.y - lastClickPoint.y) < 6
      lastClickCount = nearby && time - lastClickTime <= doubleClickInterval ? lastClickCount + 1 : 1
      lastClickTime = time
      lastClickPoint = point
      actions.append(.click(point, count: lastClickCount))
      activeGesture = nil
    default: break
    }
    return actions
  }

  mutating func expire(at time: TimeInterval, cursor: CGPoint) -> [Action] {
    guard activeGesture != nil, time - lastActivity >= Self.lease else { return [] }
    return cancel(cursor: cursor)
  }

  mutating func cancel(cursor: CGPoint) -> [Action] {
    let actions: [Action] = isDown ? [.up(cursor)] : []
    isDown = false
    activeGesture = nil
    translation = .zero
    return actions
  }

  static func clamp(_ point: CGPoint, to screens: [CGRect]) -> CGPoint {
    // Project into a real display, rather than the bounding box's empty gaps.
    screens.map { rect in
      CGPoint(x: min(max(point.x, rect.minX), rect.maxX - 1),
              y: min(max(point.y, rect.minY), rect.maxY - 1))
    }.min { hypot($0.x - point.x, $0.y - point.y) < hypot($1.x - point.x, $1.y - point.y) } ?? point
  }
}
