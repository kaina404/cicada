import Foundation
import Testing
@testable import Cicada

struct ShadowTimelineTests {
    @Test func audioClockRecomputesPartialFillGapsAndBackwardSeek() {
        let words = [ShadowWordTiming(text: "Hello", start: 1, end: 2),
                     ShadowWordTiming(text: "world", start: 3, end: 4)]
        var playback = ShadowPlayback(words: ShadowPlayback.align(words, to: ["hello", "world"], startingAt: 0))
        playback.seconds = 1.5
        #expect(playback.currentWord == 0 && playback.progress(for: 0) == 0.5)
        playback.seconds = 2.8
        #expect(playback.progress(for: 0) == 1 && playback.progress(for: 1) == 0)
        playback.seconds = 3.5
        #expect(playback.currentWord == 1 && playback.progress(for: 1) == 0.5)
        playback.seconds = 1.25
        #expect(playback.currentWord == 0 && playback.progress(for: 0) == 0.25)
        #expect(playback.progress(for: 1) == 0)
        playback.seconds = 0
        #expect(playback.currentWord == nil)
        #expect(ShadowWordTiming(text: ".", start: 2, end: 2).progress(at: 2) == 1)
    }
    @Test func tokensPreserveContractionsAndNeverGuessMismatches() {
        let words = [ShadowWordTiming(text: "Don't", start: 0, end: 1),
                     ShadowWordTiming(text: "retry", start: 1.5, end: 2)]
        let mapped = ShadowPlayback.align(words, to: ["we", "don", "t", "retry"], startingAt: 1)
        #expect(mapped.map(\.range) == [1..<3, 3..<4])
        #expect(ShadowPlayback.align(words, to: ["do", "retry"], startingAt: 0).isEmpty)
    }
    @Test func originalOffsetsKeepIPAUnicodeHyphensAndPunctuation() {
        let text = "We persist /pəˈsɪst/ don't retry. 缓存 end-to-end."
        let ranges = ShadowPlayback.displayRanges(text)
        #expect(ranges.map { (text as NSString).substring(with: $0) } ==
                ["We", "persist", "don", "t", "retry", "缓存", "end", "to", "end"])
        let ascii = "A cache /kæʃ/ and /api/v1 path."
        #expect(ShadowPlayback.displayRanges(ascii).map { (ascii as NSString).substring(with: $0) } ==
                ["A", "cache", "and", "api", "v1", "path"])
    }
}
