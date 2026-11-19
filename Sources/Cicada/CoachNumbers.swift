import Foundation

/// Past-work answers must not carry numbers no source gives. Strict wallet run 1413, P2-change: an update said
/// "after two failed attempts the backend falls back", while the candidate's knowledge only says retries have
/// a limit. The prompt already forbids invented numbers; this drops the sentence that still has one.
enum CoachNumbers {
    /// Questions about the candidate's own work, where every number must come from <knowledge> or the talk.
    static let pastWork = #"(?i)\b(you|your)\b[^.?]{0,40}\b(personally|made|built|owned|led|shipped|changed|worked on)\b|\byour (project|team|role)\b|\btell me about a time\b|\bgive me an example\b"#
    static let words = ["two": "2", "three": "3", "four": "4", "five": "5", "six": "6", "seven": "7", "eight": "8",
                        "nine": "9", "ten": "10", "eleven": "11", "twelve": "12", "twenty": "20", "thirty": "30",
                        "forty": "40", "fifty": "50", "hundred": "100", "thousand": "1000", "twice": "2", "thrice": "3", "dozen": "12"]
    static let number = #"(?i)\b(\d[\d,.]*\d|\d|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|twenty|thirty|forty|fifty|hundred|thousand|twice|thrice|dozen)\b"#

    /// `say` without the sentences whose numbers no source states near a word the sentence also uses.
    static func withoutInvented(_ say: String, question: String, sources: [String]) -> String {
        guard question.range(of: pastWork, options: .regularExpression) != nil else { return say }
        let text = sources.joined(separator: "\n")
        return CoachScript.sentences(say).filter { sentence in
            found(sentence).allSatisfy { sourced($0, in: sentence, text: text) }
        }.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
    }

    private static func found(_ sentence: String) -> [String] {
        let ns = sentence as NSString
        guard let re = try? NSRegularExpression(pattern: number) else { return [] }
        return re.matches(in: sentence, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range).lowercased() }
    }

    /// The number (or its digits) appears in a source within 150 characters of one of the sentence's content
    /// words: "two years" in the background does not make "two failed attempts" true.
    private static func sourced(_ value: String, in sentence: String, text: String) -> Bool {
        let own = CoachCards.contentWords(sentence).subtracting(words.keys)
        let forms = [value] + (words[value].map { [$0] } ?? [])
        for form in forms {
            let pattern = #"(?i)(?<![\w,.])"# + NSRegularExpression.escapedPattern(for: form) + #"(?![\w])"#
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            let ns = text as NSString
            for match in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let start = max(0, match.range.location - 150), end = min(ns.length, match.range.location + match.range.length + 150)
                let near = CoachCards.contentWords(ns.substring(with: NSRange(location: start, length: end - start)))
                if !own.isDisjoint(with: near) { return true }
            }
        }
        return false
    }
}
