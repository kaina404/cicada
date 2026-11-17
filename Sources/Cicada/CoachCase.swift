import Foundation

/// The walkthrough's working memory (docs/walkthrough-coach-plan.md §2): every problem of the interview,
/// what was decided, said and actually built, plus an append-only log of how it got there.
/// DeepSeek proposes changes as `CoachCaseOp`s; this type decides what they may claim.
struct CoachCase: Codable, Equatable {
    struct Fact: Codable, Equatable {
        enum Source: String, Codable { case interviewer, candidate, board }
        enum Status: String, Codable { case confirmed, unconfirmed, superseded }
        var text: String
        var source: Source
        var status: Status
        var evidence: [String] = []
    }
    struct Problem: Codable, Equatable {
        var id: String
        var goal: String
        var constraints: [Fact] = []
        var adopted: Fact?
        var alternatives: [String] = []
        var abandoned: [Fact] = []
        var spoken: [String] = []
        var implemented: [Fact] = []
        var pending: [String] = []
    }
    struct Aside: Codable, Equatable { var question: String; var returnTo: String }
    struct Entry: Codable, Equatable {
        var id: String
        var seconds: Double
        var problem: String
        var text: String
        var evidence: [String]
        /// A correction points at the entry it corrects; the old entry itself never changes.
        var corrects: String? = nil
    }

    private(set) var problems: [Problem] = []
    private(set) var current: Int?
    private(set) var asides: [Aside] = []
    private(set) var log: [Entry] = []

    var problem: Problem? { current.map { problems[$0] } }

    /// Applies DeepSeek's proposed changes. `evidence` holds the IDs that really exist: transcript
    /// line IDs by role and board version IDs. A claim without real evidence is kept as unconfirmed,
    /// a decision without the interviewer's or candidate's words is only an alternative, and coverage
    /// counts only what the candidate actually said.
    mutating func apply(_ ops: [CoachCaseOp], evidence: CoachEvidence, at seconds: Double) {
        for op in ops { apply(op, evidence: evidence, at: seconds) }
    }

    private mutating func apply(_ op: CoachCaseOp, evidence: CoachEvidence, at seconds: Double) {
        let ids = (op.evidence ?? []).filter(evidence.contains)
        let text = (op.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        func fact(_ source: CoachCase.Fact.Source) -> Fact {
            Fact(text: text, source: source, status: ids.isEmpty ? .unconfirmed : .confirmed, evidence: ids)
        }
        func record(_ note: String, corrects: String? = nil) {
            log.append(Entry(id: "E\(log.count + 1)", seconds: seconds, problem: problem?.id ?? "",
                             text: note, evidence: ids, corrects: corrects))
        }
        switch op.op {
        case "newProblem":
            guard !text.isEmpty else { return }
            // The same goal again is going back to it, not a second copy (seen live in AC-10).
            if let index = problems.firstIndex(where: { Self.sameGoal($0.goal, text) }) {
                guard index != current else { return }
                current = index; asides = []
                record("Back to: " + problems[index].goal); return
            }
            let id = op.id.flatMap { id in problems.contains { $0.id == id } ? nil : id } ?? "P\(problems.count + 1)"
            problems.append(Problem(id: id, goal: text))
            current = problems.count - 1; asides = []
            record("New problem: " + text)
        case "switch":
            // An unknown id with the goal's words still finds the problem.
            let match = problems.firstIndex { $0.id == op.id } ?? (text.isEmpty ? nil : problems.firstIndex { Self.sameGoal($0.goal, text) })
            guard let index = match, index != current else { return }
            current = index; asides = []
            record("Back to: " + problems[index].goal)
        case "pushAside":
            guard !text.isEmpty else { return }
            asides.append(Aside(question: text, returnTo: op.returnTo ?? problem?.pending.first ?? ""))
            record("Follow-up: " + text)
        case "popAside":
            guard let aside = asides.popLast() else { return }
            record("Answered: " + aside.question)
        case "correct":
            guard let target = op.of, log.contains(where: { $0.id == target }), !text.isEmpty else { return }
            record(text, corrects: target)
        default:
            guard let index = current, !text.isEmpty else { return }
            var p = problems[index]
            let note = Self.update(&p, op: op.op, text: text, fact: fact, ids: ids, evidence: evidence)
            problems[index] = p
            note.forEach { record($0) }
        }
    }

    /// Two goal phrasings of one problem: most of the shorter one's longer words appear in the other.
    static func sameGoal(_ a: String, _ b: String) -> Bool {
        let x = Set(CoachScript.words(a).filter { $0.count > 3 }), y = Set(CoachScript.words(b).filter { $0.count > 3 })
        guard !x.isEmpty, !y.isEmpty else { return false }
        return Double(x.intersection(y).count) / Double(min(x.count, y.count)) >= 0.75
    }

    /// Returns the log lines for what actually changed.
    private static func update(_ p: inout Problem, op: String, text: String, fact: (Fact.Source) -> Fact,
                               ids: [String], evidence: CoachEvidence) -> [String] {
        var notes: [String] = []
        func record(_ note: String, _ corrects: String?) { notes.append(note) }
        let said = ids.contains { evidence.interviewer.contains($0) || evidence.candidate.contains($0) }
        // Only words that choose something make a decision; a tentative question keeps it an option.
        let decided = ids.contains { (evidence.interviewer.contains($0) || evidence.candidate.contains($0)) && !evidence.tentative.contains($0) }
        switch op {
        case "constraint":
            guard !p.constraints.contains(where: { $0.text == text && $0.status != .superseded }) else { return notes }
            p.constraints.append(fact(.interviewer)); record("Constraint: " + text, nil)
        case "dropConstraint":
            guard let i = p.constraints.firstIndex(where: { $0.text == text && $0.status != .superseded }), said else { return notes }
            p.constraints[i].status = .superseded; record("Constraint dropped: " + text, nil)
        case "alternative":
            guard !p.alternatives.contains(text) else { return notes }
            p.alternatives.append(text); record("Alternative discussed: " + text, nil)
        case "adopt":
            // "Could we use B?" is not a decision: without someone actually choosing it, B stays an option.
            guard decided else {
                if !p.alternatives.contains(text) { p.alternatives.append(text); record("Alternative discussed: " + text, nil) }
                return notes
            }
            if var old = p.adopted, old.text != text {
                old.status = .superseded; p.abandoned.removeAll { $0.text == old.text }; p.abandoned.append(old)
                record("Abandoned: " + old.text, nil)
            }
            p.abandoned.removeAll { $0.text == text }
            p.alternatives.removeAll { $0 == text }
            p.adopted = fact(.interviewer); record("Adopted: " + text, nil)
        case "spoken":
            // Coverage comes only from the candidate's own final speech, never from the AI script.
            guard ids.contains(where: evidence.candidate.contains), !p.spoken.contains(text) else { return notes }
            p.spoken.append(text); record("Explained: " + text, nil)
        case "implemented":
            let source: Fact.Source = ids.contains(where: evidence.board.contains) ? .board : .candidate
            guard ids.contains(where: { evidence.board.contains($0) || evidence.candidate.contains($0) }) else { return notes }
            p.implemented.removeAll { $0.text == text }
            p.implemented.append(fact(source)); record("Implemented: " + text, nil)
        case "notImplemented":
            guard let i = p.implemented.firstIndex(where: { $0.text == text }) else { return notes }
            p.implemented[i].status = .superseded; record("No longer on the board: " + text, nil)
        case "pending":
            guard !p.pending.contains(text) else { return notes }
            p.pending.append(text)
        case "done":
            p.pending.removeAll { $0 == text }
        default:
            break
        }
        return notes
    }
}

/// One change DeepSeek proposes in a card's `CASE:` line.
struct CoachCaseOp: Codable, Equatable {
    var op: String
    var text: String? = nil
    var id: String? = nil
    var of: String? = nil
    var returnTo: String? = nil
    var evidence: [String]? = nil
}

/// IDs the app can vouch for when a card is applied.
struct CoachEvidence: Equatable {
    var interviewer: Set<String> = []
    var candidate: Set<String> = []
    var board: Set<String> = []
    /// Lines phrased as a tentative question ("Could we use Flow?"): evidence of an option, not a decision.
    var tentative: Set<String> = []

    static func isTentative(_ text: String) -> Bool {
        let t = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasSuffix("?") else { return false }
        // "Can you switch it to Flow?" asks for work; "Could we use Flow?" weighs an option.
        return t.range(of: #"\b(could|should|can|shall) we\b|\bwhat about\b|\bhow about\b|\bwhat if\b|\bwould .* (work|be better)\b|\bis .* better\b|\bdo you think\b|\bwhy not\b"#,
                       options: .regularExpression) != nil
    }
    func contains(_ id: String) -> Bool { interviewer.contains(id) || candidate.contains(id) || board.contains(id) }
}

/// What changed since the last applied card. The base moves only when a card is applied, so a
/// cancelled or stale request leaves its changes for the next one (plan §2.2).
struct CoachBase: Equatable {
    private(set) var lineIDs: Set<String> = []
    private(set) var board: [String] = []

    func newLines(_ turns: [CoachTurn]) -> [CoachTurn] { turns.filter { !lineIDs.contains($0.id) } }
    /// Board lines not seen before. P0: the model lists content that only scrolled into view as
    /// added, so novelty is decided here against what was already read, not by the model.
    func newBoard(_ lines: [String]) -> [String] { lines.filter { !Self.seen($0, in: board) } }

    mutating func confirm(turns: [CoachTurn], board lines: [String]) {
        lineIDs.formUnion(turns.map(\.id))
        board += newBoard(lines)
    }

    static func normalized(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }
    static func seen(_ line: String, in known: [String]) -> Bool {
        let line = normalized(line)
        guard !line.isEmpty else { return true }
        return known.contains { other in
            let other = normalized(other)
            return other == line || (line.count > 3 && other.contains(line)) || similarity(line, other) > 0.85
        }
    }
    /// Ratio of matching characters, like Python's difflib quick ratio on the longest common subsequence.
    static func similarity(_ a: String, _ b: String) -> Double {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty, !b.isEmpty, min(a.count, b.count) * 2 >= max(a.count, b.count) else { return 0 }
        var row = [Int](repeating: 0, count: b.count + 1)
        for x in a {
            var diagonal = 0
            for (j, y) in b.enumerated() {
                let above = row[j + 1]
                row[j + 1] = x == y ? diagonal + 1 : max(row[j + 1], row[j])
                diagonal = above
            }
        }
        return Double(2 * row[b.count]) / Double(a.count + b.count)
    }
}
