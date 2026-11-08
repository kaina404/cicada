import Foundation
import Testing
@testable import Cicada

@Suite struct VoiceRecordingTests {
    @Test func captureDistinguishesMissingFramesSilenceAndSound() {
        let capture = VoiceRecordingCapture()
        #expect(capture.snapshot.frames == 0)
        capture.append(frames: 16000, peak: 0)
        #expect(capture.snapshot.frames == 16000)
        #expect(capture.snapshot.peak == 0)
        capture.append(frames: 8000, peak: 0.2)
        capture.append(frames: 8000, peak: 0.001)
        #expect(capture.snapshot.frames == 32000)
        #expect(capture.snapshot.peak == 0.2)
        #expect(capture.snapshot.currentPeak == 0.001)
        capture.failed()
        #expect(capture.snapshot.writeFailed)
        capture.reset()
        #expect(capture.snapshot.frames == 0)
        #expect(!capture.snapshot.writeFailed)
    }

    @Test func rawRecordingExcludesOtherReservationsAndEchoPreparation() async {
        let mic = VoiceMic()
        #expect(await mic.beginRawRecording())
        #expect(await mic.beginRawRecording() == false)
        // While reserved, prepare must finish immediately without constructing a starving unit.
        var ready: Bool?
        mic.prepare(input: 0) { ready = $0 }
        #expect(ready == false)
        // Do not restore an invalid input in this device-free test.
        // A fresh mic tests release/reacquire without a pending prepare request.
        let other = VoiceMic()
        #expect(await other.beginRawRecording())
        other.endRawRecording()
        await withCheckedContinuation { continuation in
            AudioLifecycle.queue.async { continuation.resume() }
        }
        #expect(await other.beginRawRecording())
        other.endRawRecording()
    }
}
