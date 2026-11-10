import Foundation

struct ShadowWordTiming: Equatable, Sendable {
    var text: String
    var start: Double
    var end: Double
    func progress(at seconds: Double) -> Double {
        guard seconds.isFinite else { return 0 }
        if end == start { return seconds >= end ? 1 : 0 }
        return min(1, max(0, (seconds - start) / (end - start)))
    }
}

/// Positions are in the original script's spoken words, independent of microphone evidence.
struct ShadowPlayback: Equatable {
    var answerID = ""
    var seconds = 0.0
    var anchorWord: Int?
    var words: [Word] = []
    struct Word: Equatable {
        var range: Range<Int>
        var timing: ShadowWordTiming
    }
    var currentWord: Int? { words.last(where: { $0.timing.start <= seconds })?.range.lowerBound ?? anchorWord }
    func progress(for word: Int) -> Double {
        words.first(where: { $0.range.contains(word) })?.timing.progress(at: seconds) ?? 0
    }
    static func align(_ timings: [ShadowWordTiming], to expected: [String], startingAt start: Int) -> [Word] {
        var cursor = start
        var result: [Word] = []
        for timing in timings {
            let parts = CoachScript.words(timing.text)
            guard !parts.isEmpty else { continue }
            guard cursor + parts.count <= expected.count,
                  Array(expected[cursor..<(cursor + parts.count)]) == parts else { return [] }
            result.append(Word(range: cursor..<(cursor + parts.count), timing: timing))
            cursor += parts.count
        }
        return result
    }

    /// spokenText only removes annotations. Retain UTF-16 source offsets so IPA and punctuation
    /// stay visible, with no substitution of the original script by the synthesizer's tokens.
    static func displayRanges(_ text: String) -> [NSRange] {
        let original = Array(text.utf16), clean = Array(CoachPronunciation.spokenText(text).utf16)
        let changes = clean.difference(from: original)
        var removed = Set<Int>()
        for change in changes {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert: return []
            }
        }
        let offsets = original.indices.filter { !removed.contains($0) }
        guard offsets.count == clean.count,
              let expression = try? NSRegularExpression(pattern: #"[\p{L}\p{N}]+"#) else { return [] }
        let spoken = CoachPronunciation.spokenText(text)
        return expression.matches(in: spoken, range: NSRange(location: 0, length: clean.count)).map {
            let first = offsets[$0.range.location], last = offsets[NSMaxRange($0.range) - 1]
            return NSRange(location: first, length: last - first + 1)
        }
    }
}
