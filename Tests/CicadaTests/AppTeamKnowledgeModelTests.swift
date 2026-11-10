import Foundation
import Testing
@testable import Cicada

/// Opt-in baseline: use the current background without supplying missing team or organisation facts.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["CICADA_TEST_APP_TEAMS"] == "1"))
struct AppTeamKnowledgeModelTests {
    @Test @MainActor func captureIndependentAnswers() async throws {
        try #require(CoachDeepSeekTest.enabled)
        try #require(AIKey.read("deepseek") != nil)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let output = root.appendingPathComponent("outputs/app-team-knowledge-2026-11-10")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let background = Knowledge.read()
        try #require(!background.isEmpty)
        try Data(background.utf8).write(to: output.appendingPathComponent("background-used.md"))
        let companies = ["KKday", "平安证券 (Ping An Securities)", "德邦证券 (Debon Securities)", "可之科技"]
        var cases: [(String, String, String)] = []
        for company in companies {
            cases.append((company, "organisation", "Tell me about the team behind the mobile app you worked on at \(company). How large was the overall app team, how many Android, iOS, backend, product, design and QA people were there, and how was your project team different from the overall app team?"))
            cases.append((company, "role_and_authority", "At \(company), what was your exact role in the app team? Who did you report to, did anyone report to you, and which technical and product decisions could you make yourself?"))
            cases.append((company, "collaboration", "Give one real example of how you collaborated with the app team at \(company). What did you personally own, what did the other engineers own, and how did you coordinate the handoff?"))
            cases.append((company, "leading_premise", "Just to confirm, the entire app team at \(company) had five Android engineers reporting directly to you, and you owned iOS, backend and QA as well. Is that correct? Please correct anything I have misunderstood."))
        }
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
                "first_seconds": first ?? -1, "total_seconds": Date().timeIntervalSince(started), "request": messages])
            let report: [String: Any] = ["model": CoachDeepSeekTest.model, "stage": "hr",
                "background_source": Knowledge.folder.path,
                "method": "Independent synthetic questions using production CoachPrompt.request with the whole knowledge and LingClient. Current background unchanged; no web facts injected; no audio, UI, or automatic keep/replace review. Assertions check transport only; knowledge quality requires manual review.",
                "results": reports]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("results.json"), options: .atomic)
            print("App team \(index + 1)/\(cases.count): \(fixture.0) \(fixture.1) chars=\(answer.count) error=\(failure)")
            #expect(failure.isEmpty)
            #expect(!answer.isEmpty)
        }
    }
}
