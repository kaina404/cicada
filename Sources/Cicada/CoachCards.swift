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
    /// Meeting time the current card appeared; candidate lines after it are their own words for this card.
    private var cardShownAt = Double.infinity
    /// The candidate said the current card with the talk key: there is no sentence of it left to finish.
    private var talked = false

    init(stream: @escaping InterviewCoach.Stream) { self.stream = stream }

    // MARK: Events

    func receive(_ trigger: CoachCardSchedule.Trigger, now: Double) {
        clock = now
        // Wallet run 2327, W7: the card request restarted every second for 45 s with no new interviewer words,
        // and only half a sentence ever showed. A turn the running request already read does not restart it.
        if trigger == .interviewer, schedule.running == .interviewer, let heard = runningHeard, heard == Self.lastInterviewer(input?()?.turns ?? []) {
            debugLog("coach: interviewer trigger with no new words, running request kept")
            return
        }
        if trigger >= .manual { held = nil }
        prepTask?.cancel(); prepTask = nil
        act(schedule.receive(trigger, now: now))
    }
    /// The interviewer's last line (id and text) the running request was built from.
    private var runningHeard: String?
    nonisolated static func lastInterviewer(_ turns: [CoachTurn]) -> String? {
        turns.last(where: { $0.role == "interviewer" }).map { $0.id + "\u{1F}" + $0.text }
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

    /// The candidate said something with the talk key (their own language, translated into the room).
    /// Reading cannot follow that, so the card counts as said: its code is next, or the next card
    /// follows what they actually said. A card held for a sentence end shows now.
    func candidateTalked(_ script: CoachScript, now: Double) {
        clock = now; lastCommitCursor = script.cursor
        talked = true
        if let held { self.held = nil; publish(held.card, now: now); return }
        guard phase != .idle, let card else { return }
        if phase == .say, card.edit != nil { phase = .write; emit("cardWrite"); return }
        checkedCard = true
        receive(.check, now: now)
    }

    func tick(now: Double, script: CoachScript) {
        clock = now
        if let held, talked || Self.atSentenceStart(script) || now - held.since > 4 { self.held = nil; publish(held.card, now: now) }
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
        cardShownAt = .infinity; talked = false
        // The next meeting's clock and reading cursor start at zero again: values left from this one kept
        // its first own-words line from being checked.
        clock = 0; boardChangedAt = -.infinity; checkedCard = false; lastCommitCursor = 0; idleSince = 0
    }

    // MARK: Requests

    private func act(_ action: CoachCardSchedule.Action) {
        switch action {
        case .none: return
        case .start(let trigger): run(trigger)
        case .restart(let trigger): debugLog("coach: card request restarted by \(trigger)"); task?.cancel(); task = nil; run(trigger)
        }
    }

    private func run(_ trigger: CoachCardSchedule.Trigger) {
        guard let input = input?() else { finish(); return }
        let tok = UUID(); token = tok
        runningHeard = Self.lastInterviewer(input.turns)
        let newLines = base.newLines(input.turns)
        let newBoard = base.newBoard(boardLines)
        let usedBoard = boardLines
        let boardID = boardCount > 0 ? "B\(boardCount)" : nil
        let evidence = CoachEvidence(
            interviewer: Set(input.turns.filter { $0.role == "interviewer" }.map(\.id)),
            candidate: Set(input.turns.filter { $0.role == "candidate" }.map(\.id) + input.script.committed.map(\.id)),
            board: Set((0..<boardCount).map { "B\($0 + 1)" }),
            tentative: Set(input.turns.filter { $0.role == "interviewer" && CoachEvidence.isTentative($0.text) }.map(\.id)),
            candidateText: Dictionary(input.turns.filter { $0.role == "candidate" }.map { ($0.id, $0.text) }
                                      + input.script.committed.map { ($0.id, $0.text) }, uniquingKeysWith: { a, _ in a }))
        // The candidate's own words since the current card appeared, not just since the last request: a check
        // right after they spoke moves the base, and a manual "next" then repeated them (AC-13).
        // "I have not explained the data flow yet" covers nothing: as a point already made it got the data flow
        // edited out of the card (ME-03).
        // Since the interviewer's latest line too: a check can swap the card mid-answer, and "next" then saw nothing
        // said and restated the lines just read (strict wallet run 2026-11-19, W3/W4/W6).
        let asked = input.turns.last(where: { $0.role == "interviewer" })?.seconds ?? cardShownAt
        let said = input.turns.filter { $0.role == "candidate" && ($0.seconds >= min(cardShownAt, asked) || newLines.contains($0)) }
            .map(\.text).filter { !Self.saysNotCovered($0) }
        let messages = CoachCardPrompt.request(.init(
            turns: input.turns, background: input.background, frames: input.frames, script: input.script,
            stage: input.stage, memory: memory, newLines: newLines, newBoard: newBoard, boardID: boardID,
            card: card, trigger: trigger, prepared: prepared, said: said))
        let previousSay = card?.say
        // Only a new question or a manual action may replace the card while it streams; a card that must
        // first be checked against the candidate's words waits for that check (AC-13).
        let live = trigger == .interviewer || card == nil || (trigger == .manual && said.isEmpty)
        // A self-introduction keeps its longer limit while the candidate pages through it with "next".
        let limit = Self.sentenceLimit(for: CoachCardPrompt.interviewerTurn(input.turns) ?? "")
        busy = true; failed = false; requests += 1; firstToken = nil
        // Request size, to keep the knowledge trim honest (the full folder is about 60,000 tokens).
        let chars = messages.reduce(0) { sum, m in
            sum + ((m["content"] as? String)?.count ?? ((m["content"] as? [[String: Any]]) ?? []).reduce(0) { $0 + (($1["text"] as? String)?.count ?? 0) })
        }
        debugLog("coach: card request chars=\(chars) talk_tracks=\(((messages.first?["content"] as? String) ?? "").contains("<talk_tracks>"))")
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
                    guard live, var partial = try CoachCard.parse(raw, finished: false), !partial.keep, !partial.say.isEmpty else { continue }
                    partial.sentenceLimit = limit
                    if !shown { self.adopt(partial, now: self.clock); shown = true }
                    else { self.card = partial.withOps(self.card?.ops ?? []); self.onSay?(Self.spoken(partial), false) }
                }
                guard !Task.isCancelled, self.token == tok else { return }
                debugLog("coach: card stream done s=\(String(format: "%.1f", Date().timeIntervalSince(started))) raw_chars=\(raw.count)")
                guard var card = try CoachCard.parse(raw, finished: true) else { throw URLError(.cannotParseResponse) }
                // Seen live: asked about the API, DeepSeek copied the card already on screen word for word.
                // A new question gets one retry that names it; anything else just keeps the card.
                if !card.keep, let current = previousSay, Self.sameText(card.say, current) {
                    let question = newLines.last(where: { $0.role == "interviewer" })?.text
                    if trigger == .interviewer, let question {
                        var retry = ""
                        for try await piece in self.stream(Self.appending("Your draft repeated the card already shown. The interviewer just said: \"\(question)\". Respond to that now; do not repeat the current card.", to: messages), CoachPrompt.model) {
                            guard !Task.isCancelled, self.token == tok else { return }
                            retry += piece
                        }
                        if let again = try CoachCard.parse(retry, finished: true), !again.keep, !Self.sameText(again.say, current) {
                            card = again; shown = false
                            if self.past.last?.card.say == current { self.past.removeLast() }
                        } else { card.keep = true }
                    } else { card.keep = true }
                    // A copy that already streamed onto the screen left the old card in the history twice.
                    if card.keep, shown, self.past.last?.card.say == current { self.past.removeLast() }
                }
                // 1339: asked the chat change, DeepSeek answered the account switch again (its HEARD said so) and the
                // card stayed on it for 96 s, since nothing new was asked. One retry that names the new question.
                if !card.keep, trigger == .interviewer, let latest = newLines.last(where: { $0.role == "interviewer" }) {
                    let turn = CoachCardPrompt.interviewerTurn(input.turns) ?? latest.text
                    if CoachRequiredPoints.answersAnotherQuestion(question: turn, heard: card.heard, goal: self.memory.problem?.goal) {
                        debugLog("coach: card answered another question, heard=\(card.heard)")
                        var retry = ""
                        for try await piece in self.stream(Self.appending("Your draft answered an earlier question (\"\(card.heard)\"). The interviewer just asked: \"\(turn)\". Answer that new question now; HEARD names it.", to: messages), CoachPrompt.model) {
                            guard !Task.isCancelled, self.token == tok else { return }
                            retry += piece
                        }
                        if let again = try CoachCard.parse(retry, finished: true), !again.keep,
                           !CoachRequiredPoints.answersAnotherQuestion(question: turn, heard: again.heard, goal: self.memory.problem?.goal) {
                            card = again; shown = false
                            if let previousSay, self.past.last?.card.say == previousSay { self.past.removeLast() }
                        }
                    }
                }
                // "Could we use Flow?" still sometimes got "Yes, Flow fits better, I'll switch" (AC-04): retry once
                // with the rule spelled out.
                if !card.keep, trigger == .interviewer, let latest = newLines.last(where: { $0.role == "interviewer" }),
                   CoachEvidence.isTentative(latest.text), Self.announcesSwitch(card) {
                    var retry = ""
                    for try await piece in self.stream(Self.appending("The interviewer only asked whether another option could work: \"\(latest.text)\". Do not switch and do not write code. In two or three sentences weigh the current approach against it, then ask whether they want the switch.", to: messages), CoachPrompt.model) {
                        guard !Task.isCancelled, self.token == tok else { return }
                        retry += piece
                    }
                    if let again = try CoachCard.parse(retry, finished: true), !again.keep, !Self.announcesSwitch(again) {
                        card = again; shown = false
                        if let previousSay, self.past.last?.card.say == previousSay { self.past.removeLast() }
                    }
                }
                // "Add another one after it." names nothing, yet DeepSeek picked a value and a spot itself (CH-06):
                // retry once asking for the clarifying question, and never keep a TYPE for it.
                if !card.keep, trigger == .interviewer, let latest = newLines.last(where: { $0.role == "interviewer" }),
                   Self.unresolvedReference(latest.text), card.edit != nil || !card.say.contains("?") {
                    var retry = ""
                    for try await piece in self.stream(Self.appending("The interviewer said \"\(latest.text)\" without naming what to add. SAY is one short clarifying question of at most 15 words, with no list of options. No TYPE.", to: messages), CoachPrompt.model) {
                        guard !Task.isCancelled, self.token == tok else { return }
                        retry += piece
                    }
                    if let again = try CoachCard.parse(retry, finished: true), !again.keep, again.say.contains("?") {
                        card = again; shown = false
                        if let previousSay, self.past.last?.card.say == previousSay { self.past.removeLast() }
                    }
                    card.edit = nil
                }
                // After new requirements, DeepSeek reads them back; drop sentences that only echo the
                // interviewer's informational line (the newsfeed run, step 2).
                if !card.keep, trigger == .interviewer, let latest = newLines.last(where: { $0.role == "interviewer" }),
                   !latest.text.trimmingCharacters(in: .whitespaces).hasSuffix("?"), !Self.checksNewProblem(card, line: latest.text) {
                    card.say = Self.withoutRecital(card.say, of: latest.text)
                }
                // Without any whiteboard there is nothing to draw on (AC-01 drew a diagram for a concept question),
                // unless the interviewer asked for a diagram: then the candidate needs it before opening a board.
                // The whole turn: recognition cut "Draw the client, the server, / and local storage as a flow. And tell
                // me what each part owns." in two, and the last piece alone read as explain-only (real-audio run 5).
                let request = CoachCardPrompt.interviewerTurn(input.turns) ?? ""
                if boardID == nil, card.edit?.action == "draw", !Self.asksToDraw(request) { card.edit = nil }
                // "Walk me through this" asks to explain the board, not to change it (AC-08 redrew arrows; NF-05
                // and ME-10 typed code for "walk me through the API" and "explain the difference").
                if card.edit != nil, Self.asksToExplain(request) { card.edit = nil }
                // 1413 W6: "Draw the new entry flow as a flowchart" got a card with no TYPE at all. Ask once for the
                // diagram alone and keep the SAY already on screen.
                if !card.keep, trigger == .interviewer, card.edit == nil, Self.asksToDraw(request), !Self.asksToExplain(request) {
                    var retry = ""
                    for try await piece in self.stream(Self.appending("The interviewer asked for a diagram: \"\(request)\". Your draft has no TYPE. Write the same card with TYPE draw and the Mermaid diagram they asked for.", to: messages), CoachPrompt.model) {
                        guard !Task.isCancelled, self.token == tok else { return }
                        retry += piece
                    }
                    if let again = try CoachCard.parse(retry, finished: true), let edit = again.edit, edit.action == "draw" {
                        card.edit = edit
                        debugLog("coach: diagram added on retry")
                    }
                }
                // DeepSeek keeps restating what the candidate just said in their own words, even when told
                // not to; a short focused edit removes it (AC-13). Only for cards not already on screen.
                if !shown, !card.keep, !said.isEmpty, trigger != .interviewer {
                    let revised = try await self.withoutRepeats(card.say, said: said)
                    guard !Task.isCancelled, self.token == tok else { return }
                    if !revised.isEmpty { card.say = revised }
                    // The edit still let whole sentences through (strict wallet run 2026-11-19: W3, W4 and W6's
                    // next cards restated what had just been read): drop those here.
                    let fresh = Self.withoutSaid(card.say, said: said)
                    if !fresh.isEmpty { card.say = fresh }
                    else if trigger == .check { card.keep = true }
                }
                // A "next" card repeated the card just read, the added required point included (1413 W6).
                if !card.keep, trigger == .manual, let previousSay {
                    let fresh = Self.withoutSaid(card.say, said: [previousSay])
                    if !fresh.isEmpty { card.say = fresh }
                }
                // Numbers in a past-work answer come from <knowledge> or the talk (1413 P2: "two failed attempts").
                if !card.keep {
                    let kept = CoachNumbers.withoutInvented(card.say, question: request, sources: [input.background] + input.turns.map(\.text))
                    if !kept.isEmpty, kept != card.say { debugLog("coach: dropped a sentence with an unsourced number"); card.say = kept }
                    else if kept.isEmpty, trigger == .check { card.keep = true }
                }
                card.sentenceLimit = limit
                card.say = Self.capped(card.say, limit: limit)
                // Graded points the model keeps leaving out, added after the cap so they always fit
                // (strict wallet runs 2026-11-19: W6, W7 and P2 missed them every round).
                // Only what was said on this question: across the interview, W3's "reconciliation" and "resumes on
                // next launch" counted as W7's spike plan (1233).
                if !card.keep {
                    let history = input.turns.filter { $0.role == "candidate" && $0.seconds >= asked }.map(\.text)
                    let added = CoachRequiredPoints.missing(question: request, heard: card.heard, goal: self.memory.problem?.goal, say: card.say, said: history,
                                                            last: input.turns.last(where: { $0.role == "interviewer" })?.text)
                    if !added.isEmpty {
                        card.say += " " + added.joined(separator: " ")
                        card.sentenceLimit = limit + added.count
                        debugLog("coach: added \(added.count) required point(s)")
                    }
                }
                card.ops = Self.withoutSubtaskProblems(card.ops, newLines: newLines, memory: self.memory)
                card.ops = Self.withoutAgendaProblem(card.ops, newLines: newLines, memory: self.memory)
                card.ops = Self.missingProblemOps(card.ops, newLines: newLines, memory: self.memory) + card.ops
                // Also when the card's own adopt cites nothing usable (seen live: dropped as an alternative).
                if let latest = newLines.last(where: { $0.role == "interviewer" }),
                   !card.ops.contains(where: { $0.op == "adopt" && ($0.evidence ?? []).contains(latest.id) }),
                   let approach = Self.decidedApproach(latest.text) {
                    card.ops.append(CoachCaseOp(op: "adopt", text: approach, evidence: [latest.id]))
                }
                // A retry stream can end after the meeting was reset or a newer request took over.
                guard !Task.isCancelled, self.token == tok else { return }
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
            else if talked || trigger >= .manual || !card.fix.isEmpty || card.heard.isEmpty == false || Self.atSentenceStart(input.script) {
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
        card = partial; phase = .say; checkedCard = false; written = false; cardShownAt = now; talked = false
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
        let say = capped(card.say, limit: card.sentenceLimit)
        return card.fix.isEmpty ? say : card.fix + "\n" + say
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
    /// The card switches approach outright: code to type, or "I'll switch / let's use / fits better".
    nonisolated static func announcesSwitch(_ card: CoachCard) -> Bool {
        if let edit = card.edit, !edit.code.isEmpty { return true }
        return card.say.lowercased().range(of: #"\b(i'll|i will|let me|let's|we'll) (switch|change|move|rewrite|migrate|use)\b|\bfits better\b|\bi'd switch\b"#, options: .regularExpression) != nil
    }
    /// "Let's switch this to Kotlin Flow." / "Use Flow instead." → the chosen approach, when the card's CASE
    /// forgot to record the decision (AC-03).
    nonisolated static func decidedApproach(_ text: String) -> String? {
        guard !CoachEvidence.isTentative(text) else { return nil }
        // "Switch … to X" is the clearest; "use X instead" counts unless negated ("I'd rather not use RxJava").
        let patterns = [#"(?i)\b(?:switch(?: this| it| that)?(?: part)? to|change (?:it|this|that) to)\s+([A-Za-z][A-Za-z0-9+ ]{1,30}?)(?:\s+instead\b|\s+here\b|[.!,]|$)"#,
                        #"(?i)(?<!not )\buse\s+([A-Za-z][A-Za-z0-9+ ]{1,30}?)\s+instead\b"#,
                        // "Please replace RxJava with Kotlin Flow." (CH-01 left the decision unrecorded).
                        #"(?i)(?<!not |n't )\breplace\s+[A-Za-z][A-Za-z0-9+ ]{0,30}?\s+with\s+([A-Za-z][A-Za-z0-9+ ]{1,30}?)(?:\s+instead\b|\s+here\b|[.!,]|$)"#]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text) else { continue }
            let approach = text[range].trimmingCharacters(in: .whitespaces)
            // "use it", "use this" name nothing.
            if !["it", "this", "that", "them", "one"].contains(approach.lowercased()) { return approach }
        }
        return nil
    }

    /// Cards are one small step: at most five sentences, plus a closing check-in question when there is one.
    /// Seen in the newsfeed run: a twelve-sentence design monologue on one card.
    nonisolated static let sentenceLimit = 5
    /// "Tell me about yourself in two minutes" got five sentences, about 30 seconds (the 40-minute run, O-01).
    nonisolated static let introductionLimit = 14
    /// A line asking several things gets up to two sentences for each, at most eight: P3's five-sentence cap cut
    /// "who decided" and "what did you finish yourself" off a four-part question (strict wallet run 2026-11-19).
    nonisolated static let multiPartLimit = 8
    /// A story ("tell me about a time…") needs its setup before the parts asked: wallet run 2144, P3's eight
    /// sentences ended on the options, and "who decided" and "what I finished" were cut again.
    nonisolated static let storyLimit = 12
    nonisolated static func sentenceLimit(for line: String) -> Int {
        // Recognition punctuates badly ("…already exist. What? In the first version, who signs off, and if …"), so
        // the question words in the turn count too (real-audio run 6, W7).
        let asked = (try? NSRegularExpression(pattern: #"(?i)\b(what|why|how|who|which|when|where)\b"#))?
            .numberOfMatches(in: line, range: NSRange(line.startIndex..., in: line)) ?? 0
        let parts = max(CoachCardPrompt.questionParts(line).count, min(asked, 4))
        let base = line.range(of: #"(?i)\b(tell me (a bit |a little )?about yourself|introduce yourself|self-introduction|(give|do) (me |us )?(a |an )?(quick |short |brief )?introduction(?! (to|of|on|for)\b)|walk me through your (background|resume|cv|career))\b"#,
                   options: .regularExpression) != nil ? introductionLimit : sentenceLimit
        // Clarifying questions plus a direct answer (W1: "Start by clarifying the requirements. Which user path
        // would you define as the MVP?") did not fit five sentences, and the MVP was left out.
        let clarifies = parts >= 1 && line.range(of: #"(?i)\bclarif(y|ying)\b"#, options: .regularExpression) != nil
        if clarifies { return max(base, 6) }
        let story = line.range(of: #"(?i)\b(tell me about a time|give me an example|walk me through a time|describe a time)\b"#, options: .regularExpression) != nil
        if story && parts > 1 { return max(base, min(storyLimit, parts * 3)) }
        return parts > 1 ? max(base, min(multiPartLimit, parts * 2)) : base
    }
    nonisolated static func capped(_ say: String, limit: Int = sentenceLimit) -> String {
        let sentences = CoachScript.sentences(say)
        guard sentences.count > limit else { return say }
        var kept = Array(sentences.prefix(limit - 1))
        if let last = sentences.last, last.trimmingCharacters(in: .whitespaces).hasSuffix("?") { kept.append(last) }
        else { kept.append(sentences[limit - 1]) }
        return kept.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
    }

    nonisolated static func sameText(_ a: String, _ b: String) -> Bool {
        let x = CoachScript.words(a), y = CoachScript.words(b)
        guard !x.isEmpty, !y.isEmpty else { return false }
        return x == y || CoachBase.similarity(x.joined(separator: " "), y.joined(separator: " ")) > 0.9
    }
    /// Content words: what a sentence is about, without the glue.
    nonisolated static func contentWords(_ text: String) -> Set<String> {
        Set(CoachScript.words(text).filter { $0.count > 3 && !["that", "this", "with", "have", "they", "then", "will", "would", "about", "each", "there", "into", "from", "your", "just"].contains($0) })
    }
    /// Drops sentences that mostly repeat `line`. The first sentence is the one allowed acknowledgement
    /// ("Got it, so the feed has to work offline too.") and always stays.
    nonisolated static func withoutRecital(_ say: String, of line: String) -> String {
        let source = contentWords(line)
        let sentences = CoachScript.sentences(say)
        let kept = sentences.enumerated().filter { index, sentence in
            guard index > 0 else { return true }
            let words = contentWords(sentence)
            guard words.count >= 3 else { return true }
            return Double(words.intersection(source).count) / Double(words.count) < 0.6
        }.map(\.element)
        return kept.isEmpty ? (sentences.first ?? say) : kept.joined(separator: " ")
    }
    /// A new problem's statement is read back on purpose: the scope check repeats the task, then asks "Is that
    /// right?" (the 40-minute run, D-01: dropping the echo left "let me check the scope. Is that right?").
    nonisolated static func checksNewProblem(_ card: CoachCard, line: String) -> Bool {
        card.ops.contains { $0.op == "newProblem" } || line.range(of: newQuestionPattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
    nonisolated static func appending(_ note: String, to messages: [[String: Any]]) -> [[String: Any]] {
        var messages = messages
        guard var content = messages.last?["content"] as? [[String: Any]] else { return messages }
        content.append(["type": "text", "text": note])
        messages[messages.count - 1]["content"] = content
        return messages
    }

    /// "Okay, can you write the ViewModel?" is part of the current problem, yet DeepSeek kept opening a new
    /// one for it (AC-02). Its newProblem stands only when nothing is open yet, the interviewer marks a new
    /// question, or the new goal shares nothing with the current one and the line does not continue it.
    nonisolated static func withoutSubtaskProblems(_ ops: [CoachCaseOp], newLines: [CoachTurn], memory: CoachCase) -> [CoachCaseOp] {
        guard let current = memory.problem, let line = newLines.last(where: { $0.role == "interviewer" }) else { return ops }
        let t = line.text.lowercased()
        if t.range(of: newQuestionPattern, options: .regularExpression) != nil { return ops }
        let continues = t.range(of: #"^\s*(okay|ok|so|now|and|then|why|how come|can you|could you|please|great|good|alright|right)\b"#, options: .regularExpression) != nil
        let generic: Set<String> = ["android", "design", "build", "implement", "write", "make", "would", "could", "app", "your", "with"]
        return ops.filter { op in
            guard op.op == "newProblem", let goal = op.text else { return true }
            let shared = contentWords(goal).intersection(contentWords(current.goal)).subtracting(generic)
            return shared.isEmpty && !continues
        }
    }
    /// The founder's agenda ("Today we'll start with a project you owned, then design a fictional mobile
    /// wallet") came just before the first question, and the first card filed the wallet as the problem
    /// (wallet run 2026-11-19 03:45, P1). With nothing open yet, a newProblem taken from an announcement of
    /// what comes later is the question just asked.
    nonisolated static func withoutAgendaProblem(_ ops: [CoachCaseOp], newLines: [CoachTurn], memory: CoachCase) -> [CoachCaseOp] {
        guard memory.problem == nil else { return ops }
        let interviewer = newLines.filter { $0.role == "interviewer" }
        guard let latest = interviewer.last else { return ops }
        // The agenda alone (its own card before the first question): nothing has been asked yet.
        if isAgenda(latest.text) { return ops.filter { $0.op != "newProblem" } }
        let agenda = interviewer.dropLast().filter { isAgenda($0.text) }
        guard !agenda.isEmpty, CoachCardPrompt.asks(latest.text) else { return ops }
        return ops.map { op in
            guard op.op == "newProblem", let goal = op.text, !(op.evidence ?? []).contains(latest.id) else { return op }
            let words = contentWords(goal)
            let fromAgenda = agenda.contains { (op.evidence ?? []).contains($0.id) || words.intersection(contentWords($0.text)).count > words.intersection(contentWords(latest.text)).count }
            return fromAgenda ? CoachCaseOp(op: "newProblem", text: String(latest.text.prefix(120)), id: op.id, evidence: [latest.id]) : op
        }
    }
    /// Drops every sentence that mostly repeats one the candidate already said (60 % of its content words).
    nonisolated static func withoutSaid(_ say: String, said: [String]) -> String {
        let spoken = said.flatMap { CoachScript.sentences($0) }.map(contentWords).filter { $0.count >= 3 }
        return CoachScript.sentences(say).filter { sentence in
            let words = contentWords(sentence)
            guard words.count >= 3 else { return true }
            return !spoken.contains { Double(words.intersection($0).count) / Double(words.count) >= 0.6 }
        }.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
    }
    /// A bare acknowledgement: "Oh.", "Okay.", "Mm-hm, right.", "I see." Nothing to answer.
    nonisolated static func isBackchannel(_ text: String) -> Bool {
        let filler: Set<String> = ["oh", "ok", "okay", "mm", "mhm", "hmm", "hm", "uh", "huh", "um", "ah", "right", "yeah",
                                   "yes", "yep", "sure", "i", "see", "got", "it", "great", "good", "cool", "nice", "alright", "interesting"]
        let words = text.lowercased().split { !($0.isLetter || $0 == "'") }.flatMap { $0.split(separator: "-") }.map(String.init)
        return !text.contains("?") && !words.isEmpty && words.count <= 3 && words.allSatisfy(filler.contains)
    }
    /// "Today we'll start with …, then design …": what comes later, in order, with no question in it.
    nonisolated static func isAgenda(_ line: String) -> Bool {
        !line.contains("?")
            && line.range(of: #"(?i)\b(we'?ll|we will|we'?re going to|we are going to)\b"#, options: .regularExpression) != nil
            && line.range(of: #"(?i)\b(start with|begin with|then|after that|later|at the end|leave time)\b"#, options: .regularExpression) != nil
    }
    // "This is a new problem: design the chat cache" shares "cache" with the feed cache and was merged into it (ME-08).
    // "Do you have any questions for me?" ends the design; it was filed under its last question (the 40-minute run, P2-7).
    /// "Let's switch to the design exercise" kept the whole wallet design under the resume question (wallet run 5).
    /// "What questions do you have for me?" (wallet rerun 2026-11-19) stayed in the release question and got its answer again.
    /// "Now a different one: draw me a sequence diagram of login" (founder runs 2026-11-18/19) is a new
    /// problem too; DeepSeek kept it inside the chat flowchart's design problem.
    nonisolated static let newQuestionPattern = #"\b((new|next|different|another) question|(new|different) (problem|topic)|next topic|let'?s move on|moving on|switch(ing)? gears|let'?s (switch|move|turn) to (the |a )?(design|coding|system|next)|let'?s pause (that|this)|(any |what )?questions (do you have |have you got )?for (me|us)|(different|another) one\W+(can you |could you |please )?(draw|sketch)|(a |one )?(new|different|another|second) (diagram|chart))\b"#

    /// The interviewer plainly opens a new question or returns to an earlier one, and the card's CASE did
    /// not record it (AC-10): the app records it from the interviewer's own line. Applied before the
    /// card's own ops.
    nonisolated static func missingProblemOps(_ ops: [CoachCaseOp], newLines: [CoachTurn], memory: CoachCase) -> [CoachCaseOp] {
        let interviewer = newLines.filter { $0.role == "interviewer" }
        guard let line = interviewer.last else { return [] }
        let recorded = ops.contains { $0.op == "newProblem" || $0.op == "switch" }
        let t = line.text.lowercased()
        let opensNew = t.range(of: newQuestionPattern, options: .regularExpression) != nil
        var extra: [CoachCaseOp] = []
        // "Let's pause that" pauses a question that was never recorded when its card was cancelled by this
        // very turn: record that earlier question first, so it can be resumed.
        if opensNew, memory.problem == nil, let earlier = interviewer.dropLast().first {
            extra.append(CoachCaseOp(op: "newProblem", text: String(earlier.text.prefix(120)), evidence: [earlier.id]))
        }
        guard !recorded else { return extra }
        let back = #"\b(go(ing)? back to|back to the|return to|resume)\b"#
        if t.range(of: back, options: .regularExpression) != nil {
            // Only the sentence that goes back, and only to a problem it matches better than the current one:
            // "Back to the first transfer. … What could go wrong …" matched "what" in a resume question (wallet run 6).
            let sentence = t.components(separatedBy: CharacterSet(charactersIn: ".?!")).first { $0.range(of: back, options: .regularExpression) != nil } ?? t
            let words = Set(CoachScript.words(sentence).filter { $0.count > 3 })
            func score(_ p: CoachCase.Problem) -> Int { Set(CoachScript.words(p.goal)).intersection(words).count }
            let current = memory.problem.map(score) ?? 0
            let best = memory.problems.filter { $0.id != memory.problem?.id }.map { ($0, score($0)) }.max { $0.1 < $1.1 }
            if let (problem, s) = best, s > current { return [CoachCaseOp(op: "switch", id: problem.id, evidence: [line.id])] }
            return []
        }
        if opensNew { extra.append(CoachCaseOp(op: "newProblem", text: String(line.text.prefix(120)), evidence: [line.id])) }
        return extra
    }

    /// "I haven't explained the data flow yet": the candidate names what is still missing.
    nonisolated static func saysNotCovered(_ text: String) -> Bool {
        text.range(of: #"(?i)\b(haven't|have not|didn't|did not|not yet)\b.{0,20}\b(explain|cover|talk|mention|discuss|gone|go|got)"#,
                   options: .regularExpression) != nil
    }

    /// "Add another one", "add one more after it": the thing to add is not named.
    nonisolated static func unresolvedReference(_ text: String) -> Bool {
        text.range(of: #"(?i)\b(add|insert|put|write)\s+(another|one more)(\s+one)?\s*(after|before|below|above|here|there|next to|please|[.!?]|$)"#,
                   options: .regularExpression) != nil
    }

    /// An explain-only request: walk through, explain, describe… without asking to draw, add or write anything.
    nonisolated static func asksToExplain(_ text: String) -> Bool {
        let t = text.lowercased()
        let explain = t.range(of: #"\b(walk (me )?through|explain|describe|tell me about|how does|what is|what are)\b"#, options: .regularExpression) != nil
        let change = t.range(of: #"\b(draw|sketch|add|write|implement|code|change|update|extend)\b"#, options: .regularExpression) != nil
        return explain && !change
    }
    /// "Draw the flow", "sketch the architecture", "can you show the sequence diagram": a diagram is wanted.
    nonisolated static func asksToDraw(_ text: String) -> Bool {
        text.range(of: #"(?i)\b(draw|sketch|diagram|flow ?chart)"#, options: .regularExpression) != nil
    }
    nonisolated private static let keywords: Set<String> = ["val", "var", "fun", "class", "return", "private", "override", "data",
        "import", "package", "object", "true", "false", "null", "this", "when", "else", "suspend", "public", "internal",
        // Mermaid words never written on a whiteboard.
        "flowchart", "graph", "sequenceDiagram", "participant", "actor", "alt", "end", "opt", "loop"]
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
