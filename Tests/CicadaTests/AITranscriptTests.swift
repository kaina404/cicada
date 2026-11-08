import Foundation
import Testing
@testable import Cicada

@MainActor struct AITranscriptTests {
    let heard = TranscriptLine(id: "h1", t: 1, speaker: "them", src: "The budget is 42.", srcLang: "en", dstLang: "zh-CN")
    let ai = TranscriptLine(id: "a2", t: 2, speaker: "ai", src: "Q: What should we do?\n- Secret assistant fact.\n> Propose a test.", dst: "中文对照", srcLang: "en", dstLang: "zh-CN")

    @Test func classificationAndEvidenceKeepAIOutOfMeetingFacts() {
        #expect(ai.isAI && !ai.isSpoken && !ai.isScreen)
        #expect(heard.isSpoken && !heard.isAI)
        let notes = NotesEngine.prompt(notes: MeetingNotes(), lines: [heard, ai, heard], from: 2, language: "English", final: false)
        #expect(!notes.contains("Secret assistant fact"))
        #expect(notes.contains("[L3"))
        let request = AskPrompt.request(lines: [heard, ai], now: 3, partial: "")
        #expect(!request.user.contains("Secret assistant fact"))
        #expect(!CopilotRules.needsResponse(ai.src, speaker: "ai"))
        #expect(SpeakerLabels.numbers([ai]).isEmpty)
        #expect(SpeakerLabels.runStarts([heard, ai, heard], [:]).contains(ai.id))
        #expect(AskPrompt.history([heard, ai]).first?.points == ["Secret assistant fact."])
    }

    @Test func completeRecordRoundTripsAndExportsSeparateAIFromSubtitles() throws {
        let session = Session(id: "fixture", title: "Test", startedAt: Date(timeIntervalSince1970: 0), lines: [heard, ai], hasAudio: false)
        let data = try JSONEncoder().encode(session)
        #expect(try JSONDecoder().decode(Session.self, from: data) == session)
        #expect(!TranscriptExport.srt(session).contains("Secret assistant fact"))
        #expect(TranscriptExport.markdown(session).contains("AI"))
        #expect(TranscriptExport.markdown(session).contains("Secret assistant fact"))
        #expect(AskPrompt.recordTime(trigger: 10, last: 15) == 15)
        #expect(AskPrompt.recordTime(trigger: 20, last: 15) == 20)
    }

    @Test func glossIsSavedOnlyWhenAllRowsAreTranslated() {
        let reply = AskPrompt.parse(ai.src)
        #expect(AskPrompt.transcript(reply) == ai.src)
        #expect(AskPrompt.transcript(reply, translated: [reply.understood: "问题"]) == nil)
        let gloss = Dictionary(uniqueKeysWithValues: ([reply.understood] + reply.points + reply.suggestions).map { ($0, "中文" + $0) })
        #expect(AskPrompt.transcript(reply, translated: gloss)?.components(separatedBy: "\n").count == 3)
        #expect(AskPrompt.history(Array(repeating: ai, count: 5)).count == 3)
    }
}
