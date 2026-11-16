import AppKit
import Foundation
import Testing
@testable import Cicada

/// Real cloud calls with synthetic evidence only. Never enabled by the normal test run.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["CICADA_TEST_DEEPSEEK"] == "1"))
struct CoachDeepSeekModelTests {
    @Test @MainActor func framedWeaknessAnswerThroughRealProvider() async throws {
        try #require(CoachDeepSeekTest.enabled)
        let coach = InterviewCoach(readingInfer: { _ in "" })
        coach.stage = .hr
        coach.gloss.enabled = false
        coach.start(background: "Synthetic ActAI Android interview. My weakness is expanding code scope too early. I now agree the scope before coding.", available: true, prepare: { true })
        defer { coach.endMeeting() }
        coach.observe(lines: [TranscriptLine(id: "q", t: 0, speaker: "them",
            src: "What is one weakness you are currently working on?", srcLang: "en", dstLang: "")], now: 0)
        coach.ask()
        let deadline = Date().addingTimeInterval(60)
        while (coach.state == .loading || coach.state == .generating), Date() < deadline {
            #expect(!coach.script.pending.contains("CICADA_ANSWER"))
            #expect(!coach.script.pending.contains("confidence"))
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(coach.state == .ready)
        let answer = try #require(coach.paragraphs.last?.output.next)
        #expect(!answer.isEmpty)
        #expect(!answer.contains("decision"))
        #expect(!answer.contains("0.95"))
        try Data(answer.utf8).write(to: URL(fileURLWithPath: "/tmp/cicada-framed-weakness-answer.txt"))
    }

    @Test @MainActor func degradedRecognitionResolvesIntentWithRealProvider() async throws {
        let cloud = LingClient()
        let background = "Synthetic interview: the candidate's weakness is expanding code scope too early, improved by agreeing limits before implementation. Their current project is a personal assistant app named CabinetAI."
        let cases: [(String, String, String)] = [
            ("What's one weakness you're currently working on?", "you'… you're currently working on?", "weakness"),
            ("What is one failure you learned from?", "you learned from?", "failure"),
            ("What is your weakness?", "Actually, don't discuss weakness. Tell me about your current project.", "CabinetAI"),
            ("Could you tell me about the...", "the...", "?")
        ]
        var reports: [[String: String]] = []
        for (earlier, latest, expected) in cases {
            var script = CoachScript(modelReading: true)
            script.replacePending("My strength is being proactive.", since: [])
            let turn = CoachTurn(id: "q", seconds: 1, role: "interviewer", text: latest,
                                 recognitionAlternatives: [earlier])
            let messages = CoachPrompt.reviewRequest(turns: [turn], background: background,
                                                    frames: [], script: script, stage: .general)
            var raw = ""
            for try await chunk in cloud.streamCoachTest(messages) { raw += chunk }
            reports.append(["earlier": earlier, "latest": latest, "response": raw])
            try JSONSerialization.data(withJSONObject: reports, options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: "/tmp/cicada-recognition-provider-results.json"))
            let result = try #require(try CoachReviewResponse.parse(raw, finished: true))
            #expect(result.decision.action == .replace)
            #expect(result.answer.localizedCaseInsensitiveContains(expected))
            if expected == "weakness" {
                let opening = CoachScript.sentences(result.answer).first ?? ""
                #expect(opening.localizedCaseInsensitiveContains("weakness"))
                #expect(!opening.contains("building CabinetAI"))
            }
        }
        try JSONSerialization.data(withJSONObject: reports, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: "/tmp/cicada-recognition-provider-results.json"))
    }

    @Test @MainActor func firstVisibleTokenThroughCoach() async throws {
        try #require(CoachDeepSeekTest.enabled)
        let image = NSImage(size: NSSize(width: 1600, height: 900))
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1600, height: 900)).fill()
        for (i, row) in ["ActAI Android Practice", "Offline queue -> Room -> WorkManager", "Stable client ID -> server deduplication", "Retry after process death"].enumerated() {
            (row as NSString).draw(at: NSPoint(x: 80, y: 740 - i * 140), withAttributes: [.font: NSFont.systemFont(ofSize: 42), .foregroundColor: NSColor.black])
        }
        image.unlockFocus()
        let cg = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let jpeg = try #require(RealtimeMedia.jpeg(cg))
        try jpeg.write(to: URL(fileURLWithPath: "/tmp/cicada-deepseek-slide.jpg"))
        var reports: [[String: Any]] = []
        for index in 0..<6 {
            let coach = InterviewCoach(readingInfer: { _ in "" })
            coach.start(background: "Synthetic ActAI Android interview. Candidate has ten years of Android and Flutter experience. Discuss reliable offline chat; do not invent employment achievements.", available: true, prepare: { true })
            var lines: [TranscriptLine] = []
            if index >= 3 {
                for turn in 0..<30 {
                    lines.append(TranscriptLine(id: "history\(turn)", t: Double(turn), speaker: turn.isMultiple(of: 2) ? "them" : "me", src: String(repeating: "We discussed Android offline chat, persisted queue state, stable client IDs, retry backoff, WorkManager constraints and server acknowledgement. ", count: 4), srcLang: "en", dstLang: ""))
                }
            }
            for frame in 0..<3 { coach.picture(CoachFrame(jpeg: jpeg, seconds: Double(frame), ocr: "Room -> WorkManager -> server deduplication")) }
            lines.append(TranscriptLine(id: "question", t: 40, speaker: "them", src: "How would you resume offline message retries after Android kills the process, without sending duplicates? Use the diagram on the screen.", srcLang: "en", dstLang: ""))
            coach.observe(lines: lines, now: 40)
            coach.ask()
            let deadline = Date().addingTimeInterval(60)
            while (coach.state == .loading || coach.state == .generating), Date() < deadline {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            #expect(coach.state == .ready)
            let answer = coach.paragraphs.last?.output.next ?? ""
            #expect(!answer.isEmpty)
            reports.append(["case": index < 3 ? "short_3screens" : "long_3screens", "first_token": coach.firstLatency ?? -1,
                            "first_sentence": coach.firstSentenceLatency ?? -1, "answer": answer])
            coach.stop()
            try JSONSerialization.data(withJSONObject: reports, options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: "/tmp/cicada-deepseek-coach-results.json"))
        }
    }
}
