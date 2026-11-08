import Foundation
import Testing
@testable import Cicada

struct CoachDeepSeekTestTests {
    @Test func cloudRequestKeepsReferencesAndPicturesButNeverAudio() throws {
        let messages = CoachPrompt.request(
            turns: [CoachTurn(id: "q", seconds: 1, role: "interviewer", text: "How do retries survive process death?")],
            background: "ActAI Android background", frames: [CoachFrame(jpeg: Data([1, 2, 3]), seconds: 1)],
            audio: CoachAudioBuffer())
        let body = CoachDeepSeekTest.body(messages)
        #expect(body["model"] as? String == "deepseek-flash")
        #expect((body["thinking"] as? [String: String])?["type"] == "disabled")
        let result = try #require(body["messages"] as? [[String: Any]])
        let system = try #require(result.first?["content"] as? String)
        #expect(system.contains("How do retries survive process death?"))
        #expect(system.contains("ActAI Android background"))
        let parts = try #require(result.last?["content"] as? [[String: Any]])
        #expect(parts.filter { $0["type"] as? String == "image_url" }.count == 1)
        let json = String(decoding: try JSONSerialization.data(withJSONObject: body), as: UTF8.self)
        #expect(!json.contains("input_audio"))
        #expect(!json.contains("audio_url"))
    }
    @Test func cloudUpdatePreservesTheKeepOrReplaceTask() throws {
        var script = CoachScript()
        script.replacePending("I persist messages in Room.", since: [])
        let body = CoachDeepSeekTest.body(CoachPrompt.reviewRequest(turns: [], background: "", frames: [], script: script))
        let messages = try #require(body["messages"] as? [[String: Any]])
        let system = try #require(messages[0]["content"] as? String)
        #expect(system.contains("For keep, STOP immediately"))
        #expect(system.contains("this SAME response"))
        #expect(system.contains("unread_remainder"))
        let parts = try #require(messages[1]["content"] as? [[String: Any]])
        let task = parts.last?["text"] as? String ?? ""
        #expect(task.contains("exact output protocol"))
    }
}
