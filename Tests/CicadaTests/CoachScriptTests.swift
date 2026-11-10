import Foundation
import Testing
@testable import Cicada

struct CoachScriptTests {
    @Test func partialASRRetractionsKeepProgressAndOnlyFinalSpeechCommits() {
        var script = CoachScript()
        script.replacePending("I store each message in Room. Then I retry it safely.", since: [])
        script.preview("I store each message in Room")
        #expect(script.cursor == 6)
        #expect(script.currentSentence == 1)
        #expect(script.committed.isEmpty)
        script.preview("I store each")
        #expect(script.cursor == 6)
        let matched = script.commit(id: "one", text: "I store each message in Room")
        #expect(matched)
        #expect(script.pending == "I store each message in Room. Then I retry it safely.")
        _ = script.commit(id: "one", text: "REVISED_ASR_CANNOT_REWRITE_COMMITTED")
        #expect(script.spokenText == "I store each message in Room")
        script.replacePending("I store each message in Room. Then I retry using a stable ID.", since: [])
        #expect(script.pending == "I store each message in Room. Then I retry using a stable ID.")
        #expect(script.spokenText == "I store each message in Room")
    }
    @Test func finalFragmentsAndASRRetractionsNeverRemoveOrReorderTheScript() {
        var script = CoachScript()
        let answer = "I store each message in Room. Then I retry it safely."
        script.replacePending(answer, since: [])
        script.preview("I store each message")
        #expect(script.cursor == 4)
        script.preview("I store")
        #expect(script.cursor == 4)
        _ = script.commit(id: "a", text: "I store each message")
        #expect(script.pending == answer)
        #expect(script.cursor == 4)
        script.preview("in Room")
        _ = script.commit(id: "b", text: "in Room")
        #expect(script.pending == answer)
        #expect(script.cursor == 6)
        script.replacePending(answer + " I bound the retry count.", since: [])
        #expect(script.cursor == 6)
        #expect(script.pending.hasPrefix(answer))
    }

    @Test func technicalOverlapCannotSkipUnsaidParagraphs() {
        #expect(CoachScript.matchedPrefix("Room could also work", in: "I use Room as the source of truth. Then I retry safely.") == 0)
        #expect(CoachScript.matchedPrefix("I use Room as source of truth", in: "I use Room as the source of truth.") == 8)
    }
    @Test func noisyRealSpeechAdvancesConservativelyAndNewAnswersResetProgress() {
        var script = CoachScript()
        let answer = "I believe my background in building complex, scalable applications, especially with AI integration, makes me a strong fit for this role."
        script.replacePending(answer, since: [])
        let speech = "I believe in my background in building compass, it's kind of application, especially with an AI intelligration."
        let followed = script.commit(id: "a", text: speech)
        #expect(followed)
        #expect(script.cursor >= 7)
        #expect(script.cursor < CoachScript.words(answer).count)
        #expect(script.pending == answer)
        let progress = script.cursor
        _ = script.commit(id: "b", text: "UNRECOGNIZED_FRAGMENT")
        #expect(script.cursor == progress)
        script.replacePending("I persist pending messages in Room.", since: ["a", "b"], newAnswer: true)
        #expect(script.cursor == 0)
        #expect(script.committed.count == 2)
        #expect(CoachScript.matchedPrefix("Room", in: "I use Room.") == 0)
    }

    @Test func britishAnnotationsFocusOnDifficultWordsAndPreserveIdentifiers() {
        let text = "Scalability and scalability need authentication, concurrency, latency, persistence and architecture."
        let annotated = CoachPronunciation.annotate(text, finished: true)
        #expect(annotated.hasPrefix("Scalability /ˌskeɪləˈbɪləti/ and scalability need"))
        #expect(annotated.contains("latency /ˈleɪtənsi/"))
        #expect(annotated.hasSuffix("and architecture /ˈɑːkɪtektʃə/."))
        #expect(annotated.filter { $0 == "/" }.count == 12)
        #expect(CoachPronunciation.lexiconCount > 40000)
        let broader = CoachPronunciation.annotate("Reliable offline storage protects messages during recovery.", finished: true)
        #expect(!broader.contains("/"))
        #expect(CoachScript.words(broader) == CoachScript.words("Reliable offline storage protects messages during recovery."))
        let code = "`cache` ```queue``` cache_id CacheStore GET /cache/queue https://example.com/latency cache.example"
        #expect(CoachPronunciation.annotate(code, finished: true) == code)
        #expect(CoachPronunciation.annotate("latenc") == "latenc")
        #expect(CoachPronunciation.annotate("latency") == "latency")
        #expect(CoachPronunciation.annotate("latency ") == "latency /ˈleɪtənsi/ ")
        #expect(CoachPronunciation.annotate("latency", finished: true) == "latency /ˈleɪtənsi/")
        #expect(CoachPronunciation.annotate("I use a simple app.") == "I use a simple app.")
    }

    @Test func inlineIPAIsVisibleButDoesNotCountAsSpeech() {
        var script = CoachScript()
        let answer = "I consider scalability /ˌskeɪləˈbɪləti/ first. Then I use a specific /spəˈsɪfɪk/ queue."
        script.replacePending(answer, since: [])
        #expect(CoachScript.words(answer) == CoachScript.words("I consider scalability first. Then I use a specific queue."))
        script.preview("I consider scalability first")
        #expect(script.cursor == 4)
        #expect(script.currentSentence == 1)
        let first = script.commit(id: "a", text: "I consider scalability first")
        let second = script.commit(id: "b", text: "Then I use a specific queue")
        #expect(first)
        #expect(second)
        #expect(script.cursor == 10)
        #expect(script.pending == answer)
        #expect(!script.spokenText.contains("/"))
    }
    @Test func familiarIntroductionStaysReadableAtSeniorHighLevel() {
        let text = "I'm a software engineer with about ten years of experience, and most recently I've been working as a full-stack AI engineer and technical lead on an AI itinerary product. My background is mainly Android and Kotlin, plus Flutter. I've moved deeper into AI integration and agent architecture."
        let output = CoachPronunciation.annotate(text, finished: true)
        #expect(output.contains("software engineer with about ten years of experience"))
        #expect(output.contains("full-stack AI engineer and technical lead"))
        #expect(output.contains("itinerary /"))
        #expect(output.contains("architecture /"))
        #expect(output.filter { $0 == "/" }.count <= 6)
        #expect(CoachScript.words(output) == CoachScript.words(text))
        let streamed = CoachPronunciation.annotate("Architecture and architecture support synchroniz")
        let complete = CoachPronunciation.annotate("Architecture and architecture support synchronization.", finished: true)
        #expect(complete.hasPrefix(streamed))
        #expect(complete.filter { $0 == "/" }.count == 4)
    }
    @Test func numericReadingAidsIncludePercentagesAndDecimals() {
        for (number, ipa) in [("2000", "tuː ˈθaʊzənd"), ("10%", "ten pəˈsent"),
                              ("0.1%", "ˈzɪərəʊ pɔɪnt wʌn pəˈsent"),
                              ("2,000", "tuː ˈθaʊzənd"), ("0.01%", "ˈzɪərəʊ pɔɪnt ˈzɪərəʊ wʌn pəˈsent"),
                              ("10", "ten"), ("12", "twelv"), ("-10%", "ˈmaɪnəs ten pəˈsent"),
                              ("100", "wʌn ˈhʌndrəd"), ("2010", "tuː ˈθaʊzənd ænd ten")] {
            let answer = "Result: \(number)."
            let annotated = CoachPronunciation.annotate(answer, finished: true)
            #expect(annotated == "Result: \(number) /\(ipa)/.")
            #expect(CoachScript.words(annotated) == CoachScript.words(answer))
            #expect(!CoachPronunciation.spokenText(annotated).contains("/"))
        }
        #expect(CoachPronunciation.annotate("10% and 10%.", finished: true) == "10% /ten pəˈsent/ and 10% /ten pəˈsent/.")
        for partial in ["2000", "10", "0.1", "0.1%"] {
            #expect(CoachPronunciation.annotate(partial) == partial)
        }
        let code = "`2000` ```10%``` https://example.com/2000 /api/2000 v2000 value_10 10ms 1.2.3"
        #expect(CoachPronunciation.annotate(code, finished: true) == code)
    }

    @Test func pronunciationFilteringHandlesStreamingWithoutRemovingCodeOrURLs() {
        #expect(CoachScript.words("Consider scalability /ˌskeɪlə") == ["consider", "scalability"])
        #expect(CoachPronunciation.spokenText("a cache /kæʃ/ and a queue /kjuː/.") == "a cache  and a queue .")
        let code = "GET /api/v1/messages, a/b, https://example.com and client_id."
        #expect(CoachPronunciation.spokenText(code) == code)
        let ascii = CoachPronunciation.annotate("psst.", finished: true)
        #expect(!ascii.contains("/psst/"))
        #expect(CoachScript.words(ascii) == ["psst"])
        #expect(CoachScript.words("psst /psst/.") == ["psst"])
    }

    @Test func reviewDecisionsAreStrictControlData() throws {
        #expect(try CoachReviewDecision.decode(#"{"action":"keep","reason":"Already covered"}"#).action == .keep)
        #expect(try CoachReviewDecision.decode(#"{"action":"replace","reason":"New constraint"}"#).action == .replace)
        for raw in ["keep", "I would use Room.", #"{"action":"skip","reason":"x"}"#,
                    #"{"action":"replace","reason":""}"#, #"{"action":"keep"}"#] {
            #expect(throws: (any Error).self) { try CoachReviewDecision.decode(raw) }
        }
        #expect(CoachEndpoint.delay("How do you handle the") > CoachEndpoint.delay("How do you handle retries?"))
    }
    @Test func updateProtocolSeparatesPrivateDecisionFromStreamedAnswer() throws {
        #expect(try CoachReviewResponse.parse("{", finished: false) == nil)
        let keep = try #require(try CoachReviewResponse.parse(#"{"action":"keep","reason":"Covered"}"#, finished: true))
        #expect(keep.answer.isEmpty)
        let replace = try #require(try CoachReviewResponse.parse(#"{"action":"replace","reason":"Missing"}"# + "\nI persist messages.", finished: true))
        #expect(replace.answer == "I persist messages.")
        for invalid in [#"{"action":"replace","reason":"Missing"}"#,
                        #"{"action":"keep","reason":"Covered"}"# + "\nUnwanted new answer"] {
            #expect(throws: (any Error).self) { try CoachReviewResponse.parse(invalid, finished: true) }
        }
    }
    @Test func reviewPromptIncludesExistingAnswerUnreadRemainderAndActualSpeech() throws {
        var script = CoachScript(modelReading: true)
        script.replacePending("I save messages in Room. WorkManager resumes them after a restart.", since: [])
        script.advanceReading(to: 5, answerID: script.answerID)
        script.commit(id: "m", text: "I save messages in Room")
        let messages = CoachPrompt.reviewRequest(turns: [CoachTurn(id: "q", seconds: 2, role: "interviewer",
            text: "So how does recovery work?")], background: "", frames: [], script: script)
        let text = String(data: try JSONSerialization.data(withJSONObject: messages), encoding: .utf8) ?? ""
        #expect(text.contains("unread_remainder"))
        #expect(script.remainingText == "WorkManager resumes them after a restart.")
        #expect(text.contains("WorkManager resumes them after a restart."))
        #expect(text.contains("actual_committed_speech"))
        #expect(text.contains("NOT keywords"))
        #expect(!text.contains("Write the COMPLETE remaining English answer now"))
    }

    @Test func retrievalFindsRelevantMaterialBeyondTheOldPrefixLimit() {
        let background = String(repeating: "Unrelated biography line.\n", count: 1000) + "Project: Android Room offline queue and stable message IDs."
        let found = CoachKnowledge.retrieve(background, query: "Android offline Room", limit: 200)
        #expect(found.contains("stable message IDs"))
        #expect(found.count <= 200)
    }
    @Test func chineseHRQuestionsRetrieveEnglishEmployerAndTopicFacts() {
        let background = String(repeating: "Unrelated reference material.\n", count: 500)
            + "Kezhi departure: joined the next company through an internal referral, closer to home.\n"
            + "Kezhi salary: monthly fixed pay; the next company's annual bonus was variable.\n"
            + "Debon handover: the watchlist shipped and was handed over cleanly."
        let move = CoachKnowledge.retrieve(background, query: "为什么离开可之？", limit: 120)
        #expect(move.contains("internal referral"))
        let pay = CoachKnowledge.retrieve(background, query: "可之的薪资是多少？", limit: 120)
        #expect(pay.contains("monthly fixed pay"))
        let handover = CoachKnowledge.retrieve(background, query: "德邦交接怎么做的？", limit: 120)
        #expect(handover.contains("watchlist shipped"))
    }
    @Test func teamCorrectionSurvivesNoisyASRInInitialAndFollowupRequests() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("tools/copilot-interview-background.json"))
        let fixture = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let resume = try #require(fixture["candidate_resume"] as? [String])
        let background = String(repeating: "Unrelated reference material.\n", count: 1000)
            + resume.joined(separator: "\n")
        let turns = [CoachTurn(id: "q", seconds: 1, role: "interviewer",
            text: "At Kesi, behind the DKO Tong exam app, how was the team organised and who did you report to?")]
        var script = CoachScript()
        script.replacePending("I reported to a technical director and had no direct reports.", since: [])
        for messages in [CoachPrompt.request(turns: turns, background: background, frames: [], audio: nil, stage: .hr),
                         CoachPrompt.reviewRequest(turns: turns, background: background, frames: [], script: script, stage: .hr)] {
            let content = try #require(messages[1]["content"] as? [[String: Any]])
            let reference = try #require(content.first?["text"] as? String)
            #expect(reference.contains("one Android engineer, one iOS engineer and three web engineers"))
            #expect(reference.contains("initially owned Android and later moved to responsibility for RAG"))
            #expect(reference.contains("He reported to the CTO"))
            #expect(reference.contains("Kezhi direct-report count is unknown"))
        }
        for company in ["KKday", "Debon Securities", "Ping An Securities"] {
            let found = CoachKnowledge.retrieve(background,
                query: "At \(company), how was the team organised and who did you report to?")
            #expect(found.contains("Recorded organisation boundary for \(company):"))
            #expect(found.contains("reporting manager"))
            #expect(found.contains("unknown in this record"))
        }
        let pingAn = CoachKnowledge.retrieve(background, query: "At Ping An Securities, how many Android, iOS, web, backend and QA staff were there, and who did you report to?")
        #expect(pingAn.contains("five Android engineers, five iOS engineers, ten web engineers, ten testers and around ten backend engineers"))
        #expect(pingAn.contains("reported to the project manager"))
        let debon = CoachKnowledge.retrieve(background, query: "At Debon Securities, how many Android, iOS, web, backend and QA staff were there?")
        #expect(debon.contains("three iOS engineers, three Android engineers, five web engineers, eight backend engineers and five testers"))
        let aihuishou = CoachKnowledge.retrieve(background, query: "Why do Aihuishou and Ping An Haoxue dates overlap? Was Aihuishou full-time employment?")
        #expect(aihuishou.contains("part-time consulting side project on the Aihuishou Android app"))
        #expect(aihuishou.contains("outside working hours while I was full-time at Ping An Haoxue"))
        #expect(aihuishou.contains("Selected Projects rather than Professional Experience"))
    }
    @Test func promptRequestsFullSpeakableAnswerAndIncludesOCRAndImmutableSpeech() throws {
        let frame = CoachFrame(jpeg: Data([1]), seconds: 2, ocr: "First token: 850 ms")
        let messages = CoachPrompt.request(turns: [], background: "", frames: [frame], audio: nil, committed: "I use Room.")
        let text = String(data: try JSONSerialization.data(withJSONObject: messages), encoding: .utf8) ?? ""
        #expect(text.contains("COMPLETE"))
        #expect(text.contains("B1–B2"))
        #expect(text.contains("850 ms"))
        #expect(text.contains("I use Room."))
        #expect(CoachOutput("I would use Room. Then I add a worker.").next == "I would use Room. Then I add a worker.")
    }
}
