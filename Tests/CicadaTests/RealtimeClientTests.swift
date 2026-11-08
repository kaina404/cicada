import AppKit
import Foundation
import Testing
@testable import Cicada

struct RealtimeClientTests {
    @Test func gatewayErrorsPreserveOnlySafeCode() throws {
        let gateway = try JSONDecoder().decode(RealtimeEvent.self, from: Data(#"{"code":"AccessDenied.Unpurchased","message":"private input","request_id":"opaque"}"#.utf8))
        #expect(gateway.type == "error")
        #expect(gateway.error?.safeCode == "AccessDenied.Unpurchased")
        #expect(!RealtimeClient.Failure.rejected("AccessDenied.Unpurchased").retryable)
        #expect(RealtimeClient.Failure.transport(-1005, 101).retryable)
        let nested = try JSONDecoder().decode(RealtimeEvent.self, from: Data(#"{"type":"error","error":{"code":"invalid-input_code","message":"private input"}}"#.utf8))
        #expect(nested.error?.safeCode == "invalid-input_code")
        for code in ["secret input", "private\ntext", String(repeating: "x", count: 81), ""] {
            #expect(RealtimeEvent.Failure(code: code).safeCode == "unknown")
        }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(RealtimeEvent.self, from: Data(#"{"message":"missing event"}"#.utf8)) }
    }
    @Test func protocolAndUnknownEvents() throws {
        let config = RealtimeConfiguration(workspace: "llm-test", region: "cn-beijing", model: "qwen3.8-omni-flash-realtime")
        #expect(config.url?.host == "llm-test.cn-beijing.maas.aliyuncs.com")
        let data = try JSONEncoder().encode(config.session("candidate"))
        let json = try JSONDecoder().decode([String: RealtimeJSON].self, from: data)
        #expect(json["type"] == .string("session.update"))
        guard case .object(let session) = json["session"] else { Issue.record("missing session"); return }
        #expect(session["modalities"] == .array([.string("text")]))
        #expect(session["turn_detection"] == .object(["type": .string("server_vad"), "silence_duration_ms": .number(900)]))
        let text = RealtimeConfiguration.text("question")
        #expect(text["type"] == .string("conversation.item.create"))
        let continuation = RealtimeConfiguration.create(continuing: true, prompt: "Candidate background")
        guard case .object(let continuationResponse) = continuation["response"],
              case .string(let instructions) = continuationResponse["instructions"] else { Issue.record("Missing continuation instructions"); return }
        #expect(instructions.hasPrefix("Candidate background\n"))
        #expect(instructions.contains("Do not repeat"))
        for type in ["future.unknown", "input_audio_buffer.speech_started", "response.done", "error"] {
            let event = try JSONDecoder().decode(RealtimeEvent.self, from: Data("{\"type\":\"\(type)\"}".utf8))
            #expect(event.type == type)
        }
        let response = try JSONDecoder().decode(RealtimeEvent.self, from: Data("{\"type\":\"response.done\",\"response\":{\"id\":\"r1\",\"status\":\"completed\",\"usage\":{\"total_tokens\":100}}}".utf8))
        #expect(response.id == "r1")
        #expect(response.response?.usage?["total_tokens"] == .number(100))
    }
    @Test func audioClipsAndRounds() {
        let data = RealtimeMedia.pcm([-2, -1, -0.5, 0, 0.5, 1, 2, .nan])
        #expect(Array(data) == [0,128, 0,128, 0,192, 0,0, 0,64, 255,127, 255,127, 0,0])
        #expect(RealtimeMedia.pcm(Array(repeating: 0.5, count: 1600)).count == 3200)
    }
    @Test func reconnectBufferKeepsRecentAudioAndPartialPacket() {
        var queue = RealtimeAudioBuffer()
        queue.append(Data(repeating: 1, count: 1700))
        #expect(queue.next() == nil)
        queue.append(Data(repeating: 2, count: 1500))
        #expect(queue.next() == Data(repeating: 1, count: 1700) + Data(repeating: 2, count: 1500))
        for value in 0..<110 { queue.append(Data(repeating: UInt8(value), count: 3200)) }
        queue.append(Data(repeating: 200, count: 100))
        #expect(queue.byteCount == 320_100)
        for value in 10..<110 { #expect(queue.next() == Data(repeating: UInt8(value), count: 3200)) }
        #expect(queue.next() == nil)
        queue.append(Data(repeating: 201, count: 3100))
        #expect(queue.next() == Data(repeating: 200, count: 100) + Data(repeating: 201, count: 3100))
    }
    @Test func imageWaitsForAudioTurnAndCanBeClearedBeforeUpload() {
        var image = RealtimeImageBuffer()
        image.append(Data([1])); image.append(Data([2]))
        #expect(image.next(audioSent: false, speechActive: true) == nil)
        #expect(image.next(audioSent: true, speechActive: false) == nil)
        #expect(image.next(audioSent: true, speechActive: true) == Data([2]))
        #expect(image.isEmpty)
        image.append(Data([3])); image.clear()
        #expect(image.next(audioSent: true, speechActive: true) == nil)
    }
    @Test func imageLimitsAndGates() throws {
        let width = 3000, height = 2000
        let bytes = (0..<(width * height * 4)).map { UInt8(truncatingIfNeeded: $0 &* 73 &+ $0 / 13) }
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        let image = try #require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                         provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent))
        let data = try #require(RealtimeMedia.jpeg(image))
        #expect(data.count < 190_000)
        #expect(data.base64EncodedString().utf8.count < 256_000)
        var gate = RealtimeImageGate()
        let observed1 = !gate.allow(signature: [0], now: 0, audioSent: false, slide: true)
        #expect(observed1)
        let observed2 = !gate.allow(signature: [0], now: 0, audioSent: true, slide: false)
        #expect(observed2)
        let observed3 = gate.allow(signature: [0], now: 0, audioSent: true, slide: true)
        #expect(observed3)
        let observed4 = !gate.allow(signature: [255], now: 0.9, audioSent: true, slide: true)
        #expect(observed4)
        let observed5 = gate.allow(signature: [255], now: 1, audioSent: true, slide: true)
        #expect(observed5)
        let observed6 = !gate.allow(signature: [255], now: 2, audioSent: true, slide: true)
        #expect(observed6)
    }
}
