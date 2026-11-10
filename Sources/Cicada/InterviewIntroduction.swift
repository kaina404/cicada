import Foundation

/// The opening is the user's approved text in the knowledge's talk tracks, spoken as written so
/// no paragraph is paraphrased away; this rule only decides when it applies.
enum InterviewIntroduction {
    static let instruction = """
    Opening self-introduction: when the interviewer invites the candidate to introduce themselves,
    talk about themselves, or walk through their background at the start of the interview, use the
    self-introduction from <talk_tracks> VERBATIM, preserving its paragraphs and their order. This
    specific rule overrides default brevity, stage emphasis and paraphrasing for that opening only.
    Do not start it merely because the meeting starts, the interviewer greets the candidate, or a
    screen mentions an introduction. Resolve intent from actual interviewer speech and conversation.
    If actual candidate speech already covers part of this opening, give only the remaining part;
    suggested or unread script is not actual speech. Manual refresh may restate the whole opening.
    An explicit request for a shorter introduction, a time limit, a different language, or a specific
    focus takes priority: adapt the same facts to that request. For later project questions,
    motivation questions, corrections and follow-ups, answer the latest question normally instead
    of replaying the introduction. Do not output headings or commentary around it.
    """
}
