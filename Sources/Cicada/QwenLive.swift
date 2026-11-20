import Foundation

/// 千问实时翻译 (`qwen3.8-livetranslate-flash-realtime`, DashScope realtime WebSocket): the mic
/// streams in as 16 kHz mono PCM while the talk key is held, and the translated voice (24 kHz mono
/// PCM) and both texts stream back, so the room hears me while I am still talking instead of after
/// I let go. One session per press; `finish()` asks the server to translate what is left.
final class QwenLiveSession: @unchecked Sendable {
    static let model = "qwen3.8-livetranslate-flash-realtime"
    static let keyService = "dashscope"
    /// Beijing. A workspace host (`<id>.cn-beijing.maas.aliyuncs.com`) also works; the shared one needs no id.
    static let endpoint = URL(string: "wss://dashscope.aliyuncs.com/api-ws/v1/realtime?model=\(model)")!

    /// The translated voice as 24 kHz mono 16-bit PCM; ends after `session.finished`.
    let audio: AsyncThrowingStream<Data, Error>
    /// Called on the main actor with what was said and its translation so far.
    var onText: (@MainActor (_ source: String, _ translation: String) -> Void)?
    /// Called on the main actor when the session failed before any voice came back.
    var onFailed: (@MainActor (String) -> Void)?

    private let audioCont: AsyncThrowingStream<Data, Error>.Continuation
    private let task: URLSessionWebSocketTask
    private let lock = NSLock()
    private var ready = false
    private var closed = false
    private var gotAudio = false
    /// Audio said before `session.updated`, and the part of a 100 ms chunk not sent yet.
    private var pending = Data()
    private var sourceDone: [String] = []
    private var sourcePart = ""
    private var transDone: [String] = []
    private var transPart = ""

    struct Failure: Error, CustomStringConvertible { let description: String }

    /// Whose voice speaks the translation.
    enum Voice: Equatable {
        /// The service's own (Tina).
        case builtin
        /// Learned from the press as it goes (real-time cloning, no extra charge; voice "default").
        case live
        /// A voice made ahead from my recording (`QwenVoiceEnrollment`): mine from the first word.
        case custom(String)
    }

    init(key: String, target: String, voice: Voice) {
        var req = URLRequest(url: Self.endpoint)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        task = URLSession.shared.webSocketTask(with: req)
        (audio, audioCont) = AsyncThrowingStream<Data, Error>.makeStream()
        task.resume()
        // Server-side voice activity: a press is one stretch of talk, and pauses in it end a sentence.
        var session: [String: Any] = [
            "input_modalities": ["audio"],
            "output_modalities": ["text", "audio"],
            "audio": ["input": ["format": ["type": "pcm", "sample_rate": 16_000]]],
            "translation": ["language": Self.language(target)],
        ]
        let input: [String: Any] = ["format": ["type": "pcm", "sample_rate": 16_000]]
        switch voice {
        case .builtin: break
        case .live:
            // One speaker per press (me): learn the voice once.
            session["enable_voice_clone"] = true
            session["voice_clone_options"] = ["frequency": "once"]
            session["audio"] = ["input": input, "output": ["voice": "default"]]
        case .custom(let id):
            // The docs' example puts it at the top level, the field table under audio.output: both.
            session["enable_voice_clone"] = true
            session["voice_clone_options"] = ["frequency": "never"]
            session["voice"] = id
            session["audio"] = ["input": input, "output": ["voice": id]]
        }
        send(["type": "session.update", "session": session])
        receive()
        debugLog("qwen live: session opened → \(Self.language(target)), voice \(voice)")
    }

    /// The service's target codes are bare ("zh", "en"); ours carry a region ("zh-CN").
    static func language(_ code: String) -> String {
        String(code.split(separator: "-").first ?? Substring(code)).lowercased()
    }

    var texts: (source: String, translation: String) {
        lock.lock(); defer { lock.unlock() }
        return ((sourceDone + [sourcePart]).joined(), (transDone + [transPart]).filter { !$0.isEmpty }.joined(separator: " "))
    }

    /// Any thread: 16 kHz mono 16-bit samples from the mic, sent in 100 ms chunks.
    func append(_ samples: UnsafeBufferPointer<Int16>) {
        lock.lock()
        guard !closed else { lock.unlock(); return }
        for s in samples { withUnsafeBytes(of: s.littleEndian) { pending.append(contentsOf: $0) } }
        var chunks: [Data] = []
        if ready {
            while pending.count >= 3200 { chunks.append(pending.prefix(3200)); pending.removeFirst(3200) }
        }
        lock.unlock()
        for c in chunks { send(["type": "input_audio_buffer.append", "audio": c.base64EncodedString()]) }
    }

    /// The key was let go of: send what is left and ask for the last translation. The audio stream
    /// ends on `session.finished`, or after 10 s.
    func finish() {
        lock.lock()
        let rest = ready ? pending : Data()
        if ready { pending = Data() }
        closed = true
        lock.unlock()
        if !rest.isEmpty { send(["type": "input_audio_buffer.append", "audio": rest.base64EncodedString()]) }
        send(["type": "session.finish"])
        DispatchQueue.global().asyncAfter(deadline: .now() + 10) { [weak self] in self?.end(nil) }
    }

    func cancel() { end(nil) }

    private func send(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object), let s = String(data: data, encoding: .utf8) else { return }
        task.send(.string(s)) { [task] error in
            if let error { debugLog("qwen live: send failed \((task.response as? HTTPURLResponse).map { "HTTP \($0.statusCode)" } ?? error.localizedDescription)") }
        }
    }

    private func receive() {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                // A refused handshake reads only "bad server response": the status says why (401 = key).
                let status = (self.task.response as? HTTPURLResponse)?.statusCode
                self.end(Failure(description: status.map { "HTTP \($0)" } ?? error.localizedDescription))
            case .success(let message):
                var data: Data?
                switch message {
                case .string(let s): data = Data(s.utf8)
                case .data(let d): data = d
                @unknown default: break
                }
                if let data, let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { self.handle(event) }
                self.receive()
            }
        }
    }

    private func handle(_ e: [String: Any]) {
        let type = e["type"] as? String ?? ""
        switch type {
        case "session.updated":
            lock.lock()
            ready = true
            var chunks: [Data] = []
            while pending.count >= 3200 { chunks.append(pending.prefix(3200)); pending.removeFirst(3200) }
            // Let go of before the session was ready: the rest goes too, then finish follows it.
            if closed, !pending.isEmpty { chunks.append(pending); pending = Data() }
            let finishNow = closed
            lock.unlock()
            debugLog("qwen live: session ready")
            for c in chunks { send(["type": "input_audio_buffer.append", "audio": c.base64EncodedString()]) }
            if finishNow { send(["type": "session.finish"]) }
        case "conversation.item.input_audio_transcription.delta":
            update { $0.sourcePart += e["delta"] as? String ?? "" }
        case "conversation.item.input_audio_transcription.completed":
            update { s in
                let t = e["transcript"] as? String ?? s.sourcePart
                if !t.isEmpty { s.sourceDone.append(t) }
                s.sourcePart = ""
            }
        case "response.audio_transcript.delta", "response.text.delta":
            update { $0.transPart += e["delta"] as? String ?? "" }
        case "response.audio_transcript.done", "response.text.done":
            update { s in
                let t = (e["transcript"] as? String) ?? (e["text"] as? String) ?? s.transPart
                if !t.isEmpty { s.transDone.append(t) }
                s.transPart = ""
            }
        case "response.audio.delta":
            guard var pcm = (e["delta"] as? String).flatMap({ Data(base64Encoded: $0) }) else { return }
            pcm = Self.stripWAVHeader(pcm)
            lock.lock(); gotAudio = true; lock.unlock()
            audioCont.yield(pcm)
        case "session.finished":
            debugLog("qwen live: session finished")
            end(nil)
        case "error":
            let err = e["error"] as? [String: Any]
            let msg = (err?["message"] as? String) ?? (err?["code"] as? String) ?? "error"
            debugLog("qwen live: error \(msg)")
            end(Failure(description: msg))
        default:
            break
        }
    }

    /// The docs' example delta starts with a RIFF header; the quickstart plays deltas as raw PCM.
    /// Take the samples after the `data` chunk when a header is there.
    static func stripWAVHeader(_ d: Data) -> Data {
        guard d.count > 44, d.prefix(4) == Data("RIFF".utf8) else { return d }
        let bytes = [UInt8](d)
        var i = 12
        while i + 8 <= bytes.count {
            let size = Int(bytes[i + 4]) | Int(bytes[i + 5]) << 8 | Int(bytes[i + 6]) << 16 | Int(bytes[i + 7]) << 24
            if bytes[i..<i + 4].elementsEqual("data".utf8) { return d.subdata(in: (i + 8)..<min(bytes.count, i + 8 + size)) }
            i += 8 + size
        }
        return d
    }

    private func update(_ change: (QwenLiveSession) -> Void) {
        lock.lock(); change(self); lock.unlock()
        let t = texts
        let cb = onText
        DispatchQueue.main.async { MainActor.assumeIsolated { cb?(t.source, t.translation) } }
    }

    private var ended = false
    private func end(_ error: Error?) {
        lock.lock()
        guard !ended else { lock.unlock(); return }
        ended = true
        closed = true
        let silent = !gotAudio
        lock.unlock()
        if let error, silent {
            let cb = onFailed
            DispatchQueue.main.async { MainActor.assumeIsolated { cb?(String(describing: error)) } }
            audioCont.finish(throwing: error)
        } else {
            audioCont.finish()
        }
        task.cancel(with: .normalClosure, reason: nil)
    }
}

/// Makes a voice for 千问实时翻译 from my recording (`VoiceReference`, the clip Ming clones from),
/// so translations sound like me from the first word instead of after the service has heard me.
/// 0.01 元 per voice; the recording goes inline as a data URI (the docs ask for a public URL, but
/// DashScope takes the data too).
enum QwenVoiceEnrollment {
    static let endpoint = URL(string: "https://dashscope.aliyuncs.com/api/v1/services/audio/tts/customization")!

    /// The new voice's id, or why it failed.
    static func create(key: String, audioDataURI: String) async -> Result<String, QwenLiveSession.Failure> {
        let body: [String: Any] = ["model": "qwen-voice-enrollment", "input": [
            "action": "create", "target_model": QwenLiveSession.model,
            "preferred_name": "cicada", "audio": ["data": audioDataURI],
        ]]
        guard let reply = await post(key: key, body: body) else { return .failure(.init(description: L("连不上千问"))) }
        if let id = (reply["output"] as? [String: Any])?["voice"] as? String { return .success(id) }
        let msg = reply["message"] as? String ?? reply["code"] as? String ?? L("生成失败")
        return .failure(.init(description: msg))
    }

    /// Frees the service's quota; best effort.
    static func delete(key: String, voice: String) async {
        _ = await post(key: key, body: ["model": "qwen-voice-enrollment", "input": ["action": "delete", "voice": voice]])
    }

    private static func post(key: String, body: [String: Any]) async -> [String: Any]? {
        var req = URLRequest(url: endpoint, timeoutInterval: 60)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, resp) = try? await URLSession.shared.data(for: req) else { return nil }
        debugLog("qwen voice: \((body["input"] as? [String: Any])?["action"] ?? "") HTTP \((resp as? HTTPURLResponse)?.statusCode ?? 0)")
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
