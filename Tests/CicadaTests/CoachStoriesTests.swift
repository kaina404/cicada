import Foundation
import Testing
@testable import Cicada

struct CoachStoriesTests {
    let knowledge = """
    ## P02 KKday Android
    - story: kkday-sku | SKU, 300 milliseconds / 300 ms / three hundred milliseconds, one second
    story: cabinet | Cabinet, agent
    - story: broken
    - not a story: x | y, z
    """

    private func text(_ messages: [[String: Any]]) -> String {
        String(decoding: (try? JSONSerialization.data(withJSONObject: messages)) ?? Data(), as: UTF8.self)
    }

    @Test func parsesStoryLinesOnly() {
        let stories = CoachStory.parse(knowledge)
        #expect(stories.map(\.id) == ["kkday-sku", "cabinet"])
        #expect(stories[0].keywords.count == 3)
        #expect(stories[0].keywords[1] == [" 300 milliseconds ", " 300 ms ", " three hundred milliseconds "])
    }

    @Test func toldNeedsTwoKeywordsWithinOneAnswer() {
        let sku = CoachStory.parse(knowledge)[0]
        #expect(!sku.isTold(in: "At KKday I worked on the SKU page."))
        #expect(sku.isTold(in: "The SKU tap went from one second to 300 ms."))
        #expect(!sku.isTold(in: "I sent 300 msgs a day"))   // whole words only
        let turns = [CoachTurn(id: "q1", seconds: 60, role: "interviewer", text: "Proudest work?"),
                     CoachTurn(id: "a1", seconds: 75, role: "candidate", text: "I rebuilt the SKU calculation."),
                     CoachTurn(id: "a2", seconds: 80, role: "candidate", text: "It dropped to three hundred milliseconds."),
                     CoachTurn(id: "q2", seconds: 200, role: "interviewer", text: "SKU and 300 ms?")]
        let told = CoachStory.told(CoachStory.parse(knowledge), in: turns)
        #expect(told.map(\.id) == ["kkday-sku"])
        #expect(told.first?.seconds == 75)
        // The interviewer saying it is not the candidate telling it.
        #expect(CoachStory.told(CoachStory.parse(knowledge), in: [turns[3]]).isEmpty)
    }

    @Test func ledgerSurvivesEveryTaskAndTheWindow() throws {
        let early = [CoachTurn(id: "a0", seconds: 754, role: "candidate", text: "The SKU tap took one second, now 300 ms.")]
        let filler = (1...30).map { CoachTurn(id: "f\($0)", seconds: 800 + Double($0), role: $0.isMultiple(of: 2) ? "interviewer" : "candidate", text: String(repeating: "word ", count: 600)) }
        let turns = early + filler + [CoachTurn(id: "q", seconds: 2000, role: "interviewer", text: "What are you proud of?")]
        let ordinary = text(CoachPrompt.request(turns: turns, background: knowledge, frames: [], audio: nil))
        #expect(!ordinary.contains("now 300 ms"))   // out of the 60,000-character window…
        #expect(ordinary.contains("kkday-sku (at 12:34)"))   // …yet still known as told
        #expect(text(CoachPrompt.request(turns: turns, background: knowledge, frames: [], audio: nil, refresh: true)).contains("kkday-sku (at 12:34)"))
        var script = CoachScript()
        script.replacePending("I am proud of my work.", since: [])
        #expect(text(CoachPrompt.reviewRequest(turns: turns, background: knowledge, frames: [], script: script)).contains("kkday-sku (at 12:34)"))
        #expect(!text(CoachPrompt.request(turns: turns, background: "", frames: [], audio: nil)).contains("Stories the candidate has already told"))
    }

    @Test func wholeInterviewStaysAndItsPrefixIsStable() throws {
        let turns = (0..<40).map { CoachTurn(id: "t\($0)", seconds: Double($0) * 60, role: $0.isMultiple(of: 2) ? "interviewer" : "candidate", text: "line \($0) " + String(repeating: "x", count: 1000)) }
        let first = text(CoachPrompt.request(turns: Array(turns.dropLast()), background: "", frames: [], audio: nil))
        let next = text(CoachPrompt.request(turns: turns, background: "", frames: [], audio: nil))
        #expect(next.contains("line 0 "))   // 40,000 characters: nothing dropped
        let speech = { (s: String) in s.components(separatedBy: "Actual speech")[1] }
        #expect(speech(next).hasPrefix(String(speech(first).prefix(30000))))
    }
}
