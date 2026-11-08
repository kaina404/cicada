import Foundation
import Testing
@testable import Cicada

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["CICADA_TEST_COACH_REVIEW"] == "1"))
struct CoachReviewModelTests {
    @Test @MainActor func decisionsUseCoverageRatherThanAcknowledgementKeywords() async throws {
        try #require(CoachDeepSeekTest.enabled)
        try #require(AIKey.read("deepseek") != nil, "Configure the DeepSeek key before this opt-in cloud evaluation")
        let client = LingClient()
        let original = "I would use Room as the local source of truth. I save each outgoing message with a stable client ID and a pending status before making a network request. The UI observes the Room database through Flow. WorkManager retries pending messages after a reconnect or process restart. The server deduplicates retries by client ID, so an interrupted request does not create duplicate messages. I apply exponential backoff with a bounded retry count and show failed messages so the user can retry them."
        var script = CoachScript(modelReading: true)
        script.replacePending(original, since: [])
        let fixtures: [(String, CoachReviewDecision.Action)] = [
            ("OK, all right, continue.", .keep),
            ("Lovely, by all means carry on with your reasoning.", .keep),
            ("That's precisely the direction I was hoping for. The floor is yours.", .keep),
            ("很好，我们继续聊。", .keep),
            ("So how do you resume sending after the Android process restarts?", .keep),
            ("Can you also explain how you prevent duplicates on retry?", .keep),
            ("By offline sending I mean save locally and retry when connected again.", .keep),
            ("Actually, assume persistent storage and WorkManager are prohibited.", .replace),
            ("Now switch topics. Explain Kotlin coroutine failure isolation with SupervisorJob.", .replace),
            ("Instead of offline sending, please design end-to-end encryption and key rotation.", .replace),
            ("We need to resolve concurrent edits on multiple devices. Explain conflict resolution.", .replace),
            ("So how do you resume sending after the Android process restarts?", .replace),
            ("Can you also explain how you prevent duplicates on retry?", .replace)
        ]
        var reports: [[String: Any]] = []
        for (index, fixture) in fixtures.enumerated() {
            if index >= 11 {
                script.replacePending("I keep messages in memory and send each request once.", since: [], newAnswer: true)
            }
            let turns = [CoachTurn(id: "q", seconds: 0, role: "interviewer", text: "For this ActAI Android interview, how would you implement reliable offline message sending?"),
                         CoachTurn(id: "follow", seconds: 3, role: "interviewer", text: fixture.0)]
            let start = Date()
            var raw = ""
            for try await delta in client.streamCoachTest(CoachPrompt.reviewRequest(turns: turns, background: "Synthetic ActAI Android practice, not company implementation facts.", frames: [], script: script)) {
                raw += delta
            }
            let update = try? CoachReviewResponse.parse(raw, finished: true)
            let decision = update?.decision
            reports.append(["input": fixture.0, "expected": fixture.1.rawValue, "actual": decision?.action.rawValue ?? "invalid",
                            "raw": raw, "answer": update?.answer ?? "", "seconds": Date().timeIntervalSince(start), "passed": decision?.action == fixture.1])
            try JSONSerialization.data(withJSONObject: reports, options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: "/tmp/cicada-deepseek-answer-update.json"))
            print("Review fixture \(index + 1): \(decision?.action.rawValue ?? "invalid") expected \(fixture.1.rawValue)")
            #expect(decision?.action == fixture.1)
            if fixture.1 == .keep { #expect(update?.answer.isEmpty == true) }
            else { #expect(update?.answer.isEmpty == false) }
        }
    }
    @Test @MainActor func clarificationRequestsChangeTheImmediateAnswer() async throws {
        try #require(CoachDeepSeekTest.enabled)
        try #require(AIKey.read("deepseek") != nil)
        let client = LingClient()
        let original = "I built the Android client so each day card and map route appeared as soon as it was ready. That changed the experience from one long wait to progressive results. The second part was reliability. I added schema validation, retries and fallback. We ran evaluations and regression tests before release. I cannot quote exact latency numbers from memory. Users saw usable results earlier and broken plans were caught before release."
        let cases: [(String, CoachReviewDecision.Action)] = [
            ("I want to make sure I got this right. Could you see one more simple sentence?", .replace),
            ("Could you give me another simple example?", .replace),
            ("Please explain that again in simpler words.", .replace),
            ("Do you have any numbers or signals that showed you worked better, even something directional is fine?", .replace),
            ("Thanks, that makes sense. Please continue.", .keep)
        ]
        var reports: [[String: Any]] = []
        for (index, fixture) in cases.enumerated() {
            var script = CoachScript(modelReading: true)
            script.replacePending(original, since: [])
            script.commit(id: "a", text: "The client displays partial results and we run regression tests.")
            script.advanceReading(to: 16, answerID: script.answerID)
            let turns = [CoachTurn(id: "q", seconds: 0, role: "interviewer", text: "For this ActAI Android interview, give an example of improving the AI itinerary experience."),
                         CoachTurn(id: "a", seconds: 5, role: "candidate", text: script.spokenText),
                         CoachTurn(id: "f", seconds: 10, role: "interviewer", text: fixture.0)]
            let start = Date()
            var raw = ""
            for try await piece in client.streamCoachTest(CoachPrompt.reviewRequest(turns: turns,
                background: "Synthetic practice: the candidate implemented progressive day cards over SSE, schema validation and regression tests. No measured metrics are supplied.", frames: [], script: script)) { raw += piece }
            let update = try CoachReviewResponse.parse(raw, finished: true)
            reports.append(["input": fixture.0, "expected": fixture.1.rawValue,
                "actual": update?.decision.action.rawValue ?? "invalid", "answer": update?.answer ?? "",
                "reason": update?.decision.reason ?? "", "seconds": Date().timeIntervalSince(start)])
            try JSONSerialization.data(withJSONObject: reports, options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: "/tmp/cicada-clarification-review.json"))
            #expect(update?.decision.action == fixture.1)
            if fixture.1 == .replace { #expect(update?.answer.isEmpty == false) }
            if index == 0 {
                let answer = try #require(update?.answer)
                #expect(CoachScript.sentences(answer).count == 1)
                #expect(CoachScript.words(answer).count <= 45)
            }
        }
    }

    @Test @MainActor func manualRefreshRespectsTheLatestOneSentenceRequest() async throws {
        try #require(AIKey.read("deepseek") != nil)
        let turns = [CoachTurn(id: "q", seconds: 0, role: "interviewer", text: "Explain how Room and WorkManager keep offline messages reliable."),
                     CoachTurn(id: "a", seconds: 2, role: "candidate", text: "Room saves messages locally first."),
                     CoachTurn(id: "f", seconds: 3, role: "interviewer", text: "Could you see one more simple sentence?")]
        var answer = ""
        for try await piece in LingClient().streamCoachTest(CoachPrompt.request(turns: turns,
            background: "Synthetic ActAI Android practice", frames: [], audio: nil,
            committed: "Room saves messages locally first.", refresh: true)) { answer += piece }
        #expect(CoachScript.sentences(answer).count == 1)
        #expect(CoachScript.words(answer).count <= 45)
        try Data(answer.utf8).write(to: URL(fileURLWithPath: "/tmp/cicada-manual-refresh-answer.txt"))
    }

}
