import AVFoundation
import Foundation
import Testing
@testable import Cicada

private final class BuildCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

private func flushAudioLane() async {
    await withCheckedContinuation { continuation in
        AudioLifecycle.queue.async { continuation.resume() }
    }
}

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

    @Test func meetingLeasePreventsRebuildingAfterEveryPress() async {
        let builds = BuildCounter()
        let mic = VoiceMic(currentOutput: { 2 }, createUnit: { _, _ in builds.increment(); return nil })
        let room = UUID()
        await withCheckedContinuation { continuation in
            mic.acquirePlainInput(room) { ready in
                #expect(ready)
                continuation.resume()
            }
        }
        for _ in 0..<5 {
            let press = UUID()
            await withCheckedContinuation { continuation in
                mic.acquirePlainInput(press) { ready in
                    #expect(ready)
                    continuation.resume()
                }
            }
            mic.endPlainInput(press)
            mic.prepare(input: 1) { ready in #expect(!ready) }
            await flushAudioLane()
            #expect(builds.value == 0)
        }
        #expect(await mic.beginRawRecording() == false)
        mic.endPlainInput(room)
        await flushAudioLane()
        await flushAudioLane() // The final release queues the one deferred prepare.
        #expect(builds.value == 1)
    }

    @Test func reservationArrivingDuringBuildWaitsWithoutBlockingMain() async {
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let builds = BuildCounter()
        let mic = VoiceMic(currentOutput: { 2 }, createUnit: { _, _ in
            builds.increment()
            entered.signal()
            if builds.value == 1 { _ = release.wait(timeout: .now() + 3) }
            return nil
        })
        mic.prepare(input: 1)
        let began = await withCheckedContinuation { continuation in
            DispatchQueue.global().async { continuation.resume(returning: entered.wait(timeout: .now() + 3) == .success) }
        }
        #expect(began)
        let room = UUID()
        let ready = Task {
            await withCheckedContinuation { continuation in
                mic.acquirePlainInput(room) { continuation.resume(returning: $0) }
                release.signal()
            }
        }
        #expect(await ready.value)
        // A build finishing late cannot open VoiceProcessingIO over the reserved plain input.
        mic.prepare(input: 1) { #expect(!$0) }
        #expect(builds.value == 1)
        mic.endPlainInput(room)
        await flushAudioLane()
        await flushAudioLane()
    }

    @Test func exclusiveSampleLeaseRejectsMeetingAndAllowsReacquisitionAfterStop() async {
        let mic = VoiceMic(currentOutput: { nil })
        #expect(await mic.beginRawRecording())
        #expect(await mic.beginRawRecording() == false)
        let accepted = await withCheckedContinuation { continuation in
            mic.acquirePlainInput(UUID()) { continuation.resume(returning: $0) }
        }
        #expect(!accepted)
        mic.endRawRecording()
        await flushAudioLane()
        #expect(await mic.beginRawRecording())
        mic.endRawRecording()
        await flushAudioLane()
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

    @MainActor @Test func playbackTimeoutDoesNotDependOnHardwareLaneOrMainLoopTimers() async throws {
        let release = DispatchSemaphore(value: 0)
        AudioLifecycle.queue.async { _ = release.wait(timeout: .now() + 3) }
        defer { release.signal() }
        let output = SpeechOutput(operationTimeout: 0.03)
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24_000, channels: 1, interleaved: false))
        let tail = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 240))
        tail.frameLength = 240
        #expect(await output.prepare(format: format, device: nil) == false)
        #expect(await output.drain(tail, limit: 0.03) == false)
        // Neither timed-out operation may start hardware or play a stale buffer when unblocked.
        release.signal()
        await flushAudioLane()
    }

}
