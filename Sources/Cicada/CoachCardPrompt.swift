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
    lives. Never only announce what you will explain or draw. Explain what code does and why; never read symbols aloud. When the interviewer
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
    At most 8 boxes or participants, short English labels, plain arrows with short labels; no styling,
    classDef, subgraphs or notes. A later draw on that diagram has only the new boxes and arrows, reusing
    the ids of the boxes they connect to. SAY walks through the diagram in drawing order.
    THEN: one line: what comes after this step, or "Wait for the interviewer." when the question is covered.
    HEARD: the interviewer instruction you act on, in a few words, when the card follows one.
    FIX: only when the sentence the candidate is reading now has become wrong: one natural correcting sentence.
    REASON: only for a reason nobody stated; start it with "(optional)". It is a suggestion, not history.

    A system design question ("design X") opens with a card that briefly confirms scope and requirements
    (functional, non-functional, out of scope) before any design, even when some are already on the board;
    that is what interviewers grade first. A narrow technical question is answered directly.
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
    newProblem only when the interviewer moves to a different question. Implementing, extending or asking
    about part of the current problem ("now write the ViewModel", "why StateFlow there?", "how do you test
    it?", "what if the input has no newline?") stays in it, and so does a line that points back with it,
    this or that. In a design problem, every question about the product being designed (protocol, event
    format, stop, network loss, process death, sync, voice, photo, metrics, what to build first) stays in the
    design problem. Only between separate knowledge questions (no design or code open) is a question about a
    different concept its own newProblem (StateFlow, then repeatOnLifecycle). "Any questions for me?" is a
    newProblem.
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
        // Last, where it is read: after new requirements DeepSeek recited them back before moving on.
        if c.trigger == .interviewer, let latest = c.newLines.last(where: { $0.role == "interviewer" }),
           !latest.text.trimmingCharacters(in: .whitespaces).hasSuffix("?") {
            parts.append("The interviewer's latest line gives information rather than asking a question. Acknowledge it in ONE short sentence without repeating its details, then move the design forward.")
        }
        if let hint = focusHint(memory: c.memory, latest: c.newLines.last(where: { $0.role == "interviewer" })?.text) {
            parts.append(hint)
        }
        parts.append("Trigger: \(c.trigger). Write the next card now. " + CoachPrompt.personalFactsReminder + " " + CoachPrompt.localTime(language: .english))
        return parts.joined(separator: "\n\n")
    }

    /// Read last, so it wins over the long transcript. The 40-minute runs: with Room chosen as the single
    /// source of truth, one run still answered "keep the text in the ViewModel" for 50 tokens a second
    /// (D-06), and voice and phone-call answers left out echo cancellation and the foreground service
    /// (D-13, D-14) although the rules list them.
    static func focusHint(memory: CoachCase, latest: String?) -> String? {
        var notes: [String] = []
        if let adopted = memory.problem?.adopted?.text {
            notes.append("Already decided in this problem: \(adopted) Keep this answer consistent with it. Never add a second place the UI reads the same data from (no \"keep the text in the ViewModel\" next to a database source of truth): batching, throttling and caching happen on the way into that one place, and the UI keeps reading only from it.")
        }
        if let latest, latest.range(of: #"(?i)\b(voice|phone call|incoming call|microphone|mic|speak(s|ing)?|talking|audio)\b"#, options: .regularExpression) != nil {
            notes.append("Android points for this answer (one clause each, only those that fit): a foreground service of type microphone keeps voice mode running; audio focus (a call takes it); the device's echo cancellation (AcousticEchoCanceler) so the mic does not hear the AI's own speech.")
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
