import Foundation
import Testing
@testable import Cicada

struct CandidateTests {
    @Test func streamingMarkersAndPlanNeverLeak() {
        let raw = "→ Clarify offline scope\nI would start with Room.\n[[more]]"
        for n in 1...raw.count {
            let partial = CandidateOutput(String(raw.prefix(n)))
            #expect(!partial.text.contains("[["))
            #expect(!partial.text.hasSuffix("["))
        }
        let malformed = CandidateOutput("→ Explain buffering I would retain every delta. [[end]]", finished: true)
        #expect(malformed.plan.isEmpty)
        #expect(malformed.text.contains("retain every delta"))
        #expect(CandidateOutput("→ Still writing the plan").text.isEmpty)
        let parsed = CandidateOutput(raw)
        #expect(parsed.plan == "Clarify offline scope")
        #expect(parsed.text == "I would start with Room.")
        #expect(parsed.marker == .more)
        #expect(CandidateOutput("Half a sentence").marker == .end)
        #expect(CandidateOutput("An answer\n[[end]]").text == "An answer")
    }
    @Test func continuationAndInterrupt() {
        var loop = CandidateLoop()
        loop.responseStarted("one")
        #expect(loop.accepts("one"))
        loop.responseDone(.more, now: 0)
        let observed1 = !loop.tick(now: 1.19)
        #expect(observed1)
        let observed2 = loop.tick(now: 1.2)
        #expect(observed2)
        let observed3 = !loop.tick(now: 2)
        #expect(observed3)
        loop.responseStarted("two")
        let observed4 = loop.speechStarted() == "two"
        #expect(observed4)
        #expect(!loop.accepts("two"))
        #expect(loop.continues == 0)
        let observed5 = !loop.tick(now: 20)
        #expect(observed5)
        loop.speechStopped()
        let observed6 = !loop.tick(now: 30)
        #expect(observed6)
        for i in 0..<8 {
            loop.responseStarted("\(i)")
            loop.responseDone(.more, now: Double(i) * 3)
            let observed7 = loop.tick(now: Double(i) * 3 + 2)
            #expect(observed7)
        }
        loop.responseStarted("last"); loop.responseDone(.more, now: 50)
        let observed8 = !loop.tick(now: 99)
        #expect(observed8)
    }
    @Test func promptAndBoundedRecovery() {
        let prompt = CandidatePrompt.make(background: String(repeating: "resume", count: 2000))
        #expect(prompt.count <= 8000)
        #expect(prompt.contains("[fill in:"))
        #expect(prompt.contains("Never silently discard unsent user messages"))
        #expect(prompt.contains("during\nstreaming, not just when finished"))
        #expect(CandidatePrompt.make(background: "").contains("(none given)"))
        var history = CandidateHistory()
        for i in 0..<30 { history.heard("\(i) " + String(repeating: "a", count: 400)); history.answered("\(i) answer") }
        #expect(history.interviewer.count == 20)
        #expect(history.candidate.count == 10)
        #expect(history.context.count <= 6000)
        #expect(history.context.contains("29 answer"))
    }
    @Test @MainActor func missingKeyAndRoomModeNeverConnect() {
        let engine = CandidateEngine()
        let config = RealtimeConfiguration(workspace: "llm-test", region: "cn-beijing", model: "test")
        engine.start(config: config, key: nil, background: "", roomOnly: false, delay: 1.2, maxContinues: 8)
        #expect(engine.state == .setup)
        engine.start(config: config, key: "test", background: "", roomOnly: true, delay: 1.2, maxContinues: 8)
        #expect(engine.state == .room)
        engine.endMeeting()
        #expect(engine.state == .idle)
    }
    @Test @MainActor func manualAskRetiresResponseBeforeItsFirstDelta() throws {
        let engine = CandidateEngine()
        engine.receive(try JSONDecoder().decode(RealtimeEvent.self, from: Data(#"{"type":"session.updated"}"#.utf8)))
        let created = try JSONDecoder().decode(RealtimeEvent.self, from: Data(#"{"type":"response.created","response":{"id":"empty"}}"#.utf8))
        engine.receive(created)
        engine.ask()
        engine.receive(created)
        #expect(engine.current == nil)
        engine.endMeeting()
    }
    @Test @MainActor func cancelledResponseCannotGrowOrReplaceNewAnswer() throws {
        let engine = CandidateEngine()
        func event(_ json: String) throws { engine.receive(try JSONDecoder().decode(RealtimeEvent.self, from: Data(json.utf8))) }
        try event(#"{"type":"response.created","response":{"id":"old"}}"#)
        try event(#"{"type":"response.text.delta","response_id":"old","delta":"→ Start\nI would use Room"}"#)
        try event(#"{"type":"input_audio_buffer.speech_started"}"#)
        #expect(engine.current == nil)
        #expect(engine.paragraphs.count == 1)
        #expect(engine.paragraphs[0].interrupted)
        #expect(engine.paragraphs[0].output.text == "I would use Room")
        try event(#"{"type":"response.text.delta","response_id":"old","delta":" stale"}"#)
        try event(#"{"type":"response.created","response":{"id":"old"}}"#)
        #expect(engine.current == nil)
        try event(#"{"type":"input_audio_buffer.speech_stopped"}"#)
        try event(#"{"type":"response.created","response":{"id":"new"}}"#)
        try event(#"{"type":"response.text.delta","response_id":"new","delta":"→ Explain\nRoom is a good fit. [[end]]"}"#)
        try event(#"{"type":"response.done","response":{"id":"old","status":"cancelled"}}"#)
        #expect(engine.current?.id == "new")
        try event(#"{"type":"response.done","response":{"id":"new","status":"completed"}}"#)
        #expect(engine.paragraphs.count == 2)
        #expect(!engine.paragraphs[1].interrupted)
        #expect(engine.paragraphs[1].output.text == "Room is a good fit.")
        engine.endMeeting()
    }

}
