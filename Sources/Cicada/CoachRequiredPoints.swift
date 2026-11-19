import Foundation

/// Points an interviewer always grades for some question types, added to the card when the model left them out.
/// The strict wallet runs on 2026-11-19 (1101, 1139) missed the same points round after round although
/// `CoachCardPrompt.focusHint` lists every one: five or six spoken sentences don't hold them all, and the
/// misses that were never caught up while the candidate read are fixed here, after the card is written.
enum CoachRequiredPoints {
    struct Point {
        /// The point counts as made when the card or anything the candidate already said matches this.
        let covered: String
        let sentence: String
        /// A clause of one merged question ("A few quick checks: a, b and c?") instead of its own sentence:
        /// W1's misses rotated (1413: rail and currency), and four added questions would bury the MVP.
        var clause = false
    }
    struct Rule {
        /// Matches the interviewer's question.
        let asks: String
        /// Also required in the question plus the problem's goal (nil: none), so a notes app's "two users at
        /// the same time" gets no transfer IDs.
        let topic: String?
        let points: [Point]
    }

    static let money = #"(?i)\b(wallet|pay(s|ing|ment)?|transfer(s|red)?|balance|ledger|dollars?|money)\b"#

    static let rules: [Rule] = [
        // W3 (1139): lost response plus process kill, the replay was never tied to the idempotency contract.
        Rule(asks: #"(?i)\b(response|reply)\b.{0,40}\b(lost|never (arrives|arrived|comes|came)|dropped)\b|\blost (the )?(response|reply)\b|\bbefore (any|the) response\b|\b(kill(s|ed)?|dies|died)\b.{0,30}\bprocess\b|\bprocess\b.{0,30}\b(kill(s|ed)?|death|dies|died)\b"#,
             topic: money, points: [
                Point(covered: #"(?i)idempoten\w*.{0,40}\b(contract|window|record|allows?|permits?)\b|\b(contract|window)\b.{0,40}\b(allows?|permits?|covers?|still)\b"#,
                      sentence: "I'd resend that same client ID only while the server's idempotency window still covers it; after that, I'd rely on the lookup and reconciliation, never a new ID."),
                // 1233: with the window covered, the repeat's answer and the single ledger entry went missing.
                Point(covered: #"(?i)\boriginal (transfer|result|status|record)\b|\b(one|single|only one) (transfer|ledger entry|debit)\b"#,
                      sentence: "The server answers a repeat of that ID with the original transfer's status, so the ledger still has only one transfer."),
             ]),
        // W2 (1307): every layer said what it owns, but not that the server's ledger has the final word.
        Rule(asks: #"(?i)\bwhat each (part|piece|layer|box) owns\b|\bdraw\b.{0,40}\b(client|server)\b.{0,40}\b(server|local storage|database)\b"#,
             topic: money, points: [
                Point(covered: #"(?i)\bsource of truth\b|\bauthorit|\bledger\b.{0,40}\b(decides|has the final|is the truth|owns the (money|balance))"#,
                      sentence: "The server's ledger is the only source of truth for balances; the app only shows what the server confirms."),
             ]),
        // W1 (1233): asked about custody, currency and offline, never who is the authority; 1413 asked users,
        // authority and offline, never rail or currency, and "the ledger" in passing counted as the authority.
        Rule(asks: #"(?i)\b(clarify|clarifying|requirements?)\b"#,
             topic: money, points: [
                Point(covered: #"(?i)\b(rails?|bank|card network|stored (balance|value)|held by us|hold(s)? the money|custod\w*)\b"#,
                      sentence: "is the balance held by us, or does money move on a bank or card rail", clause: true),
                Point(covered: #"(?i)\bcurrenc"#, sentence: "which currencies do we support", clause: true),
                Point(covered: #"(?i)\boffline\b|\bno (network|signal)\b|\bnetwork drops\b"#,
                      sentence: "what should work offline", clause: true),
                Point(covered: #"(?i)\bsource of truth\b|\bauthorit|\bonly record\b|\bledger\b.{0,30}\b(truth|record|final say)\b"#,
                      sentence: "is the server's ledger the only source of truth for balances", clause: true),
                // 1339: the questions came, the MVP only on an update the reader may never reach.
                Point(covered: #"(?i)\bMVP\b|\bone path\b|\bfirst (version|path)\b"#,
                      sentence: "For the MVP, I'd pick one path: send money to a contact, with balance and history."),
             ]),
        // W4 (1101, 1139): "one at a time" without two IDs or the transaction.
        Rule(asks: #"(?i)\b(same time|at once|concurrent(ly)?|simultaneous(ly)?|two (phones|devices)|in parallel)\b"#,
             topic: money, points: [
                Point(covered: #"(?i)\b(two|separate|different|independent)\s+(transfer\s+)?(intents?|client( transfer)? IDs?|IDs)\b|\b(its|their) own (client )?(transfer )?(ID|intent)\b"#,
                      sentence: "These are two separate intents, each with its own client transfer ID, so idempotency doesn't merge them."),
                Point(covered: #"(?i)\b(one|single|same) (database )?transaction\b|\brow lock\b|\bconditional update\b|\bfor update\b"#,
                      sentence: "The server checks and debits the balance in one database transaction, with a row lock or a conditional update, so the second one fails for insufficient funds."),
             ]),
        // W5 (1139): stale callbacks dropped, but A's committed transfer was never brought back.
        Rule(asks: #"(?i)\b(log(s|ged)? ?out|sign(s|ed)? ?out|switch(es|ed)? (to )?(another |a different )?(account|user)|to account [A-Z])\b"#,
             topic: money, points: [
                Point(covered: #"(?i)\b(sign|log)s? (back )?in (again|back)\b|\bback in as\b|\b(own|old account's|A's) history\b"#,
                      sentence: "A's committed transfer stays on the server, and it comes back from A's own history when A signs in again."),
             ]),
        // W6 (every strict run): a repeated tool call was never tied to the original intent.
        // 1139's W6 named no money at all ("a chat message naming one of two Alexes"): the wallet comes from the
        // problem's goal. Not a bare "model", which the candidate's AI trip planner questions use.
        // 1413: the right question, but the amount was never asked and the server never bound the authorization.
        // 1516: "which Alex or which amount" and "binds that approval" are the same points in other words.
        Rule(asks: #"(?i)\b(chat|assistant|agent|tool call)\b"#,
             topic: money, points: [
                Point(covered: #"(?i)\bhow much\b|\b(which|what) amount\b|\b(ask(s|ed)?|types?|enters?|picks?|chooses?|fills? in)\b.{0,40}\bamount\b|\bamount\b.{0,30}\b(field|blank|empty|typed|entered)\b"#,
                      sentence: "The chat gives no reliable amount, so the user types the amount on that confirm screen; the model never fills it in."),
                Point(covered: #"(?i)\bserver\b.{0,60}\b(binds?|ties?|tied|bound)\b.{0,40}\b(authori|approv)|\b(authori|approv)\w*.{0,60}\b(bound|tied)\b.{0,40}\b(payer|recipient|amount)"#,
                      sentence: "The server binds that authorization to the payer, recipient, amount and expiry; chat or model text can suggest a payment but never authorizes one."),
                Point(covered: #"(?i)\b(tool|function)( call)?\b.{0,80}\b(same|original|that|one)\b.{0,20}\b(intent|client( transfer)? ID|ID)\b|\b(again|twice|repeat(ed)?|retr(y|ies|ied))\b.{0,60}\b(same|original)\b.{0,20}\b(intent|client( transfer)? ID|ID)\b"#,
                      sentence: "If the model calls the payment tool again, that call maps to the same intent and client ID, so it can never create a second transfer."),
             ]),
        // W2-seq (runs 2232, 2327): the sequence of "A sending B 80 dollars" never said the amount travels in cents.
        Rule(asks: #"(?i)\b(send(s|ing)?|transfer(s|ring)?|pay(s|ing)?)\b[^.?]{0,30}\b\d+ (dollars?|usd)\b"#,
             topic: money, points: [
                Point(covered: #"(?i)\bcents?\b|\bminor units?\b"#,
                      sentence: "The amount travels as a Long in cents, never a floating-point number."),
             ]),
        // W7 (every strict run): paused, but kept no reads, named no reconciliation and never said when to resume.
        Rule(asks: #"(?i)\b(spike[sd]?|surge[sd]?|jump(s|ed)?|pil(e|es|ing) up|backlog)\b"#,
             topic: money, points: [
                Point(covered: #"(?i)\b(reads?|history|status( checks?)?|balances?)\b.{0,30}\b(keep|keeps|still|stay|stays)\b.{0,10}\b(working|work|on|up|available)\b|\bkeep(ing)? (reads|history|status)\b"#,
                      sentence: "During the pause, balance, history and status checks keep working."),
                Point(covered: #"(?i)\breconcil"#,
                      sentence: "The backend owner and I reconcile each pending transfer against the ledger."),
                Point(covered: #"(?i)\bresum(e|es|ed|ing)\b|\bturn\b.{0,20}\bback on\b|\bre-?enabl|\breopen"#,
                      sentence: "We resume new submissions once the pending queue is back to normal and the ledger matches."),
             ]),
        // P2 (every strict run): "how did you know it worked" got the metric but not what it can't prove.
        Rule(asks: #"(?i)\bhow (did|do|would) you know\b|\bknow (that )?(the|it|your) (change|fix)?\s*worked\b"#,
             topic: nil, points: [
                // Verification run: the card deferred "how did you know" to a next card that never came, and a
                // lone "Its limit is…" pointed at nothing; without a source, both come in one sentence.
                Point(covered: #"(?i)\b(after (the )?(release|launch)|after (it|we) (shipped|released|launched)|in production|crash (rate|reports?)|Bugly|dashboards?|tickets?|user feedback|metrics?)\b"#,
                      sentence: "After release, I checked it with our tests and the logs from real users; they only cover the cases we saw, so they can't prove there's no problem on devices or networks we didn't test."),
                Point(covered: #"(?i)\b(can't|cannot|doesn't|does not|didn't|won't|couldn't)\s+(prove|tell|show|cover|catch|rule out)\b|\bonly (counts?|covers?|shows?|measures?|catches|tells?)\b|\blimit(s|ation)?\b"#,
                      sentence: "Its limit is that it only covers the cases we saw, so it can't prove there's no problem on devices or networks we didn't test."),
             ]),
    ]

    /// At most this many sentences are added to one card, so it stays readable.
    static let maxAdded = 3

    /// Sentences to add to `say` for the points its question needs that neither `say` nor `said` makes.
    /// The question is the one the card says it answers (`heard`); the interviewer's latest turn only when
    /// `heard` matches no rule. 1339: asked W6, DeepSeek answered W5 again, and the chat point from the
    /// interviewer's turn landed on an account-switch answer.
    static func missing(question: String, heard: String = "", goal: String?, say: String, said: [String], last: String? = nil) -> [String] {
        let asked = rules.contains(where: { matches(heard, $0.asks) }) ? heard : question
        var made = ([say] + said).joined(separator: "\n")
        // The last interviewer line, not the whole turn: run 2327's P1 came before any problem was recorded, and
        // the agenda merged into its turn ("…design a fictional mobile wallet") still made it a money question.
        let topic = (last ?? question) + " " + heard + " " + (goal ?? "")
        var out: [String] = []
        for rule in rules where matches(asked, rule.asks) && applies(rule, topic: topic, goal: goal) {
            let open = rule.points.filter { !matches(made, $0.covered) }
            let clauses = open.filter(\.clause).map(\.sentence)
            if !clauses.isEmpty {
                let list = clauses.count == 1 ? clauses[0] : clauses.dropLast().joined(separator: ", ") + " and " + clauses.last!
                out.append("A few quick checks: " + list + "?")
            }
            // An added sentence counts as said, so a later point it already makes is not added again.
            for point in open where !point.clause && !matches(made, point.covered) && !out.contains(point.sentence) {
                out.append(point.sentence); made += "\n" + point.sentence
            }
        }
        return Array(out.prefix(maxAdded))
    }

    /// The card says it answers one graded question type and the interviewer just asked a different one
    /// (1339: asked the chat change, DeepSeek answered the account switch again and stayed there 96 s).
    static func answersAnotherQuestion(question: String, heard: String, goal: String?) -> Bool {
        let topic = question + " " + heard + " " + (goal ?? "")
        let kinds = { (text: String) in Set(rules.indices.filter { matches(text, rules[$0].asks) && applies(rules[$0], topic: topic, goal: goal) }) }
        let fromHeard = kinds(heard), fromQuestion = kinds(question)
        return !fromHeard.isEmpty && !fromQuestion.isEmpty && fromHeard.isDisjoint(with: fromQuestion)
    }

    /// A topic rule belongs to a design exercise, never to a question about the candidate's own work: wallet run
    /// 2144 merged the opener ("an agent-first app… then design a fictional mobile wallet") into P1's turn, and
    /// the project intro got three chat-payment sentences.
    private static func applies(_ rule: Rule, topic: String, goal: String?) -> Bool {
        guard let pattern = rule.topic else { return true }
        let goal = goal ?? ""
        if matches(goal, CoachCardPrompt.pastGoal), !matches(goal, CoachCardPrompt.designGoal) { return false }
        return matches(topic, pattern)
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
}
