import Foundation
import Testing
@testable import Cicada

struct CopilotRulesTests {
    @Test func thirtyMeetingTurns() {
        let cases: [(String, String, Bool)] = [
            ("StateFlow 是什么？", "them", true), ("你能解释 Binder 吗", "them", true),
            ("为什么这里会泄漏", "them", true), ("我们应该怎么灰度上线", "them", true),
            ("能不能先验证性能", "them", true), ("我担心内存不够", "them", true),
            ("还有一个顾虑是电量", "them", true), ("是否支持离线", "them", true),
            ("那第二点呢", "them", true), ("我们不同意这个重试方案", "them", true),
            ("What is TensorFlow Lite", "them", true), ("How does Compose work", "them", true),
            ("Why is this slow", "them", true), ("Can we retry a partial response", "them", true),
            ("I am concerned about latency", "them", true), ("We are worried about duplicate messages", "them", true),
            ("I disagree with that retry policy", "them", true), ("Which option is safer", "them", true),
            ("我们使用 Kotlin。", "them", false), ("面试将讨论流式聊天。", "them", false),
            ("候选人介绍了项目。", "them", false), ("The interview covers Kotlin.", "them", false),
            ("We use Jetpack Compose.", "them", false), ("The build passed yesterday.", "them", false),
            ("我们明天继续。", "them", false), ("The team reviewed the design.", "them", false),
            ("怎么测试取消？", "me", false), ("What is Flow?", "me", false),
            ("我担心重试重复发送", "me", false), ("What is token latency?", "screen", false),
            // Question words inside a statement are not a question.
            ("That's how we did it.", "them", false), ("Let me explain how our team works.", "them", false),
            ("However, we shipped on time.", "them", false), ("We merged it when the build passed.", "them", false),
            ("Tell me about a crash you fixed.", "them", true), ("Walk me through your offline sync design.", "them", true),
            ("OK, so how would you test it", "them", true),
        ]
        for (text, speaker, expected) in cases { #expect(CopilotRules.needsResponse(text, speaker: speaker) == expected, "\(text)") }
    }

    @Test func prioritiesReplacementCancellationAndDebounce() {
        var q = CopilotRules.Queue()
        q.insert(.init(kind: .term, text: "Flow", due: 0))
        q.insert(.init(kind: .situation, text: "summary", due: 0))
        #expect(q.take(now: 0)?.kind == .situation)
        #expect(q.insert(.init(kind: .response, text: "old", due: 1.5, at: 1, contextID: "a")).interrupted)
        #expect(q.take(now: 1) == nil)
        // A second question waits its turn instead of erasing the first.
        #expect(!q.insert(.init(kind: .response, text: "new", due: 2, at: 2, contextID: "b")).interrupted)
        q.delayResponse(until: 3)
        #expect(q.take(now: 2.9) == nil)
        let response = q.take(now: 3)
        #expect(response?.text == "old")
        #expect(q.insert(.init(kind: .manual, text: "now", due: 3)).interrupted)
        let manual = q.take(now: 3)
        #expect(manual?.kind == .manual)
        q.finish(response!.id) // A cancelled generation cannot release its successor.
        #expect(q.active?.id == manual?.id)
        q.finish(manual!.id)
        let resumed = q.take(now: 4)!
        #expect(resumed.text == "old")
        q.finish(resumed.id)
        let second = q.take(now: 4)!
        #expect(second.text == "new")
        q.finish(second.id)
        #expect(q.take(now: 5)?.kind == .situation)
    }

    @Test func anUpdateReplacesTheSameTaskAndReportsItDropped() {
        var q = CopilotRules.Queue()
        q.insert(.init(kind: .term, text: "Binder", due: 0, contextID: "a"))
        let first = q.take(now: 0)!
        // Another line's terms don't cancel the running one.
        #expect(q.insert(.init(kind: .term, text: "ANR", due: 0, contextID: "b")) == .init())
        let update = q.insert(.init(kind: .term, text: "Binder; AIDL", due: 0, contextID: "a"))
        #expect(update.interrupted && update.dropped?.id == first.id)
        #expect(q.take(now: 0)?.text == "ANR")
    }

    @Test func attentionAndTerms() {
        var gate = CopilotRules.Attention()
        #expect(gate.emphasize(.response, now: 0) == true)
        #expect(gate.emphasize(.response, now: 19.9) == false)
        #expect(gate.emphasize(.manual, now: 20) == true)
        #expect(gate.emphasize(.term, now: 50) == false)
        #expect(gate.situationDue(now: 0, topicChanged: false) == true)
        #expect(gate.situationDue(now: 59, topicChanged: false) == false)
        #expect(gate.situationDue(now: 60, topicChanged: false) == true)
        #expect(gate.situationDue(now: 61, topicChanged: true) == true)
        #expect(CopilotRules.terms(in: "Flow and Binder use ViewModel, not workflow", known: [], explained: ["flow"]) == ["Binder", "ViewModel"])
        #expect(CopilotRules.finishedTurn("That is all"))
        #expect(!CopilotRules.needsResponse("We will run the benchmark.", speaker: "them"))
        #expect(CopilotRules.topicShift("Next topic is Binder") == "Binder")
        #expect(CopilotRules.terms(in: "OK, the CEO said FYI the ANR is fixed", known: [], explained: []) == ["ANR"])
        #expect(CopilotRules.endsTurn("What is Flow？ ") && !CopilotRules.endsTurn("What is Flow"))
    }

    @Test func factsAdviceAndOnlyCompletedLines() {
        let p = AskPrompt.parse("Q: How should we respond?\n- Uncertain: no measured latency.\n> Ask for the latency budget.\n> Offer a benchmark before committing.")
        #expect(p.points == ["Uncertain: no measured latency."])
        #expect(p.suggestions.count == 2)
        #expect(AskPrompt.isUncertain(p.points[0]))
        #expect(AskPrompt.completeLines("Q: How?\n- Fact still stream") == ["How?"])
        #expect(AskPrompt.completeLines("Q: How?\n- Fact\n> Suggestion") == ["How?", "Fact"])
        #expect(AskPrompt.completeLines("Q: How?\n- Fact\n> Suggestion", finished: true) == ["How?", "Fact", "Suggestion"])
        #expect(AskPrompt.completeLines("StateFlow holds the current UI state.", finished: true) == ["StateFlow holds the current UI state."])
        #expect(AskPrompt.completeLines("Q: How?\n- A wrapped\npoint.\n") == ["How?", "A wrapped point."])
    }

    @Test func nearDuplicateSuggestionsAreSuppressed() {
        #expect(CopilotRules.repeatsAdvice("Please provide the specific code snippet or architectural pattern for the Flow collection lifecycle.",
                                         previous: ["Please provide the specific architectural pattern or code snippet where Flow collection starts."]))
        #expect(!CopilotRules.repeatsAdvice("Measure memory on the target device.", previous: ["Confirm the interview scenario."]))
    }

    @Test func subtitleFinalizationDoesNotExtendTheDebounce() {
        let old = Date(timeIntervalSince1970: 10)
        let now = Date(timeIntervalSince1970: 11)
        #expect(CopilotRules.speechTime(text: "", previous: "question", last: old, now: now) == old)
        #expect(CopilotRules.speechTime(text: "question", previous: "question", last: old, now: now) == old)
        #expect(CopilotRules.speechTime(text: "new words", previous: "question", last: old, now: now) == now)
    }

    @Test @MainActor func feedStateDedupAndMeetingLifecycle() {
        let c = Copilot()
        c.submit(.response, text: "one?", due: 0)
        let first = c.next(now: 0)!
        let reply = AskPrompt.Reply(understood: "one", points: ["fact"], suggestions: ["Measure latency."])
        c.completed(first, reply: reply)
        c.submit(.response, text: "two?", due: 10)
        let second = c.next(now: 10)!
        c.completed(second, reply: reply)
        #expect(c.cards.count == 2)
        #expect(c.cards[0].reply.suggestions == ["Measure latency."])
        #expect(!c.cards[0].emphasized)
        c.toggle(c.cards[0].id)
        #expect(c.cards[0].collapsed)
        c.endMeeting()
        #expect(c.cards.isEmpty)
        #expect(c.meeting.suggestions.isEmpty)
        #expect(!c.hasPending)
    }

    @Test @MainActor func onlyWhatToSayIsGenerated() {
        // No meeting updates, term notes, page notes or reminders: the panel only says what to say next.
        let c = Copilot()
        let hello = TranscriptLine(id: "m", t: -5, speaker: "me", src: "Thanks for having me.", srcLang: "en", dstLang: "zh-CN")
        let line = TranscriptLine(id: "1", t: 0, speaker: "them", src: "How does Flow work", srcLang: "en", dstLang: "zh-CN")
        let screen = TranscriptLine(id: "s", t: 1, speaker: "screen", src: "Slide: Kotlin Flow", srcLang: "en", dstLang: "zh-CN")
        c.observe(lines: [hello, line], notes: MeetingNotes(), now: 0, enabled: true, quietFor: 0)
        #expect(c.next(now: 0) == nil)
        c.observe(lines: [hello, line], notes: MeetingNotes(), now: 1, enabled: true, quietFor: 1)
        #expect(c.next(now: 1) == nil)
        let response = c.next(now: 1.5)!
        #expect(response.kind == .response)
        c.completed(response, reply: .init(understood: "How does Flow work"))
        c.observe(lines: [hello, line, screen], notes: MeetingNotes(), now: 130, enabled: true, quietFor: 130)
        #expect(c.next(now: 130) == nil)
    }

    @Test @MainActor func aQuestionMarkAnswersAtOnce() {
        let c = Copilot()
        let line = TranscriptLine(id: "1", t: 0, speaker: "them", src: "What is Flow?", srcLang: "en", dstLang: "zh-CN")
        c.observe(lines: [line], notes: MeetingNotes(), now: 0, enabled: true, quietFor: 0)
        #expect(c.next(now: 0)?.kind == .response)
    }

    @Test @MainActor func noReplyReminderOnlyWhenOurSideIsHeard() {
        // Over system audio alone our answers are silent here: two quiet minutes prove nothing.
        let c = Copilot()
        let line = TranscriptLine(id: "1", t: 0, speaker: "them", src: "What is Flow?", srcLang: "en", dstLang: "zh-CN")
        c.observe(lines: [line], notes: MeetingNotes(), now: 0, enabled: true, quietFor: 2)
        while let task = c.next(now: 2) { c.completed(task, reply: .init(understood: task.text)) }
        c.observe(lines: [line], notes: MeetingNotes(), now: 130, enabled: true, quietFor: 130)
        var kinds: [CopilotRules.Kind] = []
        while let task = c.next(now: 130) { kinds.append(task.kind); c.completed(task, reply: .init(understood: task.text)) }
        #expect(!kinds.contains(.followup))
    }

    @Test @MainActor func aSplitQuestionIsAnsweredWhole() {
        let c = Copilot()
        let a = TranscriptLine(id: "1", t: 0, speaker: "them", src: "How would you design offline sync", srcLang: "en", dstLang: "zh-CN")
        let b = TranscriptLine(id: "2", t: 3, speaker: "them", src: "for a chat app with retries?", srcLang: "en", dstLang: "zh-CN")
        c.observe(lines: [a], notes: MeetingNotes(), now: 0, enabled: true, quietFor: 0)
        c.observe(lines: [a, b], notes: MeetingNotes(), now: 3, enabled: true, quietFor: 0)
        // The design question's plan comes first, without waiting for quiet, then the answer.
        let plan = c.next(now: 3)!
        #expect(plan.kind == .plan)
        c.completedPlan(plan, text: "")
        let task = c.next(now: 3)!
        #expect(task.kind == .response && task.contextID == "1")
        #expect(task.question == "How would you design offline sync for a chat app with retries?")
        c.completed(task, reply: .init(understood: task.question))
        #expect(c.groups.filter { $0.cards.contains { $0.kind == .response } }.count == 1)
    }

    @Test @MainActor func aLaterQuestionDoesNotEraseTheOneBeingAnswered() {
        let c = Copilot()
        let a = TranscriptLine(id: "1", t: 0, speaker: "them", src: "What is Flow?", srcLang: "en", dstLang: "zh-CN")
        let b = TranscriptLine(id: "2", t: 30, speaker: "them", src: "What is a Looper?", srcLang: "en", dstLang: "zh-CN")
        c.observe(lines: [a], notes: MeetingNotes(), now: 0, enabled: true, quietFor: 0)
        let first = c.next(now: 0)!
        c.observe(lines: [a, b], notes: MeetingNotes(), now: 30, enabled: true, quietFor: 0)
        #expect(c.active?.id == first.id)
        c.completed(first, reply: .init(understood: "Flow"))
        let second = c.next(now: 30)!
        #expect(second.kind == .response && second.contextID == "2")
    }

    @Test @MainActor func aStatementWithATermAsksForNothing() {
        let c = Copilot()
        let a = TranscriptLine(id: "1", t: 0, speaker: "them", src: "We use Binder here.", srcLang: "en", dstLang: "zh-CN")
        c.observe(lines: [a], notes: MeetingNotes(), now: 0, enabled: true, quietFor: 5)
        #expect(c.next(now: 0) == nil)
    }

    @Test @MainActor func evaluatorUsesTheProductPrompt() throws {
        // tools/copilot-eval.py fills this template, so the evaluation measures the prompt the app sends.
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("tools/copilot-prompt.json")
        let them = TranscriptLine(id: "q", t: 0, speaker: "them", src: "{{QUESTION}}", srcLang: "en", dstLang: "zh-CN")
        var base = AskPrompt.request(lines: [them], now: 0, partial: "")
        base.user = base.user.replacingOccurrences(of: "<background>\n\n</background>", with: "<background>\n{{BACKGROUND}}\n</background>")
        var request = Copilot().prompt(.init(kind: .manual, text: "{{QUESTION}}", due: 0, question: "{{QUESTION}}"), base: base)
        // The evaluator names the language of each question itself.
        if let name = CopilotRules.languageName(of: "{{QUESTION}}") {
            request.user = request.user.replacingOccurrences(of: "in \(name) (the language", with: "in the language")
        }
        request.user = request.user.replacingOccurrences(of: "in the language of the question", with: "in {{LANGUAGE}} (the language of the question)")
        let expected = ["system": request.system, "user": request.user]
        #expect(request.user.contains("{{BACKGROUND}}"))
        if ProcessInfo.processInfo.environment["WRITE_COPILOT_PROMPT"] == "1" {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(expected).write(to: file)
        }
        let saved = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: file))
        #expect(saved == expected, "Prompt changed: rerun with WRITE_COPILOT_PROMPT=1 to update tools/copilot-prompt.json")
    }
}

struct CopilotGroupingTests {
    @Test @MainActor func relatedCardsKeepTheirQuestionAcrossInterleavedUpdates() throws {
        let c = Copilot()
        func finish(_ kind: CopilotRules.Kind, _ question: String, _ context: String, _ time: Double) throws {
            c.submit(kind, text: question, due: time, at: time, contextID: context, question: question)
            let task = try #require(c.next(now: time))
            c.completed(task, reply: .init(understood: question, points: ["Information"]))
        }
        try finish(.response, "How do you diagnose ANR?", "anr", 1)
        try finish(.response, "What is Binder?", "binder", 2)
        try finish(.followup, "How do you diagnose ANR?", "anr", 121)
        #expect(c.groups.count == 2)
        let anr = try #require(c.groups.first { $0.id == "anr" })
        #expect(anr.question == "How do you diagnose ANR?")
        #expect(anr.cards.map(\.kind) == [.response, .followup])
        #expect(anr.at == 1)
        c.toggleGroup("anr")
        #expect(c.collapsedGroups.contains("anr"))
        c.endMeeting()
        #expect(c.groups.isEmpty && c.collapsedGroups.isEmpty)
    }

    @Test func interruptedTermsRetainTheirOriginalContext() throws {
        var queue = CopilotRules.Queue()
        queue.insert(.init(kind: .term, text: "ANR", due: 0, contextID: "anr", question: "What is ANR?"))
        let initial = queue.take(now: 0)
        #expect(initial != nil)
        queue.insert(.init(kind: .response, text: "What is Binder?", due: 1, contextID: "binder"))
        let answerTask = queue.take(now: 1)
        let answer = try #require(answerTask)
        queue.finish(answer.id)
        let termTask = queue.take(now: 2)
        let term = try #require(termTask)
        #expect(term.contextID == "anr" && term.question == "What is ANR?")
    }

    @Test @MainActor func aQuestionKeepsOnlyItsAnswer() throws {
        let c = Copilot()
        let hello = TranscriptLine(id: "m", t: -5, speaker: "me", src: "Hello.", srcLang: "en", dstLang: "zh-CN")
        let line = TranscriptLine(id: "anr", t: 0, speaker: "them", src: "What is ANR?", srcLang: "en", dstLang: "zh-CN")
        c.observe(lines: [hello, line], notes: MeetingNotes(), now: 0, enabled: true, quietFor: 2)
        while let task = c.next(now: 2) { c.completed(task, reply: .init(understood: task.text)) }
        c.observe(lines: [hello, line], notes: MeetingNotes(), now: 120, enabled: true, quietFor: 120)
        while let task = c.next(now: 120) { c.completed(task, reply: .init(understood: task.text)) }
        let group = try #require(c.groups.first { $0.id == "anr" })
        #expect(group.cards.map(\.kind) == [.response])
        #expect(c.groups.count == 1)
    }

    @Test @MainActor func answerPromptProducesSpeechWithoutInventingExperience() {
        let c = Copilot()
        let task = CopilotRules.Trigger(kind: .response, text: "How do you diagnose ANR?", due: 0)
        let base = AskPrompt.request(lines: [], now: 0, partial: "", notes: MeetingNotes(), previousAnswers: [], image: nil)
        let prompt = c.prompt(task, base: base)
        #expect(prompt.user.contains("ready-to-say answer in the first person"))
        #expect(prompt.user.contains("language of the question"))
        #expect(prompt.user.contains("in the language of the question"))
        let long = c.prompt(.init(kind: .response, text: "How would you use StateFlow and Compose without redrawing the whole list?", due: 0,
                                  question: "How would you use StateFlow and Compose without redrawing the whole list?"), base: base)
        #expect(long.user.contains("in English (the language of the question)"))
        #expect(CopilotRules.languageName(of: "Binder 是什么？") == "Chinese")
        #expect(CopilotRules.languageName(of: "OK?") == nil)
        #expect(prompt.user.contains("never turn general knowledge into a claim"))
        #expect(prompt.user.contains("[fill in: ...]"))
        // Every task shares one system prompt, so the model server can reuse its cache.
        #expect(c.prompt(.init(kind: .term, text: "ANR", due: 0), base: base).system == prompt.system)
    }
}
