// Compile with RealtimeClient.swift and CandidateLogic.swift; see tools/README.md.
// Only synthetic interview fixtures and their answers are exported. Never use private meeting audio here.
import Foundation
import AVFoundation

struct InterviewFixture: Codable { var id: String; var question: String; var audio: String; var image: String?; var context: String? }
struct InterviewResult: Codable {
    var id: String; var question: String; var paragraphs: [String] = []
    var firstMilliseconds: Double?; var continued = 0; var formatOK = true
    var inputTokens = 0; var outputTokens = 0; var usages: [[String: RealtimeJSON]] = []; var failure: String?
}

@MainActor final class InterviewEval {
    let client = RealtimeClient()
    var loop = CandidateLoop()
    var raw = ""
    var result: InterviewResult
    var ended = false
    var audioEnd: Double?
    var firstAt: Double?
    var now: Double { ProcessInfo.processInfo.systemUptime }
    init(_ fixture: InterviewFixture) { result = InterviewResult(id: fixture.id, question: fixture.question) }

    func run(_ fixture: InterviewFixture, config: RealtimeConfiguration, key: String, prompt: String) async -> InterviewResult {
        var feed: Task<Void, Never>?
        let watchdog = Task { try? await Task.sleep(for: .seconds(100)); if !Task.isCancelled { await client.close() } }
        let ticker = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                if loop.tick(now: now) { await client.send(RealtimeConfiguration.create(continuing: true, prompt: prompt)) }
            }
        }
        defer { feed?.cancel(); watchdog.cancel(); ticker.cancel() }
        do {
            let events = try await client.open(config, key: key, prompt: prompt, context: fixture.context)
            for try await event in events {
                switch event.type {
                case "session.updated":
                    feed = Task { do { try await audio(fixture) } catch { result.failure = "audio fixture failed"; await client.close() } }
                case "input_audio_buffer.speech_started":
                    loop.speechStarted()
                    await client.send(["type": .string("response.cancel")])
                case "input_audio_buffer.speech_stopped": loop.speechStopped()
                case "response.created": raw = ""; loop.responseStarted(event.id)
                case "response.text.delta":
                    guard loop.accepts(event.id), let delta = event.delta else { continue }
                    if firstAt == nil { firstAt = now }
                    raw += delta
                case "response.done":
                    guard loop.accepts(event.id) else { continue }
                    if let usage = event.response?.usage { result.usages.append(usage) }
                    if case .number(let n) = event.response?.usage?["input_tokens"] { result.inputTokens += Int(n) }
                    if case .number(let n) = event.response?.usage?["output_tokens"] { result.outputTokens += Int(n) }
                    guard event.response?.status == "completed" else { loop.cancel(); continue }
                    let parsed = CandidateOutput(raw)
                    result.paragraphs.append(raw)
                    result.formatOK = result.formatOK && raw.hasPrefix("→") && !parsed.plan.isEmpty && !parsed.text.isEmpty && (raw.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("[[end]]") || parsed.marker == .more)
                    loop.responseDone(parsed.marker, now: now)
                    if parsed.marker == .end || loop.continues >= 8 { ended = true }
                default: break
                }
                if ended { break }
            }
            if !ended && result.failure == nil { result.failure = "session ended or timed out" }
        } catch {
            if case RealtimeClient.Failure.rejected(let code) = error { result.failure = "server: " + code }
            else if case RealtimeClient.Failure.protocolField(let field) = error { result.failure = "decode_field: " + field }
            else if case RealtimeClient.Failure.transport(let code, let status) = error { result.failure = "transport_\(code)_http_\(status)" }
            else { result.failure = "transport or server failure (details redacted)" }
        }
        await client.close()
        result.formatOK = result.formatOK && !result.paragraphs.isEmpty
        result.continued = loop.continues
        if let firstAt, let audioEnd { result.firstMilliseconds = (firstAt - audioEnd) * 1000 }
        return result
    }
    private func audio(_ fixture: InterviewFixture) async throws {
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: fixture.audio), commonFormat: .pcmFormatInt16, interleaved: true)
        guard file.processingFormat.sampleRate == 16000, file.processingFormat.channelCount == 1,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1600) else { throw CocoaError(.fileReadCorruptFile) }
        let clock = ContinuousClock(); let start = clock.now
        var sent = 0
        while file.framePosition < file.length {
            try Task.checkCancellation()
            try file.read(into: buffer, frameCount: 1600)
            guard let samples = buffer.int16ChannelData else { throw CocoaError(.fileReadCorruptFile) }
            let count = Int(buffer.frameLength)
            await client.append(Data(bytes: samples[0], count: count * 2))
            if sent == 16000, let path = fixture.image { await client.picture(try Data(contentsOf: URL(fileURLWithPath: path))) }
            sent += count
            try await clock.sleep(until: start.advanced(by: .seconds(Double(sent) / 16000)))
        }
        audioEnd = now
        // Flush a partial 100 ms packet, then keep VAD running after the fixture ends.
        for _ in 0..<50 {
            try Task.checkCancellation()
            await client.append(Data(count: 3200)); try await Task.sleep(for: .milliseconds(100))
        }
    }
}

@main struct RealtimeEvaluation {
    @MainActor static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 4 else { print("Usage: qwen-realtime-eval <fixture.json> <report.json> <background.json>"); return }
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/LiveSubs Dev")
        let keyFile = root.appendingPathComponent("ai-key-dashscope")
        let permissions = try FileManager.default.attributesOfItem(atPath: keyFile.path)[.posixPermissions] as? NSNumber
        guard permissions?.intValue == 0o600 else { throw CocoaError(.fileReadNoPermission) }
        let key = try String(contentsOf: keyFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("dashscope-config.json"))) as? [String: String]
        let config = RealtimeConfiguration(workspace: object?["workspaceId"] ?? "", region: object?["region"] ?? "cn-beijing", model: "qwen3.8-omni-flash-realtime")
        let background = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[3]))) as? [String: Any]
        let text = ((background?["candidate_resume"] as? [String]) ?? []).joined(separator: "\n") + "\nCompany brief\n" + ((background?["company_brief_user_supplied"] as? [String]) ?? []).joined(separator: "\n")
        let fixtures = try JSONDecoder().decode([InterviewFixture].self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
        var results: [InterviewResult] = []
        for fixture in fixtures {
            let value = await InterviewEval(fixture).run(fixture, config: config, key: key, prompt: CandidatePrompt.make(background: text))
            results.append(value)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(results).write(to: URL(fileURLWithPath: args[2]), options: .atomic)
            print("\(fixture.id): paragraphs=\(value.paragraphs.count) format=\(value.formatOK) failure=\(value.failure != nil)")
            fflush(stdout)
        }
    }
}
