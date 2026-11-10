import Foundation

/// Playback position belongs to audio alone, never to the candidate's spoken evidence.
struct ShadowPlan {
    private(set) var answerID = ""
    private(set) var text = ""
    private(set) var words: [String] = []
    private(set) var cursor = 0
    private var ranges: [Range<String.Index>] = []

    mutating func update(id: String, text: String, finished: Bool) -> Bool {
        let clean = CoachPronunciation.spokenText(text)
        let changed = id != answerID || !clean.hasPrefix(self.text)
        if changed { self = ShadowPlan(); answerID = id }
        // A streaming tail can still change; only complete sentences enter synthesis.
        var stable = clean
        if !finished {
            var boundary: String.Index?
            for index in clean.indices {
                let next = clean.index(after: index)
                if clean[index].isNewline || ".!?".contains(clean[index]) && next < clean.endIndex && clean[next].isWhitespace {
                    boundary = next
                }
            }
            stable = boundary.map { String(clean[..<$0]) } ?? ""
        }
        if stable.hasPrefix(self.text) {
            self.text = stable
            if let regex = try? NSRegularExpression(pattern: #"[\p{L}\p{N}]+"#) {
                ranges = regex.matches(in: stable, range: NSRange(stable.startIndex..., in: stable))
                    .compactMap { Range($0.range, in: stable) }
            }
            words = ranges.map { String(stable[$0]).lowercased() }
        }
        return changed
    }

    mutating func seek(to word: Int) { cursor = min(words.count, max(0, word)) }

    mutating func advance(to end: Int) { cursor = max(cursor, min(words.count, end)) }

    /// Shared sentence boundaries for synthesis and Watch navigation; decimals are not stops.
    var sentenceStarts: [Int] {
        guard !ranges.isEmpty else { return [] }
        return [0] + (1..<ranges.count).filter { index in
            let gap = text[ranges[index - 1].upperBound..<ranges[index].lowerBound]
            return gap.contains("\n") || (gap.contains(where: { ".!?".contains($0) }) && gap.contains(where: { $0.isWhitespace }))
        }
    }

    func sentenceStart(at word: Int, offset: Int) -> Int? {
        let starts = sentenceStarts
        guard let current = starts.lastIndex(where: { $0 <= word }) else { return nil }
        return starts[min(starts.count - 1, max(0, current + offset))]
    }

    func phrase(from start: Int) -> (text: String, end: Int)? {
        guard start >= 0, start < ranges.count else { return nil }
        let end = sentenceStarts.first(where: { $0 > start }) ?? ranges.count
        let upper = end < ranges.count ? ranges[end].lowerBound : text.endIndex
        return (String(text[ranges[start].lowerBound..<upper]).trimmingCharacters(in: .whitespacesAndNewlines), end)
    }
}
