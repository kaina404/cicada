import Foundation

/// Actual speech is immutable evidence. The replaceable script is never marked as spoken by a model.
struct CoachScript: Equatable {
    private var modelReading: Bool
    init(modelReading: Bool = false) { self.modelReading = modelReading }
    struct Spoken: Codable, Equatable { var id: String; var text: String }
    private(set) var committed: [Spoken] = []
    private(set) var pending = ""
    private(set) var partial = ""
    private(set) var answerID = UUID().uuidString
    var remainingText: String { Self.droppingWords(cursor, from: pending) }
    var spokenText: String { committed.map(\.text).joined(separator: "\n") }
    private var confirmedWords = 0
    private var previewWords = 0
    var cursor: Int { max(confirmedWords, previewWords) }
    var sentences: [String] { Self.sentences(pending) }
    static func sentences(_ text: String) -> [String] {
        var result: [String] = []; var sentence = ""
        for index in text.indices {
            let character = text[index]
            sentence.append(character)
            let next = text.index(after: index)
            let boundary = next == text.endIndex || text[next].isWhitespace
            if character.isNewline || ".!?".contains(character) && boundary {
                let value = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { result.append(value) }
                sentence = ""
            }
        }
        let value = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty { result.append(value) }
        return result
    }
    var currentSentence: Int {
        var count = 0
        for (index, sentence) in sentences.enumerated() {
            count += Self.words(sentence).count
            if cursor < count { return index }
        }
        return max(0, sentences.count - 1)
    }
    mutating func beginAnswer() {
        answerID = UUID().uuidString; committed = []; pending = ""; partial = ""
        confirmedWords = 0; previewWords = 0
    }
    mutating func preview(_ text: String) {
        guard !modelReading else { return }
        partial = text
        let rest = Self.droppingWords(confirmedWords, from: pending)
        previewWords = max(previewWords, confirmedWords + Self.matchedPrefix(text, in: rest))
    }
    @discardableResult mutating func commit(id: String, text: String) -> Bool {
        guard !committed.contains(where: { $0.id == id }) else { return true }
        let rest = Self.droppingWords(confirmedWords, from: pending)
        let matched = modelReading ? 0 : Self.matchedPrefix(text, in: rest)
        committed.append(Spoken(id: id, text: text))
        confirmedWords += matched; partial = ""
        previewWords = max(previewWords, confirmedWords)
        return matched > 0
    }
    /// Keep sentence identities and text stable while streaming and reading; only progress moves.
    mutating func replacePending(_ text: String, since spokenIDs: Set<String>, newAnswer: Bool = false) {
        if newAnswer {
            answerID = UUID().uuidString
            confirmedWords = 0; previewWords = 0; partial = ""
        }
        pending = text
        guard !modelReading else { return }
        var count = 0
        for spoken in committed where !spokenIDs.contains(spoken.id) {
            let rest = Self.droppingWords(count, from: text)
            count += Self.matchedPrefix(spoken.text, in: rest)
        }
        confirmedWords = max(confirmedWords, count)
        previewWords = max(previewWords, confirmedWords)
        if !partial.isEmpty { preview(partial) }
    }
    /// Audio-model progress cannot modify the script or turn suggested words into spoken evidence.
    mutating func advanceReading(to word: Int, answerID: String) {
        guard modelReading, self.answerID == answerID,
              word > cursor, word <= Self.words(pending).count else { return }
        confirmedWords = word; previewWords = word
    }
    static func words(_ text: String) -> [String] {
        CoachPronunciation.spokenText(text).lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
    /// Bounded edit alignment tolerates ASR substitutions, insertions and omissions.
    static func matchedPrefix(_ speech: String, in script: String) -> Int {
        let said = Array(words(speech).prefix(120))
        let expected = Array(words(script).prefix(min(180, max(12, said.count * 2 + 4))))
        guard !said.isEmpty, !expected.isEmpty else { return 0 }
        // Short final fragments are common, but may advance only an exact, anchored prefix.
        if said.count < 3 {
            return Array(expected.prefix(said.count)) == said ? said.count : 0
        }
        struct Match { var score: Int; var hits: Int }
        var previous = (0...expected.count).map { Match(score: -2 * $0, hits: 0) }
        for (i, word) in said.enumerated() {
            var row = [Match(score: -2 * (i + 1), hits: 0)]
            for (j, target) in expected.enumerated() {
                let equal = word == target
                let diagonal = Match(score: previous[j].score + (equal ? 3 : -2),
                                     hits: previous[j].hits + (equal ? 1 : 0))
                let insertion = Match(score: previous[j + 1].score - 2, hits: previous[j + 1].hits)
                let deletion = Match(score: row[j].score - 2, hits: row[j].hits)
                var best = diagonal
                for candidate in [insertion, deletion] {
                    if candidate.score > best.score ||
                        (candidate.score == best.score && candidate.hits > best.hits) { best = candidate }
                }
                row.append(best)
            }
            previous = row
        }
        var best = 0; var score = 0
        for end in 1...expected.count {
            let match = previous[end]
            guard match.hits >= 3, Double(match.hits) / Double(said.count) >= 0.45,
                  Double(match.hits) / Double(end) >= 0.45 else { continue }
            if match.score > score { score = match.score; best = end }
        }
        return best
    }
    static func droppingWords(_ count: Int, from text: String) -> String {
        let text = CoachPronunciation.spokenText(text)
        guard count > 0 else { return text }
        var remaining = count; var inWord = false
        for index in text.indices {
            let word = text[index].isLetter || text[index].isNumber
            if inWord && !word { remaining -= 1 }
            if remaining == 0 {
                return String(text[index...].drop { $0.isWhitespace || ".!?,;:".contains($0) })
            }
            inWord = word
        }
        return ""
    }
}

/// Conservative text endpoint fallback. Model-based acoustic endpoints remain a separate capability.
enum CoachEndpoint {
    static func delay(_ text: String) -> Double {
        let words = CoachScript.words(text)
        guard words.count >= 3 else { return 1.5 }
        if ["and", "or", "but", "because", "if", "when", "with", "the", "a", "to", "for", "of", "then"].contains(words.last ?? "") { return 1.8 }
        return 0.65
    }
}

/// Local lexical retrieval over user-imported material; never retrieves generated answers as biography.
enum CoachKnowledge {
    /// Imported backgrounds may be English while HR questions use Chinese names and topics.
    private static func terms(_ text: String) -> Set<String> {
        var words = Set(CoachScript.words(text).filter { $0.count > 2 })
        let lower = text.lowercased()
        for (term, aliases) in [
            ("kezhi", ["kezhi", "keshi", "kesi", "可之", "科智"]),
            ("debon", ["debon", "德邦"]),
            ("departure", ["离职", "离开", "跳槽", "departure", "leave", "left", "leaving", "disbanded", "layoff"]),
            ("compensation", ["薪资", "薪酬", "工资", "降薪", "年薪", "年终奖", "salary", "compensation", "bonus"]),
            ("handover", ["交接", "handover", "hand over", "handed over"])
        ] {
            if aliases.contains(where: { lower.contains($0) }) { words.insert(term) }
        }
        return words
    }

    static func retrieve(_ background: String, query: String, limit: Int = 6000) -> String {
        let queryWords = terms(query)
        let chunks = background.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        struct Chunk { var index: Int; var text: String; var score: Int }
        var ranked: [Chunk] = []
        for (index, text) in chunks.enumerated() {
            let score = terms(text).intersection(queryWords).count
            ranked.append(Chunk(index: index, text: text, score: score))
        }
        ranked.sort { $0.score == $1.score ? $0.index < $1.index : $0.score > $1.score }
        var remaining = limit; var selected: [(Int, String)] = []
        for item in ranked where remaining > 0 {
            let text = String(item.text.prefix(remaining)); selected.append((item.index, text)); remaining -= text.count + 1
        }
        return selected.sorted { $0.0 < $1.0 }.map(\.1).joined(separator: "\n")
    }
}

struct CoachEvent: Codable, Equatable {
    var kind: String
    var seconds: Double
    var answerID: String
    var text: String = ""
    var firstToken: Double? = nil
    var firstSentence: Double? = nil
    var endpointToSentence: Double? = nil
    var transcriptToSentence: Double? = nil
    var total: Double? = nil
}

/// Inline IPA is visible guidance, never words the user needs to say or translate.
enum CoachPronunciation {
    // A bounded local lexicon keeps the model from inventing pronunciations; unknown words stay plain.
    private static let overrides: [String: String] = [
        "classic": "ˈklæsɪk", "avatar": "ˈævətɑː", "timestamp": "ˈtaɪmstæmp",
        "combined": "kəmˈbaɪnd", "ability": "əˈbɪləti", "specific": "spəˈsɪfɪk",
        "additionally": "əˈdɪʃənəli", "architecture": "ˈɑːkɪtektʃə",
        "architectural": "ˌɑːkɪˈtektʃərəl", "scalability": "ˌskeɪləˈbɪləti",
        "scalable": "ˈskeɪləbəl", "reliability": "rɪˌlaɪəˈbɪləti",
        "availability": "əˌveɪləˈbɪləti", "consistency": "kənˈsɪstənsi",
        "synchronization": "ˌsɪŋkrənaɪˈzeɪʃən", "synchronisation": "ˌsɪŋkrənaɪˈzeɪʃən",
        "asynchronous": "eɪˈsɪŋkrənəs", "synchronous": "ˈsɪŋkrənəs",
        "authentication": "ɔːˌθentɪˈkeɪʃən", "authorization": "ˌɔːθəraɪˈzeɪʃən",
        "authorisation": "ˌɔːθəraɪˈzeɪʃən", "serialization": "ˌsɪəriəlaɪˈzeɪʃən",
        "serialisation": "ˌsɪəriəlaɪˈzeɪʃən", "concurrency": "kənˈkʌrənsi",
        "concurrent": "kənˈkʌrənt", "latency": "ˈleɪtənsi", "throughput": "ˈθruːpʊt",
        "cache": "kæʃ", "queue": "kjuː", "algorithm": "ˈælɡərɪðəm",
        "algorithms": "ˈælɡərɪðəmz", "hierarchy": "ˈhaɪərɑːki",
        "infrastructure": "ˈɪnfrəstrʌktʃə", "implementation": "ˌɪmplɪmenˈteɪʃən",
        "optimization": "ˌɒptɪmaɪˈzeɪʃən", "optimisation": "ˌɒptɪmaɪˈzeɪʃən",
        "compatibility": "kəmˌpætəˈbɪləti", "persistence": "pəˈsɪstəns",
        "transaction": "trænˈzækʃən", "transactions": "trænˈzækʃənz",
        "dependency": "dɪˈpendənsi", "dependencies": "dɪˈpendənsiz",
        "repository": "rɪˈpɒzɪtəri", "repositories": "rɪˈpɒzɪtəriz",
        "encapsulation": "ɪnˌkæpsjʊˈleɪʃən", "polymorphism": "ˌpɒlɪˈmɔːfɪzəm",
        "inheritance": "ɪnˈherɪtəns", "abstraction": "æbˈstrækʃən",
        "reconciliation": "ˌrekənsɪliˈeɪʃən", "ambiguity": "ˌæmbɪˈɡjuːəti",
        "accessibility": "əkˌsesəˈbɪləti", "vulnerability": "ˌvʌlnərəˈbɪləti",
    ]

    // Reading aid for a graduating Chinese high-school student, not a curriculum word list.
    private static let basic = Set("""
    a an the i me my mine myself you your yours yourself he him his she her hers it its we us our
    ours they them their theirs this that these those am is are was were be been being do does did
    done have has had having will would can could shall should may might must need to of in on at
    by for from with without as and or but if so than then because when where who what which how
    not no yes all any some each every both few more most other such only own same too very just
    now here there also already still even ever never always often sometimes again once first next
    last one two three four five six seven eight nine ten new old good bad big small long short
    much many little less about after before over under up down out into off through between
    while until since during want wants like likes know knows think thinks say says said tell
    see get gets got give take make makes made let lets go goes went come comes use uses used
    using try tries tried work works working time day way well simple app don t s m re ve ll d
    """.split(whereSeparator: \.isWhitespace).map(String.init))

    private static let familiar = Set("""
    ability according additionally advantage advantages agreement attention available beautiful beginning behavior
    behaviour business businesses candidate candidates challenge challenges character characters
    classic combined communication community communities company companies competition complete completed completely
    condition conditions consider considered considering continue continued continues continuing
    convenient conversation conversations customer customers dangerous decision decisions describe
    described describes describing description develop developed developer developers developing
    development different difference differences difficult difficulty direction directions discover
    discovered education effective effectively efficient efficiency encourage encouraged energy
    engineer engineers engineering environment especially everyone everything example examples
    excellent exercise experience experienced experiences explain explained explains explaining
    explanation expression expressions familiar favorite favourite finally following forward
    frequently friendship further general generally government important importance improve
    improved improvement improving include included includes including increase increased increases
    increasing individual information interest interested interesting introduce introduced introduction
    interview interviews knowledge language languages learning message messages method methods
    necessary nothing notice noticed number numbers offer offered office opportunity opportunities
    organize organised organized organizing organising organization organisation original paragraph
    paragraphs particular particularly people personal position positions possible possibility
    practice prepare prepared preparing present pressure problem problems process processes
    product products production professional program programs programme programmes programmer
    programming progress project projects protect protected protecting protection provide provided
    provides providing purpose question questions quickly quality receive received receives receiving
    recently recognize recognised recognized record records recording relationship remember require
    required requirement requirements research resource resources respond response responses
    responsible responsibility result results review reviewed reviews running science scientist
    several should software solution solutions someone something sometimes special specific standard
    standards statement statements store stored storing student students subject subjects successful
    successfully suggest suggestion suggestions support supported supporting system systems teacher
    teaching technology technologies technical technique techniques therefore together traditional
    understand understanding understood university usually various version versions whatever whenever
    whether without wonderful worldwide application applications background backgrounds building
    connection connections connected connecting network networks database databases computer computers
    international working mainly android flutter
    """.split(whereSeparator: \.isWhitespace).map { $0.lowercased() })

    private static let british: [String: String] = {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/pronunciation/en-GB.txt")
        let url = Bundle.main.url(forResource: "en-GB", withExtension: "txt", subdirectory: "pronunciation") ?? source
        var result: [String: String] = [:]
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            for line in text.split(separator: "\n") {
                let parts = line.split(separator: "\t", maxSplits: 1)
                guard parts.count == 2, let first = parts[1].split(separator: ",").first else { continue }
                let ipa = first.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                if !ipa.isEmpty { result[String(parts[0]).lowercased()] = ipa }
            }
        }
        result.merge(overrides) { _, override in override }
        return result
    }()
    static var lexiconCount: Int { british.count }
    static func prepare() async {
        _ = await Task.detached(priority: .userInitiated) { lexiconCount }.value
    }

    // Keep decimal digits literal: 0.01 is “zero point zero one”, never “zero point one”.
    private static let digitsIPA = ["ˈzɪərəʊ", "wʌn", "tuː", "θriː", "fɔː", "faɪv", "sɪks", "ˈsevən", "eɪt", "naɪn",
                                    "ten", "ɪˈlevən", "twelv", "ˌθɜːˈtiːn", "ˌfɔːˈtiːn", "ˌfɪfˈtiːn",
                                    "ˌsɪksˈtiːn", "ˌsevənˈtiːn", "ˌeɪˈtiːn", "ˌnaɪnˈtiːn"]
    private static func cardinalIPA(_ number: Int) -> String {
        if number < 20 { return digitsIPA[number] }
        if number < 100 {
            let tens = ["", "", "ˈtwenti", "ˈθɜːti", "ˈfɔːti", "ˈfɪfti", "ˈsɪksti", "ˈsevənti", "ˈeɪti", "ˈnaɪnti"]
            return tens[number / 10] + (number % 10 == 0 ? "" : " " + digitsIPA[number % 10])
        }
        // British cardinal phrasing: two thousand and ten; one hundred and one.
        for (scale, ipa) in [(1_000_000_000_000, "ˈtrɪljən"), (1_000_000_000, "ˈbɪljən"),
                             (1_000_000, "ˈmɪljən"), (1_000, "ˈθaʊzənd"), (100, "ˈhʌndrəd")] {
            if number >= scale {
                let remainder = number % scale
                return cardinalIPA(number / scale) + " " + ipa
                    + (remainder == 0 ? "" : (remainder < 100 ? " ænd " : " ") + cardinalIPA(remainder))
            }
        }
        return ""
    }

    private static func numberIPA(_ token: String) -> String? {
        let percent = token.hasSuffix("%") || token.hasSuffix("％")
        var number = percent ? String(token.dropLast()).trimmingCharacters(in: .whitespaces) : token
        var sign = ""
        if number.hasPrefix("-") || number.hasPrefix("−") { sign = "ˈmaɪnəs "; number.removeFirst() }
        else if number.hasPrefix("+") { sign = "plʌs "; number.removeFirst() }
        let parts = number.replacingOccurrences(of: ",", with: "").split(separator: ".", omittingEmptySubsequences: false)
        guard let whole = Int(parts[0]), whole >= 0 else { return nil }
        // Account numbers with leading zeroes are read digit by digit.
        let integer = parts[0].count > 1 && parts[0].first == "0"
            ? parts[0].compactMap { $0.wholeNumberValue.map { digitsIPA[$0] } }.joined(separator: " ")
            : cardinalIPA(whole)
        let fraction = parts.count == 2
            ? " pɔɪnt " + parts[1].compactMap { $0.wholeNumberValue.map { digitsIPA[$0] } }.joined(separator: " ") : ""
        return sign + integer + fraction + (percent ? " pəˈsent" : "")
    }

    static func annotate(_ text: String, finished: Bool = false) -> String {
        let text = spokenText(text)
        // Consume code, links and identifiers whole so their constituent words cannot be annotated.
        let pattern = #"```[\s\S]*?(?:```|$)|`[^`\n]*(?:`|$)|https?://\S+|/[A-Za-z0-9_./-]+|[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)*|(?<![\w.])[+−-]?(?:[0-9]{1,3}(?:,[0-9]{3})+|[0-9]+)(?:\.[0-9]+)?(?:[ \t]*[%％])?(?![\w]|\.[0-9])"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = ""; var end = text.startIndex
        var annotated = Set<String>()
        for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            result += text[end..<range.upperBound]
            let word = String(text[range]); let key = word.lowercased()
            if (finished || range.upperBound < text.endIndex), let first = word.first,
               first.isNumber || "+−-".contains(first), let ipa = numberIPA(word) {
                result += " /" + ipa + "/"
            }
            let difficult = (overrides[key] != nil || key.count >= 9) && !familiar.contains(key)
            if (finished || range.upperBound < text.endIndex), difficult, !basic.contains(key),
               !annotated.contains(key),
               word != word.uppercased(), let ipa = british[key] {
                result += " /" + ipa + "/"
                annotated.insert(key)
            }
            end = range.upperBound
        }
        return result + text[end...]
    }

    static func spokenText(_ text: String) -> String {
        var text = text
        // Some valid IPA uses only ASCII (e.g. /psst/); strip it only when it matches
        // the preceding word's dictionary entry, so paths such as /api/v1 survive.
        if let expression = try? NSRegularExpression(pattern: #"([A-Za-z]+|[+−-]?[0-9][0-9,.]*(?:[ \t]*[%％])?)(\s+)/([^/\r\n]+)/"#) {
            for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
                guard let word = Range(match.range(at: 1), in: text),
                      let phonetic = Range(match.range(at: 3), in: text),
                      (british[String(text[word]).lowercased()] ?? numberIPA(String(text[word]))) == String(text[phonetic]),
                      let annotation = Range(NSRange(location: match.range(at: 3).location - 1,
                                                     length: match.range(at: 3).length + 2), in: text) else { continue }
                text.removeSubrange(annotation)
            }
        }
        // Require an IPA symbol or stress mark so URLs, paths and code such as /api/v1 survive.
        // Also hide an unfinished annotation while tokens are still streaming.
        return text.replacingOccurrences(of: #"/(?=[^/\r\n]*[\u0250-\u02FFæðøŋœθ])[^/\r\n]*(?:/|$)"#,
                                  with: "", options: .regularExpression)
    }
}
