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

}
