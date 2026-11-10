import Foundation
import Testing
@testable import Cicada

/// Opt-in capture of real product-prompt answers; generated speech is simulated, not user testimony.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["CICADA_TEST_HR_HISTORY"] == "1"))
struct HRCompanyHistoryModelTests {
    @Test @MainActor func captureCompanyByCompanyInterview() async throws {
        try #require(CoachDeepSeekTest.enabled)
        try #require(AIKey.read("deepseek") != nil)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let output = root.appendingPathComponent("outputs/hr-company-history-knowledge")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let background = Knowledge.read()
        try #require(!background.isEmpty)
        try Data(background.utf8).write(to: output.appendingPathComponent("background-used.md"))
        let questions: [(String, String, String)] = [
            ("KKday", "职责", "Let's start with KKday. What did you work on there, and what did you personally own?"),
            ("KKday", "成果", "You mentioned leading the itinerary project. What did you deliver yourself, and what evidence shows it worked? Please separate your contribution from the team's results."),
            ("KKday", "离职", "Why did you leave KKday? Was it related to your performance?"),
            ("科智", "职责", "Before KKday, you worked at Kezhi. What did that company build, and what was your role?"),
            ("科智", "交付", "Your resume mentions a four-week initial build. What did you personally do, what trade-off did you make, and what was the result?"),
            ("科智", "离职", "Why did you leave Kezhi after about a year and a half? Why move to KKday?"),
            ("德邦证券", "职责", "Let's go back to Debon Securities. What were your main responsibilities, and how did you change the existing Android app?"),
            ("德邦证券", "成果", "You say the crash rate fell by about ninety percent. What was the baseline and measurement period, and how much was your own contribution?"),
            ("德邦证券", "离职", "Why did you leave Debon Securities in July 2023? What happened between that job and joining Kezhi in September?"),
            ("平安好学", "职责", "At Ping An Haoxue, what product did you work on, and what did you personally build?"),
            ("平安好学", "成果", "Why did you extract the classroom SDK, and how do you know it improved things for the phone and tablet teams?"),
            ("平安好学", "离职", "Why did you leave Ping An Haoxue in August 2021? Was there a problem with the team or the work?"),
            ("平安证券", "职责", "Tell me about your first job at Ping An Securities. What features did you build yourself?"),
            ("平安证券", "成长", "What is one concrete engineering lesson you learned there? Please use a real example and don't just list technologies."),
            ("平安证券", "转岗", "Why did you move from Ping An Securities to Ping An Haoxue in May 2018? Was it an internal transfer?"),
            ("履历核对", "稳定性", "Three recent jobs ended after relatively short periods. How should I think about your stability and commitment if you join us?"),
            ("履历核对", "当前状态", "What have you been doing since leaving KKday in August 2026? Have you been employed somewhere else, and when could you join us?"),
            ("个人项目", "FlutterDouBan", "Was FlutterDouBan part of a company job or your own project? What did you build, and how many real users did it have?"),
            ("个人项目", "CabinetAI", "What did you personally build in CabinetAI? Is it publicly launched, and what adoption or business results can you demonstrate?")
        ]
        var turns: [CoachTurn] = []
        var reports: [[String: Any]] = []
        let client = LingClient()
        for (index, fixture) in questions.enumerated() {
            turns.append(CoachTurn(id: "q\(index)", seconds: Double(index * 120), role: "interviewer", text: fixture.2))
            let messages = CoachPrompt.request(turns: turns, background: background, frames: [], audio: nil, stage: .hr)
            let started = Date()
            var first: Double?
            var answer = ""
            var failure = ""
            do {
                for try await piece in client.streamCoachTest(messages) {
                    if first == nil, !piece.isEmpty { first = Date().timeIntervalSince(started) }
                    answer += piece
                }
            } catch { failure = String(describing: error) }
            reports.append(["id": index + 1, "company": fixture.0, "topic": fixture.1,
                "question": fixture.2, "answer": answer, "error": failure,
                "first_seconds": first ?? -1, "total_seconds": Date().timeIntervalSince(started),
                "request": messages])
            let report: [String: Any] = ["model": CoachDeepSeekTest.model, "stage": "hr",
                "background_source": Knowledge.folder.path,
                "method": "Sequential synthetic HR questions; successful AI answers are assumed spoken for subsequent turns. Production CoachPrompt.request, retrieval and LingClient; no audio, UI or automatic keep/replace review.",
                "results": reports]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("results.json"), options: .atomic)
            print("HR history \(index + 1)/\(questions.count): \(fixture.0) \(fixture.1) chars=\(answer.count) error=\(failure)")
            #expect(failure.isEmpty)
            #expect(!answer.isEmpty)
            if failure.isEmpty, !answer.isEmpty {
                turns.append(CoachTurn(id: "a\(index)", seconds: Double(index * 120 + 30), role: "candidate", text: answer))
            }
        }
    }
}
