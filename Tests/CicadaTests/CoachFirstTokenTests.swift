import Foundation
import Testing
@testable import Cicada

/// DeepSeek stand-in: the first `hangs` requests never answer, later ones stream one SSE answer.
final class SilentThenStreamStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var hangs = 0
    nonisolated(unsafe) static var requests = 0
    private static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let silent = Self.lock.withLock { Self.requests += 1; return Self.requests <= Self.hangs }
        guard !silent else { return }
        let sse = "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}\n\ndata: [DONE]\n\n"
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(sse.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

/// In LingTests' serialized suite: the DeepSeek key lives in AIKey's shared test folder.
extension LingTests {
    private func deepSeekClient(hangs: Int) -> LingClient {
        AIKey.save("sk-test-0000000000", "deepseek")
        SilentThenStreamStub.hangs = hangs; SilentThenStreamStub.requests = 0
        let ling = LingClient()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SilentThenStreamStub.self]
        ling.session = URLSession(configuration: config)
        ling.coachFirstTokenTimeout = 0.3
        return ling
    }

    @Test func aSilentCoachRequestIsResentAndTheAnswerArrives() async throws {
        let ling = deepSeekClient(hangs: 1)
        var text = ""
        for try await piece in ling.streamCoachTest([["role": "system", "content": "x"]]) { text += piece }
        #expect(text == "Hello")
        #expect(SilentThenStreamStub.requests == 2)
    }

    @Test func persistentCoachSilenceFailsAfterTheLastAttemptInsteadOfWaiting() async throws {
        let ling = deepSeekClient(hangs: 10)
        let started = Date()
        await #expect(throws: (any Error).self) {
            for try await _ in ling.streamCoachTest([["role": "system", "content": "x"]]) {}
        }
        #expect(SilentThenStreamStub.requests == 3)
        #expect(Date().timeIntervalSince(started) < 5)
    }
}

extension LingTests {
    @Test func aNewCoachRequestAnswersAfterEarlierOnesAreCancelled() async throws {
        let ling = deepSeekClientForRestarts()
        for _ in 0..<2 {
            let early = Task { @MainActor in for try await _ in ling.streamCoachTest([["role": "system", "content": "x"]]) {} }
            try await Task.sleep(for: .milliseconds(100))
            early.cancel()
        }
        let started = Date()
        var text = ""
        for try await piece in ling.streamCoachTest([["role": "system", "content": "x"]]) { text += piece }
        #expect(text == "Hello")
        #expect(Date().timeIntervalSince(started) < 3)
    }

    private func deepSeekClientForRestarts() -> LingClient {
        AIKey.save("sk-test-0000000000", "deepseek")
        SilentThenStreamStub.hangs = 0; SilentThenStreamStub.requests = 0
        let ling = LingClient()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SilentThenStreamStub.self]
        ling.session = URLSession(configuration: config)
        ling.coachFirstTokenTimeout = 6
        return ling
    }
}
