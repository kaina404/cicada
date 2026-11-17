import Foundation
import Testing
@testable import Cicada

/// Walkthrough working memory (docs/walkthrough-coach-plan.md §2), against the requirement scenarios.
struct CoachCaseTests {
    private let evidence = CoachEvidence(interviewer: ["I1", "I2", "I3", "I4"], candidate: ["C1", "C2"], board: ["B1", "B2"])
    private func op(_ op: String, _ text: String? = nil, _ ids: [String]? = nil, id: String? = nil) -> CoachCaseOp {
        CoachCaseOp(op: op, text: text, id: id, evidence: ids)
    }

    @Test func catToDogThenAToBThenBackToAKeepsLaterConstraints() {
        var c = CoachCase()
        c.apply([op("newProblem", "Chat screen with send and retry"),
                 op("constraint", "Works offline", ["I1"]),
                 op("adopt", "val cat = 1", ["I1"])], evidence: evidence, at: 10)
        // AC-05: a rename replaces the adopted name; the old one is kept as history, not advice.
        c.apply([op("adopt", "val dog = 1", ["I2"])], evidence: evidence, at: 20)
        #expect(c.problem?.adopted?.text == "val dog = 1")
        #expect(c.problem?.abandoned.map(\.text) == ["val cat = 1"])
        #expect(c.problem?.abandoned.first?.status == .superseded)
        // AC-03: the interviewer chose B, the board still shows A; both are true at once.
        c.apply([op("implemented", "RxJava stream in ChatViewModel", ["B1"]),
                 op("constraint", "Max 20 items per page", ["I3"]),
                 op("adopt", "Kotlin Flow", ["I3"])], evidence: evidence, at: 30)
        #expect(c.problem?.adopted?.text == "Kotlin Flow")
        #expect(c.problem?.implemented.map(\.text) == ["RxJava stream in ChatViewModel"])
        // AC-12: going back to an earlier choice keeps the constraints added since.
        c.apply([op("adopt", "val dog = 1", ["I4"])], evidence: evidence, at: 40)
        #expect(c.problem?.adopted?.text == "val dog = 1")
        #expect(c.problem?.constraints.map(\.text) == ["Works offline", "Max 20 items per page"])
        #expect(c.problem?.abandoned.contains { $0.text == "Kotlin Flow" } == true)
        #expect(c.problem?.abandoned.contains { $0.text == "val dog = 1" } == false)
    }

    @Test func aTentativeQuestionStaysAnAlternative() {
        var c = CoachCase()
        c.apply([op("newProblem", "Feed screen"), op("adopt", "Compose", ["I1"])], evidence: evidence, at: 0)
        // AC-04: "Could we use XML here?" has no one choosing it, so nothing is switched.
        c.apply([op("adopt", "XML + RecyclerView", [])], evidence: evidence, at: 5)
        c.apply([op("adopt", "Paging 3", ["B1"])], evidence: evidence, at: 6)
        #expect(c.problem?.adopted?.text == "Compose")
        #expect(c.problem?.alternatives == ["XML + RecyclerView", "Paging 3"])
    }

    @Test func aTentativeQuestionCannotBeTheEvidenceForADecision() {
        // Seen live (AC-04): "Hmm, could we use Flow here instead?" was recorded as adopting Flow.
        #expect(CoachEvidence.isTentative("Hmm, could we use Flow here instead?"))
        #expect(CoachEvidence.isTentative("What about Paging 3?"))
        #expect(!CoachEvidence.isTentative("Can you switch it to Flow?"))
        #expect(!CoachEvidence.isTentative("Let's switch this to Kotlin Flow."))
        var e = evidence; e.tentative = ["I2"]
        var c = CoachCase()
        c.apply([op("newProblem", "Load messages"), op("adopt", "RxJava", ["I1"]), op("adopt", "Flow", ["I2"])], evidence: e, at: 0)
        #expect(c.problem?.adopted?.text == "RxJava")
        #expect(c.problem?.alternatives == ["Flow"])
    }

    @Test func coverageAndImplementationNeedRealEvidence() {
        var c = CoachCase()
        c.apply([op("newProblem", "Bundle explained"),
                 op("spoken", "Bundle survives process death", ["I1"]),   // the interviewer's words are not coverage
                 op("spoken", "Bundle has a size limit", ["X9"]),          // an invented ID is not evidence
                 op("spoken", "Bundle keeps key-value pairs", ["C1"]),
                 op("implemented", "retry() on the board", []),
                 op("implemented", "retry() on the board", ["B2"]),
                 op("constraint", "Explain briefly", [])], evidence: evidence, at: 0)
        #expect(c.problem?.spoken == ["Bundle keeps key-value pairs"])
        #expect(c.problem?.implemented.map(\.source) == [.board])
        #expect(c.problem?.constraints.first?.status == .unconfirmed)
    }

    @Test func nestedFollowUpsAndProblemSwitchesKeepWhereToReturn() {
        var c = CoachCase()
        c.apply([op("newProblem", "Chat screen", id: "chat"), op("pending", "Retry failed sends")], evidence: evidence, at: 0)
        c.apply([op("pushAside", "Why StateFlow?"), op("pushAside", "And SharedFlow?")], evidence: evidence, at: 5)
        #expect(c.asides.map(\.question) == ["Why StateFlow?", "And SharedFlow?"])
        #expect(c.asides.first?.returnTo == "Retry failed sends")
        c.apply([op("popAside")], evidence: evidence, at: 6)
        #expect(c.asides.map(\.question) == ["Why StateFlow?"])
        // AC-10: a new problem keeps the old one, which can be resumed later.
        c.apply([op("newProblem", "Explain Bundle", id: "bundle")], evidence: evidence, at: 10)
        #expect(c.problem?.id == "bundle")
        #expect(c.asides.isEmpty)
        c.apply([op("switch", id: "chat")], evidence: evidence, at: 20)
        #expect(c.problem?.goal == "Chat screen")
        #expect(c.problem?.pending == ["Retry failed sends"])
        #expect(c.problems.count == 2)
    }

    @Test func theLogOnlyGrowsAndCorrectionsPointBack() {
        var c = CoachCase()
        c.apply([op("newProblem", "Chat screen"), op("adopt", "val cat = 1", ["I1"])], evidence: evidence, at: 0)
        let before = c.log
        c.apply([CoachCaseOp(op: "correct", text: "Interviewer said dog, not dock", of: "E2")], evidence: evidence, at: 9)
        c.apply([CoachCaseOp(op: "correct", text: "Points at nothing", of: "E99")], evidence: evidence, at: 9)
        #expect(Array(c.log.prefix(before.count)) == before)
        #expect(c.log.last?.corrects == "E2")
        #expect(c.log.count == before.count + 1)
    }

    @Test func aCancelledRequestLeavesItsChangesForTheNextOne() {
        var base = CoachBase()
        let first = [CoachTurn(id: "L1", seconds: 0, role: "interviewer", text: "Design a feed")]
        base.confirm(turns: first, board: ["GET /v1/feed?cursor=\"abc123\"&limit<20>&after"])
        let more = first + [CoachTurn(id: "L2", seconds: 5, role: "interviewer", text: "Use dog")]
        // Request built, then cancelled: nothing confirmed, so the next request still sees L2.
        #expect(base.newLines(more).map(\.id) == ["L2"])
        #expect(base.newLines(more).map(\.id) == ["L2"])
        base.confirm(turns: more, board: [])
        #expect(base.newLines(more).isEmpty)
    }

    @Test func boardTextThatOnlyScrolledIntoViewIsNotNew() {
        // P0, pair at 1100 s: DeepSeek listed these as added after a pan; only Authorization was new.
        var base = CoachBase()
        base.confirm(turns: [], board: ["Comment 1", "GET /v1/feed?cursor=\"abc123\"&limit<20>&after",
                                        "(PaginationMetadata(after, before, cursor, reachedEnd,limit,...)",
                                        "Author(id: String, name:String, avatarURL:, activeAt, ...)"])
        let read = ["Comment 1", "GET /v1/feed?cursor=\"abc123\"&limit<20>&after",
                    "Response (PaginationMetadata(after, before, cursor, reachedEnd, limit, ...)",
                    "Author(id: String, name:String, avatarURL; activeAt, ...)",
                    "Authorization : Bearer <token_API>"]
        #expect(base.newBoard(read) == ["Authorization : Bearer <token_API>"])
    }
}

struct CoachCardTests {
    @Test func streamsSayFirstAndAppliesCaseOnlyWhenFinished() throws {
        let raw = """
        <<<CICADA_CARD>>>
        HEARD: rename cat to dog
        SAY:
        OK, I'll rename it to dog.
        TYPE: replace at="val cat"
        ```kotlin
        val dog = 1
            .let { it }
        ```
        THEN: Next, I'll add the retry logic.
        REASON: (optional) Shorter names read better.
        CASE: [{"op":"adopt","text":"val dog = 1","evidence":["I2"]}]
        """
        let partial = String(raw.prefix(upTo: raw.range(of: "TYPE")!.lowerBound)) + "TY"
        let early = try #require(try CoachCard.parse(partial, finished: false))
        #expect(early.say == "OK, I'll rename it to dog.")
        #expect(early.edit == nil)
        #expect(early.ops.isEmpty)
        let card = try #require(try CoachCard.parse(raw, finished: true))
        #expect(card.heard == "rename cat to dog")
        #expect(card.edit == CoachCard.Edit(action: "replace", at: "val cat", language: "kotlin", code: "val dog = 1\n    .let { it }"))
        #expect(card.then == "Next, I'll add the retry logic.")
        #expect(card.reason == "(optional) Shorter names read better.")
        #expect(card.ops == [CoachCaseOp(op: "adopt", text: "val dog = 1", evidence: ["I2"])])
    }

    @Test func codeLinesThatLookLikeHeadersStayCode() throws {
        let raw = "<<<CICADA_CARD>>>\nSAY:\nI'll write the state.\nTYPE: add at=\"ChatViewModel\"\n```kotlin\nTHEN: not a header\n```\nTHEN: Then the UI."
        let card = try #require(try CoachCard.parse(raw, finished: true))
        #expect(card.edit?.code == "THEN: not a header")
        #expect(card.then == "Then the UI.")
    }

    @Test func keepMalformedCaseAndEmptyCards() throws {
        #expect(try CoachCard.parse("<<<CICADA_CARD>>>\nKEEP", finished: true)?.keep == true)
        let bad = try #require(try CoachCard.parse("<<<CICADA_CARD>>>\nSAY:\nSure.\nCASE: [{oops", finished: true))
        #expect(bad.say == "Sure.")
        #expect(bad.ops.isEmpty)
        #expect(try CoachCard.parse("thinking…", finished: false) == nil)
        #expect(throws: (any Error).self) { try CoachCard.parse("<<<CICADA_CARD>>>\nTHEN: x", finished: true) }
        #expect(throws: (any Error).self) { try CoachCard.parse("no marker", finished: true) }
    }

    @Test func aGarbledOrMissingMarkerStillYieldsTheCard() throws {
        // Seen live: DeepSeek wrote "<<<CICARD>>>" and the whole card was lost.
        #expect(try CoachCard.parse("<<<CICARD>>>\nSAY:\nOkay, I'll rename it.", finished: true)?.say == "Okay, I'll rename it.")
        #expect(try CoachCard.parse("SAY:\nSure.\nTHEN: Next.", finished: true)?.then == "Next.")
        #expect(try CoachCard.parse("SA", finished: false) == nil)
        #expect(try CoachCard.parse("KEEP", finished: true)?.keep == true)
        // Seen live (AC-18): an empty TYPE header showed an empty code card.
        #expect(try CoachCard.parse("<<<CICADA_CARD>>>\nSAY:\nA ViewModel holds screen state.\nTYPE: add at=\"\"\nTHEN: Wait.", finished: true)?.edit == nil)
    }

    @Test func fencedCodeDoesNotCountAsReadingWords() {
        #expect(CoachScript.words("I'll add it.\n```kotlin\nval dog = 1\n```\nDone.") == ["i", "ll", "add", "it", "done"])
        #expect(CoachScript.words("First.\n```kotlin\nval dog") == ["first"])
    }
}

struct CoachCardScheduleTests {
    @Test func candidateSpeechAndTypingNeverCancelTheRunningRequest() {
        var s = CoachCardSchedule()
        #expect(s.receive(.interviewer, now: 0) == .start(.interviewer))
        for t in 1...20 {
            #expect(s.receive(.check, now: Double(t)) == .none)
            #expect(s.receive(.board, now: Double(t)) == .none)
        }
        #expect(s.running == .interviewer)
        // AC-15: everything that arrived meanwhile becomes one follow-up request.
        #expect(s.finished(now: 21) == .start(.check))
        #expect(s.finished(now: 22) == .none)
    }

    @Test func aNewInterviewerTurnOrManualActionRestarts() {
        var s = CoachCardSchedule()
        _ = s.receive(.check, now: 0)
        _ = s.receive(.board, now: 1)
        #expect(s.receive(.interviewer, now: 2) == .restart(.interviewer))
        #expect(s.queued == nil)
        #expect(s.receive(.manual, now: 3) == .restart(.manual))
    }

    @Test func boardChangesAreThrottledButNotForgotten() {
        var s = CoachCardSchedule()
        #expect(s.receive(.board, now: 0) == .start(.board))
        #expect(s.finished(now: 1) == .none)
        #expect(s.receive(.board, now: 2) == .none)
        #expect(s.tick(now: 3) == .none)
        #expect(s.tick(now: 5.1) == .start(.board))
    }
}
