import Foundation

/// One walkthrough card (docs/walkthrough-coach-plan.md §3): what to say now, what to type or draw
/// next, and the proposed changes to `CoachCase`. Parsed from a streaming DeepSeek response.
struct CoachCard: Equatable {
    struct Edit: Equatable {
        /// add | replace | delete | draw
        var action: String
        /// Where: a class, function or box name, or words describing the spot. Never a guessed line number.
        var at: String
        var language: String = ""
        var code: String = ""
        /// The fence has closed: the code is complete. A diagram is drawn only then (half a Mermaid source
        /// would draw the wrong picture); until then its text shows.
        var closed = false
        /// A Mermaid flowchart or sequence diagram the card draws as a picture for the candidate to copy.
        var isDiagram: Bool { language.lowercased() == "mermaid" }
        /// The diagram as the card draws it: top to bottom, since a left-to-right chain of boxes shrinks to
        /// unreadable text in the narrow card (seen live: nine boxes in a row).
        var diagramSource: String {
            code.replacingOccurrences(of: #"^(\s*(?:flowchart|graph))\s+(?:LR|RL)\b"#, with: "$1 TD", options: .regularExpression)
        }
    }
    var keep = false
    var heard = ""
    var fix = ""
    var say = ""
    var edit: Edit?
    var then = ""
    var reason = ""
    var ops: [CoachCaseOp] = []
    /// Most sentences SAY may keep: a self-introduction gets more (`CoachCards.sentenceLimit(for:)`).
    var sentenceLimit = CoachCards.sentenceLimit

    static let marker = "<<<CICADA_CARD>>>"
    private static let headers = ["HEARD", "FIX", "SAY", "TYPE", "THEN", "REASON", "CASE"]

    /// nil until the marker arrives. While streaming, a partial SAY is returned as soon as it starts,
    /// so the first sentence can show; `CASE` is applied only from a finished response.
    static func parse(_ raw: String, finished: Bool) throws -> CoachCard? {
        guard let body = Self.body(raw, finished: finished) else {
            if finished { throw URLError(.cannotParseResponse) }
            return nil
        }
        var card = CoachCard()
        var section = ""
        var fenced = false
        var sections: [String: [String]] = [:]
        var lines = body.components(separatedBy: "\n")
        // An unfinished last line may still be a header in the making ("TH"); hold it back.
        if !finished, let last = lines.last, !Self.opensFence(lines.dropLast()) && headers.contains(where: { $0.hasPrefix(last) && !last.isEmpty }) {
            lines.removeLast()
        }
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if section == "TYPE" {
                    if !fenced, card.edit != nil { card.edit?.language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces) }
                    if fenced { card.edit?.closed = true }
                    fenced.toggle(); continue
                }
            }
            if !fenced {
                if trimmed == "KEEP", section.isEmpty { card.keep = true; continue }
                if let header = headers.first(where: { trimmed.hasPrefix($0 + ":") }) {
                    section = header
                    let rest = String(trimmed.dropFirst(header.count + 1)).trimmingCharacters(in: .whitespaces)
                    if header == "TYPE" { card.edit = edit(rest) } else if !rest.isEmpty { sections[header, default: []].append(rest) }
                    continue
                }
            }
            guard !section.isEmpty else { continue }
            if section == "TYPE" {
                if fenced, var edit = card.edit { edit.code += (edit.code.isEmpty ? "" : "\n") + line; card.edit = edit }
            } else {
                sections[section, default: []].append(line)
            }
        }
        func text(_ key: String) -> String {
            (sections[key] ?? []).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        card.heard = text("HEARD"); card.fix = text("FIX"); card.say = text("SAY")
        card.then = text("THEN"); card.reason = text("REASON")
        if finished {
            // An empty TYPE header ("TYPE:" with nothing to type) is not a step.
            if let edit = card.edit, edit.code.isEmpty, edit.action != "delete" { card.edit = nil }
            let json = text("CASE")
            if !json.isEmpty {
                // A malformed CASE must not lose a good card: the case simply stays as it was.
                card.ops = (try? JSONDecoder().decode([CoachCaseOp].self, from: Data(json.utf8))) ?? []
            }
            guard card.keep || !card.say.isEmpty else { throw URLError(.cannotParseResponse) }
        }
        return card
    }

    /// The text after the marker. DeepSeek sometimes garbles the marker ("<<<CICARD>>>"), so any
    /// `<<<…>>>` line counts; with no marker at all, a response that opens with a section is accepted
    /// once its first line is complete.
    private static func body(_ raw: String, finished: Bool) -> String? {
        if let start = raw.range(of: marker) { return String(raw[start.upperBound...]) }
        if let match = raw.range(of: #"<<<[A-Za-z_]{2,40}>>>"#, options: .regularExpression) { return String(raw[match.upperBound...]) }
        let trimmed = raw.drop { $0.isWhitespace }
        guard finished || trimmed.contains("\n") else { return nil }
        let first = trimmed.prefix { $0 != "\n" }.trimmingCharacters(in: .whitespaces)
        guard first == "KEEP" || headers.contains(where: { first.hasPrefix($0 + ":") }) else { return nil }
        return "\n" + trimmed
    }

    private static func opensFence(_ lines: ArraySlice<String>) -> Bool {
        lines.filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }.count % 2 == 1
    }

    /// `replace at="val cat"` → Edit(action: "replace", at: "val cat").
    private static func edit(_ header: String) -> Edit {
        let action = header.split(separator: " ").first.map(String.init) ?? "add"
        var at = ""
        if let open = header.range(of: "at=\"") {
            let rest = header[open.upperBound...]
            at = String(rest[..<(rest.firstIndex(of: "\"") ?? rest.endIndex)])
        }
        return Edit(action: ["add", "replace", "delete", "draw"].contains(action) ? action : "add", at: at)
    }
}
