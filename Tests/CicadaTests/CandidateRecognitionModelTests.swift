import AVFoundation
import Foundation
import Testing
@testable import Cicada

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["CICADA_TEST_CANDIDATE_ASR"] == "1"))
struct CandidateRecognitionModelTests {
    @Test @MainActor func localGemmaCandidateStream() async throws {
        try #require(await VisionServer.waitReady(seconds: 3))
        var report: [[String: Any]] = []
        let expected = Set(CoachScript.words("I would keep Room as the single source of truth. Each message gets a stable client ID, so retries do not send it twice."))
        for name in ["standard", "accented", "misread", "repeated", "unrelated", "silence"] {
            let samples = try #require(Voiceprints.samples(of: URL(fileURLWithPath: "/tmp/cicada-reading-\(name).wav")))
            let stream = CandidateRecognition()
            let began = Date()
            var finals: [String] = []
            let collect = Task { @MainActor in
                for try await piece in stream.results where piece.isFinal { finals.append(piece.text) }
            }
            for start in stride(from: 0, to: samples.count, by: 1600) {
                let chunk = Array(samples[start..<min(samples.count, start + 1600)])
                let buffer = try #require(AVAudioPCMBuffer(pcmFormat: stream.format, frameCapacity: AVAudioFrameCount(chunk.count)))
                buffer.frameLength = AVAudioFrameCount(chunk.count)
                chunk.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: chunk.count) }
                stream.append(buffer)
            }
            await stream.finish()
            try await collect.value
            let text = finals.joined(separator: " ")
            let reference: Set<String>
            switch name {
            case "misread", "repeated": reference = Set(CoachScript.words("I would keep room as the single source of truth"))
            case "unrelated": reference = Set(CoachScript.words("Can you hear me I need a glass of water"))
            default: reference = expected
            }
            let recall = Double(Set(CoachScript.words(text)).intersection(reference).count) / Double(reference.count)
            report.append(["sample": name, "syntheticOnly": true, "finals": finals,
                           "expectedWordRecall": recall, "seconds": Date().timeIntervalSince(began)])
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: "/tmp/cicada-candidate-asr-evaluation.json"))
            if name == "silence" { #expect(finals.isEmpty) }
            else { #expect(recall >= 0.65, "\(name): \(text)") }
        }
    }
}
