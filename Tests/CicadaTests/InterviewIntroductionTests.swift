import Foundation
import Testing
@testable import Cicada

struct InterviewIntroductionTests {
    @Test func approvedOpeningSurvivesAllPromptPathsAndLongBackground() {
        let turns = [CoachTurn(id: "q", seconds: 0, role: "interviewer", text: "Could you introduce yourself?")]
        for stage in InterviewStage.allCases {
            let background = String(repeating: "Unrelated résumé detail. ", count: 2000)
            let ordinary = CoachPrompt.request(turns: turns, background: background, frames: [], audio: nil, stage: stage)
            let refresh = CoachPrompt.request(turns: turns, background: background, frames: [], audio: nil, refresh: true, stage: stage)
            let review = CoachPrompt.reviewRequest(turns: turns, background: background, frames: [], script: CoachScript(), stage: stage)
            for messages in [ordinary, refresh, review] {
                let system = messages[0]["content"] as? String ?? ""
                #expect(system.contains(InterviewIntroduction.text))
                #expect(system.contains(InterviewIntroduction.followUpReference))
                #expect(system.contains("VERBATIM"))
                #expect(system.contains("suggested or unread script is not actual speech"))
                #expect(system.contains("For later project questions"))
            }
        }
        #expect(InterviewIntroduction.text.components(separatedBy: "\n\n").count == 5)
    }
}

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["CICADA_TEST_INTRO"] == "1"))
struct InterviewIntroductionModelTests {
    @Test @MainActor func openingAndFollowUp() async throws {
        let client = LingClient()
        var results: [[String: String]] = []
        for (question, exact) in [
            ("Could you introduce yourself?", true),
            ("Tell me about yourself in one simple sentence.", false),
            ("Why did you choose SSE for the itinerary UI? One sentence, please.", false),
            ("How did you reduce SKU response time, and what exactly did you measure? Keep it under 70 words.", false),
            ("Was your 300 ms SKU result P50 or P90, and how much of it was network time? Keep it short.", false),
            ("At Debon you reduced crashes by 90%, right? Correct me briefly.", false),
            ("What exact Redis profile pipeline and A/B GMV evaluation did you personally implement at KKday? Keep it short.", false),
            ("How would you design caching for changing prices and stock? One sentence, please.", false)
        ] {
            let messages = CoachPrompt.request(turns: [CoachTurn(id: "q", seconds: 0, role: "interviewer", text: question)],
                                               background: "Used SSE for streaming itinerary updates.", frames: [], audio: nil, stage: .cto)
            var answer = ""
            for try await piece in client.streamCoachTest(messages) { answer += piece }
            answer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
            results.append(["question": question, "answer": answer])
            try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: "/tmp/cicada-introduction-evaluation.json"))
            if exact { #expect(answer == InterviewIntroduction.text) }
            else {
                #expect(!answer.isEmpty)
                #expect(CoachScript.words(answer).count < 80)
                #expect(answer != InterviewIntroduction.text)
            }
        }
    }
}
