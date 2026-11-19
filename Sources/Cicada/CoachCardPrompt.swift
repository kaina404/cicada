import Foundation

/// The walkthrough card request (docs/walkthrough-coach-plan.md §1, §3). It reuses the coach request for
/// the whole interview's speech, knowledge and screen keyframes, and swaps the task for the next card.
enum CoachCardPrompt {
    static let rules = """
    WALKTHROUGH CARD MODE. This overrides the complete-answer and length rules above. The interview is a
    live Android technical interview at a whiteboard (code editor or diagram). Guide the candidate ONE small
    step at a time, from what is on the board and what both people said. Never write the whole answer ahead.

    SAY: what the candidate says now: one to four short spoken English sentences, answering the latest
    interviewer request first. Exception: "tell me about yourself" or "introduce yourself" gets a complete
    self-introduction of ten to fourteen sentences (about the time they asked for), with concrete facts from
    <knowledge> instead of vague claims such as "made the app faster". A direct question (where, what, which,
    how many) gets its concrete answer in SAY right now: name the layers, the choice, the place the data
    lives. A question with several parts (what risk, who watched, which signal) gets each part answered, in
    order, without restating the earlier answer. Never only announce what you will explain or draw. Explain what code does and why; never read symbols aloud. When the interviewer
    asks for one sentence, briefly or a short answer, SAY is exactly that: one sentence means one sentence.
    Before writing SAY, read the candidate's own lines since the current card: never repeat a point they
    already made in their own words; continue after it. If their own lines already answered the question, SAY
    is one short wrap-up sentence or one NEW point the interviewer would value (a limit, an edge case, process
    death…), never a restatement, and THEN is "Wait for the interviewer."
    TYPE: only when the candidate should now type or draw. Describe a LOCAL change to what is already on the
    board: action add, replace, delete or draw, and at="…" naming a class, function or box (never a line
    number), then the code (or the box and arrow labels) in one fenced block. Do not repeat the whole
    implementation. Base every change on the code visible on the board right now, not on an earlier card's
    suggestion that the board does not show; keep the board's names and values unless asked to change them.
    A concept explanation ("what is X", "how does X work", "what happens if…") gets no TYPE at all, and so
    does a request to walk through or explain what the board already shows.
    Comparison and design questions without a request to code get no code TYPE. Use draw only when
    the candidate should ADD something to a diagram now (one box, arrow or label group); never redraw what the
    board already shows, and never draw ASCII mockups of a whole screen.
    Diagrams: every draw puts Mermaid in a ```mermaid fence; the app shows it as a picture to copy. When the
    interviewer asks to draw or sketch a flow, the architecture or a sequence and the board does not show
    that diagram yet, the draw is the WHOLE small diagram at once (the candidate cannot draw from words):
    `flowchart TD` for components and data flow (top to bottom: the card is narrow), `sequenceDiagram` for calls in order over time.
    An Android client in an architecture flowchart is its layers (screen, ViewModel, repository, local database),
    not one box.
    At most 8 boxes or participants, short English labels, plain arrows with short labels; no styling,
    classDef, subgraphs or notes. A later draw on that diagram has only the new boxes and arrows, reusing
    the ids of the boxes they connect to. SAY walks through the diagram in drawing order.
    THEN: one line: what comes after this step, or "Wait for the interviewer." when the question is covered.
    HEARD: the interviewer instruction you act on, in a few words, when the card follows one.
    FIX: only when the sentence the candidate is reading now has become wrong: one natural correcting sentence.
    REASON: only for a reason nobody stated; start it with "(optional)". It is a suggestion, not history.

    A system design question ("design X") opens with a card that briefly confirms scope and requirements
    (functional, non-functional, out of scope) before any design, even when some are already on the board;
    that is what interviewers grade first. When the interviewer invites clarifying questions, SAY asks two or
    three concrete ones (who the users are, what holds the truth, offline behaviour), and when the same line also
    asks something direct ("Which path is the MVP?"), the same card answers it too, as an assumption to
    confirm; "does that match?" alone is not clarifying. A narrow technical question is answered directly.
    When the interviewer confirms or adds requirements, acknowledge them in at most one short sentence and
    move the design forward; never read the requirements back to them.
    Scope: answer what was asked. Do not add features or requirements nobody asked for (loading states, error
    handling, tests…) to the plan; mention one as an optional idea in REASON or ask, never as the next step.
    A board change by itself is not a request: when the board shows the step done, confirm briefly and go on.
    Decisions: "Could we use B?" or "What about B?" is a question, not a decision. For it, SAY weighs A and B
    in two or three sentences and ends by asking whether they want the switch; no TYPE, no "I'll switch", and
    record only "alternative", never "adopt". "Let's use B", "Change it to B" or the candidate choosing B is a decision. After a decision,
    acknowledge it briefly ("Okay, I'll switch this part to B."), stop recommending the old approach and give
    the next step for the new one, keeping every earlier requirement that still applies. Say "I'll…" for work
    not yet visible on the board; never claim it is done.
    A dropped requirement is simply no longer required: record dropConstraint citing that line and never record
    its opposite ("no offline" is not "no local database") unless someone said it.
    Facts the interviewer gives about the scenario bind: a value they call missing, unreliable or ambiguous
    (no amount in the chat, two contacts with the same name) is never filled in or guessed; asking the user
    for it is the step.
    Never state a guarantee nobody established: a requestId or cursor on the board shows intent, so what the
    server must do with it (deduplicate, keep order) is a contract to confirm ("the server would need to…"),
    and no technique "never" fails.
    A reference you cannot resolve ("add another one") gets one short clarifying question of at most 15
    words, with no list of options, and no TYPE.
    Board evidence: content that moved out of view was not deleted; text hidden by the video tile or the screen
    edge is unknown; never invent code, boxes or arrows you cannot see. The board shows what is implemented;
    the latest explicit request shows the goal. They can differ for a while.
    Follow-ups: answer the follow-up first, then return to unfinished work only if the interviewer still wants
    it; skip points the candidate already covered. Resume and project questions use only <knowledge>; a design
    made live in this interview is never a past project. When returning, separate "In that project…" from
    "For this screen, I'll…".
    Past projects stay in resume answers. A concept, coding or design question is about the general case or
    the product being designed here: answer it with neutral examples (a list screen, a chat message, "data:
    hello" as test input), never with details of a past project from <knowledge> (its screens, its fields,
    its cards), unless the interviewer asks about experience ("have you", "in your project", "a time when").
    "Restore the screen" means any screen: use a generic one (a form, a detail screen).
    Never tell the same story twice in one interview: when the story that fits was already told, tell a
    different one (another bug, another device, another project), or say "Besides the WebView case…" first.
    Android depth: name the platform mechanism an Android interviewer checks, in one clause each: parsing,
    Markdown and disk work off the main thread (Dispatchers.Default / IO); process death and lifecycle; a
    foreground service of the right type for work the user expects to keep running (voice mode always needs
    one of type microphone, and a phone call means losing audio focus); audio focus and echo cancellation (the device's AEC) for voice; WorkManager for uploads that must
    finish; and for production quality crash-free rate, ANR rate and dropped frames next to product metrics.
    When a question has an important Android point that does not fit, THEN names it ("Next: the foreground
    service.") instead of "Wait for the interviewer."
    Consistency: decisions already made in this problem (in the candidate's lines, the log and "adopted") bind
    every later answer. If the local database is the single source of truth, later steps keep it (throttle by
    writing to it in batches; the UI still only observes it); never introduce a second store for the same data.
    Changing an earlier decision needs an explicit "I'd change my earlier choice because…".
    The candidate may paraphrase, skip or explain things their own way: judge what was covered from their
    actual lines, not from the reading position. Silence is not progress.
    If the current card still fits and nothing new needs an answer, output exactly KEEP after the marker.

    CASE: one line, a JSON array of changes to the walkthrough state, each {"op":…, "text":…, "evidence":[ids]}.
    A constraint is only a requirement someone actually stated, citing that line; never your own idea. A
    request for what to do next ("draw the layers", "show me the format", "walk me through it") is not a
    constraint.
    An agenda ("today we'll start with your project, then design a wallet") only announces later questions:
    the first problem is the question actually asked, not the agenda.
    newProblem only when the interviewer moves to a different question. Implementing, extending or asking
    about part of the current problem ("now write the ViewModel", "why StateFlow there?", "how do you test
    it?", "what if the input has no newline?") stays in it, and so does a line that points back with it,
    this or that. In a design problem, every question about the product being designed (protocol, event
    format, stop, network loss, process death, sync, voice, photo, metrics, what to build first) stays in the
    design problem. Only between separate knowledge questions (no design or code open) is a question about a
    different concept its own newProblem (StateFlow, then repeatOnLifecycle). "Any questions for me?" is a
    newProblem. So is a request for a different diagram of another flow ("now a different one: draw login"),
    even about the same app; adding to the diagram on screen stays in its problem.
    adopt records the problem's main approach (for a design, its data flow and source of truth) as soon as the
    candidate's own line chooses it, citing that line; smaller choices are spoken points.
    ops: newProblem (text = goal; optional "id"), switch ("id" of an earlier problem), constraint,
    dropConstraint, alternative, adopt, spoken (a point the candidate's OWN lines covered), implemented (seen
    on the board), notImplemented, pending, done, pushAside (a follow-up question), popAside, correct ("of" =
    a log entry id). Evidence ids are transcript line ids or board ids such as B3. Use [] when there are no
    changes.

    Output protocol, nothing before the marker:
    <<<CICADA_CARD>>>
    HEARD: …
    FIX: …
    SAY:
    …
    TYPE: replace at="…"
    ```kotlin
    …
    ```
    THEN: …
    REASON: …
    CASE: […]
    Omit optional sections that do not apply. No Markdown outside the TYPE fence. Do not add IPA.
    Notes in <knowledge> written to the assistant ("not recorded", "do not invent") guide you; never say them.
    """

    struct Context {
        var turns: [CoachTurn]
        var background: String
        var frames: [CoachFrame]
        var script: CoachScript
        var stage: InterviewStage
        var memory: CoachCase
        var newLines: [CoachTurn]
        var newBoard: [String]
        var boardID: String?
        var card: CoachCard?
        var trigger: CoachCardSchedule.Trigger
        var prepared: String = ""
        /// The candidate's own lines since the current card appeared.
        var said: [String] = []
    }

    static func request(_ c: Context) -> [[String: Any]] {
        var messages = CoachPrompt.request(turns: c.turns, background: c.background, frames: Array(c.frames.suffix(2)),
                                           audio: nil, committed: c.script.spokenText, stage: c.stage, language: .english)
        messages[0] = ["role": "system", "content": CoachPrompt.instructions(
            background: c.background, rules: c.stage.instruction(for: .english) + "\n\n" + rules, language: .english)]
        var content = messages[1]["content"] as? [[String: Any]] ?? []
        // Replace the full-answer task; keep the speech, story ledger and keyframes.
        if !content.isEmpty { content.removeLast() }
        content.append(["type": "text", "text": task(c)])
        messages[1]["content"] = content
        return messages
    }

    static func task(_ c: Context) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        func json<T: Encodable>(_ value: T) -> String {
            (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
        }
        let current = c.memory.problem?.id
        let log = c.memory.log.filter { $0.problem == current || $0.problem.isEmpty }.suffix(60)
            .map { "\($0.id) [\(Int($0.seconds))s] \($0.text)" + ($0.corrects.map { " (corrects \($0))" } ?? "") }
        var parts = [
            "Walkthrough state (JSON): " + json(StateView(c.memory)),
            "Log for the current problem:\n" + (log.isEmpty ? "(empty)" : log.joined(separator: "\n")),
            "New transcript lines since the last card: " + (c.newLines.isEmpty ? "none" : c.newLines.map(\.id).joined(separator: ", ")),
            "New board text since the last card (already-seen text removed): " + (c.newBoard.isEmpty ? "none" : json(c.newBoard)),
        ]
        if let id = c.boardID { parts.append("The latest screen keyframe is board id \(id).") }
        else { parts.append("No whiteboard has been seen in this interview: use TYPE draw only when the interviewer asks to draw or sketch a diagram.") }
        // Put the candidate's own recent words where they cannot be missed (AC-13: points were repeated).
        let said = c.said.isEmpty ? c.newLines.filter { $0.role == "candidate" }.map(\.text) : c.said
        if !said.isEmpty {
            parts.append("The candidate has ALREADY SAID these in their own words since the last card. Do not repeat these points; continue after them. A line saying something is not covered yet (\"I have not explained the data flow\") is not a point made: cover that next:\n- " + said.joined(separator: "\n- "))
        }
        if let card = c.card {
            let sentences = CoachScript.sentences(c.script.pending)
            parts.append("Current card shown: " + json(CardView(card)) +
                         "\nReading position (a hint, not proof): sentence \(min(c.script.currentSentence + 1, max(sentences.count, 1))) of \(sentences.count).")
        }
        if !c.prepared.isEmpty {
            parts.append("Prepared follow-up drafts (predictions, NOT questions anyone asked; use only if the real request matches, and check them):\n" + c.prepared)
        }
        // Strict wallet run 2026-11-19, W2: a stray "Who do you remote?" heard right after the flowchart request
        // became the latest line, and the card only asked the interviewer to repeat.
        if c.trigger == .interviewer, let note = misheardNote(c.newLines) { parts.append(note) }
        if c.trigger == .interviewer, c.card != nil, finishesShownQuestion(c.turns, newLines: c.newLines) {
            // Real-audio run 6, W7: the question's last words came late and the new card dropped the scope and
            // the checks the card on screen already had.
            parts.append("The new interviewer words only finish the question the card on screen was written for. If that card already answers the whole question, output KEEP. Otherwise write the complete answer to the whole question, keeping every point of the card on screen the candidate has not read yet.")
        }
        // Last, where it is read: after new requirements DeepSeek recited them back before moving on.
        if c.trigger == .interviewer, let latest = interviewerTurn(c.newLines), !asks(latest) {
            parts.append("The interviewer's latest line gives information rather than asking a question. Acknowledge it in ONE short sentence without repeating its details, then move the design forward.")
        }
        if let hint = focusHint(memory: c.memory, latest: interviewerTurn(c.newLines)) {
            parts.append(hint)
        }
        parts.append("Trigger: \(c.trigger). Write the next card now. " + CoachPrompt.personalFactsReminder + " " + CoachPrompt.localTime(language: .english))
        return parts.joined(separator: "\n\n")
    }

    /// The interviewer's whole turn: their lines since the candidate last spoke, joined. Real recognition cut
    /// W7 into "…what do you?" and "Do in the next half hour.", and the release hint, the multi-part note and
    /// the longer card all read only the last piece (real-audio wallet run 2026-11-19).
    /// Once the candidate is reading, it is still their last turn, not its last piece: a card replaced mid-read
    /// lost the MVP sentence to the five-sentence cap (real-audio run 6, W1).
    static func interviewerTurn(_ turns: [CoachTurn]) -> String? {
        guard let end = turns.lastIndex(where: { $0.role == "interviewer" }) else { return nil }
        let tail = turns[...end].reversed().prefix { $0.role == "interviewer" }.prefix(4).reversed().map(\.text)
        return tail.joined(separator: " ")
    }

    /// The interviewer's current turn began before the card on screen was written, and only its end is new.
    static func finishesShownQuestion(_ turns: [CoachTurn], newLines: [CoachTurn]) -> Bool {
        guard let last = turns.last, last.role == "interviewer" else { return false }
        let turn = turns.reversed().prefix { $0.role == "interviewer" }
        let ids = Set(newLines.map(\.id))
        return turn.contains { ids.contains($0.id) } && turn.contains { !ids.contains($0.id) }
    }

    /// A short last line after a real request in the same turn may be misheard speech: name the request,
    /// so a fragment that makes no sense does not replace it.
    static func misheardNote(_ newLines: [CoachTurn]) -> String? {
        let interviewer = newLines.filter { $0.role == "interviewer" }
        guard interviewer.count >= 2, let last = interviewer.last, CoachScript.words(last.text).count <= 5,
              let request = interviewer.dropLast().last(where: { asks($0.text) && CoachScript.words($0.text).count > 5 })
        else { return nil }
        return "The interviewer's last line \"\(last.text)\" is short. If it does not make sense here, it was misheard: answer the earlier request in this turn, \"\(request.text.prefix(300))\", and never ask them to repeat it. If it is a real short question, answer it."
    }

    /// A question mark, or a request in the imperative: the wallet run's "Draw the client, the server and local
    /// storage as a flowchart, and tell me what each part owns." was taken as information and got one sentence.
    static func asks(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasSuffix("?") || line.range(of:
            #"(?i)\b(draw|sketch|walk (me|us) through|tell (me|us)|show (me|us)|explain|describe|design|write|add|update|revise|list|give (me|us))\b"#,
            options: .regularExpression) != nil
    }

    /// The questions in one interviewer line: "What other options did you have, why didn't you pick them, and
    /// after release how did you know the change worked?" is three. The card answered two (wallet run 03:45, P2).
    static func questionParts(_ line: String) -> [String] {
        let wh = #"(what|why|how|who|whom|when|where|which|did|do|does|is|are|can|could|would)\b"#
        // A sentence is a question by its "?" or, since recognition often ends one with "." ("Which user path
        // would you define as the MVP." in the real-audio run), by the word it starts with. Setup sentences
        // ("Separate scenario. A still has 100 dollars.") are not parts.
        return sentencesKeepingMarks(line).flatMap { sentence -> [String] in
            let asked = sentence.hasSuffix("?") || sentence.range(of: #"(?i)^((and|so|but|then|also),? )?((after|before|if|when|once) [^,]{1,60}, )?"# + wh, options: .regularExpression) != nil
            guard asked else { return [] }
            let question = sentence.trimmingCharacters(in: CharacterSet(charactersIn: ".?! ").union(.whitespaces))
            let pieces = question.replacingOccurrences(of: #"(?i),?\s*(,|\band\b)\s+(?=(after \w+ )?"# + wh + ")", with: "\u{1F}", options: .regularExpression)
            return pieces.components(separatedBy: "\u{1F}").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { $0.split(separator: " ").count >= 2 && $0.range(of: "(?i)\\b" + wh, options: .regularExpression) != nil }
        }
    }
    /// "A. B? C" → ["A.", "B?", "C"], each trimmed.
    private static func sentencesKeepingMarks(_ text: String) -> [String] {
        var out: [String] = [], current = ""
        for ch in text {
            current.append(ch)
            if ".?!".contains(ch) { out.append(current.trimmingCharacters(in: .whitespaces)); current = "" }
        }
        let rest = current.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty { out.append(rest) }
        return out.filter { !$0.isEmpty }
    }

    /// Read last, so it wins over the long transcript. The 40-minute runs: with Room chosen as the single
    /// source of truth, one run still answered "keep the text in the ViewModel" for 50 tokens a second
    /// (D-06), and voice and phone-call answers left out echo cancellation and the foreground service
    /// (D-13, D-14) although the rules list them.
    static func focusHint(memory: CoachCase, latest: String?) -> String? {
        var notes: [String] = []
        // Wallet runs 2026-11-19: "What questions do you have for me?" came before the app recorded the new
        // problem, so the old problem's money note pulled the card back to the release question.
        let opensNew = latest?.range(of: CoachCards.newQuestionPattern, options: [.regularExpression, .caseInsensitive]) != nil
        let problem = opensNew ? nil : memory.problem
        if opensNew {
            notes.append("The interviewer's latest line opens a new question: answer that question, not the previous one.")
        }
        if let latest, case let parts = questionParts(latest), parts.count > 1 {
            notes.append("This line asks \(parts.count) things; answer each in this order, one or two sentences each (this card may run to \(CoachCards.sentenceLimit(for: latest)) sentences), and move the rest to the next card (THEN) rather than drop one: " + parts.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: " "))
        }
        if let adopted = problem?.adopted?.text {
            notes.append("Already decided in this problem: \(adopted) Keep this answer consistent with it. Never add a second place the UI reads the same data from (no \"keep the text in the ViewModel\" next to a database source of truth): batching, throttling and caching happen on the way into that one place, and the UI keeps reading only from it.")
        }
        if let latest, latest.range(of: #"(?i)\b(voice|phone call|incoming call|microphone|mic|speak(s|ing)?|talking|audio)\b"#, options: .regularExpression) != nil {
            notes.append("Android points for this answer (one clause each, only those that fit): a foreground service of type microphone keeps voice mode running; audio focus (a call takes it); the device's echo cancellation (AcousticEchoCanceler) so the mic does not hear the AI's own speech.")
        }
        // Wallet run 2026-11-19: amounts, the atomic ledger, "reject the duplicate" and a chat-flow
        // confirmation kept only on the phone were missed although the interviewer graded them.
        let topic = (latest ?? "") + " " + (problem?.goal ?? "")
        if topic.range(of: #"(?i)\b(wallet|pay(s|ing|ment)?|transfer(s|red)?|balance|ledger|dollars?|refund)\b"#, options: .regularExpression) != nil {
            notes.append("Money points (one clause each, only those this question needs; a transfer of a named amount always gets the first three: its amount in cents, both final balances as numbers (\"A goes from 100 to 20 dollars, B from 0 to 80\"), the result screen's states, and the user's confirm step before the request; a lost response always gets: the intent saved before sending, the lookup by account and client ID after restart, a resend of that same ID only as the server's idempotency contract allows, never a new ID, and the server answering that repeat with the original transfer's status, so the ledger has one transfer; a payment started from a chat or by the model always gets: the user picks the recipient and amount on a trusted native confirmation, the server binds the authorization to payer, recipient, amount and expiry, and a repeated tool call or retry maps to the original intent's ID): amounts as a Long in minor units (80 dollars = 8000 cents); when the interviewer gave balances and an amount, say both balances after the transfer in numbers; the result screen's states: success, clear failure, processing, and outcome unknown (still checking); the server checks and debits the payer and credits the payee in ONE database transaction (row lock or conditional update), so a balance never goes negative; the client saves the transfer intent with its client transfer ID locally BEFORE sending it; a lost response or timeout is an unknown outcome, not a failure: after a restart, query the server by account and the same client transfer ID, and resend only that ID, only as the server's idempotency contract allows; a lookup that finds nothing does not prove no money moved (the request may still be in flight or the read may lag), so the state stays unknown; the server answers a repeat of that ID with the same parameters with the original transfer's current status (not an error) and rejects it with different parameters; after the user confirms on a trusted native screen, the server binds the authorization to payer, recipient, amount and expiry, so chat or model text never authorizes a payment or reports its success; a repeated tool call or retry from the model maps to the original intent's ID, never a second transfer, and when the chat drops the app reads the status from the payment service by that ID; the app shows success only from the server's transfer record.")
        }
        // Wallet run 2026-11-19 03:45, W1: asked to clarify, the card asked about users and stopped, with no MVP.
        if let latest, latest.range(of: #"(?i)\b(clarify|clarifying|requirements?|scope)\b"#, options: .regularExpression) != nil,
           topic.range(of: #"(?i)\b(wallet|pay(s|ing|ment)?|transfer(s|red)?|balance|money)\b"#, options: .regularExpression) != nil {
            notes.append("Clarifying a payment design: ask whether the balance is held by us or moves on a bank or card rail, which currencies, what works offline, and whether the server ledger is the authority; then, on this same card, propose one MVP path yourself (for example: send money to a contact, with balance and history) as an assumption to confirm. Four short questions plus the MVP fit in six sentences.")
        }
        // W2 (real-audio run 7): "Client: screens, ViewModel, local cache" as one box, although the rules say layers.
        if let latest, CoachCards.asksToDraw(latest), latest.range(of: #"(?i)\b(client|android|app)\b"#, options: .regularExpression) != nil,
           latest.range(of: #"(?i)\bsequence\b"#, options: .regularExpression) == nil {
            notes.append("Diagram: draw the Android client as four separate boxes in order, Screen → ViewModel → Repository → Local DB, then the server and its ledger; never one \"Client\" box.")
        }
        // P3 (real-audio wallet run 6): the delivery-risk story never said where it happened.
        if let latest, latest.range(of: #"(?i)\b(tell me about a time|give me an example of a time|describe a time|a time (when )?you)\b"#, options: .regularExpression) != nil {
            notes.append("Past-work story: name the company (and project) it happened at in the first sentence, from <knowledge>.")
        }
        // P2 (strict wallet runs 2026-11-19): "how did you know it worked" got the metric but never its limits.
        if let latest, latest.range(of: #"(?i)\bhow (did|do|would) you know\b|\bknow (that )?(the|it|your) (change|fix)?\s*worked\b"#, options: .regularExpression) != nil {
            notes.append("Evidence: name where the result came from (a metric, a test, a ticket or user feedback) and one limit of it, what it cannot prove (for example: crash rate only counts reported crashes; a test covers only the cases we wrote).")
        }
        // W4: "the server handles them one at a time" named no mechanism.
        if let latest, latest.range(of: #"(?i)\b(same time|at once|concurrent(ly)?|simultaneous(ly)?|two phones|race|in parallel)\b"#, options: .regularExpression) != nil {
            notes.append("Concurrency: say first that these are two separate intents, each with its own client transfer ID (not a duplicate of one); then name the mechanism in one clause: a row lock on the payer's balance (SELECT … FOR UPDATE) or a conditional update (UPDATE … SET balance = balance - amount WHERE balance >= amount), in the same transaction as the credit.")
        }
        if let latest, latest.range(of: #"(?i)\b(log(s|ged)? ?out|sign(s|ed)? ?out|switch(es|ed)? (to )?(another |a different )?(account|user)|account [A-Z]\b)"#, options: .regularExpression) != nil {
            notes.append("Account switch points: tag every in-flight request, cache write and callback with the account and a session generation, and drop a response whose session is no longer current, so the new account never sees the old one's data; and always say the last point too: work the old account already committed stays on the server and comes back from its own history after it signs in again.")
        }
        if let latest, latest.range(of: #"(?i)\b(ship|release|roll ?out|first version|first users|go live)\b"#, options: .regularExpression) != nil {
            // W7 (wallet run 03:45): the card gave scope, sign-off and a pause, but no checks and no resume.
            notes.append("Release answer, in this order: the first version's scope (for a wallet: balance, internal transfer, history, the confirmation step and recoverable pending or unknown states) and what waits; who signs off; the pre-release checks, each failure case already discussed in this problem named in one sentence (for a wallet: lost response plus process kill, replay of the same ID, two concurrent transfers, account switch); on a spike, pause new submissions while reads and status keep working, who owns the fix and the reconciliation, and the condition to resume. If it does not fit this card, end with a THEN that continues, and say the rest on the next card.")
        }
        return notes.isEmpty ? nil : notes.joined(separator: "\n")
    }

    private struct StateView: Encodable {
        var problems: [CoachCase.Problem]
        var current: String?
        var followUps: [CoachCase.Aside]
        init(_ c: CoachCase) { problems = c.problems; current = c.problem?.id; followUps = c.asides }
    }
    private struct CardView: Encodable {
        var heard: String, say: String, type: String?, then: String
        init(_ c: CoachCard) {
            heard = c.heard; say = c.say; then = c.then
            type = c.edit.map { "\($0.action) at \($0.at):\n\($0.code)" }
        }
    }

    /// AC-13: a small, separate edit, because the card request alone kept restating the candidate.
    static func dedupeRequest(say: String, said: [String]) -> [[String: Any]] {
        let system = """
        You edit what a job candidate will say next in a live English interview. The candidate has ALREADY said
        some things in their own words. Remove every sentence of the draft that restates any of those points,
        even when it is paraphrased or adds only small wording changes. Keep the sentences that add something
        new, word for word. A line saying something has NOT been explained yet makes no point: keep every
        sentence about that topic. If nothing new remains, write ONE short sentence that adds one new relevant point
        (a limit, an edge case, a trade-off) and never restates. Output only the final spoken text, no labels.
        """
        let user = "Already said by the candidate:\n- " + said.joined(separator: "\n- ") + "\n\nDraft:\n" + say
        return [["role": "system", "content": system], ["role": "user", "content": [["type": "text", "text": user]]]]
    }

    /// Follow-up preparation (FR-11 item 5): cheap, low priority, never shown as an answer.
    static let prepareRules = """
    Predict the two follow-up questions this interviewer is most likely to ask next about the current problem,
    and draft a two-sentence spoken English answer for each. Plain text, at most 120 words. Mark each with
    "Q:" and "A:". These are predictions only.
    """
    static func prepareRequest(_ c: Context) -> [[String: Any]] {
        var messages = request(c)
        messages[0] = ["role": "system", "content": CoachPrompt.instructions(background: c.background, rules: prepareRules, language: .english)]
        var content = messages[1]["content"] as? [[String: Any]] ?? []
        // Text only: images cost time and the drafts are hints.
        content.removeAll { $0["type"] as? String == "image_url" }
        if !content.isEmpty { content.removeLast() }
        content.append(["type": "text", "text": task(c).components(separatedBy: "\n\nTrigger:").first! + "\n\nWrite the predictions now."])
        messages[1]["content"] = content
        return messages
    }
}
