import Foundation
import Testing
@testable import Cicada

/// Opt-in: does DeepSeek retell the KKday SKU story told early in a ~45-minute interview?
/// Old (last ~17,000 characters, no ledger) against new (whole interview + told-story ledger).
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["CICADA_TEST_STORY_LEDGER"] == "1"))
struct CoachStoryModelTests {
    @Test @MainActor func earlyStoryIsNotRetold() async throws {
        try #require(CoachDeepSeekTest.enabled)
        try #require(AIKey.read("deepseek") != nil)
        let background = Knowledge.read()
        try #require(!CoachStory.parse(background).isEmpty)
        let plain = background.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("- story:") }.joined(separator: "\n")

        var turns = [CoachTurn(id: "q0", seconds: 170, role: "interviewer", text: "What motivates you as an engineer?"),
                     CoachTurn(id: "a0", seconds: 180, role: "candidate", text: "I like making slow things fast for real users. At KKday the SKU page was slow. Every tap recalculated all the stock and prices on the main thread. I separated and flattened the configuration and cached the results. A tap went from about one second to 300 milliseconds. Users felt it right away, and that motivates me.")]
        let pairs = [
            ("How do you handle disagreements with a product manager?", "I start from the user problem we both care about. I bring data or a quick prototype, and we agree on a small first version. If we still disagree, I write down the trade-off and let the owner decide, then I commit to it."),
            ("How do you keep up with new Android technology?", "I read the Android developers blog and release notes, and I try new APIs in my side project first. When something works well, I share a short demo with the team before we use it in production."),
            ("Tell me about how you test your code.", "I write unit tests for view models and business rules, and a few UI tests for the main flows. Before a release I check crash reports and the slowest screens. Tests that break often get fixed or removed."),
            ("How do you work with backend engineers?", "We agree on the API shape early and write it down. I use mock data so the app work does not wait. When something changes, we talk in the same channel and update the document the same day."),
            ("What do you do when a deadline is at risk?", "I tell my lead early, with what is done, what is left and two options. Usually we cut scope for the first version and keep quality. I don't hide the risk until the last day."),
            ("How do you mentor junior engineers?", "I pair with them on real tasks and review their code with clear reasons. I let them own a small feature end to end, and I check in often without taking over."),
        ]
        var t = 240.0
        while turns.reduce(0, { $0 + $1.text.count }) < 42000 {
            for pair in pairs {
                turns.append(CoachTurn(id: "fq\(turns.count)", seconds: t, role: "interviewer", text: pair.0)); t += 10
                turns.append(CoachTurn(id: "fa\(turns.count)", seconds: t, role: "candidate", text: pair.1 + " " + pair.1)); t += 50
            }
        }
        let questions = ["What achievement are you most proud of?",
                         "Tell me about a recent Android project that best shows your work."]
        let client = LingClient()
        var report: [String] = []
        var retold = ["old": 0, "new": 0]
        for question in questions {
            let all = turns + [CoachTurn(id: "q", seconds: t, role: "interviewer", text: question)]
            // The old cut: the last ~17,000 characters, and no story lines to build a ledger from.
            var old: [CoachTurn] = [], budget = 17000
            for turn in all.reversed() where budget > 0 { old.insert(turn, at: 0); budget -= turn.text.count }
            for (name, sent, knowledge) in [("old", old, plain), ("new", all, background)] {
                for run in 1...3 {
                    var answer = ""
                    for try await piece in client.streamCoachTest(CoachPrompt.request(turns: sent, background: knowledge, frames: [], audio: nil, stage: .general)) { answer += piece }
                    let sku = CoachStory.parse(background).first { $0.id == "kkday-sku" }!
                    let told = sku.isTold(in: answer)
                    if told { retold[name, default: 0] += 1 }
                    report.append("## \(name) run \(run) · retold=\(told)\nQ: \(question)\n\(answer)\n")
                }
            }
        }
        report.insert("retold SKU story — old: \(retold["old"]!)/6, new: \(retold["new"]!)/6\n", at: 0)
        let out = ProcessInfo.processInfo.environment["CICADA_TEST_STORY_OUT"] ?? NSTemporaryDirectory() + "story-ledger.md"
        try report.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
        print("story-ledger: \(report[0]) → \(out)")
    }
}
