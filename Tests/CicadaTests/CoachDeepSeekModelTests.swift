import AppKit
import Foundation
import Testing
@testable import Cicada

/// Real cloud calls with synthetic evidence only. Never enabled by the normal test run.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["CICADA_TEST_DEEPSEEK"] == "1"))
struct CoachDeepSeekModelTests {
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
