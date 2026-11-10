import Foundation
import Testing
@testable import Cicada

struct InterviewStageTests {
    @Test func everyGenerationPathCarriesStage() {
        for stage in InterviewStage.allCases {
            let ordinary = CoachPrompt.request(turns: [], background: "", frames: [], audio: nil, stage: stage)
            let refresh = CoachPrompt.request(turns: [], background: "", frames: [], audio: nil, refresh: true, stage: stage)
            let review = CoachPrompt.reviewRequest(turns: [], background: "", frames: [], script: CoachScript(), stage: stage)
            for messages in [ordinary, refresh, review] {
                #expect((messages[0]["content"] as? String)?.contains(stage.instruction) == true)
            }
        }
    }
}

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["CICADA_TEST_STAGE"] == "1"))
struct InterviewStageModelTests {
    @Test @MainActor func stageAnswers() async throws {
        let client = LingClient()
        var results: [[String: Any]] = []
        let cases: [(InterviewStage, String)] = InterviewStage.allCases.map {
            ($0, "Tell me about your AI itinerary project and one decision you made.")
        } + [
            (.cto, "What latency would you aim for before showing the first useful itinerary content? Give a reasonable target."),
            (.ceo, "Why SSE instead of WebSockets? One simple sentence, please."),
            (.cto, "Exactly how much faster did the full itinerary finish in your project?")
        ]
        for (stage, question) in cases {
            let messages = CoachPrompt.request(
                turns: [CoachTurn(id: "q", seconds: 0, role: "interviewer", text: question)],
                background: "Synthetic ActAI Android interview. Ten years of Android and Flutter development. Built an AI itinerary feature in an Android app. Used SSE to display the first day before the full plan finished. No numeric measurement is included in this résumé excerpt.",
                frames: [], audio: nil, stage: stage)
            let started = Date()
            var answer = ""
            for try await piece in client.streamCoachTest(messages) { answer += piece }
            #expect(!answer.isEmpty)
            #expect(!answer.contains("[fill in:"))
            #expect(!answer.lowercased().contains("not a verified result"))
            results.append(["stage": stage.rawValue, "question": question, "answer": answer,
                            "seconds": Date().timeIntervalSince(started)])
            try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: "/tmp/cicada-stage-evaluation.json"))
        }
    }
}
