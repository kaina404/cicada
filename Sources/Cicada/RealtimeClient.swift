import Foundation

indirect enum RealtimeJSON: Codable, Equatable, Sendable {
    case string(String), number(Double), bool(Bool), object([String: RealtimeJSON]), array([RealtimeJSON]), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([RealtimeJSON].self) { self = .array(a) }
        else { self = .object(try c.decode([String: RealtimeJSON].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }
}

struct RealtimeEvent: Decodable, Sendable {
    struct Response: Decodable, Sendable { var id: String?; var status: String?; var usage: [String: RealtimeJSON]? }
    struct Failure: Decodable, Sendable {
        var code: String?
        var safeCode: String {
            guard let code, !code.isEmpty, code.count <= 80,
                  code.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45, 46, 95].contains($0) }) else { return "unknown" }
            return code
        }
    }
    var type: String
    var response_id: String?
    var delta: String?
    var transcript: String?
    var response: Response?
    var error: Failure?
    var id: String { response_id ?? response?.id ?? "" }
}

extension RealtimeEvent {
    private enum CodingKeys: String, CodingKey { case type, response_id, delta, transcript, response, error, code }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let topLevelCode = try values.decodeIfPresent(String.self, forKey: .code)
        // Gateway access errors arrive without a Realtime event type or nested error object.
        if let suppliedType = try values.decodeIfPresent(String.self, forKey: .type) { type = suppliedType }
        else if topLevelCode != nil { type = "error" }
        else { throw DecodingError.keyNotFound(CodingKeys.type, .init(codingPath: decoder.codingPath, debugDescription: "Missing event type")) }
        response_id = try values.decodeIfPresent(String.self, forKey: .response_id)
        delta = try values.decodeIfPresent(String.self, forKey: .delta)
        transcript = try values.decodeIfPresent(String.self, forKey: .transcript)
        response = try values.decodeIfPresent(Response.self, forKey: .response)
        error = try values.decodeIfPresent(Failure.self, forKey: .error) ?? topLevelCode.map { Failure(code: $0) }
    }
}

struct RealtimeConfiguration: Equatable, Sendable {
    var workspace: String
    var region: String
    var model: String
    var url: URL? {
        guard ["cn-beijing", "ap-southeast-1"].contains(region), !workspace.isEmpty,
              workspace.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 }) else { return nil }
        var parts = URLComponents()
        parts.scheme = "wss"; parts.host = "\(workspace).\(region).maas.aliyuncs.com"
        parts.path = "/api-ws/v1/realtime"; parts.queryItems = [URLQueryItem(name: "model", value: model)]
        return model.isEmpty ? nil : parts.url
    }
    func session(_ prompt: String) -> [String: RealtimeJSON] {
        ["type": .string("session.update"), "session": .object([
            "modalities": .array([.string("text")]), "instructions": .string(prompt),
            // Semantic VAD missed complete questions in the ActAI audio fixtures.
            "turn_detection": .object(["type": .string("server_vad"), "silence_duration_ms": .number(900)]),
            "input_audio_transcription": .object(["model": .string("qwen3-asr-flash-realtime")]),
            "audio": .object(["input": .object(["format": .object([
                "type": .string("pcm"), "sample_rate": .number(16000), "sample_format": .string("s16le"),
                "channels": .number(1), "packing": .string("interleaved"), "channel_layout": .string("mono")])])])])]
    }
    static func text(_ text: String) -> [String: RealtimeJSON] {
        ["type": .string("conversation.item.create"), "item": .object([
            "type": .string("message"), "role": .string("user"),
            "content": .array([.object(["type": .string("input_text"), "text": .string(text)])])])]
    }
    static func create(continuing: Bool = false, prompt: String = "") -> [String: RealtimeJSON] {
        var result: [String: RealtimeJSON] = ["type": .string("response.create")]
        if continuing { result["response"] = .object(["instructions": .string(prompt + "\nContinue with the next step of your answer. Do not repeat what you already said. Keep the same candidate persona, background constraints and → / 1–4 sentences / [[more]] or [[end]] format.")]) }
        return result
    }
}

struct RealtimeAudioBuffer {
    private var packets: [Data] = []
    private var partial = Data()
    var isEmpty: Bool { packets.isEmpty }
    var byteCount: Int { packets.count * 3200 + partial.count }
    mutating func append(_ pcm: Data) {
        partial.append(pcm)
        while partial.count >= 3200 {
            packets.append(Data(partial.prefix(3200))); partial.removeFirst(3200)
            if packets.count > 100 { packets.removeFirst() }
        }
    }
    mutating func next() -> Data? { packets.isEmpty ? nil : packets.removeFirst() }
}

struct RealtimeImageBuffer {
    private var pending: Data?
    var isEmpty: Bool { pending == nil }
    mutating func append(_ jpeg: Data) { if jpeg.count < 190_000 { pending = jpeg } }
    mutating func clear() { pending = nil }
    mutating func next(audioSent: Bool, speechActive: Bool) -> Data? {
        guard audioSent, speechActive else { return nil }
        defer { pending = nil }
        return pending
    }
}

/// A single ordered writer owns the socket. Audio is bounded to ten seconds during reconnects.
actor RealtimeClient {
    enum Failure: Error {
        case configuration, rejected(String), transport(Int, Int), protocolField(String), overloaded
        var retryable: Bool {
            switch self {
            case .configuration, .protocolField, .rejected("AccessDenied.Unpurchased"): false
            default: true
            }
        }
    }
    private var socket: URLSessionWebSocketTask?
    private var receiver: Task<Void, Never>?
    private var writer: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private var output: AsyncThrowingStream<RealtimeEvent, Error>.Continuation?
    private var generation = UUID()
    private var controls: [[String: RealtimeJSON]] = []
    private var audio = RealtimeAudioBuffer()
    private var ready = false
    private var sentAudio = false
    private var speechActive = false
    private var image = RealtimeImageBuffer()

    func open(_ config: RealtimeConfiguration, key: String, prompt: String, context: String?) throws -> AsyncThrowingStream<RealtimeEvent, Error> {
        close(clearAudio: false)
        guard let url = config.url else { throw Failure.configuration }
        let pair = AsyncThrowingStream<RealtimeEvent, Error>.makeStream()
        output = pair.continuation
        var request = URLRequest(url: url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let ws = URLSession.shared.webSocketTask(with: request)
        socket = ws; ws.resume()
        let token = generation
        receiver = Task { [weak self] in
            do {
                while !Task.isCancelled {
                    let message = try await ws.receive()
                    let data: Data
                    switch message {
                    case .string(let s): data = Data(s.utf8)
                    case .data(let d): data = d
                    @unknown default: continue
                    }
                    let event = try JSONDecoder().decode(RealtimeEvent.self, from: data)
                    await self?.received(event, config: config, prompt: prompt, context: context, token: token)
                }
            } catch {
                var field: String?
                switch error {
                case DecodingError.typeMismatch(_, let c), DecodingError.valueNotFound(_, let c),
                     DecodingError.keyNotFound(_, let c), DecodingError.dataCorrupted(let c):
                    field = c.codingPath.map(\.stringValue).joined(separator: ".")
                default: break
                }
                await self?.failed(token: token, code: (error as NSError).code, field: field)
            }
        }
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else { return }
            await self?.failed(token: token)
        }
        return pair.stream
    }
    func close(clearAudio: Bool = true) {
        generation = UUID(); ready = false; sentAudio = false; speechActive = false
        receiver?.cancel(); writer?.cancel(); timeout?.cancel()
        receiver = nil; writer = nil; timeout = nil
        socket?.cancel(with: .normalClosure, reason: nil); socket = nil
        output?.finish(); output = nil; controls = []; image.clear()
        if clearAudio { audio = RealtimeAudioBuffer() }
    }
    func append(_ pcm: Data) {
        audio.append(pcm)
        drain()
    }
    func clearPicture() { image.clear() }
    func picture(_ jpeg: Data) { image.append(jpeg); drain() }
    func send(_ event: [String: RealtimeJSON]) {
        guard controls.count < 32 else { output?.finish(throwing: Failure.overloaded); return }
        controls.append(event); drain()
    }
    private func received(_ event: RealtimeEvent, config: RealtimeConfiguration, prompt: String, context: String?, token: UUID) {
        guard token == generation else { return }
        switch event.type {
        case "session.created": send(config.session(prompt))
        case "session.updated":
            ready = true; timeout?.cancel(); timeout = nil
            if let context { send(RealtimeConfiguration.text(context)) }
            drain()
        case "input_audio_buffer.speech_started":
            // Images sent before VAD starts can be omitted from that audio turn. Hold the latest
            // changed frame until speech starts, then commit it with the current utterance.
            speechActive = true; drain()
        case "input_audio_buffer.speech_stopped": speechActive = false
        case "error":
            if ["response_cancel_not_active", "response_cancel_not_in_progress"].contains(event.error?.code ?? "") { return }
            // Log only protocol identifiers, never the provider's message (which can echo input).
            output?.finish(throwing: Failure.rejected(event.error?.safeCode ?? "unknown")); return
        default: break
        }
        output?.yield(event)
    }
    private func failed(token: UUID, code: Int = -1001, field: String? = nil) {
        guard token == generation else { return }
        if let field { output?.finish(throwing: Failure.protocolField(field)) }
        else { output?.finish(throwing: Failure.transport(code, (socket?.response as? HTTPURLResponse)?.statusCode ?? 0)) }
    }
    private func drain() {
        guard writer == nil, let socket else { return }
        let token = generation
        writer = Task { [weak self] in
            do {
                while let event = await self?.next(token: token) {
                    let data = try JSONEncoder().encode(event)
                    guard let text = String(data: data, encoding: .utf8) else { throw Failure.configuration }
                    try await socket.send(.string(text))
                }
            } catch {
                var field: String?
                switch error {
                case DecodingError.typeMismatch(_, let c), DecodingError.valueNotFound(_, let c),
                     DecodingError.keyNotFound(_, let c), DecodingError.dataCorrupted(let c):
                    field = c.codingPath.map(\.stringValue).joined(separator: ".")
                default: break
                }
                await self?.failed(token: token, code: (error as NSError).code, field: field)
            }
            await self?.writerEnded(token: token)
        }
    }
    private func next(token: UUID) -> [String: RealtimeJSON]? {
        guard token == generation else { return nil }
        if !controls.isEmpty { return controls.removeFirst() }
        guard ready else { return nil }
        if let jpeg = image.next(audioSent: sentAudio, speechActive: speechActive) {
            return ["type": .string("input_image_buffer.append"), "image": .string(jpeg.base64EncodedString())]
        }
        guard let pcm = audio.next() else { return nil }
        sentAudio = true
        return ["type": .string("input_audio_buffer.append"), "audio": .string(pcm.base64EncodedString())]
    }
    private func writerEnded(token: UUID) {
        guard token == generation else { return }
        writer = nil
        if !controls.isEmpty || ready && (!audio.isEmpty || sentAudio && speechActive && !image.isEmpty) { drain() }
    }
}
