import Foundation

/// When to ask for the next card (docs/walkthrough-coach-plan.md §5). One request at a time.
/// Only a complete interviewer turn or a manual action cancels a running request: the candidate's
/// own speech and typing never do, so steady input cannot starve the answer (requirements §6, AC-15).
struct CoachCardSchedule: Equatable {
    enum Trigger: Int, Comparable {
        case board = 1, check, manual, interviewer
        static func < (a: Trigger, b: Trigger) -> Bool { a.rawValue < b.rawValue }
        var cancelsRunning: Bool { self >= .manual }
    }
    enum Action: Equatable { case none, start(Trigger), restart(Trigger) }

    /// A board change only asks again this long after the last board-triggered request.
    static let boardInterval = 5.0

    private(set) var running: Trigger?
    private(set) var queued: Trigger?
    private var lastBoardStart = -Double.infinity

    mutating func receive(_ trigger: Trigger, now: Double) -> Action {
        if trigger == .board, now - lastBoardStart < Self.boardInterval {
            // Too soon: remember it, so the change is still read once the interval passes (see tick).
            queued = max(queued ?? trigger, trigger)
            return .none
        }
        guard running != nil else { return start(trigger, now: now) }
        if trigger.cancelsRunning {
            queued = nil; running = trigger
            return .restart(trigger)
        }
        // Merge: one follow-up request reads everything that arrived meanwhile.
        queued = max(queued ?? trigger, trigger)
        return .none
    }

    /// The running request ended (applied, kept, failed or discarded as stale).
    mutating func finished(now: Double) -> Action {
        running = nil
        guard let next = queued else { return .none }
        queued = nil
        if next == .board, now - lastBoardStart < Self.boardInterval { queued = next; return .none }
        return start(next, now: now)
    }

    /// Called on the tick so a throttled board change is not forgotten.
    mutating func tick(now: Double) -> Action {
        guard running == nil, queued != nil else { return .none }
        return finished(now: now)
    }

    private mutating func start(_ trigger: Trigger, now: Double) -> Action {
        running = trigger
        if trigger == .board { lastBoardStart = now }
        return .start(trigger)
    }
}
