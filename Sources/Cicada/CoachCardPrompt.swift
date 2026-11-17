import Foundation

/// The walkthrough card request (docs/walkthrough-coach-plan.md §1, §3). It reuses the coach request for
/// the whole interview's speech, knowledge and screen keyframes, and swaps the task for the next card.
enum CoachCardPrompt {
    static let rules = """
    WALKTHROUGH CARD MODE. This overrides the complete-answer and length rules above. The interview is a
    live Android technical interview at a whiteboard (code editor or diagram). Guide the candidate ONE small
    step at a time, from what is on the board and what both people said. Never write the whole answer ahead.

    SAY: what the candidate says now: one to four short spoken English sentences, answering the latest
    interviewer request first. Explain what code does and why; never read symbols aloud. When the interviewer
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
    THEN: one line: what comes after this step, or "Wait for the interviewer." when the question is covered.
    HEARD: the interviewer instruction you act on, in a few words, when the card follows one.
    FIX: only when the sentence the candidate is reading now has become wrong: one natural correcting sentence.
    REASON: only for a reason nobody stated; start it with "(optional)". It is a suggestion, not history.

    Scope: answer what was asked. Do not add features or requirements nobody asked for (loading states, error
    handling, tests…) to the plan; mention one as an optional idea in REASON or ask, never as the next step.
    A board change by itself is not a request: when the board shows the step done, confirm briefly and go on.
    Decisions: "Could we use B?" or "What about B?" is a question, not a decision. For it, SAY weighs A and B
    in two or three sentences and ends by asking whether they want the switch; no TYPE, no "I'll switch", and
    record only "alternative", never "adopt". "Let's use B", "Change it to B" or the candidate choosing B is a decision. After a decision,
    acknowledge it briefly ("Okay, I'll switch this part to B."), stop recommending the old approach and give
    the next step for the new one, keeping every earlier requirement that still applies. Say "I'll…" for work
    not yet visible on the board; never claim it is done.
    A reference you cannot resolve ("add another one") gets one short clarifying question of at most 15
    words, with no list of options, and no TYPE.
    Board evidence: content that moved out of view was not deleted; text hidden by the video tile or the screen
    edge is unknown; never invent code, boxes or arrows you cannot see. The board shows what is implemented;
    the latest explicit request shows the goal. They can differ for a while.
    Follow-ups: answer the follow-up first, then return to unfinished work only if the interviewer still wants
    it; skip points the candidate already covered. Resume and project questions use only <knowledge>; a design
    made live in this interview is never a past project. When returning, separate "In that project…" from
    "For this screen, I'll…".
    The candidate may paraphrase, skip or explain things their own way: judge what was covered from their
    actual lines, not from the reading position. Silence is not progress.
    If the current card still fits and nothing new needs an answer, output exactly KEEP after the marker.

    CASE: one line, a JSON array of changes to the walkthrough state, each {"op":…, "text":…, "evidence":[ids]}.
    A constraint is only a requirement someone actually stated, citing that line; never your own idea.
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
        else { parts.append("No whiteboard has been seen in this interview: do not use TYPE draw.") }
        // Put the candidate's own recent words where they cannot be missed (AC-13: points were repeated).
        let said = c.newLines.filter { $0.role == "candidate" }.map(\.text)
        if !said.isEmpty {
            parts.append("The candidate has ALREADY SAID these in their own words since the last card. Do not repeat these points; continue after them:\n- " + said.joined(separator: "\n- "))
        }
        if let card = c.card {
            let sentences = CoachScript.sentences(c.script.pending)
            parts.append("Current card shown: " + json(CardView(card)) +
                         "\nReading position (a hint, not proof): sentence \(min(c.script.currentSentence + 1, max(sentences.count, 1))) of \(sentences.count).")
        }
        if !c.prepared.isEmpty {
            parts.append("Prepared follow-up drafts (predictions, NOT questions anyone asked; use only if the real request matches, and check them):\n" + c.prepared)
        }
        parts.append("Trigger: \(c.trigger). Write the next card now. " + CoachPrompt.personalFactsReminder)
        return parts.joined(separator: "\n\n")
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
        new, word for word. If nothing new remains, write ONE short sentence that adds one new relevant point
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
