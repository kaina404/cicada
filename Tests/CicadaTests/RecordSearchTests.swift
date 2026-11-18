import Foundation
import Testing
@testable import Cicada

/// The records search runs on every live line; only meetings that changed are searched again.
@Test func recordSearchOnlyRechecksMeetingsThatChanged() {
    func line(_ id: String, _ text: String) -> TranscriptLine {
        TranscriptLine(id: id, t: 1, speaker: "them", src: text, srcLang: "en", dstLang: "zh-CN")
    }
    var sessions = (0..<50).map { i in
        Session(id: "s\(i)", title: "Meeting \(i)", startedAt: Date(timeIntervalSince1970: 0),
                lines: [line("a", i == 7 ? "the flowchart" : "nothing here")], hasAudio: false)
    }
    let search = RecordSearch()
    #expect(search.filter(sessions, query: "flowchart").map(\.id) == ["s7"])
    #expect(search.searched == 50)
    // A live line on one meeting: only that meeting is searched again, and a new match shows.
    sessions[3].lines.append(line("b", "a FlowChart now"))
    #expect(search.filter(sessions, query: "flowchart").map(\.id) == ["s3", "s7"])
    #expect(search.searched == 51)
    // A new query searches everything again.
    #expect(search.filter(sessions, query: "nothing").count == 49)
    #expect(search.searched == 101)
    #expect(search.filter(sessions, query: "").count == 50)
}
