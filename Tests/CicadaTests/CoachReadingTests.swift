import Foundation
import Testing
@testable import Cicada

struct CoachReadingTests {
    private let answer = "I store each message in Room. Then I retry it safely."
    private var pcm: Data { RealtimeMedia.pcm(Array(repeating: Float(0.1), count: 24000)) }

    @Test func appleTextCannotMoveAudioModelProgressEvenAfterStreamUpdates() {
        var script = CoachScript(modelReading: true)
        script.replacePending(answer, since: [], newAnswer: true)
        script.preview("I store each message in Room")
        script.commit(id: "a", text: "I store each message in Room")
        script.replacePending(answer + " I bound the retry count.", since: [])
        #expect(script.cursor == 0)
        #expect(script.committed.count == 1)
        let id = script.answerID
        script.advanceReading(to: 6, answerID: "stale")
        #expect(script.cursor == 0)
        script.advanceReading(to: 6, answerID: id)
        script.advanceReading(to: 3, answerID: id)
        script.advanceReading(to: 100, answerID: id)
        #expect(script.cursor == 6)
        #expect(script.currentSentence == 1)
        #expect(script.pending == answer + " I bound the retry count.")
        #expect(script.spokenText == "I store each message in Room")
    }

    @Test func decisionsNeedConfidenceBoundedProgressAndSpeechEvidence() throws {
        let words = CoachScript.words(answer)
        let valid = try CoachReadingDecision.decode("```json\n{\"through\":6,\"confidence\":0.95}\n```")
        #expect(valid.advance(transcript: "I store each message in room", words: words, cursor: 0, duration: 3) == 6)
        #expect(valid.advance(transcript: "I store each message in room", words: words, cursor: 6, duration: 3) == nil)
        #expect(valid.advance(transcript: "Can you hear me now", words: words, cursor: 0, duration: 3) == nil)
        #expect(valid.advance(transcript: "Room", words: words, cursor: 0, duration: 3) == nil)
        #expect(CoachReadingDecision(through: 99, confidence: 1).advance(transcript: answer, words: words, cursor: 0, duration: 3) == nil)
        #expect(CoachReadingDecision(through: 6, confidence: 0.7).advance(transcript: answer, words: words, cursor: 0, duration: 3) == nil)
        #expect(CoachReadingDecision(through: 11, confidence: 1).advance(transcript: answer, words: words, cursor: 0, duration: 0.1) == nil)
        #expect(throws: (any Error).self) { try CoachReadingDecision.decode("no usable JSON") }
        // A mispronounced last word still has nearby audible anchors.
        let script = CoachScript.words("I would keep Room as the single source of truth.")
        #expect(CoachReadingDecision(through: 10, confidence: 0.9).advance(
            transcript: "I would keep Room as the single source of true", words: script, cursor: 0, duration: 4) == 10)
    }

    @Test func photoRegressionRecoversAfterOmittedEndOfPreviousSentence() {
        let answer = "The feed screen would fetch a list of posts, and when a user clicks on a post, the app would navigate to the detail screen to show the full content and the comments. A key consideration here is the scalability /ˌskeɪləˈbɪləti/ of the feed. Since the feed needs to be personalized and dynamic, we would need a robust mechanism for ranking and serving posts."
        let words = CoachScript.words(answer)
        let cursor = CoachScript.words("The feed screen would fetch a list of posts and").count
        let transcript = "A key consideration here is the scalability of the theta"
        let through = CoachScript.words(answer.components(separatedBy: " Since")[0]).count
        // The old cursor-distance guard rejects an otherwise well-supported endpoint.
        #expect(CoachReadingDecision(through: through - 1, confidence: 0.95).advance(
            transcript: transcript, words: words, cursor: cursor, duration: 3) == nil)
        // The audio can begin after omitted words; the cursor distance is not its length.
        #expect(CoachReadingDecision.recover(transcript: transcript, words: words,
            cursor: cursor, duration: 3) == through - 1)
        var script = CoachScript(modelReading: true)
        script.replacePending(answer, since: [], newAnswer: true)
        script.advanceReading(to: cursor, answerID: script.answerID)
        #expect(script.currentSentence == 0)
        if let recovered = CoachReadingDecision.recover(transcript: transcript, words: words,
                                                        cursor: cursor, duration: 3) {
            script.advanceReading(to: recovered, answerID: script.answerID)
        }
        #expect(script.currentSentence == 1)
        #expect(script.pending == answer)
        #expect(script.committed.isEmpty)
    }

    @Test func recoveryRequiresUniqueRecentOrderedSpeechAndStaysBounded() {
        let words = CoachScript.words("I would keep Room as the single source of truth. Each message gets a stable client ID. I would keep Room as the single source of truth. Then I bound the retry count.")
        for transcript in ["I would keep Room as the single source of truth", "Room", "truth source single the as Room keep", "Can you hear me now", "Each message gets a stable client ID but now I am discussing something completely unrelated"] {
            #expect(CoachReadingDecision.recover(transcript: transcript, words: words,
                cursor: 10, duration: 10) == nil, "Unexpected recovery: \(transcript)")
        }
        #expect(CoachReadingDecision.recover(transcript: "Then I bound the retry count", words: words,
            cursor: 10, duration: 3) == words.count)
        #expect(CoachReadingDecision.recover(transcript: "Then I bound the retry count", words: words,
            cursor: words.count, duration: 3) == nil)
        #expect(CoachReadingDecision.recover(transcript: "Then I bound the retry count", words: words,
            cursor: 10, duration: 0.1) == nil)
        let distant = Array(repeating: "padding", count: 200) + CoachScript.words("Then I bound the retry count")
        #expect(CoachReadingDecision.recover(transcript: "Then I bound the retry count", words: distant,
            cursor: 0, duration: 3) == nil)
    }

    @Test func asrHasNoScriptAndAlignmentHasNoAudioOrIPA() throws {
        let asr = try JSONSerialization.data(withJSONObject: CoachReadingPrompt.transcribe(wav: Data([1, 2])))
        let asrText = String(decoding: asr, as: UTF8.self)
        #expect(asrText.contains("input_audio"))
        #expect(!asrText.contains("Numbered script"))
        let align = try JSONSerialization.data(withJSONObject: CoachReadingPrompt.align(
            transcript: "I store each message", words: CoachScript.words(answer), cursor: 0))
        let text = String(decoding: align, as: UTF8.self)
        #expect(text.contains("[6]room"))
        #expect(text.contains("Actual microphone transcript"))
        #expect(!text.contains("input_audio"))
    }

    @Test @MainActor func audioMovesOnlyProgressAndSilenceDoesNotCallTheModel() async throws {
        var requests: [[[String: Any]]] = []
        let reader = CoachReading { messages in
            requests.append(messages)
            return requests.count % 2 == 1 ? "I store each message in Room" : "{\"through\":6,\"confidence\":0.95}"
        }
        var script = CoachScript(modelReading: true)
        script.replacePending(answer, since: [], newAnswer: true)
        reader.onProgress = { id, through, _ in script.advanceReading(to: through, answerID: id) }
        reader.begin(answerID: script.answerID)
        reader.append(Data(count: 48000), voiced: false, now: 1.5)
        reader.tick(script: script, blocked: false, now: 2)
        #expect(requests.isEmpty)
        reader.append(pcm, voiced: true, now: 3)
        reader.tick(script: script, blocked: false, now: 3)
        for _ in 0..<1000 where reader.busy { await Task.yield() }
        #expect(requests.count == 2)
        #expect(script.cursor == 6)
        #expect(script.pending == answer)
        #expect(script.committed.isEmpty)
        reader.tick(script: script, blocked: false, now: 20)
        #expect(requests.count == 2)
        reader.stop()
    }

    @Test @MainActor func stalledModelAlignmentRecoversFromIndependentAudioTranscript() async {
        let answer = "The feed screen would fetch a list of posts, and when a user clicks on a post, the app would navigate to the detail screen to show the full content and the comments. A key consideration here is the scalability of the feed."
        for response in ["{\"through\":11,\"confidence\":0.95}", "no usable JSON"] {
            var calls = 0
            let reader = CoachReading { _ in
                calls += 1
                return calls == 1 ? "A key consideration here is the scalability of the theta" : response
            }
            var script = CoachScript(modelReading: true)
            script.replacePending(answer, since: [], newAnswer: true)
            let id = script.answerID
            script.advanceReading(to: 11, answerID: id)
            reader.onProgress = { id, through, _ in script.advanceReading(to: through, answerID: id) }
            reader.begin(answerID: id)
            reader.append(pcm, voiced: true, now: 2)
            reader.tick(script: script, blocked: false, now: 2)
            for _ in 0..<1000 where reader.busy { await Task.yield() }
            #expect(calls == 2)
            #expect(script.currentSentence == 1)
            #expect(script.cursor == CoachScript.words(answer).count - 1)
            #expect(script.pending == answer)
            #expect(script.answerID == id)
            #expect(script.committed.isEmpty)
            reader.stop()
        }
    }

    @Test @MainActor func priorityAndNewAnswerRejectLateAudioResults() async throws {
        var waiting: CheckedContinuation<String, Never>?
        var calls = 0
        let reader = CoachReading { _ in
            calls += 1
            return await withCheckedContinuation { waiting = $0 }
        }
        var script = CoachScript(modelReading: true)
        script.replacePending(answer, since: [], newAnswer: true)
        var updates = 0
        reader.onProgress = { _, _, _ in updates += 1 }
        reader.begin(answerID: script.answerID)
        reader.append(pcm, voiced: true, now: 2)
        reader.tick(script: script, blocked: true, now: 2)
        #expect(calls == 0)
        reader.tick(script: script, blocked: false, now: 3)
        for _ in 0..<1000 where waiting == nil { await Task.yield() }
        try #require(waiting != nil)
        reader.tick(script: script, blocked: true, now: 4)
        waiting?.resume(returning: "I store each message in Room"); waiting = nil
        for _ in 0..<100 { await Task.yield() }
        #expect(calls == 1)
        #expect(updates == 0)
        reader.tick(script: script, blocked: false, now: 5)
        for _ in 0..<1000 where waiting == nil { await Task.yield() }
        try #require(waiting != nil)
        reader.begin(answerID: "new-answer")
        waiting?.resume(returning: "I store each message in Room"); waiting = nil
        for _ in 0..<100 { await Task.yield() }
        #expect(calls == 2)
        #expect(updates == 0)
        // Audio remains bounded while answer inference has priority.
        reader.append(Data(count: 640000), voiced: false, now: 24)
        #expect(reader.audioSeconds == 10)
        reader.begin(answerID: "new-answer")
        #expect(reader.audioSeconds == 0)
        reader.stop()
    }

    @Test @MainActor func aShortFinalFragmentFlushesAfterItsPause() async {
        var calls = 0
        let reader = CoachReading { _ in calls += 1; return "" }
        var script = CoachScript(modelReading: true)
        script.replacePending(answer, since: [], newAnswer: true)
        reader.begin(answerID: script.answerID)
        reader.append(Data(count: 6400), voiced: true, now: 0.2)
        reader.append(Data(count: 40000), voiced: false, now: 1.5)
        reader.tick(script: script, blocked: false, now: 1.5)
        for _ in 0..<1000 where reader.busy { await Task.yield() }
        #expect(calls == 1)
        #expect(script.cursor == 0)
        reader.stop()
    }

    @Test @MainActor func failureKeepsTheScriptAndRetriesAreBounded() async {
        var calls = 0, failed = false
        let reader = CoachReading { _ in calls += 1; throw URLError(.cannotConnectToHost) }
        reader.onFailure = { failed = $0 }
        var script = CoachScript(modelReading: true)
        script.replacePending(answer, since: [], newAnswer: true)
        reader.begin(answerID: script.answerID)
        reader.append(pcm, voiced: true, now: 2)
        for now in [2.0, 8, 14, 20] {
            reader.tick(script: script, blocked: false, now: now)
            for _ in 0..<1000 where reader.busy { await Task.yield() }
        }
        #expect(calls == 3)
        #expect(failed)
        #expect(script.cursor == 0)
        #expect(script.pending == answer)
        reader.retry()
        #expect(!failed)
        reader.stop()
    }
}
