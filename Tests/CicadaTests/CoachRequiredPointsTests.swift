import Testing
@testable import Cicada

/// Graded points added after the card is written; fixtures are cards from the strict wallet run 1139.
struct CoachRequiredPointsTests {
    let goal = "Design a mobile wallet from scratch: the core mobile experience, the system behind it, and how it handles failures"

    @Test func chatPaymentGetsTheRepeatedToolCall() {
        let q = "How does that flow change when the entry point is a chat message naming one of two Alexes with no reliable amount, and the chat stream disconnects right after the user confirms?"
        let say = "The chat is only the entry point. The assistant can suggest a transfer, but it can't authorize one. The user types the amount on that confirm screen. The server binds the authorization to the payer, recipient and amount."
        let added = CoachRequiredPoints.missing(question: q, goal: goal, say: say, said: [])
        #expect(added.count == 1)
        #expect(added[0].contains("same intent and client ID"))
    }

    @Test func chatPaymentGetsTheAmountAndTheServerBinding() {
        // 1413 W6: right question, but no amount asked and no server-side binding.
        let q = "The pilot also starts from a group chat: pay Alex for dinner, two contacts called Alex, no reliable amount. Draw the new entry flow as a flowchart."
        let say = "The app shows both Alexes and the user taps the right one. The payment then goes through the same native confirm screen, with the recipient, the amount and the client ID bound to that choice."
        let added = CoachRequiredPoints.missing(question: q, goal: goal, say: say, said: [])
        #expect(added.count == 3)
        #expect(added[0].contains("types the amount"))
        #expect(added[1].contains("binds that authorization"))
    }

    @Test func chatPointsInOtherWordsAreNotAddedAgain() {
        // 1516 W6: both points were made, and the same two were added again in fixed words.
        let q = "How does your flow change when the pilot starts from a group chat message, with two contacts named Alex and no reliable amount? Draw the new entry flow as a flowchart."
        let say = "The chat only starts the payment. It never authorizes it. The app can't tell which Alex or which amount, so it asks the user to pick both on a native confirmation screen. The server then binds that approval to payer, recipient, amount and expiry."
        #expect(CoachRequiredPoints.missing(question: q, goal: goal, say: say, said: []).count == 1)
    }

    @Test func aCardAnsweringAnotherGradedQuestionIsCaught() {
        let chat = "Starting from a chat with two Alexes and no amount, what happens after the user confirms and the chat stream disconnects?"
        #expect(CoachRequiredPoints.answersAnotherQuestion(question: chat, heard: "request in flight, user switches to account C, A's old response arrives", goal: goal))
        #expect(!CoachRequiredPoints.answersAnotherQuestion(question: chat, heard: "chat with two Alexes, stream drops after confirm", goal: goal))
        // A HEARD or question that names no graded type is not judged.
        #expect(!CoachRequiredPoints.answersAnotherQuestion(question: chat, heard: "the new entry flow", goal: goal))
        #expect(!CoachRequiredPoints.answersAnotherQuestion(question: "Walk me through your project.", heard: "user switches to account C", goal: goal))
    }

    @Test func releaseSpikeGetsReadsReconciliationAndResume() {
        let q = "What's in the first version, who signs off, and if transfers awaiting confirmation suddenly spike during the rollout, what do you do in the next half hour?"
        let say = "For the first version, I'd ship balance, internal transfer and history. If pending transfers spike, I'd pause new submissions first."
        let added = CoachRequiredPoints.missing(question: q, goal: goal, say: say, said: [])
        #expect(added.count == 3)
        #expect(added.last!.hasPrefix("We resume"))
    }

    @Test func concurrencyGetsBothPoints() {
        let q = "On two phones A approves two independent 80 dollar transfers to B at almost the same time. What happens to each one?"
        let say = "The ledger handles them one at a time. The second one finds only 20 dollars left, so it fails and no money moves."
        #expect(CoachRequiredPoints.missing(question: q, goal: goal, say: say, said: []).count == 2)
        let covered = "These are two intents, each with its own client ID. The server uses a row lock on A's balance."
        #expect(CoachRequiredPoints.missing(question: q, goal: goal, say: covered, said: []).isEmpty)
    }

    @Test func lostResponseAndAccountSwitch() {
        let lost = "The server committed and Android killed the process before any response arrived. What does the app do?"
        #expect(CoachRequiredPoints.missing(question: lost, goal: goal, say: "It asks the server by account and client ID.", said: []).first?.contains("idempotency window") == true)
        let swap = "While A's request is in flight the user switches to account C, and then A's old response arrives."
        #expect(CoachRequiredPoints.missing(question: swap, goal: goal, say: "I drop it if its session is no longer current.", said: []).first?.contains("signs in again") == true)
    }

    @Test func lostResponseGetsTheOriginalTransferBack() {
        // 1233's W3: the window was covered, the repeat's answer and the single ledger entry were not.
        let q = "The server commits and the response is lost before Android kills the process. What does the repository do?"
        let say = "It asks the server for that same client transfer ID. I'd resend that same client ID only while the server's idempotency window still covers it."
        let added = CoachRequiredPoints.missing(question: q, goal: goal, say: say, said: [])
        #expect(added == ["The server answers a repeat of that ID with the original transfer's status, so the ledger still has only one transfer."])
    }

    @Test func clarifyingAWalletAsksTheMissingChecksInOneQuestion() {
        let q = "Design a mobile wallet from scratch. Start by clarifying the requirements. Which user path would you define as the MVP?"
        let say = "Is the balance held by us, or does money move on a bank or card rail? Which currencies do we support? What should work offline?"
        #expect(CoachRequiredPoints.missing(question: q, goal: goal, say: say, said: [])
                == ["A few quick checks: is the server's ledger the only source of truth for balances?",
                    "For the MVP, I'd pick one path: send money to a contact, with balance and history."])
        #expect(CoachRequiredPoints.missing(question: q, goal: goal, say: say + " Is the server ledger the authority? For the MVP, I'd pick sending money to a friend.", said: []).isEmpty)
        // 1413: the MVP card named "the ledger" in passing, asked nothing about the rail, currency or offline.
        let mvp = "For the MVP, I'd pick one path: send money to a contact. That path covers the hard parts: the ledger, the confirm step and a lost response."
        #expect(CoachRequiredPoints.missing(question: q, heard: "which user path is the MVP", goal: goal, say: mvp, said: [])
                == ["A few quick checks: is the balance held by us, or does money move on a bank or card rail, which currencies do we support, what should work offline and is the server's ledger the only source of truth for balances?"])
    }

    @Test func walletDiagramNamesTheAuthority() {
        let q = "A has 100 dollars and B has zero. Draw the client, the server and local storage as a flowchart, and tell me what each part owns."
        let say = "The ViewModel holds the screen state. The repository is the only place that talks to the server. The local database keeps the cached balance."
        #expect(CoachRequiredPoints.missing(question: q, goal: goal, say: say, said: []).first?.contains("source of truth") == true)
        #expect(CoachRequiredPoints.missing(question: q, goal: goal, say: say + " The server's ledger is the authority.", said: []).isEmpty)
    }

    @Test func aCardStillAnsweringThePreviousQuestionGetsThatQuestionsPoints() {
        // 1339: the interviewer asked the chat plan change, the card's HEARD was still the account switch.
        let chat = "Starting from a chat with two Alexes and no amount, what happens after the user confirms and the chat stream disconnects?"
        let heard = "request in flight, user switches to account C, A's old response arrives"
        let say = "The old response can land on C's screen. I'd tag every request with the account and a session generation."
        let added = CoachRequiredPoints.missing(question: chat, heard: heard, goal: goal, say: say, said: [])
        #expect(added.count == 1)
        #expect(added[0].contains("signs in again"))
        // A HEARD that names no rule leaves the interviewer's turn in charge.
        #expect(CoachRequiredPoints.missing(question: chat, heard: "the new entry flow", goal: goal, say: say, said: []).contains { $0.contains("same intent") })
    }

    @Test func evidenceGetsItsLimitWithoutAWallet() {
        let q = "What other options did you have, and after release how did you know the change worked?"
        #expect(CoachRequiredPoints.missing(question: q, goal: "KKday product page", say: "Crash reports stayed flat.", said: [])
                == ["Its limit is that it only covers the cases we saw, so it can't prove there's no problem on devices or networks we didn't test."])
        #expect(CoachRequiredPoints.missing(question: q, goal: nil, say: "Crash reports stayed flat, but they only count reported crashes.", said: []).isEmpty)
        // The verification run's card named two alternatives and no source: one sentence brings both.
        let alternativesOnly = "I had two other options. One was a mutex around the StateFlow update. I didn't pick it because events could still run in any order."
        let added = CoachRequiredPoints.missing(question: q, goal: nil, say: alternativesOnly, said: [])
        #expect(added.count == 1)
        #expect(added[0].hasPrefix("After release"))
    }

    @Test func pointAlreadySaidIsNotRepeated() {
        let q = "If transfers awaiting confirmation spike during the rollout, what do you do?"
        let said = ["Reads and status checks keep working.", "I reconcile with the backend owner.", "We resume once the queue is normal."]
        #expect(CoachRequiredPoints.missing(question: q, goal: goal, say: "I'd pause new submissions.", said: said).isEmpty)
    }

    @Test func noMoneyTopicNoTransferSentences() {
        // A notes app's concurrency or a trip planner's assistant must not get wallet sentences.
        #expect(CoachRequiredPoints.missing(question: "Two users edit the same note at the same time. What happens?", goal: "Design a notes app", say: "Last write wins.", said: []).isEmpty)
        #expect(CoachRequiredPoints.missing(question: "How did the assistant stream cards to the app?", goal: "KKday AI trip planner", say: "Over SSE.", said: []).isEmpty)
    }
}

/// Wallet run 2144: the opener ("an agent-first app… then design a fictional mobile wallet") was merged into P1's
/// turn, and the project intro got three chat-payment sentences.
@Test func aProjectQuestionAfterTheWalletOpenerGetsNoWalletPoints() {
    let turn = "Hi, I'm the founder of ActAI. We're building an agent-first mobile communication app. Today we'll start with a project you really owned, then design a fictional mobile wallet together. Pick the one project that best shows your mobile skills. Who used it, what problem did it solve, and where did your responsibility start and end?"
    let say = "The project that best shows my mobile skills is the AI trip planner at KKday."
    #expect(CoachRequiredPoints.missing(question: turn, heard: "pick the project, who used it, problem, my responsibility",
                                        goal: "Tell the project that best shows mobile skills: users, problem, responsibility", say: say, said: []).isEmpty)
    #expect(!CoachRequiredPoints.missing(question: "Now the assistant can start a payment from chat. What changes?",
                                         goal: "Design a mobile wallet: core mobile experience, backend system and failure handling", say: "It opens a confirm screen.", said: []).isEmpty)
}

/// Run 2327: P1 came before any problem was recorded, so only the last interviewer line may set the topic.
@Test func theFirstProjectQuestionWithNoProblemYetGetsNoWalletPoints() {
    let p1 = "Pick the one project that best shows your mobile skills. Who used it, and where did your responsibility start and end?"
    let turn = "Today we'll start with a project you really owned, then design a fictional mobile wallet together. " + p1
    #expect(CoachRequiredPoints.missing(question: turn, heard: "the project and my responsibility", goal: nil,
                                        say: "The AI trip planner at KKday, with an agent tool call per step.", said: [], last: p1).isEmpty)
}

/// Runs 2232 and 2327, W2-seq: the sequence of a named amount never said it travels in cents.
@Test func aNamedAmountTravelsInCents() {
    let q = "Now draw a sequence diagram of A sending B 80 dollars: confirmation, request, ledger and the result screen."
    let goal = "Design a mobile wallet: core mobile experience, backend system and failure handling"
    #expect(CoachRequiredPoints.missing(question: q, goal: goal, say: "A confirms, the server moves the money.", said: []).contains { $0.contains("cents") })
    #expect(CoachRequiredPoints.missing(question: q, goal: goal, say: "A sends 8000 cents.", said: []).allSatisfy { !$0.contains("cents") })
}
