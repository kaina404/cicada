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

    /// "Draw the flow" with an empty screen gets the whole diagram as a picture; a concept question does not.
    @Test @MainActor func aRequestedDiagramIsKeptWithoutAWhiteboardAndDrawnOnceComplete() async throws {
        let reply = { (heard: String, say: String) in """
        <<<CICADA_CARD>>>
        HEARD: \(heard)
        SAY:
        \(say)
        TYPE: draw at="new diagram"
        ```mermaid
        flowchart LR
          UI[Feed UI] --> VM[ViewModel]
          VM --> Repo[Repository]
          Repo --> Cache[(Room cache)]
          Repo --> API[Feed API]
        ```
        THEN: Wait for the interviewer.
        """ }
        let model = Model([reply("draw the flow", "The app asks the repository, which checks the cache first and falls back to the API."),
                           reply("what is a repository", "A repository hides where the data comes from behind one interface.")])
        let engine = coach(model)
        defer { engine.endMeeting() }
        engine.observe(lines: [line("q", "them", "Can you draw the data flow for loading the feed?")], now: 0)
        for t in stride(from: 0.0, through: 4, by: 0.5) { engine.tick(now: t) }
        await settle(engine)
        let edit = try #require(engine.cards.card?.edit)
        #expect(edit.action == "draw" && edit.isDiagram && edit.closed)
        #expect(edit.code.hasPrefix("flowchart LR"))
        #expect(edit.diagramSource.hasPrefix("flowchart TD\n  UI[Feed UI] --> VM[ViewModel]"))
        #expect(text(model.asked[0]).contains("```mermaid"))

        engine.observe(lines: [line("q2", "them", "What is a repository in this design?", t: 10)], now: 10)
        for t in stride(from: 10.0, through: 14, by: 0.5) { engine.tick(now: t) }
        await settle(engine)
        #expect(engine.cards.card?.heard == "what is a repository")
        #expect(engine.cards.card?.edit == nil)
    }

    @Test func aStreamingDiagramStaysTextUntilItsFenceCloses() throws {
        let head = "<<<CICADA_CARD>>>\nSAY: The client calls the API.\nTYPE: draw at=\"new\"\n```mermaid\nsequenceDiagram\n  App->>API: GET /feed\n"
        let partial = try #require(try CoachCard.parse(head, finished: false))
        #expect(partial.edit?.isDiagram == true && partial.edit?.closed == false)
        let done = try #require(try CoachCard.parse(head + "  API-->>App: items\n```\nTHEN: Wait for the interviewer.", finished: true))
        #expect(done.edit?.closed == true)
        #expect(done.edit?.code == "sequenceDiagram\n  App->>API: GET /feed\n  API-->>App: items")
        #expect(CoachCards.asksToDraw("Sketch the sequence for a login."))
        #expect(CoachCards.asksToDraw("Show me a flowchart of the upload."))
        #expect(!CoachCards.asksToDraw("What happens on process death?"))
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

    @Test func aScopeCheckOnANewProblemKeepsItsReadBack() {
        // Seen in the 40-minute run, D-01: the problem statement ends without "?", so the echo filter removed the
        // scope itself and left "Before I design, let me check the scope. Is that right?".
        let line = "Great. For the rest of the time, a new problem: design the Android app for ChatGPT. Users chat with the AI and see answers stream in. They can stop or regenerate an answer, upload a photo, use voice mode, and see their history on phone and web. Focus on the client. Tell me what you need from the backend."
        var card = CoachCard()
        card.say = "Before I design, let me check the scope. Users chat with the AI and see answers stream in, with stop and regenerate. Photo upload, voice mode and history on phone and web are also in. Is that right?"
        #expect(CoachCards.checksNewProblem(card, line: line))
        card.ops = [CoachCaseOp(op: "newProblem", text: "ChatGPT Android client")]
        #expect(CoachCards.checksNewProblem(card, line: "Design the Android app for ChatGPT. Focus on the client."))
        // Plain new requirements are still not read back (the newsfeed run, step 2).
        #expect(!CoachCards.checksNewProblem(CoachCard(), line: "Posts can be text, images or video. Assume about 100 million daily users."))
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

    // The 40-minute run, O-01: "two minutes" about yourself got a five-sentence card, about 30 seconds.
    @Test func aSelfIntroductionGetsALongerCard() {
        #expect(CoachCards.sentenceLimit(for: "Let's start easy: tell me about yourself in two minutes.") == CoachCards.introductionLimit)
        #expect(CoachCards.sentenceLimit(for: "Could you give us a short introduction?") == CoachCards.introductionLimit)
        #expect(CoachCards.sentenceLimit(for: "Give me an introduction to SSE.") == CoachCards.sentenceLimit)
        #expect(CoachCards.sentenceLimit(for: "Tell me about a device-specific bug.") == CoachCards.sentenceLimit)
        #expect(CoachCards.sentenceLimit(for: "What is the introduction of Compose about?") == CoachCards.sentenceLimit)
        let intro = (1...16).map { "Sentence \($0)." }.joined(separator: " ")
        var card = CoachCard(say: intro)
        #expect(CoachScript.sentences(CoachCards.spoken(card)).count == CoachCards.sentenceLimit)
        card.sentenceLimit = CoachCards.introductionLimit
        #expect(CoachScript.sentences(CoachCards.spoken(card)).count == CoachCards.introductionLimit)
    }

    // The 40-minute runs, D-06 / D-13 / D-14: the decision and the Android points are repeated last.
    @Test func theFocusHintRepeatsTheDecisionAndAndroidVoicePoints() {
        var memory = CoachCase()
        memory.apply([CoachCaseOp(op: "newProblem", text: "Design the ChatGPT Android app", evidence: ["t1"]),
                      CoachCaseOp(op: "adopt", text: "Room is the single source of truth.", evidence: ["m2"])],
                     evidence: CoachEvidence(interviewer: ["t1"], candidate: ["m2"]), at: 0)
        let tokens = CoachCardPrompt.focusHint(memory: memory, latest: "Tokens arrive 50 times a second. How do you update the UI?")
        #expect(tokens?.contains("Room is the single source of truth.") == true)
        #expect(tokens?.contains("foreground service") == false)
        let call = CoachCardPrompt.focusHint(memory: CoachCase(), latest: "A phone call comes in during voice mode. What happens?")
        #expect(call?.contains("foreground service of type microphone") == true)
        #expect(CoachCardPrompt.focusHint(memory: CoachCase(), latest: "How do you test it?") == nil)
    }

    // Wallet run 2026-11-19: cents, the atomic ledger, idempotent replay, server-side authorization,
    // stale-session callbacks and the pre-release checks were missed.
    @Test func theFocusHintCarriesMoneyAccountAndReleasePoints() {
        var wallet = CoachCase()
        wallet.apply([CoachCaseOp(op: "newProblem", text: "Design a mobile wallet", evidence: ["t1"])],
                     evidence: CoachEvidence(interviewer: ["t1"]), at: 0)
        let chat = CoachCardPrompt.focusHint(memory: wallet, latest: "Now the pilot must also start from a group chat. Two contacts are called Alex.")
        #expect(chat?.contains("8000 cents") == true)
        #expect(chat?.contains("never authorizes") == true)
        #expect(chat?.contains("Release answer") == false)
        let money = CoachCardPrompt.focusHint(memory: CoachCase(), latest: "A has 100 dollars. Walk me through sending B 80.")
        #expect(money?.contains("ONE database transaction") == true)
        let account = CoachCardPrompt.focusHint(memory: CoachCase(), latest: "While the request is in flight the user switches to account C. What goes wrong?")
        #expect(account?.contains("session generation") == true)
        #expect(account?.contains("Money points") == false)
        #expect(money?.contains("does not prove no money moved") == true)
        let close = CoachCardPrompt.focusHint(memory: wallet, latest: "That's it from me. What questions do you have for me about the team or the role?")
        #expect(close?.contains("Money points") == false)
        #expect(close?.contains("opens a new question") == true)
        let release = CoachCardPrompt.focusHint(memory: CoachCase(), latest: "You have two weeks. What's in the first version and how do you roll it out?")
        #expect(release?.contains("pre-release checks") == true)
    }

    // Wallet run 6, 2026-11-19: "Back to the first transfer" inside the wallet design went to a resume question.
    @Test func goingBackWithinTheDesignDoesNotSwitchToAnOldQuestion() {
        var memory = CoachCase()
        memory.apply([CoachCaseOp(op: "newProblem", text: "Tell about a delivery risk: what you did and when", id: "risk")], evidence: CoachEvidence(), at: 0)
        memory.apply([CoachCaseOp(op: "newProblem", text: "Design a mobile wallet: transfer, ledger, failures", id: "wallet")], evidence: CoachEvidence(), at: 1)
        let back = CoachTurn(id: "t40", seconds: 40, role: "interviewer", text: "Back to the first transfer. While the request is in flight the user switches to account C. What could go wrong?")
        #expect(CoachCards.missingProblemOps([], newLines: [back], memory: memory).isEmpty)
        let risk = CoachTurn(id: "t41", seconds: 41, role: "interviewer", text: "Let's go back to the delivery risk you mentioned. What happened next?")
        #expect(CoachCards.missingProblemOps([], newLines: [risk], memory: memory).first?.id == "risk")
    }

    // Wallet rerun 2026-11-19: an imperative request without "?" got a one-sentence acknowledgement.
    @Test func anImperativeRequestIsAQuestionNotInformation() {
        #expect(CoachCardPrompt.asks("Draw the client, the server and local storage as a flowchart, and tell me what each part owns."))
        #expect(CoachCardPrompt.asks("Why StateFlow there?"))
        #expect(!CoachCardPrompt.asks("Users are signed in. Cached reads work offline; submitting money needs the network."))
    }

    // Founder runs 2026-11-18/19: a second, different diagram stayed inside the first diagram's problem.
    @Test func aDifferentDiagramOpensANewProblem() {
        var memory = CoachCase()
        memory.apply([CoachCaseOp(op: "newProblem", text: "Draw a flowchart of a chat message", evidence: ["t1"])],
                     evidence: CoachEvidence(interviewer: ["t1"]), at: 0)
        let login = CoachTurn(id: "t9", seconds: 90, role: "interviewer", text: "Good. Now a different one: draw me a sequence diagram of login.")
        let ops = CoachCards.missingProblemOps([CoachCaseOp(op: "implemented", text: "Login drawn")], newLines: [login], memory: memory)
        #expect(ops.first?.op == "newProblem")
        let drop = CoachTurn(id: "t5", seconds: 60, role: "interviewer", text: "What happens if the network drops? Add it to the diagram.")
        #expect(CoachCards.missingProblemOps([], newLines: [drop], memory: memory).isEmpty)
        #expect(CoachCardPrompt.rules.contains("different diagram of another flow"))
    }

    // The 40-minute run, P2-7: "Do you have any questions for me?" stayed under the two-week trade-off.
    @Test func questionsForTheInterviewerOpenANewProblem() {
        var memory = CoachCase()
        memory.apply([CoachCaseOp(op: "newProblem", text: "Design the ChatGPT Android app")], evidence: CoachEvidence(), at: 0)
        let line = CoachTurn(id: "t90", seconds: 9, role: "interviewer", text: "Okay, we're almost out of time. Do you have any questions for me?")
        #expect(CoachCards.missingProblemOps([], newLines: [line], memory: memory).map(\.op) == ["newProblem"])
        let design = CoachTurn(id: "t92", seconds: 11, role: "interviewer", text: "Let's switch to the design exercise. Design a mobile wallet from scratch.")
        #expect(CoachCards.missingProblemOps([], newLines: [design], memory: memory).map(\.op) == ["newProblem"])
        // Wallet rerun 2026-11-19: this wording stayed under the release question.
        let what = CoachTurn(id: "t91", seconds: 10, role: "interviewer", text: "That's it from me. What questions do you have for me about the team or the role?")
        #expect(CoachCards.missingProblemOps([], newLines: [what], memory: memory).map(\.op) == ["newProblem"])
    }

    /// Wallet run 2026-11-19 03:45 under the strict judge: parts of multi-part questions were dropped (P2, W1),
    /// W4 named no locking, W7 had no checks and no resume.
    @Test func multiPartQuestionsAndWalletNotesNameEveryPart() {
        let alt = CoachCardPrompt.questionParts("What other options did you have, why didn't you pick them, and after release how did you know the change worked?")
        #expect(alt.count == 3)
        #expect(alt.last?.hasPrefix("after release how") == true)
        #expect(CoachCardPrompt.questionParts("Separate scenario. A still has 100 dollars. What happens to each one and what do the phones show?")
            == ["What happens to each one", "what do the phones show"])
        #expect(CoachCardPrompt.questionParts("How do you test it?").count == 1)
        let risk = "Tell me about a time the team disagreed. When did you tell whom, how many options did you give, who decided, and what did you finish yourself?"
        #expect(CoachCards.sentenceLimit(for: risk) == CoachCards.storyLimit)
        #expect(CoachCards.sentenceLimit(for: "When did you tell whom, how many options did you give, who decided?") == 6)
        #expect(CoachCards.sentenceLimit(for: "How do you test it?") == CoachCards.sentenceLimit)
        #expect(CoachCards.sentenceLimit(for: "Start by clarifying the requirements. Which user path would you define as the MVP?") == 6)
        // Real recognition ended the question with a full stop.
        #expect(CoachCards.sentenceLimit(for: "The system behind it and how it handles failures. Start by clarifying the requirements. Which user path would you define as the MVP.") == 6)
        #expect(CoachCardPrompt.questionParts("What other options did you have. Why didn't you pick them. And after release, how did you know the change worked.").count == 3)
        #expect(CoachCardPrompt.questionParts("Draw the client and tell me what each part owns.").isEmpty)
        let hint = CoachCardPrompt.focusHint(memory: CoachCase(), latest: "What other options did you have, why didn't you pick them, and after release how did you know the change worked?") ?? ""
        #expect(hint.contains("asks 3 things"))
        #expect(hint.contains("one limit of it"))
        #expect(CoachCardPrompt.focusHint(memory: CoachCase(), latest: "Tell me about a time you saw a delivery risk and the team disagreed.")?.contains("name the company") == true)
        let scope = CoachCardPrompt.focusHint(memory: CoachCase(), latest: "Design a mobile wallet from scratch. Start by clarifying the requirements. Which user path would you define as the MVP?") ?? ""
        #expect(scope.contains("propose one MVP path"))
        #expect(scope.contains("currencies"))
        let race = CoachCardPrompt.focusHint(memory: CoachCase(), latest: "On two phones A approves two 80 dollar transfers at almost the same time. What happens?") ?? ""
        #expect(race.contains("conditional update"))
        let release = CoachCardPrompt.focusHint(memory: CoachCase(), latest: "What's in the first version, who signs off, and if transfers spike during the rollout, what do you do?") ?? ""
        #expect(release.contains("replay of the same ID"))
        #expect(release.contains("condition to resume"))
    }

    @Test func aShortMisheardLineDoesNotReplaceTheRequestBeforeIt() {
        let draw = CoachTurn(id: "t1", seconds: 0, role: "interviewer", text: "Draw the client, the server and local storage as a flowchart, and tell me what each part owns.")
        let noise = CoachTurn(id: "t2", seconds: 9, role: "interviewer", text: "Who do you remote?")
        #expect(CoachCardPrompt.misheardNote([draw, noise])?.contains("Draw the client") == true)
        #expect(CoachCardPrompt.misheardNote([noise]) == nil)
        #expect(CoachCardPrompt.misheardNote([noise, draw]) == nil)
    }

    @Test func sentencesAlreadyReadAreDroppedFromTheNextCard() {
        let said = ["The server checks and debits A in one transaction, with a row lock on A's balance or a conditional update.",
                    "The second finds only 20 dollars left, so it fails cleanly and B stays at 80."]
        let next = "The second request is rejected, because the balance check and the debit happen in one transaction. The second finds only 20 dollars left, so it fails and B stays at 80. Each request carries its own client transfer ID, so they are two intents."
        let kept = CoachCards.withoutSaid(next, said: said)
        #expect(!kept.contains("only 20 dollars left"))
        #expect(kept.contains("own client transfer ID"))
        #expect(CoachCards.withoutSaid("The second finds only 20 dollars left, so it fails cleanly and B stays at 80.", said: said).isEmpty)
    }

    @Test func aQuestionCutByRecognitionIsReadAsOneTurn() {
        let lines = [CoachTurn(id: "c1", seconds: 0, role: "candidate", text: "That's the account switch."),
                     CoachTurn(id: "t1", seconds: 1, role: "interviewer", text: "You have two weeks, and log in plus a usable ledger already exist."),
                     CoachTurn(id: "t2", seconds: 4, role: "interviewer", text: "What's in the first version? Who signs off? And if transfers suddenly spike during the rollout, what do you?"),
                     CoachTurn(id: "t3", seconds: 9, role: "interviewer", text: "Do in the next half hour.")]
        let turn = CoachCardPrompt.interviewerTurn(lines) ?? ""
        #expect(turn.hasPrefix("You have two weeks") && turn.hasSuffix("half hour."))
        #expect(CoachCardPrompt.focusHint(memory: CoachCase(), latest: turn)?.contains("Release answer") == true)
        #expect(CoachCards.sentenceLimit(for: turn) >= 6)
        #expect(CoachCards.sentenceLimit(for: "You have two weeks, and log in plus a usable ledger already exist. What? In the first version, who signs off, and if transfers suddenly spike during the rollout, what do you do in the next half hour? The.") >= 6)
        #expect(CoachCardPrompt.finishesShownQuestion(lines, newLines: [lines[3]]))
        #expect(!CoachCardPrompt.finishesShownQuestion(lines, newLines: Array(lines[1...])))
        let reading = lines + [CoachTurn(id: "c2", seconds: 12, role: "candidate", text: "For the first version, I'd ship balance and transfer.")]
        #expect(CoachCardPrompt.interviewerTurn(reading) == turn)
        // A draw request cut before "tell me what each part owns" is still a draw request.
        let cut = [CoachTurn(id: "t4", seconds: 20, role: "interviewer", text: "Has one hundred dollars, and B has zero. Draw the client, the server,"),
                   CoachTurn(id: "t5", seconds: 22, role: "interviewer", text: "and local storage as a flow. And tell me what each part owns.")]
        let whole = CoachCardPrompt.interviewerTurn(cut) ?? ""
        #expect(CoachCards.asksToDraw(whole))
        #expect(CoachCardPrompt.focusHint(memory: CoachCase(), latest: whole)?.contains("four separate boxes") == true)
        #expect(CoachCardPrompt.focusHint(memory: CoachCase(), latest: "Now draw a sequence diagram of the app sending 80 dollars.")?.contains("four separate boxes") != true)
        #expect(!CoachCards.asksToExplain(whole))
    }

    @Test func aBareAcknowledgementIsNotAQuestion() {
        for ack in ["Oh.", "Okay.", "Mm-hm, right.", "I see.", "Got it", "Great."] { #expect(CoachCards.isBackchannel(ack), "\(ack)") }
        for line in ["Okay, why?", "Right, now draw it.", "Oh, and what about offline mode", "Good. Next question."] { #expect(!CoachCards.isBackchannel(line), "\(line)") }
    }

    /// Wallet run 2026-11-19 03:45: the agenda's "design a fictional mobile wallet" became the first problem.
    @Test func theFirstProblemIsTheQuestionNotTheAgenda() {
        let agenda = CoachTurn(id: "t1", seconds: 1, role: "interviewer", text: "Today we'll start with a project you really owned, then design a fictional mobile wallet together.")
        let ask = CoachTurn(id: "t2", seconds: 9, role: "interviewer", text: "Pick the one project that best shows your mobile skills. Who used it?")
        let wallet = [CoachCaseOp(op: "newProblem", text: "Design a fictional mobile wallet")]
        let fixed = CoachCards.withoutAgendaProblem(wallet, newLines: [agenda, ask], memory: CoachCase())
        #expect(fixed.first?.evidence == ["t2"])
        #expect(fixed.first?.text?.hasPrefix("Pick the one project") == true)
        // Citing the question, or a problem already open, leaves the card's goal alone.
        let project = [CoachCaseOp(op: "newProblem", text: "The KKday product page project", evidence: ["t2"])]
        #expect(CoachCards.withoutAgendaProblem(project, newLines: [agenda, ask], memory: CoachCase()) == project)
        var open = CoachCase()
        open.apply([CoachCaseOp(op: "newProblem", text: "Resume project")], evidence: CoachEvidence(), at: 0)
        #expect(CoachCards.withoutAgendaProblem(wallet, newLines: [agenda, ask], memory: open) == wallet)
        // The agenda's own card opens nothing; a plain task in the future tense still does.
        #expect(CoachCards.withoutAgendaProblem(wallet, newLines: [agenda], memory: CoachCase()).isEmpty)
        let task = CoachTurn(id: "t3", seconds: 1, role: "interviewer", text: "Now we'll design a chat app. Draw the architecture.")
        #expect(CoachCards.withoutAgendaProblem(wallet, newLines: [task], memory: CoachCase()) == wallet)
        // Without an agenda line nothing changes.
        #expect(CoachCards.withoutAgendaProblem(wallet, newLines: [ask], memory: CoachCase()) == wallet)
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

    /// Wallet run 2327, W7: the request restarted every second with no new interviewer words. A repeated
    /// interviewer trigger for the turn the running request read keeps it; a new line still replaces it.
    @Test @MainActor func anInterviewerTriggerWithNoNewWordsKeepsTheRunningRequest() async throws {
        var open: [AsyncThrowingStream<String, Error>.Continuation] = []
        let cards = CoachCards { _, _ in AsyncThrowingStream { open.append($0) } }
        var turns = [CoachTurn(id: "t1", seconds: 0, role: "interviewer", text: "What's in the first version?")]
        cards.input = { .init(turns: turns, background: "", frames: [], script: CoachScript(), stage: .general) }
        cards.receive(.interviewer, now: 1)
        for _ in 0..<50 { await Task.yield() }
        #expect(cards.requests == 1)
        cards.receive(.interviewer, now: 2)
        #expect(cards.requests == 1)
        turns.append(CoachTurn(id: "t2", seconds: 2, role: "interviewer", text: "And who signs off?"))
        cards.receive(.interviewer, now: 3)
        #expect(cards.requests == 2)
        open.forEach { $0.finish() }
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

/// Wallet run 2144 scored every rubric dimension 3 of 4 for lack of evidence: design answers get one concrete
/// proof, project answers one measured result from <knowledge>; neither goes where it does not belong.
@Test func designAndProjectAnswersAskForEvidence() {
    var wallet = CoachCase()
    wallet.apply([CoachCaseOp(op: "newProblem", text: "Design a mobile wallet", evidence: ["t1"])],
                 evidence: CoachEvidence(interviewer: ["t1"]), at: 0)
    #expect(CoachCardPrompt.focusHint(memory: wallet, latest: "Two phones send at once. What happens?")?.contains("ONE concrete proof") == true)
    #expect(CoachCardPrompt.focusHint(memory: wallet, latest: "Tell me about a time you disagreed with your manager.")?.contains("ONE concrete proof") != true)
    let project = CoachCardPrompt.focusHint(memory: CoachCase(), latest: "Pick the one project that best shows your mobile skills. Who used it?")
    #expect(project?.contains("measured result") == true)
    #expect(project?.contains("ONE concrete proof") != true)
    #expect(CoachCardPrompt.focusHint(memory: CoachCase(), latest: "How do you test it?") == nil)
}

/// Run 2232: the agenda ("…then design a fictional mobile wallet") merged into P1's turn gave the project answer
/// the money notes, and its updates went on to design the wallet.
@Test func theWalletAgendaGivesTheProjectAnswerNoMoneyNotes() {
    let agenda = "Today we'll start with a project you really owned, then design a fictional mobile wallet together."
    let p1 = "Pick the one project that best shows your mobile skills. Who used it, what problem did it solve?"
    let hint = CoachCardPrompt.focusHint(memory: CoachCase(), latest: agenda + " " + p1, last: p1)
    #expect(hint?.contains("Money points") != true)
    var project = CoachCase()
    project.apply([CoachCaseOp(op: "newProblem", text: "Tell the project that best shows mobile skills", evidence: ["t1"])],
                  evidence: CoachEvidence(interviewer: ["t1"]), at: 0)
    #expect(CoachCardPrompt.focusHint(memory: project, latest: "Which balance did the payment screen show?")?.contains("Money points") != true)
}
