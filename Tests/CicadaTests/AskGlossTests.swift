import Foundation
import Testing
@testable import Cicada

@MainActor
struct AskGlossTests {
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }

    @Test func transientFailureRetriesTheSameSentence() async throws {
        var calls = 0
        let gloss = AskGloss { _, _ in
            calls += 1
            return calls == 1 ? nil : "我会先保存消息。"
        }
        let line = "I would save the message first."
        gloss.enqueue([line])
        try await waitUntil { gloss.translations[line] != nil }
        #expect(calls == 2)
    }

    @Test func failedSentenceDoesNotBlockFollowingSentences() async throws {
        let first = "I would save the message first."
        let second = "Then I would retry the request."
        var recovered = false
        let gloss = AskGloss { text, _ in
            text == first && !recovered ? nil : "中文对照"
        }
        gloss.enqueue([first, second])
        try await waitUntil { gloss.translations[second] != nil }
        #expect(gloss.translations[first] == nil)
        recovered = true
        gloss.enqueue([first])
        try await waitUntil { gloss.translations[first] != nil }
    }

    @Test func disablingRejectsLateResultsAndAllowsRetry() async throws {
        var waiting: CheckedContinuation<String?, Never>?
        var calls = 0
        let gloss = AskGloss { _, _ in
            calls += 1
            if calls == 1 { return await withCheckedContinuation { waiting = $0 } }
            return "新的译文"
        }
        let line = "I would save the message first."
        gloss.enqueue([line])
        try await waitUntil { waiting != nil }
        gloss.enabled = false
        gloss.enabled = true
        gloss.enqueue([line])
        try await waitUntil { gloss.translations[line] == "新的译文" }
        waiting?.resume(returning: "过期译文")
        await Task.yield()
        #expect(gloss.translations[line] == "新的译文")
    }

    @Test func clearRejectsLateResults() async throws {
        var waiting: CheckedContinuation<String?, Never>?
        let gloss = AskGloss { _, _ in await withCheckedContinuation { waiting = $0 } }
        gloss.enqueue(["I would save the message first."])
        try await waitUntil { waiting != nil }
        gloss.clear()
        waiting?.resume(returning: "过期译文")
        await Task.yield()
        #expect(gloss.translations.isEmpty)
    }
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["CICADA_TEST_GLOSS"] == "1"))
@MainActor
struct AskGlossLocalTests {
    @Test func streamedSentenceUsesInstalledAppleTranslationBeforeAnswerEnds() async throws {
        var continuation: AsyncThrowingStream<String, Error>.Continuation?
        let engine = InterviewCoach { _, _ in AsyncThrowingStream { continuation = $0 } }
        defer { continuation?.finish(); engine.endMeeting() }
        engine.start(background: "ActAI Android interview", available: true, prepare: { true })
        engine.observe(lines: [TranscriptLine(id: "q", t: 0, speaker: "them",
            src: "How would you save messages offline?", srcLang: "en", dstLang: "zh-CN")], now: 0)
        engine.tick(now: 1)
        for _ in 0..<100 where continuation == nil { try await Task.sleep(for: .milliseconds(10)) }
        let stream = try #require(continuation)
        stream.yield("I would save the message first. Then")
        for _ in 0..<1000 where engine.gloss.translations.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(engine.state == .generating)
        #expect(engine.gloss.translations["I would save the message first."]?.contains("消息") == true)
        #expect(engine.gloss.translations["Then"] == nil)
        print("Apple streamed gloss:", engine.gloss.translations)
    }
}
