import Foundation
import Testing
@testable import Cicada

struct AnswerPlanTests {
    @Test func openEndedQuestionsStartAPlan() {
        let cases: [(String, String, Bool)] = [
            ("How would you design an offline-first chat app on Android?", "them", true),
            ("Walk me through your offline sync design.", "them", true),
            ("How would you build a feed that scales to a million users?", "them", true),
            ("请你设计一个离线优先的聊天应用？", "them", true),
            ("这个图片加载你会怎么设计", "them", true),
            ("讲讲你的架构方案吧？", "them", true),
            // Questions that one answer covers, and statements.
            ("How would you collect StateFlow in Compose?", "them", false),
            ("What is Binder?", "them", false),
            ("The team reviewed the design.", "them", false),
            ("How would you design this?", "me", false),
            // The problem set as a statement.
            ("So we need to design an app that has 2 screens.", "them", true),
            ("Let's design a news feed for Android.", "them", true),
            ("我们来设计一个新闻流应用。", "them", true),
            ("We designed it last year.", "them", false),
        ]
        for (text, speaker, expected) in cases { #expect(AnswerPlan.starts(text, speaker: speaker) == expected, "\(text)") }
    }

    @Test func parsesMarksNumberingAndHints() throws {
        let reply = """
        **Q:** Offline-first chat app
        - [x] Clarify scope
        2. [✓] Architecture: Compose, ViewModel
        * [>] Local data with Room | message status
        - [>] Sync with WorkManager | ignored second current
        - [ ] Real-time updates
        - Stray fact without a mark
        > Say each message has a client UUID.
        > Then cover the outbox.
        > A third hint is dropped.
        """
        let plan = try #require(AnswerPlan.parse(reply, contextID: "c", question: "Design a chat app?", at: 5))
        #expect(plan.goal == "Offline-first chat app")
        #expect(plan.steps.map(\.status) == [.done, .done, .current, .todo, .todo])
        #expect(plan.steps[2].text == "Local data with Room" && plan.steps[2].missing == "message status")
        #expect(plan.steps[3].missing.isEmpty)
        #expect(plan.next == ["Say each message has a client UUID.", "Then cover the outbox."])
        // The text sent back to the model reads the same way.
        #expect(AnswerPlan.parse(plan.text, contextID: "c", question: "Design a chat app?", at: 5) == plan)
    }

    @Test func aBrokenReplyHasNoPlanAndAMissingCurrentStepIsChosen() throws {
        #expect(AnswerPlan.parse("Q: Design\n- I would start with Room.", contextID: "c", question: "q", at: 0) == nil)
        let plan = try #require(AnswerPlan.parse("- [x] Scope\n- [ ] Data\n- [ ] Sync", contextID: "c", question: "Design it?", at: 0))
        #expect(plan.goal == "Design it?")
        #expect(plan.steps.map(\.status) == [.done, .current, .todo])
    }

    private func line(_ id: String, _ t: Double, _ speaker: String, _ text: String) -> TranscriptLine {
        TranscriptLine(id: id, t: t, speaker: speaker, src: text, srcLang: "en", dstLang: "zh-CN")
    }
    private let reply = """
    Q: Chat app
    - [>] Message types
    - [ ] Data
    - [ ] Sync
    > Ask about scale.
    > Then the data layer.
    """

    @Test @MainActor func ourAnswerMovesThePlanAndThePlanComesFirst() throws {
        let c = Copilot()
        let ask = line("1", 0, "them", "How would you design an offline-first chat app?")
        c.observe(lines: [ask], notes: MeetingNotes(), now: 0, enabled: true, quietFor: 3)
        #expect(c.plan?.steps.isEmpty == true)
        // The first plan outranks the answer card: its "say now" is what the user waits for.
        let first = try #require(c.next(now: 0))
        #expect(first.kind == .plan && first.text == "No plan yet.")
        c.completedPlan(first, text: reply)
        #expect(c.plan?.steps.count == 3)
        #expect(c.plan?.next.first == "Ask about scale.")
        let response = try #require(c.next(now: 0))
        #expect(response.kind == .response)
        c.completed(response, reply: .init(understood: "q", points: ["I would start with scope."]))

        // Our side talks: the update waits until they pause.
        let me = line("2", 10, "me", "It's one-to-one and group chat for a million users.")
        c.observe(lines: [ask, me], notes: MeetingNotes(), now: 10, enabled: true, quietFor: 0)
        #expect(c.next(now: 20) == nil)
        c.observe(lines: [ask, me], notes: MeetingNotes(), now: 12, enabled: true, quietFor: 2)
        #expect(c.next(now: 13.9) == nil)
        let update = try #require(c.next(now: 14))
        #expect(update.kind == .plan && update.text.contains("[>] Message types"))
        // A reply that does not parse keeps the plan.
        c.completedPlan(update, text: "Sorry, I can't.")
        #expect(c.plan?.steps.count == 3)
    }

    @Test @MainActor func aDeepDiveKeepsThePlanAndATopicChangeEndsIt() throws {
        let c = Copilot()
        let ask = line("1", 0, "them", "How would you design an offline-first chat app?")
        c.observe(lines: [ask], notes: MeetingNotes(), now: 0, enabled: true, quietFor: 3)
        c.completedPlan(try #require(c.next(now: 0)), text: reply)
        _ = c.next(now: 0).map { c.completed($0, reply: .init(understood: "q", points: ["a"])) }
        let me = line("m", 20, "me", "It is one-to-one chat for a million users.")
        c.observe(lines: [ask, me], notes: MeetingNotes(), now: 20, enabled: true, quietFor: 3)
        c.completedPlan(try #require(c.next(now: 22)), text: "- Done: 1\n- Now: 2")
        let deep = line("2", 30, "them", "How would you design the conflict resolution?")
        c.observe(lines: [ask, me, deep], notes: MeetingNotes(), now: 30, enabled: true, quietFor: 3)
        #expect(c.plan?.contextID == "1")
        let shift = line("3", 60, "them", "OK, let's move on to your last project.")
        c.observe(lines: [ask, me, deep, shift], notes: MeetingNotes(), now: 60, enabled: true, quietFor: 3)
        #expect(c.plan == nil)
        // The interviewer closing the interview ends it too.
        c.startPlan(question: "Design a feed?", contextID: "4", at: 70, now: 70)
        let wrap = line("5", 80, "them", "All right. Let's wrap up. Thank you for your time.")
        c.observe(lines: [ask, me, deep, shift, wrap], notes: MeetingNotes(), now: 80, enabled: true, quietFor: 3)
        #expect(c.plan == nil)
        // Their feedback quotes the design without asking for one.
        let feedback = line("6", 90, "them", "Your first diagram was a high-level design. How do they play together? I liked it.")
        c.observe(lines: [ask, me, deep, shift, wrap, feedback], notes: MeetingNotes(), now: 90, enabled: true, quietFor: 3)
        #expect(c.plan == nil)
    }

    @Test @MainActor func aProblemSetInPiecesKeepsThePlanRunning() throws {
        let c = Copilot()
        let ask = line("1", 0, "them", "How would you design a news feed app?")
        c.observe(lines: [ask], notes: MeetingNotes(), now: 0, enabled: true, quietFor: 3)
        // Captions still moving: the first plan does not wait for quiet.
        c.observe(lines: [ask], notes: MeetingNotes(), now: 0, enabled: true, quietFor: 0)
        let first = try #require(c.next(now: 0))
        #expect(first.kind == .plan)
        // More of the problem while the plan is written: it is not started over.
        let more = line("2", 4, "them", "Can you also support offline reading?")
        c.observe(lines: [ask, more], notes: MeetingNotes(), now: 4, enabled: true, quietFor: 3)
        #expect(c.active?.id == first.id)
        #expect(c.plan?.question.contains("offline") == true)
        c.completedPlan(first, text: reply)
        #expect(c.plan?.steps.count == 3)
        // The answer card follows, then the rest of the problem as an update.
        let response = try #require(c.next(now: 20))
        #expect(response.kind == .response)
        c.completed(response, reply: .init(understood: "q"))
        let update = try #require(c.next(now: 20))
        #expect(update.kind == .plan && update.text != "No plan yet.")
    }

    @Test func sidesFromTheWords() {
        let cases: [(String, String?)] = [
            ("How would you design an offline-first news feed?", "them"),
            ("So we need you to design a news feed app with two screens.", "them"),
            ("I'd like to hear more about how caching works here.", "them"),
            ("You can assume ten million daily users.", "them"),
            ("I'd store the posts in Room and page with a cursor.", "me"),
            ("So my approach would be to start with the requirements.", "me"),
            ("We could use WorkManager to sync when the network comes back.", "me"),
            ("Can I assume the feed is read-heavy?", "me"),
            ("So, I'm imagining this should be like an infinite scroll list, right?", "me"),
            ("I'm thinking about how you would cache it?", "them"),
            ("Do we need to support offline mode?", "me"),
            ("我会先把需求和范围确认清楚。", "me"),
            ("你会怎么设计这个缓存？", "them"),
            ("Before I jump into the design, can I ask some clarifying questions?", "me"),
            ("Yeah, sure, that does it.", "them"),
            ("Yep, this sounds really amazing, especially the social part.", "them"),
            ("Let's assume we can have up to 100 million daily active users.", "them"),
            ("Maybe we don't need it. Let's leave it out of scope.", "them"),
            ("So I would love to do today a classic news feed problem.", "them"),
            ("Um, you know, different kinds of content here.", nil),
            ("and then the list scrolls.", nil),
        ]
        for (text, side) in cases { #expect(CopilotRules.side(of: text) == side, "\(text)") }
    }

    @Test func theVoiceThatAnswersIsOurs() {
        var sides = VoiceSides()
        // The interviewer (voice 0) sets the problem and settles questions; the candidate (voice 1)
        // answers and asks clarifying questions, one of which reads like the interviewer's.
        for text in ["So we need you to design a news feed app.", "Let's assume 100 million users.",
                     "Let's leave it out of scope.", "Yeah, sure, that does it."] { sides.count(0, text: text) }
        #expect(sides.ours == nil)
        for text in ["I'd page with a cursor.", "We could use Room for the cache.",
                     "What scale of user base are we looking at?", "Can I assume it is read-heavy?"] { sides.count(1, text: text) }
        #expect(sides.ours == 1)
        #expect(sides.side(of: 1) == "me" && sides.side(of: 0) == "them" && sides.side(of: 2) == "them")
        // One voice alone may be the other side only: not decided.
        var alone = VoiceSides()
        for text in ["I'd page with a cursor.", "We could use Room.", "I'd cache it."] { alone.count(0, text: text) }
        #expect(alone.ours == nil)
    }

    @Test @MainActor func turningTheAssistantOffOrEndingTheMeetingDropsThePlan() {
        let c = Copilot()
        c.startPlan(question: "Design a feed?", contextID: "x", at: 0, now: 0)
        #expect(c.hasPending)
        c.observe(lines: [], notes: MeetingNotes(), now: 1, enabled: false, quietFor: 3)
        #expect(c.plan == nil && !c.hasPending)
        c.startPlan(question: "Design a feed?", contextID: "x", at: 0, now: 0)
        c.endMeeting()
        #expect(c.plan == nil && !c.hasPending)
    }
}

extension AnswerPlanTests {
    @Test @MainActor func anUpdateKeepsTheGoalThatWasAsked() throws {
        let c = Copilot()
        c.startPlan(question: "Design a chat app?", contextID: "x", at: 0, now: 0)
        c.completedPlan(try #require(c.next(now: 0)), text: "Q: Chat app\n- [>] Message types\n- [ ] Data")
        c.observe(lines: [line("m", 5, "me", "It is one-to-one chat.")], notes: MeetingNotes(), now: 5, enabled: true, quietFor: 3)
        let update = try #require(c.next(now: 7))
        // Our answer reaches the model after the question, not in the background before it.
        let prompt = c.prompt(update, base: .init(system: "", user: "<background>\n</background>"))
        #expect(prompt.user.contains("<since_question>\nMe: It is one-to-one chat.\n</since_question>"))
        #expect(update.text == "1 [>] Message types\n2 [ ] Data")
        c.completedPlan(update, text: "Q: Local storage\n- Done: 1\n- Now: 2 | ordering\n> Use Room.\n> Then sync.")
        #expect(c.plan?.goal == "Chat app")
        #expect(c.plan?.steps.map(\.status) == [.done, .current])
        #expect(c.plan?.steps[1].missing == "ordering")
        #expect(c.plan?.next == ["Use Room.", "Then sync."])
    }

    @Test func anUpdateAnswersWithNumbers() throws {
        let plan = try #require(AnswerPlan.parse("Q: Chat\n- [>] Scope\n- [ ] Data\n- [ ] Sync", contextID: "c", question: "q", at: 0))
        // Covered steps stay covered; their deep dive jumps ahead.
        let jumped = try #require(plan.applying("**Q:** Chat\n- **Done:** 1\n- Now: 3. | retries"))
        #expect(jumped.steps.map(\.status) == [.done, .todo, .current])
        let back = try #require(jumped.applying("- Done: none\n- Now: 2"))
        #expect(back.steps.map(\.status) == [.done, .current, .todo])
        // Something no step covers goes in after what we have covered.
        let added = try #require(back.applying("- Done: 1\n- Now: Encryption at rest | key storage"))
        #expect(added.steps.map(\.text) == ["Scope", "Encryption at rest", "Data", "Sync"])
        #expect(added.steps[1].status == .current && added.steps[1].missing == "key storage")
        // A step named instead of numbered is that step, not a second copy.
        let named = try #require(added.applying("- Done: 1\n- Now: sync"))
        #expect(named.steps.count == 4 && named.steps[3].status == .current)
        let finished = try #require(added.applying("- Done: 1, 2, 3, 4\n- Now: done"))
        #expect(finished.finished)
        #expect(plan.applying("Q: Chat\n- [x] Scope\n- [>] Data") == nil)
    }
}

extension AnswerPlanTests {
    /// From a recorded mock interview: "ready for the system design round?" came first, the problem after.
    @Test @MainActor func theProblemReplacesAPlanNothingOfWhichIsCovered() throws {
        let c = Copilot()
        let ready = line("1", 8, "them", "Are you ready to start our mobile system design mock interview?")
        c.observe(lines: [ready], notes: MeetingNotes(), now: 12, enabled: true, quietFor: 3)
        _ = c.next(now: 12).map { c.completed($0, reply: .init(understood: "q", points: ["Yes."])) }
        c.completedPlan(try #require(c.next(now: 12)), text: reply)
        let yes = line("2", 13, "me", "Yes.")
        let problem = line("3", 30, "them", "So we need to design an app that has 2 screens.")
        c.observe(lines: [ready, yes, problem], notes: MeetingNotes(), now: 30, enabled: true, quietFor: 3)
        #expect(c.plan?.contextID == "3" && c.plan?.steps.isEmpty == true)
    }

    /// A line every second or two must neither push the update back nor cut the running one off.
    @Test @MainActor func aSteadyConversationStillMovesThePlan() throws {
        let c = Copilot()
        c.startPlan(question: "Design a feed?", contextID: "x", at: 0, now: 0)
        c.completedPlan(try #require(c.next(now: 0)), text: reply)
        var lines: [TranscriptLine] = []
        for i in 1...6 {
            lines.append(line("m\(i)", Double(i), "me", "Sentence \(i) of our answer."))
            c.observe(lines: lines, notes: MeetingNotes(), now: Double(i), enabled: true, quietFor: 3)
        }
        let update = try #require(c.next(now: 6))
        #expect(update.kind == .plan)
        // More talk while it is being written leaves it running, and one more update follows it.
        lines.append(line("m7", 7, "me", "Sentence 7."))
        c.observe(lines: lines, notes: MeetingNotes(), now: 7, enabled: true, quietFor: 3)
        #expect(c.active?.id == update.id)
        c.completedPlan(update, text: "- Done: 1\n- Now: 2")
        #expect(c.plan?.steps[1].status == .current)
        #expect(c.hasPending)
    }
}

/// The user reads the plan out like a teleprompter (2026-11-07): the mic hears the "say now" line.
extension AnswerPlanTests {
    @Test func readingTheLineOutCoversIt() {
        let hint = "I'd keep Room as the single source of truth, so the screen works offline."
        #expect(AnswerPlan.covers("so I would keep room as the single source of truth so the screen works offline", hint: hint))
        // Rephrased and partly misheard still counts; a different point does not.
        #expect(AnswerPlan.covers("we keep Room as the source of truth", hint: hint))
        #expect(!AnswerPlan.covers("For the network layer I'd use Retrofit.", hint: hint))
        // Too short a hint to tell.
        #expect(!AnswerPlan.covers("Yes, sure.", hint: "Yes, sure."))
    }

    @Test @MainActor func readingTheLineMovesTheNextUp() throws {
        let c = Copilot()
        c.startPlan(question: "Design a chat app?", contextID: "x", at: 0, now: 0)
        c.completedPlan(try #require(c.next(now: 0)), text:
            "Q: Chat app\n- [>] Local storage\n- [ ] Sync\n> I'd keep Room as the single source of truth, so the screen works offline.\n> Then the outbox for sending.")
        // Half of it so far: nothing moves.
        var lines = [line("m1", 10, "me", "So I'd keep Room")]
        c.observe(lines: lines, notes: MeetingNotes(), now: 10, enabled: true, quietFor: 0.5)
        #expect(c.plan?.next.first?.hasPrefix("I'd keep Room") == true)
        lines.append(line("m2", 12, "me", "as the single source of truth, so the screen works offline."))
        c.observe(lines: lines, notes: MeetingNotes(), now: 12, enabled: true, quietFor: 0.5)
        let plan = try #require(c.plan)
        #expect(plan.next == ["Then the outbox for sending."])
        #expect(plan.earlier.first?.hasPrefix("I'd keep Room") == true)
        // And the words for the line that moved up are asked for.
        #expect(c.next(now: 20)?.kind == .plan)
    }

    /// The other side's words are not our reading.
    @Test @MainActor func theirWordsDoNotReadTheLine() throws {
        let c = Copilot()
        c.startPlan(question: "Design a chat app?", contextID: "x", at: 0, now: 0)
        c.completedPlan(try #require(c.next(now: 0)), text:
            "Q: Chat app\n- [>] Local storage\n- [ ] Sync\n> I'd keep Room as the single source of truth.\n> Then sync.")
        c.observe(lines: [line("t1", 10, "them", "Would you keep Room as the single source of truth?")],
                  notes: MeetingNotes(), now: 10, enabled: true, quietFor: 3)
        #expect(c.plan?.next.count == 2)
    }
}

/// From the Facebook-feed mock interview heard only through the Mac (2026-11-07).
extension AnswerPlanTests {
    private var requirementsReply: String {
        "Q: News feed app\n- [>] Requirements and scope\n- [ ] API contract\n- [ ] Client architecture\n> Ask about scale.\n> Then the API."
    }

    /// Before the voices settle, the interviewer setting the problem read as our answer and ticked
    /// the requirements off at 45 s: guessed lines neither move the plan nor ask for an update.
    @Test @MainActor func linesWhoseSideIsAGuessDoNotMoveThePlan() throws {
        let c = Copilot()
        c.startPlan(question: "Design a news feed app?", contextID: "x", at: 0, now: 0)
        c.completedPlan(try #require(c.next(now: 0)), text: requirementsReply)
        let guess = line("g", 30, "me", "So for example, we can have a text and an image, and like and comment on a post.")
        let them = line("t", 35, "them", "Yep, this sounds really amazing.")
        c.observe(lines: [guess, them], notes: MeetingNotes(), now: 40, enabled: true, quietFor: 5, unsure: ["g"])
        #expect(c.next(now: 60) == nil)
        // A sure line of ours does, and the model sees the guess for what it is.
        let ours = line("m", 50, "me", "That covers the requirements: the feed shows posts with text, images and video, and the detail adds comments.")
        c.observe(lines: [guess, them, ours], notes: MeetingNotes(), now: 55, enabled: true, quietFor: 3, unsure: ["g"])
        let update = try #require(c.next(now: 60))
        let prompt = c.prompt(update, base: .init(system: "", user: ""))
        #expect(prompt.user.contains("Unsure: So for example") && prompt.user.contains("Me: That covers"))
        #expect(prompt.user.contains("no Q: line") && prompt.user.contains("never count Unsure: lines"))
    }

    /// Our side on the requirements step: the next clarifying question comes from the list, without
    /// the model, and never one about what has already come up.
    @Test @MainActor func clarifyingQuestionsComeFromTheList() throws {
        let c = Copilot()
        c.startPlan(question: "So we need to design an app with a feed of text, image or video posts.", contextID: "x", at: 0, now: 0)
        c.completedPlan(try #require(c.next(now: 0)), text: requirementsReply)
        let ask = line("m", 20, "me", "And what scale of the user base are we looking at?")
        let answer = line("t", 25, "them", "Let's assume 100 million daily active users.")
        c.observe(lines: [ask, answer], notes: MeetingNotes(), now: 26, enabled: true, quietFor: 0)
        #expect(c.next(now: 60) == nil)
        let next = try #require(c.plan?.next)
        #expect(next.count == 2 && next[0].contains("infinite list"))
        #expect(!next.joined().contains("scale") && !next.joined().contains("content types"))
        #expect(c.plan?.steps[0].status == .current)
        // Stating a requirement keeps the step; moving on hands it to the model.
        let plan = try #require(c.plan)
        #expect(plan.clarifying(talk: ["Me: We also want to support user interactions."]) != nil)
        #expect(plan.clarifying(talk: ["Me: I think that covers the high level functional requirements."]) == nil)
        #expect(plan.clarifying(talk: ["Me: For the API I'd page the feed with a cursor."]) == nil)
    }

    @Test @MainActor func ourOwnReplyDropsTheWaitingAnswer() throws {
        let c = Copilot()
        let q = line("1", 0, "them", "So, do you see the mock up on the screen")
        c.observe(lines: [q], notes: MeetingNotes(), now: 0, enabled: true, quietFor: 0)
        #expect(c.hasPending)
        let yes = line("2", 2, "me", "Yes, I do see the news feed and the post screen.")
        c.observe(lines: [q, yes], notes: MeetingNotes(), now: 2, enabled: true, quietFor: 0)
        #expect(!c.hasPending)
    }
}

extension AnswerPlanTests {
    /// Each update replaced "say now": what it said before stays on the card, newest first.
    @Test @MainActor func earlierHintsStayOnThePlan() throws {
        let c = Copilot()
        c.startPlan(question: "Design a chat app?", contextID: "x", at: 0, now: 0)
        c.completedPlan(try #require(c.next(now: 0)), text: "Q: Chat app\n- [>] Message types\n- [ ] Data\n> First.\n> Then.")
        #expect(c.plan?.earlier.isEmpty == true)
        c.observe(lines: [line("m", 5, "me", "It is one-to-one chat.")], notes: MeetingNotes(), now: 5, enabled: true, quietFor: 3)
        c.completedPlan(try #require(c.next(now: 7)), text: "- Done: 1\n- Now: 2\n> Second.\n> Then.")
        c.observe(lines: [line("m", 5, "me", "It is one-to-one chat."), line("n", 20, "me", "Messages are text only.")],
                  notes: MeetingNotes(), now: 20, enabled: true, quietFor: 3)
        // The same hint again adds nothing.
        c.completedPlan(try #require(c.next(now: 22)), text: "- Done: 1\n- Now: 2\n> Second.\n> Then.")
        #expect(c.plan?.earlier == ["First."])
        let plan = try #require(c.plan)
        let third = try #require(plan.applying("- Done: 1\n- Now: 2\n> Third.")).following(plan)
        #expect(third.earlier == ["Second.", "First."])
    }
}
