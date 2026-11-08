import Foundation
import Testing
@testable import Cicada

struct InterviewCoachTests {
    private func line(_ id: String, _ role: String, _ text: String, t: Double = 0, via: String? = nil) -> TranscriptLine {
        TranscriptLine(id: id, t: t, speaker: role, src: text, dst: "TRANSLATION_MUST_NOT_ENTER", srcLang: "en", dstLang: "zh", via: via)
    }
    @Test func rolesComeFromChannelsAndOnlyOriginalHumanSpeechIsEvidence() throws {
        let turns = CoachTurn.spoken([line("q", "them", "How does cancellation work?"),
            line("r", "them", "Child jobs cancel with their parent.", t: 1, via: "room"),
            line("m", "me", "SupervisorJob isolates failures.", t: 2),
            line("a", "ai", "AI_SUGGESTION_MUST_NOT_ENTER"), line("s", "screen", "SCREEN_IS_NOT_SPEECH")])
        #expect(turns.map(\.role) == ["interviewer", "candidate", "candidate"])
        let messages = CoachPrompt.request(turns: turns, background: "", frames: [], audio: nil)
        let text = String(data: try JSONSerialization.data(withJSONObject: messages), encoding: .utf8) ?? ""
        #expect(!text.contains("TRANSLATION_MUST_NOT_ENTER"))
        #expect(!text.contains("AI_SUGGESTION_MUST_NOT_ENTER"))
        #expect(!text.contains("SCREEN_IS_NOT_SPEECH"))
        #expect(text.contains("Child jobs cancel with their parent."))
    }
    @Test func audioAndPicturesAreActuallyInTheMultimodalRequest() throws {
        var audio = CoachAudioBuffer()
        audio.append(RealtimeMedia.pcm([0, 0.1, -0.1]), endingAt: 10)
        let frame = CoachFrame(jpeg: Data([1, 2, 3]), seconds: 9)
        let messages = CoachPrompt.request(turns: [], background: "Resume", frames: Array(repeating: frame, count: 6), audio: audio)
        let content = try #require(messages[1]["content"] as? [[String: Any]])
        #expect(content.filter { $0["type"] as? String == "image_url" }.count == 3)
        let part = try #require(content.first { $0["type"] as? String == "input_audio" }?["input_audio"] as? [String: String])
        #expect(part["format"] == "wav")
        let wav = try #require(Data(base64Encoded: part["data"] ?? ""))
        #expect(String(data: wav.prefix(4), encoding: .utf8) == "RIFF")
        #expect(wav.count == 50)
        #expect(Array(wav[24..<28]) == [128, 62, 0, 0]) // 16000 Hz
    }
    @Test func longAnswersKeepTheLatestQuestionAndBoundText() throws {
        let turns = [CoachTurn(id: "q", seconds: 0, role: "interviewer", text: "Explain durable offline sending.")]
            + (1...50).map { CoachTurn(id: "m\($0)", seconds: Double($0), role: "candidate", text: String(repeating: "x", count: 5000)) }
        let data = try JSONSerialization.data(withJSONObject: CoachPrompt.request(turns: turns, background: "", frames: [], audio: nil))
        #expect(data.count < 26000)
        #expect(String(data: data, encoding: .utf8)?.contains("Explain durable offline sending.") == true)
    }
    @Test func audioBufferKeepsGapsAndStaysBounded() {
        var buffer = CoachAudioBuffer()
        buffer.append(Data(count: 32000), endingAt: 1)
        buffer.append(Data(count: 32000), endingAt: 3)
        #expect(buffer.pcm.count == 96000)
        #expect(buffer.start == 0)
        buffer.append(Data(count: 32000), endingAt: 100)
        #expect(buffer.pcm.count == CoachAudioBuffer.limit)
        #expect(buffer.start == 55)
    }
    @Test func pictureChangesIncludeCodeAndNonTextDiagrams() {
        var policy = CoachKeyframePolicy()
        let blank = [UInt8](repeating: 0, count: 128 * 72)
        let changed1 = policy.accept(fingerprint: blank, text: "", at: 0)
        #expect(changed1)
        let changed2 = policy.accept(fingerprint: blank, text: "", at: 3)
        #expect(!changed2)
        let changed3 = policy.accept(fingerprint: blank, text: "fun send() = saveToRoom()", at: 4)
        #expect(changed3)
        let changed4 = policy.accept(fingerprint: blank, text: "fun send() = saveToRoom()", at: 8)
        #expect(!changed4)
        let changed5 = policy.accept(fingerprint: [UInt8](repeating: 220, count: blank.count), text: "", at: 9)
        #expect(changed5)
        let changed6 = policy.accept(fingerprint: blank, text: "", at: 9.5)
        #expect(!changed6)
    }
    @Test func airpodsAreAValidCandidateMicButVirtualInputsAreNot() {
        let inputs = [RoomMicPlan.Input(uid: "mac", builtIn: true), .init(uid: "pods", bluetooth: true), .init(uid: "virtual", virtual: true)]
        #expect(RoomMicPlan.pick(defaultUID: "pods", inputs: inputs, headset: true) == "pods")
        #expect(RoomMicPlan.pick(defaultUID: "pods", inputs: inputs) == "mac")
        #expect(RoomMicPlan.pick(defaultUID: "virtual", inputs: inputs, headset: true) == "mac")
        #expect(RoomMicPlan.pick(defaultUID: "gone", inputs: inputs, headset: true) == "mac")
        let gate = EchoGate()
        gate.headphones = true; gate.hold(now: 1)
        #expect(!gate.closed(now: 1.1))
        gate.headphones = false; gate.hold(now: 2)
        #expect(gate.closed(now: 2.1))
        let repeated = EchoMatch.Heard(text: "Stable client ID", start: 1, end: 2)
        #expect(EchoMatch.isEcho(repeated, online: [repeated]))
        #expect(!EchoMatch.isEcho(repeated, online: [repeated], headphones: true))
    }
    @Test func outputSeparatesQuestionCoverageAndNextSuggestion() {
        let value = CoachOutput("Question: Offline chat?\nCovered: Room queue\nMissing: Idempotency\nNext: I'd assign a stable client ID.\nThe server deduplicates retries.")
        #expect(value.covered == "Room queue")
        #expect(value.next.contains("stable client ID"))
        #expect(value.next.contains("deduplicates"))
        #expect(value.grounded(candidateSpoke: false).covered == "Not yet answered")
        #expect(value.grounded(candidateSpoke: true).covered == "Room queue")
    }

    @Test @MainActor func semanticKeepPreservesScriptProgressAndDoesNotPublishANewAnswer() async throws {
        var streams: [AsyncThrowingStream<String, Error>.Continuation] = []
        var requests: [[[String: Any]]] = []
        var published = 0
        let engine = InterviewCoach { messages, _ in
            requests.append(messages)
            return AsyncThrowingStream { streams.append($0) }
        }
        engine.gloss.enabled = false; engine.onParagraph = { _ in published += 1 }
        engine.start(background: "", available: true, prepare: { true })
        defer { engine.endMeeting(); streams.forEach { $0.finish() } }
        let question = line("q", "them", "How do you handle offline sending on Android?")
        engine.observe(lines: [question], now: 0); engine.tick(now: 2)
        for _ in 0..<1000 where streams.isEmpty { await Task.yield() }
        try #require(streams.count == 1)
        streams[0].yield("I save messages in Room. A worker resumes sending after a restart.")
        streams[0].finish()
        for _ in 0..<1000 where engine.state != .ready { await Task.yield() }
        engine.reading.onProgress?(engine.script.answerID, 5, "I save messages in Room")
        engine.observe(lines: [question, line("m", "me", "I save messages in Room", t: 2)], now: 2)
        let original = engine.script, response = engine.responseID
        #expect(original.cursor == 5)
        for (index, text) in ["Lovely, by all means carry on with your reasoning.",
                              "So how do you resume sending after restarting?", "OK, all right, continue.",
                              "很好，我们继续聊。"].enumerated() {
            let time = Double(5 + index * 3)
            engine.speech(text, role: "interviewer", now: time); engine.tick(now: time + 2)
            for _ in 0..<1000 where streams.count < index + 2 { await Task.yield() }
            try #require(streams.count == index + 2)
            #expect(engine.script == original)
            #expect(engine.responseID == response)
            let request = String(data: try JSONSerialization.data(withJSONObject: requests.last ?? []), encoding: .utf8) ?? ""
            #expect(request.contains("unread_remainder"))
            #expect(request.contains(text))
            streams.last?.yield(#"{"action":"keep","reason":"Recovery is already in the remaining answer."}"#)
            streams.last?.finish()
            for _ in 0..<1000 where engine.state != .ready { await Task.yield() }
            #expect(engine.script == original)
            #expect(engine.responseID == response)
            #expect(engine.generationCount == 1)
            #expect(published == 1)
        }
        #expect(engine.reviewCount == 4)
    }

    @Test @MainActor func newSpeechFinishesVisibleStreamThenReviewsBeforeReplacing() async throws {
        var streams: [AsyncThrowingStream<String, Error>.Continuation] = []
        let engine = InterviewCoach { _, _ in AsyncThrowingStream { streams.append($0) } }
        engine.gloss.enabled = false
        engine.start(background: "", available: true, prepare: { true })
        defer { engine.endMeeting(); streams.forEach { $0.finish() } }
        engine.speech("How do retries work on Android?", role: "interviewer", now: 0)
        engine.tick(now: 2)
        for _ in 0..<1000 where streams.isEmpty { await Task.yield() }
        try #require(streams.count == 1)
        streams[0].yield("I save the queue in Room.")
        for _ in 0..<1000 where engine.script.pending.isEmpty { await Task.yield() }
        let response = engine.responseID
        engine.speech("OK, all right, continue", role: "interviewer", now: 3)
        engine.speech("Actually, assume persistent storage is prohibited.", role: "interviewer", now: 4)
        engine.tick(now: 6)
        #expect(engine.current?.id == response)
        #expect(engine.generationCount == 1)
        streams[0].yield(" A worker retries with a stable ID."); streams[0].finish()
        for _ in 0..<1000 where engine.state != .ready { await Task.yield() }
        let original = engine.script
        engine.tick(now: 7)
        for _ in 0..<1000 where streams.count < 2 { await Task.yield() }
        try #require(streams.count == 2)
        streams[1].yield(#"{"action":"replace","reason":""#)
        for _ in 0..<100 { await Task.yield() }
        #expect(engine.script == original)
        #expect(engine.generationCount == 1)
        streams[1].yield(#"Persistent storage is now prohibited."}"# + "\n")
        for _ in 0..<100 { await Task.yield() }
        #expect(engine.script == original)
        streams[1].yield("I keep unsent messages in memory and explain the process death limitation.")
        streams[1].finish()
        for _ in 0..<1000 where engine.state != .ready { await Task.yield() }
        #expect(engine.generationCount == 2)
        #expect(streams.count == 2) // Decision and replacement use the same cloud response.
        #expect(engine.script.answerID != original.answerID)
        #expect(engine.script.pending.contains("in memory"))
        #expect(!engine.script.pending.contains("action"))
    }

    @Test @MainActor func obsoleteAndMalformedReviewsCannotOverwriteTheAnswer() async throws {
        var streams: [AsyncThrowingStream<String, Error>.Continuation] = []
        let engine = InterviewCoach { _, _ in AsyncThrowingStream { streams.append($0) } }
        engine.gloss.enabled = false
        engine.start(background: "", available: true, prepare: { true })
        defer { engine.endMeeting(); streams.forEach { $0.finish() } }
        engine.speech("Explain offline sending on Android.", role: "interviewer", now: 0); engine.tick(now: 2)
        for _ in 0..<1000 where streams.isEmpty { await Task.yield() }
        streams.first?.yield("I save messages in Room."); streams.first?.finish()
        for _ in 0..<1000 where engine.state != .ready { await Task.yield() }
        let original = engine.script
        engine.speech("Assume storage is prohibited.", role: "interviewer", now: 3); engine.tick(now: 5)
        for _ in 0..<1000 where streams.count < 2 { await Task.yield() }
        try #require(streams.count == 2)
        engine.speech("Actually, Room is allowed. Please continue.", role: "interviewer", now: 6)
        streams[1].yield(#"{"action":"replace","reason":"Obsolete constraint"}"#); streams[1].finish()
        for _ in 0..<1000 where engine.state != .ready { await Task.yield() }
        #expect(engine.script == original)
        engine.tick(now: 8)
        for _ in 0..<1000 where streams.count < 3 { await Task.yield() }
        try #require(streams.count == 3)
        streams[2].yield("INVALID CONTROL RESPONSE"); streams[2].finish()
        for _ in 0..<1000 where engine.state != .failed { await Task.yield() }
        #expect(engine.state == .failed)
        #expect(engine.script == original)
        #expect(engine.generationCount == 1)
        engine.retry(); engine.tick(now: 10)
        for _ in 0..<1000 where streams.count < 4 { await Task.yield() }
        try #require(streams.count == 4)
        streams[3].finish(throwing: URLError(.timedOut))
        for _ in 0..<1000 where engine.state != .failed { await Task.yield() }
        #expect(engine.script == original)
        #expect(engine.generationCount == 1)
    }

    @Test @MainActor func newlyCommittedSpeechInvalidatesReplacementAndManualAskBypassesReview() async throws {
        var streams: [AsyncThrowingStream<String, Error>.Continuation] = []
        let engine = InterviewCoach { _, _ in AsyncThrowingStream { streams.append($0) } }
        engine.gloss.enabled = false
        engine.start(background: "", available: true, prepare: { true })
        defer { engine.endMeeting(); streams.forEach { $0.finish() } }
        let q = line("q", "them", "Explain reliable offline sending on Android.")
        engine.observe(lines: [q], now: 0); engine.tick(now: 2)
        for _ in 0..<1000 where streams.isEmpty { await Task.yield() }
        streams.first?.yield("I save each message in Room."); streams.first?.finish()
        for _ in 0..<1000 where engine.state != .ready { await Task.yield() }
        let id = engine.script.answerID
        let follow = line("f", "them", "How does the server avoid duplicates?", t: 3)
        engine.observe(lines: [q, follow], now: 3); engine.tick(now: 5)
        for _ in 0..<1000 where streams.count < 2 { await Task.yield() }
        try #require(streams.count == 2)
        engine.observe(lines: [q, follow, line("m", "me", "The server deduplicates by stable client ID.", t: 5)], now: 5)
        streams[1].yield(#"{"action":"replace","reason":"Deduplication was missing"}"# + "\nI add server deduplication."); streams[1].finish()
        for _ in 0..<1000 where engine.state != .ready { await Task.yield() }
        #expect(engine.script.answerID == id)
        #expect(engine.generationCount == 1)
        engine.tick(now: 7)
        for _ in 0..<1000 where streams.count < 3 { await Task.yield() }
        try #require(streams.count == 3)
        // Explicit regeneration remains available even if an AI review is in flight.
        engine.ask()
        for _ in 0..<1000 where streams.count < 4 { await Task.yield() }
        try #require(streams.count == 4)
        streams[2].yield(#"{"action":"replace","reason":"STALE"}"#); streams[2].finish()
        streams[3].yield("I use a stable client ID."); streams[3].finish()
        for _ in 0..<1000 where engine.state != .ready { await Task.yield() }
        #expect(engine.generationCount == 2)
        #expect(engine.script.spokenText == "The server deduplicates by stable client ID.")
        #expect(!engine.script.pending.contains("STALE"))
    }

    @Test @MainActor func noisyReadingAndScreenUpdatesKeepTheVisibleAnswer() async throws {
        var streams: [AsyncThrowingStream<String, Error>.Continuation] = []
        let engine = InterviewCoach { _, _ in AsyncThrowingStream { streams.append($0) } }
        engine.gloss.enabled = false
        engine.start(background: "", available: true, prepare: { true })
        let question = line("q", "them", "Why are you a strong fit for this Android role?")
        engine.observe(lines: [question], now: 0)
        engine.tick(now: 1)
        for _ in 0..<1000 where streams.isEmpty { await Task.yield() }
        try #require(streams.count == 1)
        let generated = "I believe my background in building complex, scalable applications, especially with AI integration, makes me a strong fit for this role. I have ten years of experience."
        let answer = CoachPronunciation.annotate(generated, finished: true)
        streams[0].yield(generated); streams[0].finish()
        for _ in 0..<1000 where engine.state != .ready { await Task.yield() }
        try #require(engine.script.pending == answer)
        // Actual ASR fragments from the reported reading session.
        let first = line("a", "me", "I believe in my background in building compass, it's kind of application, especially with an AI intelligration.", t: 2)
        engine.speech(first.src, role: "candidate", now: 2)
        engine.observe(lines: [question, first], now: 3)
        engine.tick(now: 5)
        #expect(engine.generationCount == 1)
        #expect(engine.script.pending == answer)
        let second = line("b", "me", "Makes me as strong the.", t: 6)
        engine.speech(second.src, role: "candidate", now: 6)
        engine.observe(lines: [question, first, second], now: 7)
        engine.picture(CoachFrame(jpeg: Data([1]), seconds: 7, ocr: "Changed slide"))
        engine.tick(now: 10)
        for _ in 0..<100 { await Task.yield() }
        #expect(engine.generationCount == 1)
        #expect(engine.script.pending == answer)
        #expect(engine.script.committed.map(\.text) == [first.src, second.src])
        // Starting a microphone can produce a punctuation-only system subtitle.
        engine.speech(".", role: "interviewer", now: 10)
        engine.tick(now: 11)
        for _ in 0..<100 { await Task.yield() }
        #expect(engine.generationCount == 1)
        // A late copy of candidate speech on the other channel is not a new question.
        engine.speech(first.src, role: "interviewer", now: 10)
        engine.speech(first.src + " I also have ten years of experience across mobile applications.", role: "interviewer", now: 11)
        engine.tick(now: 12)
        for _ in 0..<100 { await Task.yield() }
        #expect(engine.generationCount == 1)
        // A real follow-up must still start a new answer with the latest screen context.
        engine.speech("What changes if the Android process is killed?", role: "interviewer", now: 13)
        engine.tick(now: 14)
        for _ in 0..<1000 where streams.count < 2 { await Task.yield() }
        #expect(engine.generationCount == 1)
        #expect(engine.reviewCount == 1)
        #expect(engine.script.pending == answer)
        streams.last?.yield(#"{"action":"replace","reason":"Process death recovery is missing."}"# + "\n")
        streams.last?.yield("I persist the queue in Room before sending.")
        streams.last?.finish()
        for _ in 0..<1000 where engine.state != .ready { await Task.yield() }
        #expect(engine.script.pending == CoachPronunciation.annotate("I persist the queue in Room before sending.", finished: true))
        #expect(engine.script.cursor == 0)
        engine.endMeeting()
    }

    @Test @MainActor func joinedMicrophoneTextCannotBecomeInterviewerSubtitles() {
        let main = ListenEngine(settings: AppSettings())
        let room = ListenEngine(settings: AppSettings(), role: .room)
        main.translationOff = { true }; room.translationOff = { true }
        var interviewer: [String] = []; var candidate: [String] = []
        main.onSubtitle = { text, _ in interviewer.append(text) }
        room.onSubtitle = { text, _ in candidate.append(text) }
        let first = ListenEngine.roomIDs + 1
        let second = first + 1
        let joined = "I'm very excited about this opportunity to discuss my background."
        // The former AppModel route sent a room merge to the main engine.
        main.join(second, into: first, text: joined)
        #expect(interviewer.isEmpty)
        room.join(second, into: first, text: joined)
        #expect(candidate == [joined])
        // Mixed-source segments must never be merged, even when clocks happen to match.
        room.join(second + 1, into: 1, text: "MIXED_CHANNEL")
        main.join(2, into: first, text: "MIXED_CHANNEL")
        #expect(candidate == [joined])
        #expect(interviewer.isEmpty)
    }

    @Test @MainActor func delayedCandidateCopiesAfterLongReadingDoNotRewrite() async throws {
        var streams: [AsyncThrowingStream<String, Error>.Continuation] = []
        let engine = InterviewCoach { _, _ in AsyncThrowingStream { streams.append($0) } }
        engine.gloss.enabled = false
        engine.start(background: "", available: true, prepare: { true })
        let question = line("q", "them", "Hi, Meja, how are you?", t: 10.6)
        engine.observe(lines: [question], now: 13)
        engine.tick(now: 14)
        for _ in 0..<1000 where streams.isEmpty { await Task.yield() }
        try #require(streams.count == 1)
        let answer = "I'm doing well, thank you for asking. I'm very excited about this opportunity. I have a strong background in mobile development."
        streams[0].yield(answer); streams[0].finish()
        for _ in 0..<1000 where engine.state != .ready { await Task.yield() }
        let answerID = engine.script.answerID
        let pending = engine.script.pending
        // Recorded in the failing session: the finalized line was extended much later,
        // then arrived on the system channel after the candidate draft was cleared.
        let partial = "I'm very excited about the, uh, opportunity to discuss how my background alliance with your, um,"
        let full = partial + " Visition for a proactive global voice and attack communication FP."
        engine.observe(lines: [question, line("a", "me", partial, t: 21.97, via: "room")], now: 32.45)
        engine.finalized(role: "candidate")
        engine.observe(lines: [question, line("a", "me", full, t: 21.97, via: "room")], now: 42.1)
        engine.speech(full, role: "interviewer", now: 42.11)
        engine.tick(now: 44)
        for _ in 0..<1000 { await Task.yield() }
        #expect(engine.generationCount == 1)
        #expect(engine.script.answerID == answerID)
        #expect(engine.script.pending == pending)
        // A repeated copy stays harmless even long after the original turn.
        engine.speech(full + " I also build Android apps.", role: "interviewer", now: 112.85)
        engine.tick(now: 115)
        for _ in 0..<1000 { await Task.yield() }
        #expect(engine.generationCount == 1)
        engine.speech("How would you handle an Android process restart?", role: "interviewer", now: 116)
        engine.tick(now: 118)
        for _ in 0..<1000 where streams.count < 2 { await Task.yield() }
        #expect(engine.generationCount == 1)
        #expect(engine.reviewCount == 1)
        streams.forEach { $0.finish() }
        engine.endMeeting()
    }

    @Test @MainActor func candidateScrollingUsesGemmaAudioInsteadOfAppleText() async throws {
        var audioRequests = 0
        let engine = InterviewCoach(stream: { _, _ in
            AsyncThrowingStream { stream in
                stream.yield("I store each message in Room. Then I retry it safely.")
                stream.finish()
            }
        }, readingInfer: { _ in
            audioRequests += 1
            return audioRequests % 2 == 1 ? "I store each message in Room" : "{\"through\":6,\"confidence\":0.95}"
        })
        engine.gloss.enabled = false
        engine.start(background: "", available: true, prepare: { true })
        let q = line("q", "them", "How would you persist offline messages?")
        engine.observe(lines: [q], now: 0); engine.tick(now: 1)
        for _ in 0..<1000 where engine.state != .ready { await Task.yield() }
        try #require(!engine.script.pending.isEmpty)
        let answer = engine.script.pending, id = engine.script.answerID
        engine.speech("I store each message in Room. Then I retry it safely.", role: "candidate", now: 2)
        engine.observe(lines: [q, line("a", "me", "I store each message in Room. Then I retry it safely.")], now: 2)
        #expect(engine.script.cursor == 0)
        engine.appendCandidateAudio(RealtimeMedia.pcm(Array(repeating: Float(0.1), count: 24000)), voiced: true, now: 3)
        engine.tick(now: 3)
        for _ in 0..<1000 where engine.reading.busy { await Task.yield() }
        #expect(audioRequests == 2)
        #expect(engine.script.cursor == 6)
        #expect(engine.script.currentSentence == 1)
        #expect(engine.script.pending == answer)
        #expect(engine.script.answerID == id)
        #expect(engine.generationCount == 1)
        engine.endMeeting()
    }

    @Test @MainActor func generationWaitsForEndpointAndStopRejectsLateDeltas() async throws {
        var continuation: AsyncThrowingStream<String, Error>.Continuation?
        let engine = InterviewCoach { _, _ in AsyncThrowingStream { continuation = $0 } }
        engine.start(background: "", available: true, prepare: { true })
        engine.speech("How would you design offline chat?", role: "interviewer", now: 0)
        engine.tick(now: 0.36)
        for _ in 0..<100 { await Task.yield() }
        #expect(continuation == nil)
        #expect(engine.generationCount == 0)
        engine.tick(now: 0.7)
        for _ in 0..<100 where continuation == nil { await Task.yield() }
        try #require(continuation != nil)
        continuation?.yield("I make Room the source of truth. I queue messages before sending.")
        for _ in 0..<100 where engine.script.pending.isEmpty { await Task.yield() }
        #expect(CoachScript.words(engine.script.pending).joined(separator: " ").contains("source of truth"))
        #expect(engine.firstSentenceLatency != nil)
        engine.stop()
        let pending = engine.script.pending
        continuation?.yield("LATE"); continuation?.finish()
        for _ in 0..<10 { await Task.yield() }
        #expect(engine.state == .idle)
        #expect(engine.script.pending == pending)
    }

    @Test @MainActor func continuousDraftsCoalesceAndFinalPunctuationDoesNotRestart() async throws {
        var streams: [AsyncThrowingStream<String, Error>.Continuation] = []
        var requests: [[[String: Any]]] = []
        let engine = InterviewCoach { messages, _ in
            requests.append(messages)
            return AsyncThrowingStream { streams.append($0) }
        }
        engine.gloss.enabled = false
        engine.start(background: "", available: true, prepare: { true })
        let words = "How would you design reliable offline message sending on Android".split(separator: " ")
        for end in 1...words.count {
            let now = Double(end) * 0.5
            engine.speech(words.prefix(end).joined(separator: " "), role: "interviewer", now: now)
            engine.tick(now: now + 0.4)
            for _ in 0..<20 { await Task.yield() }
            #expect(engine.generationCount == 0)
        }
        let end = Double(words.count) * 0.5
        engine.tick(now: end + 0.7)
        for _ in 0..<1000 where streams.isEmpty { await Task.yield() }
        try #require(streams.count == 1)
        let request = String(data: try JSONSerialization.data(withJSONObject: requests[0]), encoding: .utf8) ?? ""
        #expect(request.contains("reliable offline message sending on Android"))
        engine.speech("How would you design reliable offline message sending on Android?", role: "interviewer", now: end + 0.8)
        engine.tick(now: end + 2)
        for _ in 0..<100 { await Task.yield() }
        #expect(engine.generationCount == 1)
        streams[0].yield("I persist each message before sending.")
        for _ in 0..<1000 where engine.script.pending.isEmpty { await Task.yield() }
        #expect(engine.script.pending.contains("persist"))
        engine.speech("What happens if the process dies?", role: "interviewer", now: end + 3)
        streams[0].finish()
        for _ in 0..<1000 where engine.state != .ready { await Task.yield() }
        engine.tick(now: end + 4)
        for _ in 0..<1000 where streams.count < 2 { await Task.yield() }
        #expect(streams.count == 2)
        #expect(engine.reviewCount == 1)
        engine.endMeeting()
        streams.forEach { $0.finish() }
    }

    @Test @MainActor func acousticHoldAndCompletionControlAutomaticGeneration() async throws {
        var streams: [AsyncThrowingStream<String, Error>.Continuation] = []
        let engine = InterviewCoach { _, _ in AsyncThrowingStream { streams.append($0) } }
        engine.start(background: "", available: true, prepare: { true })
        engine.speech("How would you design offline chat?", role: "interviewer", now: 0)
        engine.acoustic.onEvent?(.init(kind: "endpoint", role: "interviewer", now: 0.5, complete: false))
        engine.tick(now: 0.8)
        for _ in 0..<100 { await Task.yield() }
        #expect(engine.generationCount == 0)
        engine.acoustic.onEvent?(.init(kind: "endpoint", role: "interviewer", now: 1, complete: true))
        engine.tick(now: 1)
        for _ in 0..<1000 where streams.isEmpty { await Task.yield() }
        #expect(engine.generationCount == 1)
        engine.endMeeting()
        streams.forEach { $0.finish() }
    }

    @Test @MainActor func translationsAndAIRecordsCannotTriggerInference() {
        let engine = InterviewCoach { _, _ in AsyncThrowingStream { $0.finish() } }
        engine.start(background: "", available: true, prepare: { true })
        engine.observe(lines: [line("ai", "ai", "A proposed answer")], now: 0)
        engine.tick(now: 10)
        #expect(engine.generationCount == 0)
        engine.endMeeting()
    }
    @Test @MainActor func repeatedManualRefreshReanswersWithConversationAndBypassesCoverage() async throws {
        var streams: [AsyncThrowingStream<String, Error>.Continuation] = []
        var requests: [[[String: Any]]] = []
        let engine = InterviewCoach { messages, _ in
            requests.append(messages)
            return AsyncThrowingStream { streams.append($0) }
        }
        engine.gloss.enabled = false
        engine.start(background: "Synthetic ActAI Android practice", available: true, prepare: { true })
        defer { engine.endMeeting(); streams.forEach { $0.finish() } }
        let lines = [line("q", "them", "Explain offline sending and retries."),
                     line("m", "me", "I persist messages in Room.", t: 2),
                     line("f", "them", "Could you give one simple example?", t: 3)]
        engine.observe(lines: lines, now: 4)
        for index in 0..<2 {
            engine.ask()
            for _ in 0..<1000 where streams.count <= index { await Task.yield() }
            try #require(streams.count == index + 1)
            let messages = requests[index]
            let text = String(data: try JSONSerialization.data(withJSONObject: messages), encoding: .utf8) ?? ""
            #expect(text.contains("Explicit manual refresh"))
            #expect(text.contains("Explain offline sending and retries."))
            #expect(text.contains("I persist messages in Room."))
            #expect(text.contains("Could you give one simple example?"))
            #expect(!text.contains("unread_remainder"))
            streams[index].yield("An offline message stays in Room until a worker can send it.")
            streams[index].finish()
            for _ in 0..<1000 where engine.state != .ready { await Task.yield() }
        }
        #expect(engine.generationCount == 2)
        #expect(engine.reviewCount == 0)
        #expect(engine.script.spokenText == "I persist messages in Room.")
    }

}
