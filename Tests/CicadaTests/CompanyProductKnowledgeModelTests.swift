import Foundation
import Testing
@testable import Cicada

/// Opt-in baseline: use the current background without adding researched product facts.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["CICADA_TEST_COMPANY_PRODUCTS"] == "1"))
struct CompanyProductKnowledgeModelTests {
    @Test @MainActor func captureIndependentAnswers() async throws {
        try #require(CoachDeepSeekTest.enabled)
        try #require(AIKey.read("deepseek") != nil)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let output = root.appendingPathComponent("outputs/company-product-knowledge-2026-11-10")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let background = CandidateBackground.read()
        try #require(!background.isEmpty)
        try Data(background.utf8).write(to: output.appendingPathComponent("background-used.md"))
        let companies = ["KKday", "平安证券 (Ping An Securities)", "德邦证券 (Debon Securities)", "可之科技"]
        var cases: [(String, String, String)] = []
        for company in companies {
            cases.append((company, "company", "Could you introduce \(company), the company you worked for? What business is it in, who are its customers, and what user problem does it solve?"))
            cases.append((company, "app", "Please introduce the main mobile app you worked on at \(company) to someone who has never used it. Name the app, describe its target users, three core user-facing features, and one typical end-to-end user journey. Focus on the product before discussing implementation."))
            cases.append((company, "ownership", "At \(company), which app features did you personally build, and which were broader company capabilities? What evidence do you have of the app's users, adoption, or business impact?"))
        }
        cases.append(("可之科技", "alias", "你在可之科技做的 App 是什么？请介绍公司的业务、App 的中文名称、目标用户和核心功能。"))
        cases.append(("Kezhi", "english_alias", "At Kezhi (Ningbo) AI Technology, what was the Daikaotong app? Which exams and age groups did it serve, and what could a student actually do in it?"))
        let client = LingClient()
        var reports: [[String: Any]] = []
        for (index, fixture) in cases.enumerated() {
            // No earlier generated answers are fed back as candidate testimony.
            let turns = [CoachTurn(id: "q\(index)", seconds: 0, role: "interviewer", text: fixture.2)]
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
                "retrieved_background": CoachKnowledge.retrieve(background, query: fixture.2), "request": messages])
            let report: [String: Any] = ["model": CoachDeepSeekTest.model, "stage": "hr",
                "background_source": CandidateBackground.file.path,
                "method": "Independent synthetic questions using production CoachPrompt.request, CoachKnowledge and LingClient. Current background unchanged; no web facts injected; no audio, UI, or automatic keep/replace review. Assertions check transport only; knowledge quality requires manual review.",
                "results": reports]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("results.json"), options: .atomic)
            print("Company product \(index + 1)/\(cases.count): \(fixture.0) \(fixture.1) chars=\(answer.count) error=\(failure)")
            #expect(failure.isEmpty)
            #expect(!answer.isEmpty)
        }
    }
}
