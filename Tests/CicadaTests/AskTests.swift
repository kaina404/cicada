import Foundation
import Testing
@testable import Cicada

struct AskTests {
    private func line(_ id: String, _ t: Double, _ speaker: String, _ src: String) -> TranscriptLine {
        TranscriptLine(id: id, t: t, speaker: speaker, src: src, dst: nil, srcLang: "zh-CN", dstLang: "en")
    }

    @Test func theQuestionIsTheOtherSidesLastWordsAndTheRestIsBackground() {
        let lines = [
            line("1", 10, "them", "先介绍一下 AI 通信应用项目。"),
            line("2", 30, "me", "好的，我做过三年安卓。"),
            line("s1", 35, "screen", "含义：ActAI Android 技术面试\n原文：ActAI / Android"),
            line("3", 50, "them", "你做过安卓吧？"),
            line("4", 55, "them", "那 Enjoy 的 Compose 是什么？"),
        ]
        let r = AskPrompt.request(lines: lines, now: 58, partial: "", topics: ["AI 通信应用"])
        #expect(r.user.contains("<question>\nThem: 你做过安卓吧？\nThem: 那 Enjoy 的 Compose 是什么？\n</question>"))
        #expect(r.user.contains("Screen at 00:35: 含义：ActAI Android 技术面试"))
        #expect(r.user.contains("Me: 好的，我做过三年安卓。"))
        #expect(r.user.contains("Topics so far: AI 通信应用"))
        // The question isn't repeated in the background.
        #expect(!r.user.components(separatedBy: "</background>")[0].contains("Compose"))
        #expect(r.system == Copilot.system)
    }

    @Test func myOwnLastWordsDontHideTheQuestion() {
        let lines = [line("1", 40, "them", "AI 消息重试有什么风险？"), line("2", 45, "me", "嗯，我想一下")]
        let r = AskPrompt.request(lines: lines, now: 46, partial: "", topics: [])
        #expect(r.user.contains("<question>\nThem: AI 消息重试有什么风险？\n</question>"))
    }

    @Test func theSentenceStillBeingHeardJoinsTheQuestion() {
        let lines = [line("1", 40, "them", "我们用 StateFlow。")]
        let r = AskPrompt.request(lines: lines, now: 44, partial: "它和 SharedFlow 有什么区别", topics: [])
        #expect(r.user.contains("Them: 我们用 StateFlow。\nThem: 它和 SharedFlow 有什么区别\n</question>"))
    }

    @Test func theBackgroundStartsOnAWholeMinuteWithinFiveMinutes() {
        let lines = [line("1", 311, "them", "五分钟前刚过"), line("2", 361, "them", "整分钟之后"), line("3", 600, "them", "离线消息同步怎么实现？")]
        let r = AskPrompt.request(lines: lines, now: 601, partial: "", topics: [])
        #expect(!r.user.contains("五分钟前刚过"))
        #expect(r.user.contains("整分钟之后"))
    }

    @Test func speechEndsTheBackgroundAndDropsWholeMinutes() {
        var notes = MeetingNotes()
        notes.summary = "summary"
        let long = String(repeating: "长", count: 1500)
        let lines = [line("1", 250, "them", "第一分钟 " + long), line("2", 262, "them", "第一分钟又一句"),
                     line("3", 300, "them", "第二分钟 " + long), line("4", 380, "them", "第三分钟 " + long),
                     line("q", 420, "them", "怎么实现？")]
        let r = AskPrompt.request(lines: lines, now: 420, partial: "", notes: notes)
        let back = r.user.components(separatedBy: "</background>")[0]
        #expect(!back.contains("第一分钟"))
        #expect(back.contains("第二分钟") && back.contains("第三分钟"))
        #expect(back.hasPrefix("<background>\nNotes: summary\nThem: 第二分钟"))
    }

    @Test func oldLinesStayOutOfTheBackground() {
        let lines = [line("1", -201, "them", "很早以前说的"), line("2", 100, "them", "离线消息同步怎么实现？")]
        let r = AskPrompt.request(lines: lines, now: 101, partial: "", topics: [])
        #expect(!r.user.contains("很早以前说的"))
    }

    @Test func theReplyIsReadAsItGrows() {
        #expect(AskPrompt.parse("Q: Jetpack Com").understood == "Jetpack Com")
        let text = "**Q:** Jetpack Compose 是什么？\n\n* 声明式 UI 工具包。\n2. 用 Kotlin 写界面\n- 取代 XML 布局\n- 第四条不要"
        let p = AskPrompt.parse(text)
        #expect(p.understood == "Jetpack Compose 是什么？")
        #expect(p.points == ["声明式 UI 工具包。", "用 Kotlin 写界面", "取代 XML 布局"])
    }

    @Test func aLabelInTheNotesLanguageAndAWrappedPointAreKept() {
        let p = AskPrompt.parse("理解为：AI 消息重试的风险\n- 重试时前一次请求\n可能已完成")
        #expect(p.understood == "AI 消息重试的风险")
        #expect(p.points == ["重试时前一次请求 可能已完成"])
    }

    @Test func serverEventsGiveTheirText() {
        #expect(AskPrompt.delta(#"{"choices":[{"delta":{"content":"声明式"}}]}"#) == "声明式")
        #expect(AskPrompt.delta(#"{"choices":[{"delta":{"role":"assistant"}}]}"#) == nil)
        #expect(AskPrompt.delta("not json") == nil)
    }
}

struct AskV2Tests {
    private func line(_ id: String, _ t: Double, _ text: String, speaker: String = "me") -> TranscriptLine {
        TranscriptLine(id: id, t: t, speaker: speaker, src: text, dst: nil, srcLang: "zh-CN", dstLang: "en")
    }

    @Test func fiveMinuteWindowAndWholeOldestLinesAreDropped() {
        let r = AskPrompt.request(lines: [line("old", 199, "expired"), line("recent", 241, "retained"),
                                          line("q", 500, "question", speaker: "them")], now: 500, partial: "")
        #expect(r.user.contains("retained"))
        #expect(!r.user.contains("expired"))
        let bounded = AskPrompt.request(lines: [line("1", 10, "oldest"), line("2", 20, String(repeating: "中", count: 1995)),
                                                line("3", 30, String(repeating: "文", count: 1996))], now: 40, partial: "")
        #expect(!bounded.user.contains("oldest"))
        let speech = bounded.user.components(separatedBy: "<background>\n")[1].components(separatedBy: "\n</background>")[0]
        #expect(speech.count == AskPrompt.speechLimit)
        #expect(speech.hasPrefix("Me: 中"))
        #expect(speech.hasSuffix("文"))
    }

    @Test func screensKeepThreeRecentPagesInOrderAndExactOCR() {
        let screens = (0...4).map { line("s\($0)", Double($0 * 100), "含义：page \($0)\n原文：850 ms p95 token latency", speaker: "screen") }
        let r = AskPrompt.request(lines: screens, now: 450, partial: "")
        #expect(!r.user.contains("page 0"))
        #expect(!r.user.contains("page 1"))
        #expect(r.user.contains("Screen at 03:20: 含义：page 2\n原文：850 ms p95 token latency"))
        #expect(r.user.contains("Screen at 05:00: 含义：page 3"))
        #expect(r.user.contains("Screen at 06:40: 含义：page 4"))
        #expect(AskPrompt.screenText("含义：" + String(repeating: "长", count: 500) + "\n原文：123").count <= 300)
        let chrome = "含义：ActAI streaming latency\n原文：" + String(repeating: "browser toolbar / ", count: 50) + "First token 850 ms"
        #expect(AskPrompt.screenText(chrome).hasSuffix("First token 850 ms"))
        #expect(AskPrompt.screenText(chrome).count == 300)
    }

    @Test func notesTermsAndPreviousAnswersHaveBoundedFixedSections() {
        var notes = MeetingNotes()
        notes.summary = "Practice token target is 850 ms"
        notes.topics = (0...3).map { NoteTopic(start: Double($0), title: "Topic \($0)", summary: "detail", points: []) }
        notes.conclusions = [NoteItem(text: "measure on a midrange Android device", support: 1)]
        notes.terms = [NoteTerm(name: "Jetpack Compose", note: "", heard: ["Enjoy Compose"])]
        let answers = (0...3).map { AskPrompt.Answer(understood: "question \($0)", points: ["point \($0)"]) }
        let r = AskPrompt.request(lines: [], now: 500, partial: "那第二点呢？", notes: notes, previousAnswers: answers)
        #expect(r.user.contains("Notes: Practice token target is 850 ms\nTopic 1: detail\nTopic 2: detail\nTopic 3: detail\nmeasure on a midrange Android device"))
        #expect(!r.user.contains("Topic 0"))
        #expect(r.user.contains("Terms: Jetpack Compose (heard: Enjoy Compose)"))
        #expect(r.user.contains("<previous_answers>\nQ: question 1\n- point 1\nQ: question 2\n- point 2\nQ: question 3\n- point 3\n</previous_answers>"))
        #expect(!r.user.contains("question 0"))
        notes.summary = String(repeating: "纪", count: 900)
        let long = AskPrompt.request(lines: [], now: 0, partial: "", notes: notes)
        let summary = long.user.components(separatedBy: "Notes: ")[1].components(separatedBy: "\nTerms:")[0]
        #expect(summary.count == 800)
    }

    @Test func imageSelectionRespectsFreshnessVideoAndPrivacy() {
        let now = Date(timeIntervalSince1970: 1000)
        let latest = AskPrompt.Image(jpeg: Data([1]), width: 1280, height: 720, capturedAt: now.addingTimeInterval(-2))
        let page = AskPrompt.Image(jpeg: Data([2]), width: 1024, height: 768, capturedAt: now.addingTimeInterval(-300))
        #expect(AskPrompt.selectImage(enabled: true, latest: latest, isSlide: true, page: page, now: now) == latest)
        #expect(AskPrompt.selectImage(enabled: true, latest: latest, isSlide: true, page: page, now: now.addingTimeInterval(0.1)) == nil)
        var stale = latest
        stale.capturedAt = now.addingTimeInterval(-3)
        #expect(AskPrompt.selectImage(enabled: true, latest: stale, isSlide: true, page: page, now: now) == page)
        #expect(AskPrompt.selectImage(enabled: true, latest: latest, isSlide: false, page: page, now: now) == page)
        #expect(AskPrompt.selectImage(enabled: true, latest: latest, isSlide: false, page: nil, now: now) == nil)
        #expect(AskPrompt.selectImage(enabled: false, latest: latest, isSlide: true, page: page, now: now) == nil)
    }

    @Test func requestUsesImageFirstAndKeepsTextOnlyContentAsString() throws {
        let image = AskPrompt.Image(jpeg: Data([1, 2]), width: 1280, height: 720, capturedAt: Date())
        var r = AskPrompt.request(lines: [], now: 0, partial: "question", image: image)
        let parts = try #require(r.messages[1]["content"] as? [[String: Any]])
        #expect(parts[0]["type"] as? String == "image_url")
        #expect((parts[0]["image_url"] as? [String: String])?["url"] == "data:image/jpeg;base64,AQI=")
        #expect(parts[1]["text"] as? String == r.user)
        #expect(JSONSerialization.isValidJSONObject(r.messages))
        r.image = nil
        #expect(r.messages[1]["content"] as? String == r.user)
    }

    @Test func uncertaintyIsParsedAsAPointAndRecognizedInEveryUILanguage() {
        let reply = AskPrompt.parse("Q: What was the measured token latency?\n- The practice target was 850 ms.\n- Uncertain: Measurements were not provided.")
        #expect(reply.points == ["The practice target was 850 ms.", "Uncertain: Measurements were not provided."])
        #expect(!AskPrompt.isUncertain(reply.points[0]))
        #expect(AskPrompt.isUncertain(reply.points[1]))
        for label in ["不确定：未知", "不確か：不明", "불확실: 모름"] { #expect(AskPrompt.isUncertain(label)) }
        #expect(!AskPrompt.omitImageNextTime(first: 2))
        #expect(AskPrompt.omitImageNextTime(first: 2.01))
    }

    @Test @MainActor func meetingEndClearsMemoryAndDismissOnlyHidesCard() {
        let engine = AskEngine()
        engine.displayCompleted(.init(understood: "q", points: ["answer"]))
        engine.dismiss()
        #expect(engine.state == .idle && engine.points.isEmpty)
        engine.endMeeting()
        #expect(engine.state == .idle)
    }

    @Test func continuousMotionRunsOCRAtFiveSecondIntervalsButNotGemmaForDuplicateText() {
        var policy = ScreenReadPolicy()
        let text = "ActAI Android interview streaming Kotlin StateFlow latency 850 milliseconds"
        var checks: [Int] = []
        for t in 0...15 {
            let trigger = policy.next(now: Double(t), difference: 0.02, steady: 0, fromRead: 0.02, busy: false, reading: false)
            if trigger == .fallback { checks.append(t) }
        }
        #expect(checks == [5, 10, 15])
        #expect(!ScreenReadPolicy.shouldRead(ocr: text, previous: text))
        #expect(!ScreenReadPolicy.shouldRead(ocr: "Alice Bob", previous: text))
        #expect(ScreenReadPolicy.shouldRead(ocr: "Android interview TensorFlow Lite inference delegate memory battery", previous: text))
    }

    @Test func priorityStableTriggerAndAccumulatedChanges() {
        var policy = ScreenReadPolicy()
        #expect(policy.next(now: 0, difference: 1, steady: 0, fromRead: 1, busy: false, reading: false) == .none)
        #expect(policy.next(now: 1, difference: 0, steady: 1, fromRead: 1, busy: true, reading: false) == .none)
        #expect(policy.next(now: 5, difference: 0, steady: 5, fromRead: 1, busy: false, reading: true) == .none)
        #expect(policy.next(now: 6, difference: 0, steady: 6, fromRead: 1, busy: false, reading: false) == .fallback)
        #expect(policy.next(now: 12, difference: 0, steady: 12, fromRead: 0, busy: false, reading: false) == .none)
        #expect(policy.next(now: 13, difference: 0.1, steady: 0, fromRead: 0.1, busy: false, reading: false) == .fallback)
        #expect(policy.next(now: 14, difference: 0, steady: 1, fromRead: 0.1, busy: false, reading: false) == .stable)
    }
}
