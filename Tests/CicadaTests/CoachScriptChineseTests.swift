import Foundation
import Testing
@testable import Cicada

struct CoachScriptChineseTests {
    @Test func hanCharactersAreTokensAndLatinWordsStayWhole() {
        #expect(CoachScript.words("我用 Kotlin 写了 3 个模块。") == ["我", "用", "kotlin", "写", "了", "3", "个", "模", "块"])
        #expect(CoachScript.words("用Room存") == ["用", "room", "存"])
        #expect(CoachScript.words("I store it in Room.") == ["i", "store", "it", "in", "room"])
    }
    @Test func droppingCountsTheSameTokensAsWords() {
        let text = "我用 Kotlin 写，然后上线。"
        #expect(CoachScript.droppingWords(2, from: text) == "Kotlin 写，然后上线。")
        #expect(CoachScript.droppingWords(3, from: text) == "写，然后上线。")
        #expect(CoachScript.droppingWords(4, from: text) == "然后上线。")
        #expect(CoachScript.droppingWords(1, from: "用Room存") == "Room存")
        #expect(CoachScript.droppingWords(2, from: "用Room存") == "存")
        #expect(CoachScript.droppingWords(9, from: text) == "")
    }
    @Test func chineseFullStopsSplitSentencesWithoutSpaces() {
        #expect(CoachScript.sentences("我负责离线同步。后来加了重试！效果如何？还好") ==
            ["我负责离线同步。", "后来加了重试！", "效果如何？", "还好"])
    }
    @Test func readingAdvancesThroughChineseDespiteAHomophone() {
        var script = CoachScript()
        let answer = "我负责消息的离线存储。然后我加了安全的重试。"
        script.replacePending(answer, since: [])
        // ASR heard 李 for 离: one substitution must not stop progress.
        script.preview("我负责消息的李线存储")
        #expect(script.cursor == 10)
        #expect(script.currentSentence == 1)
        #expect(script.remainingText == "然后我加了安全的重试。")
        _ = script.commit(id: "a", text: "我负责消息的李线存储")
        #expect(script.pending == answer)
        #expect(script.cursor == 10)
    }
    @Test func shortChineseFragmentsNeedAnExactPrefix() {
        var script = CoachScript()
        script.replacePending("我负责离线存储。", since: [])
        script.preview("好的")
        #expect(script.cursor == 0)
        script.preview("我负")
        #expect(script.cursor == 2)
    }
    @Test func trailingChineseConnectiveWaitsLonger() {
        #expect(CoachEndpoint.delay("我觉得这个方案可以，因为") == 1.8)
        #expect(CoachEndpoint.delay("我觉得这个方案可以。") == 0.65)
    }
}

struct CoachSentenceEndTests {
    @Test func chineseFullStopsEndASentence() {
        #expect("。！？.!?".allSatisfy(CoachScript.endsSentence))
        #expect(!"，、；".contains(where: CoachScript.endsSentence))
    }
}
