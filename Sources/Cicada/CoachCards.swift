import Foundation

/// The walkthrough engine (docs/walkthrough-coach-plan.md): asks DeepSeek for the next card when there is
/// new evidence, keeps the case and its log, and hands each card's spoken part to the coach's script so
/// reading, IPA and committed speech work as before. UI-free; `InterviewCoach` feeds it.
@MainActor
final class CoachCards: ObservableObject {
    enum Phase: String { case idle, say, write }
    struct Input {
        var turns: [CoachTurn]
        var background: String
        var frames: [CoachFrame]
        var script: CoachScript
        var stage: InterviewStage
    }
    struct Past: Identifiable, Equatable { var id: String; var card: CoachCard; var seconds: Double }

    @Published private(set) var card: CoachCard?
    @Published private(set) var busy = false
    @Published private(set) var failed = false
    @Published private(set) var phase = Phase.idle
    @Published private(set) var past: [Past] = []
    @Published private(set) var memory = CoachCase()
    /// The board shows most of the current TYPE step (a hint for the UI, not proof of completion).
    @Published private(set) var written = false
    private(set) var requests = 0
    private(set) var keeps = 0
    private(set) var firstToken: Double?
    private(set) var prepared = ""

    var input: (() -> Input?)?
    var prepare: (() async -> Bool)?
    /// (spoken text, new card): new cards restart reading; streaming updates of one card do not.
    var onSay: ((String, Bool) -> Void)?
    var onEvent: ((CoachEvent) -> Void)?
    var preparesFollowUps = false

    private let stream: InterviewCoach.Stream
    private var schedule = CoachCardSchedule()
    private var base = CoachBase()
    private var task: Task<Void, Never>?
    private var prepTask: Task<Void, Never>?
    private var token = UUID()
    private var clock = 0.0
    private var boardCount = 0
    private var boardLines: [String] = []
    private var boardChangedAt = -Double.infinity
    private var boardPending = false
    private var held: (card: CoachCard, since: Double)?
    private var checkedCard = false
    private var lastCommitCursor = 0
    private var idleSince = 0.0

    init(stream: @escaping InterviewCoach.Stream) { self.stream = stream }

    // MARK: Events

    func receive(_ trigger: CoachCardSchedule.Trigger, now: Double) {
        clock = now
        if trigger >= .manual { held = nil }
        prepTask?.cancel(); prepTask = nil
        act(schedule.receive(trigger, now: now))
    }

    func frame(_ frame: CoachFrame, now: Double) {
        clock = now
        boardCount += 1
        boardLines = frame.ocr.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !base.newBoard(boardLines).isEmpty || boardLines.isEmpty { boardChangedAt = now; boardPending = true }
    }

    /// The candidate finished a line. Final speech that did not move the reading cursor is their own
    /// wording (FR-08), so the card is checked against what they actually said.
    func candidateSpoke(_ script: CoachScript, now: Double) {
        defer { lastCommitCursor = script.cursor }
        guard phase != .idle, script.cursor == lastCommitCursor else { return }
        receive(.check, now: now)
    }

    func tick(now: Double, script: CoachScript) {
        clock = now
        if let held, Self.atSentenceStart(script) || now - held.since > 4 { self.held = nil; publish(held.card, now: now) }
        // Typing and panning settle before the board is read again (plan §5).
        if boardPending, now - boardChangedAt >= 2 { boardPending = false; receive(.board, now: now) }
        if let card, !checkedCard {
            if phase == .say, Self.finishedReading(script) {
                if card.edit != nil { phase = .write; emit("cardWrite") }
                else { checkedCard = true; receive(.check, now: now) }
            }
            if phase == .write, let edit = card.edit, now - boardChangedAt >= 3,
               Self.coverage(of: edit.code, in: boardLines) >= 0.6 {
                written = true; checkedCard = true; receive(.check, now: now)
            }
        }
        act(schedule.tick(now: now))
        if preparesFollowUps, !busy, prepTask == nil, prepared.isEmpty, card != nil, now - idleSince > 8 { prepareFollowUps() }
    }

    /// Debug (`coachCardWrite`): enter the write phase as if the candidate had finished reading.
    func enterWrite() { if card?.edit != nil { phase = .write; emit("cardWrite") } }

    func reset() {
        token = UUID(); task?.cancel(); task = nil; prepTask?.cancel(); prepTask = nil
        schedule = CoachCardSchedule(); base = CoachBase(); memory = CoachCase()
        card = nil; past = []; busy = false; failed = false; phase = .idle; held = nil; written = false
        boardCount = 0; boardLines = []; boardPending = false; prepared = ""; requests = 0; keeps = 0
    }

    // MARK: Requests

    private func act(_ action: CoachCardSchedule.Action) {
        switch action {
        case .none: return
        case .start(let trigger): run(trigger)
        case .restart(let trigger): task?.cancel(); task = nil; run(trigger)
        }
    }

    private func run(_ trigger: CoachCardSchedule.Trigger) {
        guard let input = input?() else { finish(); return }
        let tok = UUID(); token = tok
        let newLines = base.newLines(input.turns)
        let newBoard = base.newBoard(boardLines)
        let usedBoard = boardLines
        let boardID = boardCount > 0 ? "B\(boardCount)" : nil
        let evidence = CoachEvidence(
            interviewer: Set(input.turns.filter { $0.role == "interviewer" }.map(\.id)),
            candidate: Set(input.turns.filter { $0.role == "candidate" }.map(\.id) + input.script.committed.map(\.id)),
            board: Set((0..<boardCount).map { "B\($0 + 1)" }),
            tentative: Set(input.turns.filter { $0.role == "interviewer" && CoachEvidence.isTentative($0.text) }.map(\.id)))
        let messages = CoachCardPrompt.request(.init(
            turns: input.turns, background: input.background, frames: input.frames, script: input.script,
            stage: input.stage, memory: memory, newLines: newLines, newBoard: newBoard, boardID: boardID,
            card: card, trigger: trigger, prepared: prepared))
        // The candidate's own words since the last card: the draft is checked against them before showing.
        let said = newLines.filter { $0.role == "candidate" }.map(\.text)
        // Only a new question or a manual action may replace the card while it streams; a card that must
        // first be checked against the candidate's words waits for that check (AC-13).
        let live = trigger == .interviewer || card == nil || (trigger == .manual && said.isEmpty)
        busy = true; failed = false; requests += 1; firstToken = nil
        let started = Date()
        emit("cardRequest", text: "\(trigger)")
        task = Task { [weak self] in
            guard let self else { return }
            guard await self.prepare?() ?? true else { self.fail(tok); return }
            var raw = ""; var shown = false
            do {
                for try await piece in self.stream(messages, CoachPrompt.model) {
                    guard !Task.isCancelled, self.token == tok else { return }
                    if self.firstToken == nil { self.firstToken = Date().timeIntervalSince(started) }
                    raw += piece
                    guard live, let partial = try CoachCard.parse(raw, finished: false), !partial.keep, !partial.say.isEmpty else { continue }
                    if !shown { self.adopt(partial, now: self.clock); shown = true }
                    else { self.card = partial.withOps(self.card?.ops ?? []); self.onSay?(Self.spoken(partial), false) }
                }
                guard !Task.isCancelled, self.token == tok else { return }
                guard var card = try CoachCard.parse(raw, finished: true) else { throw URLError(.cannotParseResponse) }
                // Without any whiteboard there is nothing to draw on (AC-01 drew a diagram for a concept question).
                if boardID == nil, card.edit?.action == "draw" { card.edit = nil }
                // "Walk me through this" asks to explain the board, not to change it (AC-08 redrew arrows).
                if card.edit?.action == "draw", let latest = input.turns.last(where: { $0.role == "interviewer" }),
                   Self.asksToExplain(latest.text) { card.edit = nil }
                // DeepSeek keeps restating what the candidate just said in their own words, even when told
                // not to; a short focused edit removes it (AC-13). Only for cards not already on screen.
                if !shown, !card.keep, !said.isEmpty, trigger != .interviewer {
                    let revised = try await self.withoutRepeats(card.say, said: said)
                    guard !Task.isCancelled, self.token == tok else { return }
                    if !revised.isEmpty { card.say = revised }
                }
                card.ops = Self.missingProblemOps(card.ops, newLines: newLines, memory: self.memory) + card.ops
                self.apply(card, shown: shown, trigger: trigger, input: input, usedBoard: usedBoard, evidence: evidence)
                self.onEvent?(CoachEvent(kind: "latency", seconds: self.clock, answerID: input.script.answerID,
                                         firstToken: self.firstToken, total: Date().timeIntervalSince(started)))
            } catch {
                self.fail(tok)
                debugLog("coach: card failed (\((error as NSError).code)) raw_chars=\(raw.count) head=\(raw.prefix(160).replacingOccurrences(of: "\n", with: "⏎"))")
            }
        }
    }

    private func apply(_ card: CoachCard, shown: Bool, trigger: CoachCardSchedule.Trigger, input: Input,
                       usedBoard: [String], evidence: CoachEvidence) {
        busy = false; task = nil
        // The base moves only now: a cancelled request leaves its changes for the next one.
        base.confirm(turns: input.turns, board: usedBoard)
        if card.keep {
            keeps += 1; emit("cardKeep")
        } else {
            memory.apply(card.ops, evidence: evidence, at: clock)
            if !card.ops.isEmpty, let data = try? JSONEncoder().encode(card.ops) {
                emit("cardCase", text: String(decoding: data, as: UTF8.self))
            }
            if shown { self.card = card; onSay?(Self.spoken(card), false) }
            else if trigger >= .manual || !card.fix.isEmpty || card.heard.isEmpty == false || Self.atSentenceStart(input.script) {
                publish(card, now: clock)
            } else {
                // Let the candidate finish the sentence they are reading (AC-14).
                held = (card, clock)
            }
            prepared = ""
            emit("card", text: card.say)
            if let entry = memory.log.last { emit("cardLog", text: "\(entry.id) \(entry.text)") }
        }
        finish()
    }

    private func adopt(_ partial: CoachCard, now: Double) {
        if let old = card { past.append(Past(id: UUID().uuidString, card: old, seconds: now)); past = Array(past.suffix(20)) }
        card = partial; phase = .say; checkedCard = false; written = false
        onSay?(Self.spoken(partial), true)
    }

    private func publish(_ card: CoachCard, now: Double) { adopt(card, now: now) }

    private func fail(_ tok: UUID) {
        guard token == tok else { return }
        busy = false; failed = true; task = nil
        emit("cardFailure")
        finish()
    }

    private func finish() {
        idleSince = clock
        act(schedule.finished(now: clock))
    }

    private func withoutRepeats(_ say: String, said: [String]) async throws -> String {
        var raw = ""
        for try await piece in stream(CoachCardPrompt.dedupeRequest(say: say, said: said), CoachPrompt.model) { raw += piece }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^SAY:\s*"#, with: "", options: .regularExpression)
    }

    private func prepareFollowUps() {
        guard let input = input?() else { return }
        let messages = CoachCardPrompt.prepareRequest(.init(
            turns: input.turns, background: input.background, frames: [], script: input.script, stage: input.stage,
            memory: memory, newLines: [], newBoard: [], boardID: nil, card: card, trigger: .check))
        prepTask = Task { [weak self] in
            guard let self else { return }
            var raw = ""
            do {
                for try await piece in self.stream(messages, CoachPrompt.model) {
                    guard !Task.isCancelled else { return }
                    raw += piece
                }
                guard !Task.isCancelled else { return }
                self.prepared = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1200))
                self.emit("cardPrepared")
            } catch {}
            self.prepTask = nil
        }
    }

    private func emit(_ kind: String, text: String = "") {
        onEvent?(CoachEvent(kind: kind, seconds: clock, answerID: "", text: text))
    }

    // MARK: Pure helpers

    nonisolated static func spoken(_ card: CoachCard) -> String {
        card.fix.isEmpty ? card.say : card.fix + "\n" + card.say
    }
    nonisolated static func finishedReading(_ script: CoachScript) -> Bool {
        let total = CoachScript.words(script.pending).count
        return total > 0 && script.cursor >= total
    }
    /// At the start of a sentence (or of the card): replacing the script there cuts nobody off.
    nonisolated static func atSentenceStart(_ script: CoachScript) -> Bool {
        var end = 0
        if script.cursor == 0 { return true }
        for sentence in script.sentences {
            end += CoachScript.words(sentence).count
            if script.cursor == end { return true }
            if script.cursor < end { return false }
        }
        return true
    }
    /// The interviewer plainly opens a new question or returns to an earlier one, and the card's CASE did
    /// not record it (AC-10): the app records it from the interviewer's own line. Applied before the
    /// card's own ops.
    nonisolated static func missingProblemOps(_ ops: [CoachCaseOp], newLines: [CoachTurn], memory: CoachCase) -> [CoachCaseOp] {
        let interviewer = newLines.filter { $0.role == "interviewer" }
        guard let line = interviewer.last else { return [] }
        let recorded = ops.contains { $0.op == "newProblem" || $0.op == "switch" }
        let t = line.text.lowercased()
        let opensNew = t.range(of: #"\b(new question|next question|different question|another question|let'?s move on|moving on|switch(ing)? gears|let'?s pause (that|this))\b"#, options: .regularExpression) != nil
        var extra: [CoachCaseOp] = []
        // "Let's pause that" pauses a question that was never recorded when its card was cancelled by this
        // very turn: record that earlier question first, so it can be resumed.
        if opensNew, memory.problem == nil, let earlier = interviewer.dropLast().first {
            extra.append(CoachCaseOp(op: "newProblem", text: String(earlier.text.prefix(120)), evidence: [earlier.id]))
        }
        guard !recorded else { return extra }
        if t.range(of: #"\b(go(ing)? back to|back to the|return to|resume)\b"#, options: .regularExpression) != nil {
            let words = Set(CoachScript.words(t).filter { $0.count > 3 })
            let best = memory.problems.filter { $0.id != memory.problem?.id }
                .map { ($0, Set(CoachScript.words($0.goal)).intersection(words).count) }
                .max { $0.1 < $1.1 }
            if let (problem, score) = best, score > 0 { return [CoachCaseOp(op: "switch", id: problem.id, evidence: [line.id])] }
            return []
        }
        if opensNew { extra.append(CoachCaseOp(op: "newProblem", text: String(line.text.prefix(120)), evidence: [line.id])) }
        return extra
    }

    /// An explain-only request: walk through, explain, describe… without asking to draw, add or write anything.
    nonisolated static func asksToExplain(_ text: String) -> Bool {
        let t = text.lowercased()
        let explain = t.range(of: #"\b(walk (me )?through|explain|describe|tell me about|how does|what is|what are)\b"#, options: .regularExpression) != nil
        let change = t.range(of: #"\b(draw|sketch|add|write|implement|code|change|update|extend)\b"#, options: .regularExpression) != nil
        return explain && !change
    }
    nonisolated private static let keywords: Set<String> = ["val", "var", "fun", "class", "return", "private", "override", "data",
        "import", "package", "object", "true", "false", "null", "this", "when", "else", "suspend", "public", "internal"]
    /// Share of the step's identifiers visible on the board.
    nonisolated static func coverage(of code: String, in board: [String]) -> Double {
        let names = Set(code.split { !($0.isLetter || $0.isNumber || $0 == "_") }.map(String.init)
            .filter { $0.count >= 3 && $0.first?.isLetter == true && !keywords.contains($0) })
        guard !names.isEmpty else { return 0 }
        let text = board.joined(separator: " ")
        return Double(names.filter { text.contains($0) }.count) / Double(names.count)
    }
}

extension CoachCard {
    func withOps(_ ops: [CoachCaseOp]) -> CoachCard { var copy = self; copy.ops = ops; return copy }
}
