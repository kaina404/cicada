import Foundation
import Testing
@testable import Cicada

/// Fixtures: the 1413 strict wallet run's past-work cards against the candidate's real background.
struct CoachNumbersTests {
    let background = (try? String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../tools/copilot-interview-background.json").standardized, encoding: .utf8)) ?? ""
    let change = "Pick a change you personally made. Walk me from one user action through the UI, data or network path. Which logic did you actually change?"

    @Test func anInventedRetryCountIsDropped() {
        #expect(!background.isEmpty)
        let say = "One edge case: if the connection drops mid-stream, I surface a retry. The retry has a cap: after two failed attempts the backend falls back to a safe default instead of retrying indefinitely."
        #expect(CoachNumbers.withoutInvented(say, question: change, sources: [background])
                == "One edge case: if the connection drops mid-stream, I surface a retry.")
    }

    @Test func numbersTheCandidateGaveStay() {
        let said = ["Our Android team went from three people to one."]
        let say = "Our Android team went from three people to one, so I owned the whole client."
        #expect(CoachNumbers.withoutInvented(say, question: change, sources: [background] + said) == say)
        #expect(CoachNumbers.withoutInvented("The team shrank from three Android engineers to one.", question: change, sources: [background]) != "")
    }

    @Test func designQuestionsKeepTheirArithmetic() {
        let q = "A has 100 dollars and B has zero. Draw the client, the server and local storage."
        let say = "80 dollars is 8000 cents, so A goes from 100 to 20 dollars."
        #expect(CoachNumbers.withoutInvented(say, question: q, sources: [q]) == say)
    }
}
