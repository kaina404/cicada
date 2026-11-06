import Foundation
import Testing
@testable import Cicada

struct ScreenNotesTests {
    @Test func textBoxesReadRowByRowLeftToRight() {
        // Vision's y grows upwards: the title is the highest box.
        let text = ScreenWatch.rows([(y: 0.50, h: 0.04, x: 0.6, text: "$1.28M"),
                                     (y: 0.90, h: 0.06, x: 0.1, text: "October spend"),
                                     (y: 0.51, h: 0.04, x: 0.1, text: "Total"),
                                     (y: 0.40, h: 0.04, x: 0.1, text: "YoY +12.3%")])
        #expect(text == "October spend\nTotal  $1.28M\nYoY +12.3%")
    }

    @Test func numbersTheModelMadeUpAreFlagged() {
        let ocr = "Total  $1,284\nYoY +12.3%  Q3 FY26"
        #expect(ScreenWatch.unverified("Spend was $1284 in Q3 FY26, up 12.3%", ocr: ocr).isEmpty)
        #expect(ScreenWatch.unverified("up 13.2% to 1,284", ocr: ocr) == ["13.2"])
    }

    @Test func theLineKeepsTheExactTextAndSaysWhatIsUnsure() {
        let m = ScreenWatch.Meaning(slide: true, title: "Q3", meaning: "Revenue grew 13.2%.", uncertain: nil)
        let line = ScreenWatch.compose(ocr: "Revenue\nYoY +12.3%", meaning: m)
        #expect(line == "含义：《Q3》Revenue grew 13.2%.\n不确定：原文里没有 13.2\n原文：Revenue / YoY +12.3%")
        #expect(ScreenWatch.compose(ocr: "Revenue\n+12.3%", meaning: nil) == "原文：Revenue / +12.3%")
    }

    @Test func theModelsJSONIsFoundInsideAFence() {
        let m = ScreenWatch.parseMeaning("```json\n{\"slide\": true, \"title\": \"Q3\", \"meaning\": \"运营支出 $1.28M\"}\n```")
        #expect(m?.title == "Q3" && m?.slide == true && m?.meaning == "运营支出 $1.28M")
        #expect(ScreenWatch.parseMeaning("no json here") == nil)
    }

    @Test func aPageReadAgainIsNotNew() {
        #expect(!ScreenWatch.novel("Revenue YoY +12.3% Q3", after: "Revenue YoY +12.3% Q3"))
        #expect(ScreenWatch.novel("Headcount 412 Hiring plan", after: "Revenue YoY +12.3% Q3"))
        #expect(!ScreenWatch.novel("", after: ""))
    }

    @Test func pageDifference() {
        let a = [UInt8](repeating: 0, count: 1024), b = [UInt8](repeating: 255, count: 1024)
        #expect(ScreenWatch.difference(a, a) == 0)
        #expect(ScreenWatch.difference(a, b) == 1)
    }

    @MainActor @Test func screenLinesAreNoSpeakerAndNoSubtitle() {
        let lines = [TranscriptLine(id: "h1", t: 1, speaker: "them", src: "As you can see", srcLang: "en", dstLang: "zh"),
                     TranscriptLine(id: "s2", t: 2, speaker: "screen", src: "原文：Spend $1.28M", srcLang: "", dstLang: "", shot: "screens/00002.jpg")]
        let prompt = NotesEngine.prompt(notes: MeetingNotes(), lines: lines, from: 0, language: "Chinese", final: true)
        #expect(prompt.contains("[L2 00:02 屏幕] 原文：Spend $1.28M"))
        let s = Session(id: "x", title: "t", startedAt: Date(), endedAt: nil, lines: lines, hasAudio: false)
        #expect(!TranscriptExport.srt(s).contains("1.28M"))
        #expect(TranscriptExport.markdown(s).contains("屏幕"))
        // The record format: an older line without `shot` still reads.
        let old = #"{"id":"h1","t":1,"speaker":"them","src":"a","srcLang":"en","dstLang":"zh"}"#
        #expect((try? JSONDecoder().decode(TranscriptLine.self, from: Data(old.utf8)))?.shot == nil)
    }
}
