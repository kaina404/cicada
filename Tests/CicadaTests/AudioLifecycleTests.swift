import AVFoundation
import Foundation
import Testing
@testable import Cicada
@Suite(.serialized) struct AudioLifecycleTests {
    @Test func latestDeviceEventWinsAndStopInvalidatesPendingRestart() {
        var revision = AudioRevision()
        let first = revision.advance()
        let second = revision.advance()
        #expect(!revision.accepts(first))
        #expect(revision.accepts(second))
        revision.advance() // Stop, followed by a new session.
        #expect(!revision.accepts(second))
        let nextSession = revision.advance()
        #expect(revision.accepts(nextSession))
        #expect(!revision.accepts(first))
    }

    @MainActor @Test func restartBurstCoalescesAndCancelledSessionCannotRestart() async throws {
        let reconnect = AudioReconnect()
        var calls: [Int] = []
        for n in 0..<20 { reconnect.schedule(after: 0.02) { calls.append(n) } }
        try await Task.sleep(for: .milliseconds(100))
        #expect(calls == [19])
        reconnect.schedule(after: 0.02) { calls.append(100) }
        reconnect.cancel()
        reconnect.schedule(after: 0.02) { calls.append(200) }
        try await Task.sleep(for: .milliseconds(100))
        #expect(calls == [19, 200])
    }

}
