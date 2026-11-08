import Foundation
import Testing
@testable import Cicada

/// Synthetic local-model checks; prepare the /tmp WAV files with tools/coach-reading-fixtures.py.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["CICADA_TEST_READING"] == "1"))
struct CoachReadingModelTests {
    @Test @MainActor func photoSentenceAfterSkippedWords() async throws {
        try #require(await VisionServer.waitReady(seconds: 3))
        let answer = "The feed screen would fetch a list of posts, and when a user clicks on a post, the app would navigate to the detail screen to show the full content and the comments. A key consideration here is the scalability /ˌskeɪləˈbɪləti/ of the feed. Since the feed needs to be personalized and dynamic, we would need a robust mechanism for ranking and serving posts."
        var report: [[String: Any]] = []
        for name in ["photo", "photo-accented"] {
            let samples = try #require(Voiceprints.samples(of: URL(fileURLWithPath: "/tmp/cicada-reading-\(name).wav")))
            var script = CoachScript(modelReading: true)
            script.replacePending(answer, since: [], newAnswer: true)
            script.advanceReading(to: 11, answerID: script.answerID)
            var replies: [String] = []
            let reader = CoachReading { messages in
                let result = try await CoachReading.infer(messages)
                replies.append(result); return result
            }
            reader.onProgress = { id, through, _ in script.advanceReading(to: through, answerID: id) }
            reader.begin(answerID: script.answerID)
            reader.append(RealtimeMedia.pcm(samples), voiced: true, now: 10)
            let start = Date()
            reader.tick(script: script, blocked: false, now: 10)
            while reader.busy, Date().timeIntervalSince(start) < 65 {
                try await Task.sleep(for: .milliseconds(30))
            }
            report.append(["sample": name, "syntheticOnly": true, "cursorBefore": 11,
                           "cursorAfter": script.cursor, "sentenceAfter": script.currentSentence,
                           "seconds": Date().timeIntervalSince(start), "replies": replies])
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: "/tmp/cicada-reading-photo-evaluation.json"))
            #expect(script.currentSentence == 1, "\(name): \(replies)")
            #expect(script.pending == answer)
            #expect(script.committed.isEmpty)
            reader.stop()
        }
    }

    @Test @MainActor func accentedPartialRepeatedAndUnrelatedSpeech() async throws {
        let ready = await VisionServer.waitReady(seconds: 3)
        try #require(ready)
        let answer = "I would keep Room as the single source of truth. Each message gets a stable client ID, so retries do not send it twice. Then I would add exponential backoff and a maximum retry count."
        let cases: [(String, Int, ClosedRange<Int>)] = [
            ("standard", 0, 24...24), ("accented", 0, 24...24),
            ("misread", 0, 9...10), ("repeated", 10, 10...10),
            ("later", 10, 24...24), ("unrelated", 0, 0...0),
            ("silence", 0, 0...0), ("tone", 0, 0...0)
        ]
        var report: [[String: Any]] = []
        for (name, cursor, expected) in cases {
            let file = URL(fileURLWithPath: "/tmp/cicada-reading-\(name).wav")
            let samples = try #require(Voiceprints.samples(of: file))
            let audio = RealtimeMedia.pcm(samples)
            let voiced = samples.reduce(Float(0)) { $0 + $1 * $1 } / Float(max(1, samples.count)) > 0.000025
            var script = CoachScript(modelReading: true)
            script.replacePending(answer, since: [], newAnswer: true)
            script.advanceReading(to: cursor, answerID: script.answerID)
            var replies: [String] = []
            var failed = false
            let start = Date()
            let reader = CoachReading { messages in
                let result = try await CoachReading.infer(messages)
                replies.append(result)
                return result
            }
            reader.onProgress = { id, through, _ in script.advanceReading(to: through, answerID: id) }
            reader.onFailure = { failed = $0 }
            reader.begin(answerID: script.answerID)
            reader.append(audio, voiced: voiced, now: 10)
            reader.tick(script: script, blocked: false, now: 10)
            while reader.busy, Date().timeIntervalSince(start) < 65 {
                try await Task.sleep(for: .milliseconds(30))
            }
            report.append(["sample": name, "syntheticOnly": true, "cursorBefore": cursor,
                "cursorAfter": script.cursor, "expectedMin": expected.lowerBound, "expectedMax": expected.upperBound,
                "seconds": Date().timeIntervalSince(start), "replies": replies, "failed": failed])
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: "/tmp/cicada-gemma-reading-evaluation.json"))
            #expect(!failed, "\(name): local inference failed")
            #expect(expected.contains(script.cursor), "\(name): cursor \(script.cursor), replies \(replies)")
            #expect(script.pending == answer)
            #expect(script.committed.isEmpty)
            if name == "silence" { #expect(replies.isEmpty) }
            reader.stop()
        }
    }
}
