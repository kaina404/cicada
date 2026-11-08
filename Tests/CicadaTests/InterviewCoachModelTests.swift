import AppKit
import Foundation
import Testing
@testable import Cicada

/// Synthetic evidence only. Opt in with CICADA_TEST_COACH=1; uses the installed local model.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["CICADA_TEST_COACH"] == "1"))
struct InterviewCoachModelTests {
    @Test @MainActor func originalAudioImageAndCandidateProgress() async throws {
        let server = VisionServer()
        if !(await VisionServer.waitReady(seconds: 0)) { server.start(model: CoachPrompt.model) }
        defer { server.stop() }
        let ready = await VisionServer.waitReady(seconds: 90)
        try #require(ready)
        let image = NSImage(size: NSSize(width: 1600, height: 900))
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1600, height: 900)).fill()
        for (i, row) in ["ActAI Android Practice", "First visible token target: 850 ms", "Offline queue -> Room", "Stable client ID"].enumerated() {
            (row as NSString).draw(at: NSPoint(x: 100, y: 740 - i * 130), withAttributes: [.font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black])
        }
        image.unlockFocus()
        let cg = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let jpeg = try #require(RealtimeMedia.jpeg(cg))
        try jpeg.write(to: URL(fileURLWithPath: "/tmp/cicada-coach-slide.jpg"))
        let samples = try #require(Voiceprints.samples(of: URL(fileURLWithPath: "/tmp/cicada-coach-question.aiff")))
        var audio = CoachAudioBuffer()
        audio.append(RealtimeMedia.pcm(samples), endingAt: 20)
        var turns = [CoachTurn(id: "q", seconds: 20, role: "interviewer", text: "How would you keep messages reliable offline, and what is the first visible token target on the slide?")]
        var reports: [[String: Any]] = []
        for index in 0..<3 {
            if index == 1 {
                turns.append(CoachTurn(id: "a", seconds: 30, role: "candidate", text: "I persist pending messages in Room with a stable client ID."))
            }
            let messages = CoachPrompt.request(turns: index == 2 ? [] : turns, background: "This is a synthetic Android interview. Do not invent work experience.", frames: [CoachFrame(jpeg: jpeg, seconds: 18, ocr: "First visible token target: 850 ms")], audio: audio, committed: index == 1 ? (turns.last?.text ?? "") : "")
            let start = Date()
            var first: Double?
            var result = ""
            var firstSentence: Double?
            for try await piece in InterviewCoach.stream(messages, CoachPrompt.model) {
                if first == nil { first = Date().timeIntervalSince(start) }
                result += piece
                if firstSentence == nil, let sentence = CoachScript.sentences(result).first,
                   sentence.hasSuffix(".") || sentence.hasSuffix("?") || sentence.hasSuffix("!") {
                    firstSentence = Date().timeIntervalSince(start)
                }
            }
            let output = CoachOutput(result)
            reports.append(["candidateAnswered": index == 1, "audioWithoutASR": index == 2, "first": first ?? -1, "firstSentence": firstSentence ?? -1, "total": Date().timeIntervalSince(start), "output": result])
            try JSONSerialization.data(withJSONObject: reports, options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: "/tmp/cicada-interview-coach-benchmark.json"))
            #expect(!output.next.isEmpty)
            #expect(result.contains("850"))
            #expect(CoachScript.words(output.next).count >= 80)
            #expect(!output.next.hasPrefix("Question:"))
            #expect(!output.next.hasPrefix("Next:"))
            if index == 2 { #expect(result.lowercased().contains("offline")) }
        }
    }
}
