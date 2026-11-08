import AVFoundation
import Foundation
import Testing
@testable import Cicada

struct CandidateRecognitionTests {
    @Test @MainActor func draftAndFinalShareIndependentGemmaASR() async throws {
        var requests: [[[String: Any]]] = []
        let pair = AsyncThrowingStream<Recognition.Piece, Error>.makeStream()
        let worker = CandidateTranscriber(infer: { messages in
            requests.append(messages)
            return "I keep messages in Room."
        }, output: pair.continuation)
        worker.append(Array(repeating: 0.1, count: 32000))
        for _ in 0..<100 { await Task.yield() }
        worker.append(Array(repeating: 0, count: 9600))
        await worker.finish()
        var pieces: [Recognition.Piece] = []
        for try await piece in pair.stream { pieces.append(piece) }
        #expect(pieces.map(\.isFinal) == [false, true])
        #expect(pieces.allSatisfy { $0.text == "I keep messages in Room." })
        #expect(pieces.last?.start == 0)
        #expect(pieces.last?.end == 2.6)
        #expect(pieces.last?.language == "en")
        for request in requests {
            let text = String(decoding: try JSONSerialization.data(withJSONObject: request), as: UTF8.self)
            #expect(text.contains("input_audio"))
            #expect(!text.contains("Numbered script"))
            #expect(text.contains("Never translate"))
        }
    }

    @Test @MainActor func silenceDoesNotInferAndShortSpeechFlushesOnFinish() async throws {
        var calls = 0
        let pair = AsyncThrowingStream<Recognition.Piece, Error>.makeStream()
        let worker = CandidateTranscriber(infer: { _ in calls += 1; return "Room" }, output: pair.continuation)
        worker.append(Array(repeating: 0, count: 64000))
        #expect(calls == 0)
        worker.append(Array(repeating: 0.1, count: 3200))
        await worker.finish()
        var pieces: [Recognition.Piece] = []
        for try await piece in pair.stream { pieces.append(piece) }
        #expect(calls == 1)
        #expect(pieces.count == 1)
        #expect(pieces.first?.isFinal == true)
        #expect(abs((pieces.first?.start ?? 0) - 3.8) < 0.01)
    }

    @Test @MainActor func delayedDraftCannotOverwriteFinalOrNextUtterance() async throws {
        var resume: CheckedContinuation<String, Never>?
        var calls = 0
        let pair = AsyncThrowingStream<Recognition.Piece, Error>.makeStream()
        let worker = CandidateTranscriber(infer: { _ in
            calls += 1
            if calls == 1 { return await withCheckedContinuation { resume = $0 } }
            return calls == 2 ? "first answer" : "second answer"
        }, output: pair.continuation)
        worker.append(Array(repeating: 0.1, count: 32000))
        for _ in 0..<1000 where resume == nil { await Task.yield() }
        try #require(resume != nil)
        worker.flush()
        worker.append(Array(repeating: 0.1, count: 4000))
        worker.flush()
        resume?.resume(returning: "stale draft")
        await worker.finish()
        var pieces: [Recognition.Piece] = []
        for try await piece in pair.stream { pieces.append(piece) }
        #expect(pieces.map(\.text) == ["first answer", "second answer"])
        #expect(pieces.allSatisfy { $0.isFinal })
        #expect(pieces[1].start == pieces[0].end)
    }

    @Test @MainActor func cancellationDiscardsLateResults() async throws {
        var resume: CheckedContinuation<String, Never>?
        let pair = AsyncThrowingStream<Recognition.Piece, Error>.makeStream()
        let worker = CandidateTranscriber(infer: { _ in await withCheckedContinuation { resume = $0 } }, output: pair.continuation)
        worker.append(Array(repeating: 0.1, count: 32000))
        for _ in 0..<1000 where resume == nil { await Task.yield() }
        try #require(resume != nil)
        worker.cancel(); resume?.resume(returning: "late speech")
        for _ in 0..<100 { await Task.yield() }
        var count = 0
        for try await _ in pair.stream { count += 1 }
        #expect(count == 0)
    }

    @Test @MainActor func continuousSpeechHasSeparateBoundedFinals() async throws {
        let pair = AsyncThrowingStream<Recognition.Piece, Error>.makeStream()
        var calls = 0
        let worker = CandidateTranscriber(infer: { _ in calls += 1; return "sentence \(calls)" }, output: pair.continuation)
        for _ in 0..<2 { worker.append(Array(repeating: 0.1, count: 192000)) }
        await worker.finish()
        var pieces: [Recognition.Piece] = []
        for try await piece in pair.stream { pieces.append(piece) }
        #expect(pieces.count == 2)
        #expect(pieces.map(\.start) == [0, 12])
        #expect(pieces.map(\.end) == [12, 24])
        #expect(pieces.allSatisfy { $0.isFinal })
    }

    @Test @MainActor func serviceFailureRetriesThenSurfacesWithoutSubstitutingSpeech() async {
        var calls = 0
        let pair = AsyncThrowingStream<Recognition.Piece, Error>.makeStream()
        let worker = CandidateTranscriber(infer: { _ in
            calls += 1; throw URLError(.cannotConnectToHost)
        }, output: pair.continuation)
        worker.append(Array(repeating: 0.1, count: 4000))
        await worker.finish()
        var pieces = 0, failed = false
        do { for try await _ in pair.stream { pieces += 1 } }
        catch { failed = true }
        #expect(calls == 3)
        #expect(failed)
        #expect(pieces == 0)
    }

    @Test @MainActor func recordsAndReadingReuseOneTranscriptWithoutAudioInference() async throws {
        var requests: [[[String: Any]]] = []
        let reader = CoachReading { messages in
            requests.append(messages)
            return "{\"through\":6,\"confidence\":0.95}"
        }
        reader.usesTranscripts = true
        var script = CoachScript(modelReading: true)
        script.replacePending("I keep each message in Room. Then retry safely.", since: [], newAnswer: true)
        reader.begin(answerID: script.answerID)
        reader.onProgress = { id, through, _ in script.advanceReading(to: through, answerID: id) }
        let transcript = "I keep each message in Room"
        script.commit(id: "gemma-final", text: transcript)
        reader.acceptTranscript(transcript, final: true)
        reader.tick(script: script, blocked: false, now: 2)
        for _ in 0..<1000 where reader.busy { await Task.yield() }
        #expect(script.spokenText == transcript)
        #expect(script.cursor == 6)
        #expect(requests.count == 1)
        let text = String(decoding: try JSONSerialization.data(withJSONObject: requests[0]), as: UTF8.self)
        #expect(!text.contains("input_audio"))
        reader.tick(script: script, blocked: false, now: 10)
        #expect(requests.count == 1)
        reader.stop()
    }
}
