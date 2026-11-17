import Foundation
import Testing
@testable import Cicada

/// The walkthrough engine inside the coach, with a scripted model.
struct CoachCardsTests {
    init() async { await CoachPronunciation.prepare() }

    private func line(_ id: String, _ speaker: String, _ text: String, t: Double = 0) -> TranscriptLine {
        TranscriptLine(id: id, t: t, speaker: speaker, src: text, dst: nil, srcLang: "en", dstLang: "zh")
    }
    /// A model that answers each request with the next reply and records what it was asked.
    @MainActor final class Model {
        var replies: [String]
        var asked: [[[String: Any]]] = []
        init(_ replies: [String]) { self.replies = replies }
        func stream(_ messages: [[String: Any]], _ model: String) -> AsyncThrowingStream<String, Error> {
            asked.append(messages)
            let reply = replies.isEmpty ? "<<<CICADA_CARD>>>\nKEEP" : replies.removeFirst()
            return AsyncThrowingStream { $0.yield(reply); $0.finish() }
        }
    }
    @MainActor private func coach(_ model: Model) -> InterviewCoach {
        let engine = InterviewCoach { messages, name in model.stream(messages, name) }
        engine.gloss.enabled = false
        engine.cardsEnabled = true
        engine.start(background: "", available: true, prepare: { true })
        return engine
    }
    @MainActor private func settle(_ engine: InterviewCoach) async {
        for _ in 0..<2000 where engine.cards.busy { await Task.yield() }
        for _ in 0..<50 { await Task.yield() }
    }
    private func text(_ messages: [[String: Any]]) -> String {
        messages.compactMap { message -> String? in
            if let s = message["content"] as? String { return s }
            return (message["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined(separator: "\n")
        }.joined(separator: "\n")
    }

    @Test @MainActor func anInterviewerTurnBecomesACardInTheScriptWithItsCase() async throws {
        let model = Model(["""
        <<<CICADA_CARD>>>
        HEARD: design a chat screen
        SAY:
        I'd start with the scope. Which parts matter most to you?
        THEN: Then the state model.
        CASE: [{"op":"newProblem","text":"Chat screen like ChatGPT","evidence":["q"]},{"op":"constraint","text":"Works offline","evidence":["q"]}]
        """])
        let engine = coach(model)
        defer { engine.endMeeting() }
        engine.observe(lines: [line("q", "them", "Design a chat screen like ChatGPT. It must work offline.")], now: 0)
        for t in stride(from: 0.0, through: 4, by: 0.5) { engine.tick(now: t) }
        await settle(engine)
        #expect(engine.cards.card?.heard == "design a chat screen")
        #expect(engine.script.pending.hasPrefix("I'd start with the scope."))
        #expect(engine.cards.memory.problem?.goal == "Chat screen like ChatGPT")
        #expect(engine.cards.memory.problem?.constraints.first?.status == .confirmed)
        #expect(engine.paragraphs.isEmpty)
        let request = text(model.asked[0])
        #expect(request.contains("WALKTHROUGH CARD MODE"))
        #expect(request.contains("Design a chat screen like ChatGPT"))
        #expect(!request.contains("Write the COMPLETE remaining"))
    }

    @Test @MainActor func keepLeavesTheCardAndChineseKeepsTheFullAnswerPath() async throws {
        let model = Model(["<<<CICADA_CARD>>>\nSAY:\nFirst, the scope.\nCASE: []", "<<<CICADA_CARD>>>\nKEEP"])
        let engine = coach(model)
        defer { engine.endMeeting() }
        engine.observe(lines: [line("q", "them", "How would you design the feed?")], now: 0)
        for t in stride(from: 0.0, through: 4, by: 0.5) { engine.tick(now: t) }
        await settle(engine)
        engine.ask()
        await settle(engine)
        #expect(engine.cards.card?.say == "First, the scope.")
        #expect(engine.cards.keeps == 1)
        engine.language = .chinese
        #expect(!engine.cardMode)
    }

    @Test @MainActor func freeSpeechAndTheBoardAskForTheNextStepWithoutReplacingMidSentence() async throws {
        let model = Model([
            "<<<CICADA_CARD>>>\nSAY:\nI'll keep the messages in a StateFlow. The ViewModel owns it.\nTYPE: add at=\"ChatViewModel\"\n```kotlin\nval messages = MutableStateFlow(emptyList<Message>())\n```\nCASE: []",
            "<<<CICADA_CARD>>>\nSAY:\nNext, the UI collects that state.\nCASE: [{\"op\":\"implemented\",\"text\":\"messages StateFlow\",\"evidence\":[\"B1\"]}]",
        ])
        let engine = coach(model)
        defer { engine.endMeeting() }
        engine.observe(lines: [line("q", "them", "Write the ViewModel state.")], now: 0)
        for t in stride(from: 0.0, through: 4, by: 0.5) { engine.tick(now: t) }
        await settle(engine)
        #expect(engine.cards.card?.edit?.at == "ChatViewModel")
        #expect(engine.cards.phase == .say)
        // The candidate types it; once the board settles and shows the step, the next card is asked for.
        engine.picture(CoachFrame(jpeg: Data(), seconds: 5, ocr: "class ChatViewModel {\nval messages = MutableStateFlow(emptyList<Message>())\n}"))
        for t in stride(from: 5.0, through: 9, by: 0.5) { engine.tick(now: t) }
        await settle(engine)
        #expect(model.asked.count == 2)
        #expect(text(model.asked[1]).contains("Trigger: board"))
        #expect(text(model.asked[1]).contains("MutableStateFlow"))
        #expect(engine.cards.say == "Next, the UI collects that state.")
        #expect(engine.cards.memory.problem == nil)   // no problem was opened, so nothing to mark implemented
    }

    @Test @MainActor func aNewQuestionCancelsTheRunningCardButCandidateSpeechDoesNot() async throws {
        let gate = AsyncStream<Void>.makeStream()
        var calls = 0
        let engine = InterviewCoach { _, _ in
            calls += 1
            let n = calls
            return AsyncThrowingStream { continuation in
                Task {
                    if n == 1 { for await _ in gate.stream { break } }
                    continuation.yield("<<<CICADA_CARD>>>\nSAY:\nAnswer \(n).\nCASE: []")
                    continuation.finish()
                }
            }
        }
        engine.gloss.enabled = false; engine.cardsEnabled = true
        engine.start(background: "", available: true, prepare: { true })
        defer { engine.endMeeting() }
        engine.observe(lines: [line("q1", "them", "Explain the Bundle.")], now: 0)
        for t in stride(from: 0.0, through: 4, by: 0.5) { engine.tick(now: t) }
        for _ in 0..<50 { await Task.yield() }
        #expect(engine.cards.busy)
        engine.observe(lines: [line("q1", "them", "Explain the Bundle."), line("m1", "me", "A Bundle holds key value pairs.", t: 5)], now: 5)
        for _ in 0..<50 { await Task.yield() }
        #expect(calls == 1)
        engine.observe(lines: [line("q1", "them", "Explain the Bundle."), line("m1", "me", "A Bundle holds key value pairs.", t: 5),
                               line("q2", "them", "Actually, explain onSaveInstanceState instead.", t: 6)], now: 6)
        for t in stride(from: 6.0, through: 10, by: 0.5) { engine.tick(now: t) }
        await settle(engine)
        gate.continuation.finish()
        await settle(engine)
        #expect(calls == 2)
        #expect(engine.cards.card?.say == "Answer 2.")
    }

    @Test @MainActor func followUpDraftsAreHintsAndAnyTriggerCancelsThem() async throws {
        let model = Model(["<<<CICADA_CARD>>>\nSAY:\nFirst, the scope.\nCASE: []",
                           "Q: Why StateFlow?\nA: It always has a value.",
                           "<<<CICADA_CARD>>>\nSAY:\nIt always holds the latest state.\nCASE: []"])
        let engine = coach(model)
        engine.cards.preparesFollowUps = true
        defer { engine.endMeeting() }
        engine.observe(lines: [line("q", "them", "Design the chat screen.")], now: 0)
        for t in stride(from: 0.0, through: 4, by: 0.5) { engine.tick(now: t) }
        await settle(engine)
        for t in stride(from: 4.0, through: 14, by: 0.5) { engine.tick(now: t) }
        for _ in 0..<200 where engine.cards.prepared.isEmpty { await Task.yield() }
        #expect(engine.cards.prepared.contains("Why StateFlow?"))
        // The drafts reach the next request only as marked predictions, never as the card itself.
        engine.observe(lines: [line("q", "them", "Design the chat screen."), line("q2", "them", "Why StateFlow?", t: 15)], now: 15)
        for t in stride(from: 15.0, through: 19, by: 0.5) { engine.tick(now: t) }
        await settle(engine)
        #expect(text(model.asked[2]).contains("predictions, NOT questions anyone asked"))
        #expect(engine.cards.card?.say == "It always holds the latest state.")
        #expect(engine.cards.prepared.isEmpty)
    }

    @Test @MainActor func aCheckedCardDropsWhatTheCandidateAlreadySaid() async throws {
        // AC-13: the draft restates the candidate; the focused edit's reply is what reaches the script.
        let model = Model(["<<<CICADA_CARD>>>\nSAY:\nA ViewModel survives rotation.\nCASE: []",
                           "<<<CICADA_CARD>>>\nSAY:\nThe store is kept across rotation. Process death is different, so I'd use SavedStateHandle.\nCASE: []",
                           "Process death is different, so I'd use SavedStateHandle."])
        let engine = coach(model)
        defer { engine.endMeeting() }
        engine.observe(lines: [line("q", "them", "How does a ViewModel survive rotation?")], now: 0)
        for t in stride(from: 0.0, through: 4, by: 0.5) { engine.tick(now: t) }
        await settle(engine)
        engine.observe(lines: [line("q", "them", "How does a ViewModel survive rotation?"),
                               line("m", "me", "It lives in the ViewModelStore, which is kept across rotation.", t: 5)], now: 5)
        // Their own words (the reading cursor did not move) ask for a check of the card.
        for t in stride(from: 5.0, through: 7, by: 0.5) { engine.tick(now: t) }
        await settle(engine)
        #expect(model.asked.count == 3)
        #expect(text(model.asked[2]).contains("ALREADY said"))
        #expect(engine.cards.card?.say == "Process death is different, so I'd use SavedStateHandle.")
    }

    @Test @MainActor func aPlainNewQuestionOrGoingBackIsRecordedEvenWhenTheModelForgets() {
        var memory = CoachCase()
        memory.apply([CoachCaseOp(op: "newProblem", text: "Design an image loading library", id: "img")],
                     evidence: CoachEvidence(), at: 0)
        let pause = CoachTurn(id: "t2", seconds: 5, role: "interviewer", text: "Let's pause that. New question: Service or WorkManager?")
        let ops = CoachCards.missingProblemOps([], newLines: [pause], memory: memory)
        #expect(ops.first?.op == "newProblem")
        memory.apply(ops, evidence: CoachEvidence(interviewer: ["t2"]), at: 5)
        #expect(memory.problems.count == 2)
        let back = CoachTurn(id: "t3", seconds: 9, role: "interviewer", text: "Good. Now let's go back to the image loading library.")
        let ops2 = CoachCards.missingProblemOps([], newLines: [back], memory: memory)
        #expect(ops2 == [CoachCaseOp(op: "switch", id: "img", evidence: ["t3"])])
        // The model already recorded it: nothing is added.
        #expect(CoachCards.missingProblemOps([CoachCaseOp(op: "switch", id: "img")], newLines: [back], memory: memory).isEmpty)
        #expect(CoachCards.missingProblemOps([], newLines: [CoachTurn(id: "t4", seconds: 9, role: "interviewer", text: "Why StateFlow?")], memory: memory).isEmpty)
    }

    @Test @MainActor func theLiveAC10SequenceKeepsBothProblems() {
        // Recorded live: the first card was cancelled by the second question, the model then pushed the first
        // question as an aside, and later "went back" with an unknown id plus a duplicate newProblem.
        let design = CoachTurn(id: "t18", seconds: 0, role: "interviewer", text: "Design an image loading library for Android.")
        let pause = CoachTurn(id: "t19", seconds: 8, role: "interviewer", text: "Let's pause that. New question: what is the difference between a Service and a WorkManager job?")
        let back = CoachTurn(id: "t20", seconds: 14, role: "interviewer", text: "Good. Now let's go back to the image loading library.")
        let evidence = CoachEvidence(interviewer: ["t18", "t19", "t20"])
        var memory = CoachCase()
        var ops = [CoachCaseOp(op: "pushAside", text: "Design an image loading library for Android"),
                   CoachCaseOp(op: "newProblem", text: "Difference between a Service and a WorkManager job", id: "service-vs-workmanager")]
        memory.apply(CoachCards.missingProblemOps(ops, newLines: [design, pause], memory: memory) + ops, evidence: evidence, at: 8)
        #expect(memory.problems.count == 2)
        #expect(memory.problem?.id == "service-vs-workmanager")
        ops = [CoachCaseOp(op: "switch", text: "Design an image loading library for Android", id: "image-loading-library", evidence: ["t18", "t20"]),
               CoachCaseOp(op: "popAside", evidence: ["t20"]),
               CoachCaseOp(op: "newProblem", text: "Design an image loading library for Android", id: "image-loading-library", evidence: ["t18", "t20"])]
        memory.apply(CoachCards.missingProblemOps(ops, newLines: [back], memory: memory) + ops, evidence: evidence, at: 14)
        #expect(memory.problems.count == 2)
        #expect(memory.problem?.goal.hasPrefix("Design an image loading library") == true)
    }

    @Test @MainActor func aCopiedCardForANewQuestionIsRetriedWithTheQuestionNamed() async throws {
        // Seen in the newsfeed run: asked about the API, DeepSeek repeated the offline card word for word.
        let offline = "<<<CICADA_CARD>>>\nSAY:\nGot it, so the feed has to work offline too. I'd keep a local copy of the feed.\nCASE: []"
        let model = Model([offline, offline, "<<<CICADA_CARD>>>\nSAY:\nFor the API I'd use REST with a cursor for paging.\nCASE: []"])
        let engine = coach(model)
        defer { engine.endMeeting() }
        engine.observe(lines: [line("t4", "them", "Users should still see the feed when offline.")], now: 0)
        for t in stride(from: 0.0, through: 4, by: 0.5) { engine.tick(now: t) }
        await settle(engine)
        engine.observe(lines: [line("t4", "them", "Users should still see the feed when offline."),
                               line("t5", "them", "Okay. Let's talk about the API between the app and the backend.", t: 5)], now: 5)
        for t in stride(from: 5.0, through: 9, by: 0.5) { engine.tick(now: t) }
        await settle(engine)
        #expect(model.asked.count == 3)
        #expect(text(model.asked[2]).contains("Your draft repeated the card already shown"))
        #expect(engine.cards.card?.say == "For the API I'd use REST with a cursor for paging.")
        #expect(engine.cards.past.map(\.card.say) == ["Got it, so the feed has to work offline too. I'd keep a local copy of the feed."])
    }

    @Test func echoesOfTheInterviewerAndUnfoundedCoverageAreDropped() {
        // Seen in the newsfeed run, step 2.
        let line = "Good questions. Posts can be text, images or video. Show like and comment counts, and tapping a comment opens the detail screen. Assume about 100 million daily users, globally."
        let say = "Got it. So the feed mixes text, image and video posts, and each one shows like and comment counts. Tapping a comment opens the detail screen. With that scale I'd cache the feed on the phone and load thumbnails lazily."
        #expect(CoachCards.withoutRecital(say, of: line) == "Got it. With that scale I'd cache the feed on the phone and load thumbnails lazily.")
        // Seen in the newsfeed run: the card's own point marked as spoken, citing an unrelated candidate line.
        var memory = CoachCase()
        let evidence = CoachEvidence(candidate: ["m3"], candidateText: ["m3": "Okay, so we need an infinite scrolling feed with text, image and video posts."])
        memory.apply([CoachCaseOp(op: "newProblem", text: "News feed"),
                      CoachCaseOp(op: "spoken", text: "Each like carries an ID so a retry doesn't count twice", evidence: ["m3"]),
                      CoachCaseOp(op: "spoken", text: "Infinite scrolling feed with mixed posts", evidence: ["m3"])], evidence: evidence, at: 0)
        #expect(memory.problem?.spoken == ["Infinite scrolling feed with mixed posts"])
    }

    @Test func decisionsAndSwitchAnnouncementsAreRecognised() {
        #expect(CoachCards.decidedApproach("I'd rather not use RxJava here. Let's switch this to Kotlin Flow.") == "Kotlin Flow")
        #expect(CoachCards.decidedApproach("Actually, switch to Kotlin Flow.") == "Kotlin Flow")
        #expect(CoachCards.decidedApproach("Use Paging 3 instead.") == "Paging 3")
        #expect(CoachCards.decidedApproach("Please replace RxJava with Kotlin Flow.") == "Kotlin Flow")
        #expect(CoachCards.decidedApproach("Don't replace RxJava with Flow.") == nil)
        #expect(CoachCards.decidedApproach("Hmm, could we use Flow here instead?") == nil)
        #expect(CoachCards.decidedApproach("Can you write the ViewModel?") == nil)
        #expect(CoachCards.announcesSwitch(CoachCard(say: "Yes, Flow fits better here. With Flow I can collect in viewModelScope.")))
        #expect(CoachCards.announcesSwitch(CoachCard(say: "Okay.", edit: .init(action: "replace", at: "load()", code: "flow {}"))))
        #expect(!CoachCards.announcesSwitch(CoachCard(say: "Both work. Flow ties into coroutines; RxJava is already here. Do you want me to switch?")))
    }

    @Test func aLongCardKeepsFiveSentencesAndItsClosingQuestion() {
        let long = "One. Two. Three. Four. Five. Six. Seven. Does that direction sound right?"
        #expect(CoachCards.capped(long) == "One. Two. Three. Four. Does that direction sound right?")
        #expect(CoachCards.capped("One. Two. Three. Four. Five. Six.") == "One. Two. Three. Four. Five.")
        #expect(CoachCards.capped("Short. Card.") == "Short. Card.")
    }

    @Test func aSubtaskOfTheCurrentProblemIsNotANewProblem() {
        var memory = CoachCase()
        memory.apply([CoachCaseOp(op: "newProblem", text: "Design a ChatGPT-style chat screen on Android")], evidence: CoachEvidence(), at: 0)
        let viewModel = [CoachCaseOp(op: "newProblem", text: "Write the ViewModel that holds the chat message list", id: "chat-viewmodel")]
        let write = CoachTurn(id: "t19", seconds: 8, role: "interviewer", text: "Okay, can you write the ViewModel that holds the message list?")
        #expect(CoachCards.withoutSubtaskProblems(viewModel, newLines: [write], memory: memory).isEmpty)
        // A plainly new question stays new.
        let service = [CoachCaseOp(op: "newProblem", text: "Service versus WorkManager")]
        let pause = CoachTurn(id: "t20", seconds: 9, role: "interviewer", text: "Let's pause that. New question: Service or WorkManager?")
        #expect(CoachCards.withoutSubtaskProblems(service, newLines: [pause], memory: memory) == service)
        let unrelated = CoachTurn(id: "t21", seconds: 9, role: "interviewer", text: "Explain coroutine cancellation.")
        let coroutines = [CoachCaseOp(op: "newProblem", text: "Coroutine cancellation")]
        #expect(CoachCards.withoutSubtaskProblems(coroutines, newLines: [unrelated], memory: memory) == coroutines)
    }

    /// ME-08: a new problem that shares a word ("cache") with the current one is still a new problem,
    /// and is recorded even when the card's CASE forgot it.
    @Test func aNamedNewProblemIsNotMergedIntoASimilarOne() {
        var memory = CoachCase()
        memory.apply([CoachCaseOp(op: "newProblem", text: "Feed cache for the Android news feed", evidence: ["t1"])],
                     evidence: CoachEvidence(interviewer: ["t1"]), at: 0)
        let line = CoachTurn(id: "t2", seconds: 5, role: "interviewer", text: "This is a new problem: design the chat message cache. Keep the last 30 days of messages.")
        let chat = [CoachCaseOp(op: "newProblem", text: "Chat message cache")]
        #expect(CoachCards.withoutSubtaskProblems(chat, newLines: [line], memory: memory) == chat)
        #expect(CoachCards.missingProblemOps([], newLines: [line], memory: memory).first?.op == "newProblem")
        let aside = CoachTurn(id: "t3", seconds: 6, role: "interviewer", text: "Another problem with that cache is memory pressure, right?")
        #expect(CoachCards.missingProblemOps([], newLines: [aside], memory: memory).isEmpty)
    }

    /// NF-05, ME-10: explaining the board or a reference gets no code to type.
    @Test @MainActor func anExplainRequestGetsNoCode() async throws {
        let reply = "<<<CICADA_CARD>>>\nSAY:\nThe feed call takes a cursor.\nTYPE: add at=\"API\"\n```\nGET /v1/feed?cursor=x\n```\nCASE: []"
        let engine = coach(Model([reply]))
        defer { engine.endMeeting() }
        engine.picture(CoachFrame(jpeg: Data(), seconds: 0, ocr: "GET /v1/feed?cursor=abc"))
        engine.observe(lines: [line("q", "them", "Walk me through the API on the board.")], now: 0)
        for t in stride(from: 0.0, through: 4, by: 0.5) { engine.tick(now: t) }
        await settle(engine)
        #expect(engine.cards.card?.say == "The feed call takes a cursor.")
        #expect(engine.cards.card?.edit == nil)
    }

    /// ME-03: naming what is still missing is not a point already made.
    @Test func notCoveredYetIsNotAPointMade() {
        #expect(CoachCards.saysNotCovered("I have not explained the data flow yet."))
        #expect(CoachCards.saysNotCovered("We haven't talked about caching."))
        #expect(!CoachCards.saysNotCovered("The repository writes remote results to the local database."))
        #expect(!CoachCards.saysNotCovered("I did not use RxJava here because Flow is simpler."))
    }

    /// CH-06: "add another one" names nothing to add.
    @Test func unnamedAdditionsAreUnresolved() {
        #expect(CoachCards.unresolvedReference("Add another one after it."))
        #expect(CoachCards.unresolvedReference("Can you add one more here?"))
        #expect(!CoachCards.unresolvedReference("Add another field after isLoading."))
        #expect(!CoachCards.unresolvedReference("Add an optional errorMessage string to this UI state."))
    }

    /// CH-06: a card that guesses what to add is retried for a clarifying question and loses its TYPE.
    @Test @MainActor func anUnresolvedAdditionAsksInsteadOfTyping() async throws {
        let guess = "<<<CICADA_CARD>>>\nSAY:\nOkay, I'll add one more item.\nTYPE: replace at=\"items\"\n```kotlin\nval items = listOf(\"a\", \"b\", \"c\")\n```\nCASE: []"
        let model = Model([guess, "<<<CICADA_CARD>>>\nSAY:\nAnother variable, item or function?\nCASE: []"])
        let engine = coach(model)
        defer { engine.endMeeting() }
        engine.observe(lines: [line("q", "them", "Add another one after it.")], now: 0)
        for t in stride(from: 0.0, through: 4, by: 0.5) { engine.tick(now: t) }
        await settle(engine)
        #expect(engine.cards.card?.say == "Another variable, item or function?")
        #expect(engine.cards.card?.edit == nil)
        #expect(model.asked.count == 2)
    }

    @Test func helpers() {
        var script = CoachScript(modelReading: true)
        script.replacePending("One two three. Four five.", since: [], newAnswer: true)
        #expect(CoachCards.atSentenceStart(script))
        script.advanceReading(to: 2, answerID: script.answerID)
        #expect(!CoachCards.atSentenceStart(script))
        script.advanceReading(to: 3, answerID: script.answerID)
        #expect(CoachCards.atSentenceStart(script))
        script.advanceReading(to: 5, answerID: script.answerID)
        #expect(CoachCards.finishedReading(script))
        #expect(CoachCards.coverage(of: "val messages = MutableStateFlow(emptyList<Message>())", in: ["val messages = MutableStateFlow(emptyList<Message>())"]) == 1)
        #expect(CoachCards.coverage(of: "fun retry(id: String)", in: ["something else"]) == 0)
        #expect(CoachCards.asksToExplain("Can you walk me through this architecture, starting from the UI?"))
        #expect(!CoachCards.asksToExplain("Can you draw the data layer under it?"))
        #expect(!CoachCards.asksToExplain("Explain it and add the cache box."))
    }

    /// RT-08: a new meeting starts its reading cursor at zero; the cursor left from the last meeting must not
    /// stop the candidate's first own-words line in the new one from checking the card.
    @Test @MainActor func aNewMeetingChecksTheFirstOwnWordsLine() async throws {
        let model = Model(Array(repeating: "<<<CICADA_CARD>>>\nSAY:\nOne two three.\nCASE: []", count: 4))
        let cards = CoachCards { messages, name in model.stream(messages, name) }
        var script = CoachScript()
        cards.input = { .init(turns: [], background: "", frames: [], script: script, stage: .general) }
        func settle() async { for _ in 0..<2000 where cards.busy { await Task.yield() }; for _ in 0..<50 { await Task.yield() } }
        cards.receive(.manual, now: 1); await settle()
        script.replacePending("One two three.", since: [])
        script.commit(id: "c1", text: "One two three")
        #expect(script.cursor == 3)
        cards.candidateSpoke(script, now: 2); await settle()
        cards.reset()
        script = CoachScript()
        cards.receive(.manual, now: 1); await settle()
        let before = cards.requests
        script.replacePending("One two three.", since: [])
        script.commit(id: "c2", text: "I would cache the posts in Room first")
        cards.candidateSpoke(script, now: 2)
        #expect(cards.requests == before + 1)
    }
}

private extension CoachCards { var say: String? { card?.say } }
