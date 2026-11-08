import AppKit
import Foundation
import Testing
@testable import Cicada

/// Opt-in local-model probe: CICADA_TEST_ASK=1 scripts/test.sh --filter AskModelTests.
/// No downloads or cloud requests. Keep the dev app listening during latency measurements.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["CICADA_TEST_ASK"] == "1"))
struct AskModelTests {
    @Test @MainActor func localTableAndLongContext() async throws {
        let image = NSImage(size: NSSize(width: 1600, height: 900))
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1600, height: 900)).fill()
        let rows = ["ActAI Android Practice Interview", "Metric                  Target", "First visible token      850 ms", "Streaming API            REST", "On-device model          TensorFlow Lite"]
        for (i, row) in rows.enumerated() {
            (row as NSString).draw(at: NSPoint(x: 120, y: 740 - i * 110), withAttributes: [.font: NSFont.systemFont(ofSize: 42), .foregroundColor: NSColor.black])
        }
        image.unlockFocus()
        let cg = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let ocr = ScreenWatch.recognizeText(cg)
        #expect(ocr.contains("850 ms"))
        let screen = TranscriptLine(id: "s", t: 299, speaker: "screen", src: "原文：" + ocr.replacingOccurrences(of: "\n", with: " / "), srcLang: "", dstLang: "")
        let fact = TranscriptLine(id: "fact", t: 60, speaker: "me", src: "In this practice interview, the target for first visible token is 850 ms. This is not a measured result.", srcLang: "en", dstLang: "")
        let model = ProcessInfo.processInfo.environment["CICADA_ASK_MODEL"] ?? AppSettings().screenModel
        let requestedSizes = ProcessInfo.processInfo.environment["CICADA_ASK_SIZES"] ?? "1280"
        var reports: [[String: Any]] = []
        for side in [0] + requestedSizes.split(separator: ",").compactMap({ Int($0) }) {
            var firsts: [Double] = []
            for i in 0..<5 {
                let small = side == 0 ? nil : ScreenWatch.scaled(cg, longSide: side)
                let attached = small.flatMap { small in ScreenWatch.jpeg(small, longSide: side).map { AskPrompt.Image(jpeg: $0, width: small.width, height: small.height, capturedAt: Date()) } }
                let q = TranscriptLine(id: "q", t: 300, speaker: "them", src: side == 0 ? "What first visible token target did we agree in this practice interview?" : "What is the first visible token target on the interview slide? Copy the exact value.", srcLang: "en", dstLang: "")
                let request = AskPrompt.request(lines: [fact, screen, q], now: 300, partial: "", image: attached)
                let start = Date()
                var first: Double?
                var answer = ""
                for try await piece in AskEngine.stream(request, model: model) {
                    if first == nil { first = Date().timeIntervalSince(start) }
                    answer += piece
                }
                let latency = try #require(first)
                firsts.append(latency)
                reports.append(["side": side, "run": i + 1, "first": latency, "total": Date().timeIntervalSince(start), "ctx": request.user.count, "answer": answer])
                #expect(answer.contains(side == 0 ? "850 ms" : "850 ms"))
            }
            print("ask benchmark image=\(side) median=\(firsts.sorted()[2])s")
        }
        let noise = TranscriptLine(id: "noise", t: 150, speaker: "me", src: String(repeating: "The Android interviewer is discussing Kotlin coroutine cancellation, streaming chat, and offline messages. ", count: 30), srcLang: "en", dstLang: "")
        let question = TranscriptLine(id: "long-q", t: 300, speaker: "them", src: "What first visible token target did we agree in this practice interview?", srcLang: "en", dstLang: "")
        let long = AskPrompt.request(lines: [fact, noise, screen, question], now: 300, partial: "")
        var longAnswer = ""
        for try await piece in AskEngine.stream(long, model: model) { longAnswer += piece }
        #expect(longAnswer.contains("850 ms"))
        #expect(!longAnswer.lowercased().contains("you could"))
        reports.append(["scenario": "long background", "ctx": long.user.count, "answer": longAnswer])
        let data = try JSONSerialization.data(withJSONObject: reports, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: "/tmp/cicada-ask-benchmark.json"))
        try ScreenWatch.jpeg(cg, longSide: 1600)?.write(to: URL(fileURLWithPath: "/tmp/cicada-ask-table.jpg"))
    }
}
