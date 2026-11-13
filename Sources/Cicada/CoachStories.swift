import Foundation

/// A story the knowledge marks so the coach can tell when the candidate has already told it. In a
/// long interview DeepSeek retold the best-fitting story (the KKday SKU one) whenever it fitted,
/// because the first telling was far back in the transcript or out of it.
///
/// Knowledge line, anywhere, on its own: `story: kkday-sku | SKU, 300 milliseconds / 300 ms`.
/// Commas separate keywords, slashes alternatives (ASR spells numbers either way).
struct CoachStory: Equatable {
    var id: String
    var keywords: [[String]]

    static func parse(_ knowledge: String) -> [CoachStory] {
        knowledge.split(whereSeparator: \.isNewline).compactMap { raw in
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("- ") { line.removeFirst(2) }
            guard line.lowercased().hasPrefix("story:") else { return nil }
            let halves = line.dropFirst(6).split(separator: "|", maxSplits: 1)
            guard halves.count == 2 else { return nil }
            let id = halves[0].trimmingCharacters(in: .whitespaces)
            let keywords = halves[1].split(separator: ",")
                .map { $0.split(separator: "/").map { words(String($0)) }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
                .filter { !$0.isEmpty }
            guard !id.isEmpty, !keywords.isEmpty else { return nil }
            return CoachStory(id: id, keywords: keywords)
        }
    }

    /// Lowercased words between single spaces, padded so `contains` matches whole words only.
    static func words(_ text: String) -> String {
        " " + text.lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: " ") + " "
    }

    /// Two keywords, not one: a passing "at KKday" is not the story. Missing a telling only costs a
    /// repeat; a false one would hide the best example for the rest of the interview.
    func isTold(in text: String) -> Bool {
        let heard = Self.words(text)
        let hits = keywords.filter { $0.contains { heard.contains($0) } }.count
        return hits >= min(2, keywords.count)
    }

    /// From the candidate's actual speech, never the teleprompter: an answer they skipped is not told.
    /// ASR splits one answer into lines, so each run of candidate lines is checked as one answer.
    static func told(_ stories: [CoachStory], in turns: [CoachTurn]) -> [(id: String, seconds: Double)] {
        var answers: [(seconds: Double, text: String)] = []
        var open = false
        for turn in turns {
            guard turn.role == "candidate" else { open = false; continue }
            if open { answers[answers.count - 1].text += " " + turn.text }
            else { answers.append((turn.seconds, turn.text)); open = true }
        }
        return stories.compactMap { story in
            answers.first { story.isTold(in: $0.text) }.map { (story.id, $0.seconds) }
        }
    }

    static func ledger(background: String, turns: [CoachTurn]) -> String? {
        let told = told(parse(background), in: turns)
        guard !told.isEmpty else { return nil }
        let list = told.map { String(format: "%@ (at %d:%02d)", $0.id, Int($0.seconds) / 60, Int($0.seconds) % 60) }
        return "Stories the candidate has already told in this interview, from their actual speech (ids from the story: lines in <knowledge>): "
            + list.joined(separator: ", ")
            + ". Do not tell these again in full: point back in one short clause, or use a different example from <knowledge>."
    }
}
