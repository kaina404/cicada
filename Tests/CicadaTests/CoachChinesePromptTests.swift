import Foundation
import Testing
@testable import Cicada

struct CoachChinesePromptTests {
    private let turns = [CoachTurn(id: "q", seconds: 1, role: "interviewer", text: "介绍一下你做过的离线同步。")]
    private func text(_ messages: [[String: Any]]) -> (system: String, user: String) {
        let system = messages[0]["content"] as? String ?? ""
        let parts = messages[1]["content"] as? [[String: Any]] ?? []
        return (system, parts.compactMap { $0["text"] as? String }.joined(separator: "\n"))
    }

    @Test func chineseRequestAsksForSpokenChineseWithoutEnglishOrIPARules() {
        let (system, user) = text(CoachPrompt.request(turns: turns, background: "资料", frames: [], audio: nil,
                                                      stage: .hr, language: .chinese))
        #expect(system.hasPrefix(CoachPrompt.systemChinese))
        #expect(system.contains("about 150–250 Chinese characters"))
        #expect(!system.contains("60–100 words"))
        #expect(!system.contains("high-school English"))
        #expect(!system.contains("British IPA"))
        #expect(system.contains("不好意思，您能把问题完整再说一遍吗？"))
        #expect(user.contains("remaining spoken Chinese answer"))
        #expect(user.contains(CoachPrompt.personalFactsReminderChinese))
        #expect(!user.contains("high-school English"))
    }
    @Test func chineseReviewStreamsAChineseReplacement() {
        var script = CoachScript()
        script.replacePending("我负责离线存储。", since: [])
        let (system, _) = text(CoachPrompt.reviewRequest(turns: turns, background: "", frames: [], script: script,
                                                         language: .chinese))
        #expect(system.contains("remaining spoken Chinese answer"))
        #expect(!system.contains("remaining English answer"))
        #expect(!system.contains("Do not add IPA"))
    }
    @Test func chineseScreenOnlyDescribesInChinese() {
        let frame = CoachFrame(jpeg: Data([1]), seconds: 1)
        let (system, _) = text(CoachPrompt.request(turns: [], background: "", frames: [frame], audio: nil, language: .chinese))
        #expect(system.contains("briefly in spoken Chinese"))
    }
    @Test func englishPromptIsUnchangedByDefault() {
        let (system, user) = text(CoachPrompt.request(turns: turns, background: "", frames: [], audio: nil, stage: .hr))
        #expect(system.hasPrefix(CoachPrompt.system))
        #expect(system.contains("60–100 words"))
        #expect(user.contains("remaining English answer"))
    }
}
