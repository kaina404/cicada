#!/usr/bin/env swift
// Phase 0 only: no App imports, audio playback, key logging, or persisted conversation content.
import Foundation
import AVFoundation
struct ProbeFailure: Error, CustomStringConvertible {
    let description: String; init(_ description: String) { self.description = description }
}
struct Options {
    var file: URL; var workspace = ""
    var region = "cn-beijing"
    var seconds: Double = 60
    var audioOutput = false, dryRun = false, serverVAD = false
    var report: URL
    init(_ args: [String]) throws {
        guard let path = args.first, !path.hasPrefix("--") else {
            throw ProbeFailure("Usage: swift tools/qwen-realtime-probe.swift <audio-file> --workspace <id> [--region cn-beijing|ap-southeast-1] [--seconds 60] [--audio-output] [--dry-run] [--report <path>]")
        }
        file = URL(fileURLWithPath: path)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        report = URL(fileURLWithPath: "docs/evaluations/qwen-realtime-probe-\(stamp).json")
        var i = 1
        while i < args.count {
            let flag = args[i]; i += 1
            if flag == "--audio-output" { audioOutput = true; continue }
            if flag == "--server-vad" { serverVAD = true; continue }
            if flag == "--dry-run" { dryRun = true; continue }
            guard i < args.count else { throw ProbeFailure("Missing value for \(flag)") }
            let value = args[i]; i += 1
            switch flag {
            case "--workspace": workspace = value
            case "--region": region = value
            case "--seconds": seconds = Double(value) ?? 0
            case "--report": report = URL(fileURLWithPath: value)
            default: throw ProbeFailure("Unknown option \(flag)")
            }
        }
        guard ["cn-beijing", "ap-southeast-1"].contains(region), seconds.isFinite,
              seconds > 0, seconds <= 7200 else { throw ProbeFailure("Invalid region or seconds (1…7200)") }
        guard dryRun || (!workspace.isEmpty && workspace.utf8.allSatisfy({
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45
        })) else { throw ProbeFailure("A workspace ID containing only letters, digits and hyphens is required") }
    }
}
func readerFor(_ file: URL) async throws -> (AVAssetReader, AVAssetReaderTrackOutput) {
    let asset = AVURLAsset(url: file)
    guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
        throw ProbeFailure("Input has no audio track")
    }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
        AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000,
        AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ])
    guard reader.canAdd(output) else { throw ProbeFailure("Cannot decode audio as 16 kHz mono PCM") }
    reader.add(output)
    guard reader.startReading() else { throw ProbeFailure("Audio reader could not start") }
    return (reader, output)
}
actor Probe {
    let options: Options
    let started = ProcessInfo.processInfo.systemUptime
    var socket: URLSessionWebSocketTask?
    var created = false, updated = false
    var audioBytes = 0, packets = 0, audioDeltas = 0, textDeltas = 0
    var stopAt: Double?
    var active = ""
    var firstSeen = Set<String>()
    var interrupted: [String: Double] = [:]
    var latencies: [Double] = []
    var responses: [[String: Any]] = []
    var events: [[String: Any]] = []
    var lengths: [String: Int] = [:]
    init(_ options: Options) { self.options = options }
    var now: Double { ProcessInfo.processInfo.systemUptime - started }
    func log(_ type: String, _ extra: [String: Any] = [:]) {
        var entry = extra; entry["type"] = type; entry["seconds"] = now
        events.append(entry)
        print(String(format: "%.3f %@", now, type), extra)
    }
    func send(_ object: [String: Any]) async throws {
        guard let socket else { throw ProbeFailure("Socket unavailable") }
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let string = String(data: data, encoding: .utf8) else { throw ProbeFailure("Invalid event encoding") }
        try await socket.send(.string(string))
    }
    func receive() async throws {
        guard let socket else { throw ProbeFailure("Socket unavailable") }
        while !Task.isCancelled {
            let message = try await socket.receive()
            let data: Data
            switch message {
            case .data(let bytes): data = bytes
            case .string(let string): data = Data(string.utf8)
            @unknown default: continue
            }
            guard let event = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = event["type"] as? String else { continue }
            let response = event["response"] as? [String: Any] ?? [:]
            let id = event["response_id"] as? String ?? response["id"] as? String ?? ""
            switch type {
            case "session.created": created = true; log(type)
            case "session.updated": updated = true; log(type)
            case "response.created": active = id; log(type)
            case "input_audio_buffer.speech_started":
                log(type)
                if !active.isEmpty { interrupted[active] = now }
                // Always explicitly cancel; this run cannot establish automatic server cancellation.
                try await send(["type": "response.cancel"])
            case "input_audio_buffer.speech_stopped": stopAt = now; log(type)
            case "response.text.delta", "response.audio_transcript.delta":
                let count = (event["delta"] as? String ?? "").count
                textDeltas += 1; lengths[id, default: 0] += count
                var detail: [String: Any] = ["characters": count]
                if firstSeen.insert(id).inserted, let stopAt {
                    let latency = (now - stopAt) * 1000
                    latencies.append(latency); detail["since_speech_stopped_ms"] = latency
                    self.stopAt = nil
                }
                if let at = interrupted[id] { detail["after_interrupt_ms"] = (now - at) * 1000 }
                log(type, detail)
            case "response.audio.delta": audioDeltas += 1 // Discard audio; never play it.
            case "response.done":
                var summary: [String: Any] = ["status": response["status"] as? String ?? "unknown",
                    "characters": lengths[id, default: 0]]
                if let usage = response["usage"] as? [String: Any] { summary["usage"] = numericUsage(usage) }
                responses.append(summary); log(type, summary)
                if id == active { active = "" }
            case "error":
                let code = (event["error"] as? [String: Any])?["code"] as? String ?? ""
                log(type, ["code": String(code.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }.prefix(80))])
                if code != "response_cancel_not_active", code != "response_cancel_not_in_progress" {
                    throw ProbeFailure("Server rejected an event; see configuration and official protocol documentation")
                }
            case "conversation.item.input_audio_transcription.delta", "conversation.item.input_audio_transcription.completed":
                let text = event["transcript"] as? String ?? event["text"] as? String ?? ""
                log(type, ["characters": text.count])
            default: break
            }
        }
    }
    func numericUsage(_ object: [String: Any]) -> [String: Any] {
        object.reduce(into: [:]) { result, pair in
            if let value = pair.value as? NSNumber { result[pair.key] = value }
            else if let nested = pair.value as? [String: Any] { result[pair.key] = numericUsage(nested) }
        }
    }
    func stream() async throws {
        let (reader, output) = try await readerFor(options.file)
        defer { reader.cancelReading() }
        var pending = Data()
        let clock = ContinuousClock(); let start = clock.now
        let limit = Int(options.seconds * 16000) * 2
        func emit(_ packet: Data) async throws {
            if !options.dryRun { try await send(["type": "input_audio_buffer.append", "audio": packet.base64EncodedString()]) }
            audioBytes += packet.count; packets += 1
            // Absolute deadlines avoid accumulating decoder/network delay; never send ahead of real time.
            if !options.dryRun { try await clock.sleep(until: start.advanced(by: .seconds(Double(audioBytes) / 32000))) }
        }
        while audioBytes < limit, let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let block = CMSampleBufferGetDataBuffer(sample) else { throw ProbeFailure("Missing PCM buffer") }
            let size = CMBlockBufferGetDataLength(block)
            guard size > 0 else { continue }
            var data = Data(count: size)
            let status = data.withUnsafeMutableBytes { bytes in
                guard let address = bytes.baseAddress else { return OSStatus(-1) }
                return CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: bytes.count, destination: address)
            }
            guard status == kCMBlockBufferNoErr else { throw ProbeFailure("PCM buffer copy failed") }
            pending.append(data)
            while pending.count >= 3200, audioBytes < limit {
                let count = min(3200, limit - audioBytes)
                try await emit(Data(pending.prefix(count))); pending.removeFirst(count)
            }
        }
        if reader.status == .failed { throw ProbeFailure("Audio decode failed") }
        if !pending.isEmpty, audioBytes < limit { try await emit(Data(pending.prefix(limit - audioBytes))) }
        guard audioBytes > 0 else { throw ProbeFailure("Input audio is empty") }
        log("input.finished", ["pcm_bytes": audioBytes, "packets": packets])
        if !options.dryRun {
            // Keep feeding silence so VAD can finish the last utterance; no manual commit in VAD mode.
            for _ in 0..<50 { try await send(["type": "input_audio_buffer.append", "audio": Data(count: 3200).base64EncodedString()]); try await Task.sleep(for: .milliseconds(100)) }
            try await Task.sleep(for: .seconds(15))
        }
    }
    func run() async throws {
        defer { socket?.cancel(with: .normalClosure, reason: nil) }
        if options.dryRun { try await stream(); return }
        let keyFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/LiveSubs Dev/ai-key-dashscope")
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: keyFile.path),
              let mode = attrs[.posixPermissions] as? NSNumber, mode.intValue & 0o777 == 0o600,
              let rawKey = try? String(contentsOf: keyFile, encoding: .utf8),
              !rawKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProbeFailure("Missing Key or permissions != 0600 at LiveSubs Dev/ai-key-dashscope. Save the regional DashScope Key there; never pass it on the command line.")
        }
        guard let url = URL(string: "wss://\(options.workspace).\(options.region).maas.aliyuncs.com/api-ws/v1/realtime?model=qwen3.8-omni-flash-realtime") else { throw ProbeFailure("Invalid endpoint") }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(rawKey.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        let ws = URLSession.shared.webSocketTask(with: request); socket = ws; ws.resume()
        let receiver = Task { try await receive() }
        let watchdog = Task { try await Task.sleep(for: .seconds(options.seconds + 50)); ws.cancel(with: .goingAway, reason: nil) }
        defer { receiver.cancel(); watchdog.cancel() }
        let createdDeadline = now + 15
        while !created, now < createdDeadline { try await Task.sleep(for: .milliseconds(50)) }
        guard created else { throw ProbeFailure("No session.created within 15 seconds") }
        let vad: [String: Any] = options.serverVAD ? ["type": "server_vad", "silence_duration_ms": 900] : ["type": "semantic_vad"]
        try await send(["type": "session.update", "session": [
            "modalities": options.audioOutput ? ["text", "audio"] : ["text"],
            "instructions": "You are Jianhui Xu in an ActAI Android interview. Write natural spoken English in first person. Start with → and a short plan, then explain a system design step by step. Never invent personal experience; use [fill in: …] when unknown. End with [[more]] or [[end]].",
            "turn_detection": vad,
            "input_audio_transcription": ["model": "qwen3-asr-flash-realtime"],
            "audio": ["input": ["format": ["type": "pcm", "sample_rate": 16000, "sample_format": "s16le", "channels": 1, "packing": "interleaved", "channel_layout": "mono"]]]
        ]])
        let deadline = now + 15
        while !updated, now < deadline { try await Task.sleep(for: .milliseconds(50)) }
        guard updated else { throw ProbeFailure("No session.updated within 15 seconds") }
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await receiver.value }
            group.addTask { try await self.stream() }
            defer { group.cancelAll(); ws.cancel(with: .normalClosure, reason: nil) }
            try await group.next()
        }
    }
    func save(_ failure: String?) throws {
        let sorted = latencies.sorted()
        func percentile(_ p: Double) -> Any { sorted.isEmpty ? NSNull() : sorted[min(sorted.count - 1, Int(ceil(Double(sorted.count) * p)) - 1)] as Any }
        let report: [String: Any] = ["date": ISO8601DateFormatter().string(from: Date()),
            "status": failure != nil ? "blocked_or_failed" : options.dryRun ? "offline_decode_only" : "observed_not_accepted",
            "failure": failure as Any? ?? NSNull(), "region": options.region, "vad": options.serverVAD ? "server_vad" : "semantic_vad", "requested_modalities": options.audioOutput ? ["text", "audio"] : ["text"],
            "elapsed_seconds": now, "input_audio_seconds": Double(audioBytes) / 32000, "packets": packets,
            "session_updated": updated, "text_deltas": textDeltas, "audio_deltas_discarded": audioDeltas,
            "latency_basis": "server speech_stopped receipt to first delta; excludes VAD detection delay; not acoustic end-to-end latency",
            "latency_samples_ms": latencies, "p50_ms": percentile(0.5), "p90_ms": percentile(0.9),
            "responses": responses, "events": events,
            "pending": ["text_only: verify successful text response and no audio deltas", "automatic_cancel: unknown because client always sends cancel", "connection_and_context_limits: only lower bounds observed", "first_word: need 10 acoustic-end annotated questions", "long_answer: review response lengths and content live", "hourly_cost: usage recorded, regional prices and representative full-hour input required", "semantic_vad_pauses: need annotated um/pause fixture"]]
        try FileManager.default.createDirectory(at: options.report.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: options.report, options: .atomic)
        print("Report: \(options.report.path)")
    }
}
do {
    let options = try Options(Array(CommandLine.arguments.dropFirst()))
    let probe = Probe(options)
    var failure: String?
    do { try await probe.run() } catch {
        failure = (error as? ProbeFailure)?.description ?? "Transport, decoding or cancellation failure (details redacted)"
    }
    try await probe.save(failure)
    if let failure { print(failure); exit(1) }
} catch { print((error as? ProbeFailure)?.description ?? "Probe setup/report failure"); exit(1) }
