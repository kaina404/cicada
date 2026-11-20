import Foundation
import Testing
@testable import Cicada

struct QwenLiveTests {
    @Test func targetCodesAreBare() {
        #expect(QwenLiveSession.language("zh-CN") == "zh")
        #expect(QwenLiveSession.language("en") == "en")
        #expect(QwenLiveSession.language("pt-BR") == "pt")
    }

    @Test func rawPCMPassesThrough() {
        let pcm = Data((0..<100).map { UInt8($0) })
        #expect(QwenLiveSession.stripWAVHeader(pcm) == pcm)
    }

    @Test func wavHeaderIsStripped() {
        var d = Data("RIFF".utf8) + Data([0, 0, 0, 0]) + Data("WAVE".utf8)
        d += Data("fmt ".utf8) + Data([16, 0, 0, 0]) + Data(repeating: 0, count: 16)
        let samples = Data([1, 2, 3, 4, 5, 6])
        d += Data("data".utf8) + Data([6, 0, 0, 0]) + samples
        #expect(QwenLiveSession.stripWAVHeader(d) == samples)
    }
}
