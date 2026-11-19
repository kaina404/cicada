import Testing
@testable import Cicada

/// Design exercises leave <talk_tracks> out of the card request; personal questions keep it.
struct CoachKnowledgeTrimTests {
    let background = Knowledge.assemble([
        "00_profile.md": "Android engineer.", "03_projects.md": "KKday AI trip planner.",
        "04_talk_tracks.md": "Closing: invite them to the one-minute Cabinet AI demo.", "05_target_company.md": "ActAI."])

    func memory(goal: String) -> CoachCase {
        var memory = CoachCase()
        memory.apply([CoachCaseOp(op: "newProblem", text: goal, evidence: ["q"])], evidence: CoachEvidence(interviewer: ["q"]), at: 0)
        return memory
    }
    func turns(_ question: String) -> [CoachTurn] { [CoachTurn(id: "q", seconds: 0, role: "interviewer", text: question)] }

    @Test func aDesignQuestionLeavesTheTalkTracksOut() {
        let wallet = memory(goal: "Design a mobile wallet from scratch")
        let trimmed = CoachCardPrompt.knowledge(background, turns: turns("On two phones A approves two transfers at once. What happens?"), memory: wallet)
        #expect(!trimmed.contains("talk_tracks"))
        #expect(!trimmed.contains("Cabinet AI"))
        #expect(trimmed.contains("KKday AI trip planner") && trimmed.contains("ActAI."))
    }

    @Test func personalQuestionsKeepThem() {
        let wallet = memory(goal: "Design a mobile wallet from scratch")
        for question in ["What questions do you have for me about the team or the role?",
                         "In that rollout, what would you personally own and when would you escalate to me?",
                         "Tell me about a time the team disagreed with you."] {
            #expect(CoachCardPrompt.knowledge(background, turns: turns(question), memory: wallet).contains("Cabinet AI"))
        }
        // Project questions: their problem is no design exercise.
        let project = memory(goal: "Walk through the project you really owned")
        #expect(CoachCardPrompt.knowledge(background, turns: turns("Which logic did you change?"), memory: project) == background)
        #expect(CoachCardPrompt.knowledge(background, turns: turns("Which logic did you change?"), memory: memory(goal: "Walk through the system you built at KKday")) == background)
        #expect(CoachCardPrompt.knowledge(background, turns: turns("Hello"), memory: CoachCase()) == background)
        // Real goals from the wallet runs.
        for goal in ["Design a mobile wallet: core mobile experience, the system behind it, and how it handles failures",
                     "Design the entry flow for a payment started from a group chat: two contacts named Alex"] {
            #expect(!CoachCardPrompt.knowledge(background, turns: turns("What happens next?"), memory: memory(goal: goal)).contains("talk_tracks"))
        }
    }
}
