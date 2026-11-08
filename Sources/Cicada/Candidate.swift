import Foundation
import ImageIO

@MainActor
final class CandidateEngine: ObservableObject {
    enum State: String { case idle, setup, room, connecting, ready, reconnecting, failed }
    struct Paragraph: Identifiable {
        var id: String
        var output: CandidateOutput
        var interrupted = false
    }
    @Published private(set) var state = State.idle
    @Published private(set) var failureCode: String?
    @Published private(set) var current: Paragraph?
    @Published private(set) var paragraphs: [Paragraph] = []
    @Published private(set) var firstLatency: Double?
    @Published private(set) var inputTokens = 0
    @Published private(set) var outputTokens = 0
    let gloss = AskGloss()
    var onParagraph: ((Paragraph) -> Void)?
    private(set) var loop = CandidateLoop()
    private var history = CandidateHistory()
    private var client = RealtimeClient()
    private var task: Task<Void, Never>?
    private var config: RealtimeConfiguration?
    private var prompt = ""
    private var key = ""
    private var retired: Set<String> = []
    private var raw = ""
    private var epoch = UUID()
    private var connectedAt = 0.0
    private var speechStoppedAt: Double?
    private var imageGate = RealtimeImageGate()
    private var imageTask: Task<Void, Never>?
    private var hasAudio = false
    private var pendingPicture: Data?
    private var lastPicture: Data?
    private var askWhenReady: String?
    private var requestWhenReady = false
    private var now: Double { ProcessInfo.processInfo.systemUptime }
    var connected: Bool { state == .ready }
    var responseID: String? { loop.active }

    func start(config: RealtimeConfiguration, key: String?, background: String, roomOnly: Bool, delay: Double, maxContinues: Int) {
        guard !roomOnly else { if state != .room { stop(); state = .room }; return }
        guard let key, !key.isEmpty, config.url != nil else { if state != .setup { stop(); state = .setup }; return }
        let prompt = CandidatePrompt.make(background: background)
        guard self.config != config || self.prompt != prompt || self.key != key || state == .idle || state == .setup || state == .room else { return }
        stop()
        self.config = config; self.key = key; self.prompt = prompt
        loop.delay = delay; loop.maxContinues = maxContinues
        connect()
    }
    private func connect() {
        guard let config else { return }
        let token = epoch
        state = .connecting; failureCode = nil
        task = Task { [weak self] in
            var attempt = 0
            while attempt <= 5 {
                guard let self, !Task.isCancelled, self.epoch == token else { return }
                if attempt > 0 {
                    self.state = .reconnecting
                    do { try await Task.sleep(for: .seconds(min(8, pow(2, Double(attempt - 1))))) } catch { return }
                }
                self.connectedAt = 0
                do {
                    let events = try await self.client.open(config, key: self.key, prompt: self.prompt,
                                                            context: self.history.interviewer.isEmpty && self.history.candidate.isEmpty ? nil : self.history.context)
                    for try await event in events {
                        guard !Task.isCancelled, self.epoch == token else { return }
                        self.receive(event)
                    }
                } catch {
                    guard !Task.isCancelled, self.epoch == token else { return }
                    let reason: String
                    if case RealtimeClient.Failure.rejected(let code) = error { reason = code; self.failureCode = code }
                    else if case RealtimeClient.Failure.transport(let code, let status) = error { reason = "transport_\(code)_http_\(status)" }
                    else if case RealtimeClient.Failure.protocolField = error { reason = "decode_field" }
                    else { reason = "transport" }
                    debugLog("assistant: connection failed attempt=\(attempt) code=\(reason)")
                    if let failure = error as? RealtimeClient.Failure, !failure.retryable {
                        self.finish(interrupted: true); self.loop.cancel(); break
                    }
                }
                guard !Task.isCancelled, self.epoch == token else { return }
                self.finish(interrupted: true)
                self.loop.cancel()
                attempt = self.connectedAt > 0 && self.now - self.connectedAt > 30 ? 1 : attempt + 1
            }
            guard let self, self.epoch == token else { return }
            await self.client.close()
            self.state = .failed; self.task = nil
        }
    }
    func reconnectForTesting() {
        guard connected else { return }
        let client = client
        Task { await client.close(clearAudio: false) }
    }
    func retry() {
        guard state == .failed else { return }
        epoch = UUID(); connect()
    }
    func stop() {
        epoch = UUID(); task?.cancel(); task = nil
        imageTask?.cancel(); imageTask = nil
        finish(interrupted: true)
        loop.cancel(); loop = CandidateLoop(); retired = []
        hasAudio = false; pendingPicture = nil; lastPicture = nil; imageGate = RealtimeImageGate()
        requestWhenReady = false; askWhenReady = nil
        // Queue the close before a subsequent open/append, without leaving an unowned close task.
        let previous = client; client = RealtimeClient()
        Task { await previous.close() }
        state = .idle; failureCode = nil
    }
    func endMeeting() {
        stop(); paragraphs = []; current = nil; history = CandidateHistory()
        gloss.clear(); firstLatency = nil; inputTokens = 0; outputTokens = 0
        config = nil; prompt = ""; key = ""
    }
    func append(_ pcm: Data) async {
        guard task != nil, state != .failed else { return }
        hasAudio = true
        await client.append(pcm)
        if connected, let picture = pendingPicture { pendingPicture = nil; self.picture(picture) }
    }
    func picture(_ jpeg: Data) {
        lastPicture = jpeg
        guard task != nil, state != .failed else { return }
        guard connected, hasAudio else { pendingPicture = jpeg; return }
        guard imageTask == nil else { pendingPicture = jpeg; return }
        let token = epoch
        imageTask = Task { [weak self] in
            let prepared = await Task.detached(priority: .utility) { () -> (Data, [UInt8])? in
                guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                      let data = RealtimeMedia.jpeg(image) else { return nil }
                return (data, ScreenWatch.signature(image))
            }.value
            guard let self, self.epoch == token, !Task.isCancelled else { return }
            self.imageTask = nil
            guard let (data, signature) = prepared, self.imageGate.allow(signature: signature, now: self.now, audioSent: self.hasAudio, slide: true) else { return }
            await self.client.picture(data)
            debugLog("assistant: image queued bytes=\(data.count)")
        }
    }
    func clearPicture() {
        imageTask?.cancel(); imageTask = nil; pendingPicture = nil; lastPicture = nil
        let client = client
        Task { await client.clearPicture() }
    }
    func ask(_ text: String? = nil) {
        guard connected else { requestWhenReady = true; askWhenReady = text; return }
        if let id = loop.active { retired.insert(id) }
        finish(interrupted: true); loop.cancel()
        let client = client
        Task {
            await client.send(["type": .string("response.cancel")])
            if let text, !text.isEmpty { await client.send(RealtimeConfiguration.text(text)) }
            await client.send(RealtimeConfiguration.create())
        }
    }
    func tick() {
        gloss.enqueue(paragraphs.suffix(1).map { $0.output.text })
        if connected, now - connectedAt >= 118 * 60 {
            // The documented limit is 120 min; rotate before it with bounded history and buffered audio.
            task?.cancel(); epoch = UUID(); finish(interrupted: true); loop.cancel(); connect()
        }
        guard connected, loop.tick(now: now) else { return }
        let client = client; let prompt = prompt
        Task { await client.send(RealtimeConfiguration.create(continuing: true, prompt: prompt)) }
    }
    func receive(_ event: RealtimeEvent) {
        switch event.type {
        case "session.updated":
            connectedAt = now; state = .ready; retired = []
            imageGate = RealtimeImageGate(); pendingPicture = lastPicture
            debugLog("assistant: ready recovery_chars=\(history.context.count)")
            if requestWhenReady { let text = askWhenReady; requestWhenReady = false; askWhenReady = nil; ask(text) }
        case "input_audio_buffer.speech_started":
            let interruptedAt = now
            speechStoppedAt = nil
            let id = loop.speechStarted()
            if let id { retired.insert(id) }
            finish(interrupted: true)
            let client = client
            Task { await client.send(["type": .string("response.cancel")]) }
            debugLog("assistant: interrupted active=\(id == nil ? 0 : 1) at=\(interruptedAt) stop_ms=\(Int((now - interruptedAt) * 1000))")
        case "input_audio_buffer.speech_stopped": loop.speechStopped(); speechStoppedAt = now
        case "conversation.item.input_audio_transcription.completed":
            if let text = event.transcript { history.heard(text) }
        case "response.created":
            guard !event.id.isEmpty, !retired.contains(event.id) else { return }
            guard !loop.speaking else {
                retired.insert(event.id)
                let client = client
                Task { await client.send(["type": .string("response.cancel")]) }
                return
            }
            finish(interrupted: true)
            loop.responseStarted(event.id); raw = ""
            current = Paragraph(id: event.id, output: CandidateOutput(""))
        case "response.text.delta", "response.audio_transcript.delta":
            guard loop.accepts(event.id), let delta = event.delta else { return }
            if raw.isEmpty, let at = speechStoppedAt {
                firstLatency = now - at; speechStoppedAt = nil
                debugLog("assistant: first_ms=\(Int((firstLatency ?? 0) * 1000)) first_at=\(now)")
            }
            raw += delta; current?.output = CandidateOutput(raw)
        case "response.done":
            // Usage includes cancelled replies too, but no old response can change the visible paragraph.
            if case .number(let n) = event.response?.usage?["input_tokens"] { inputTokens += Int(n) }
            if case .number(let n) = event.response?.usage?["output_tokens"] { outputTokens += Int(n) }
            if case .object(let detail) = event.response?.usage?["input_tokens_details"],
               case .number(let tokens) = detail["video_tokens"], tokens > 0 {
                debugLog("assistant: image_input_tokens=\(Int(tokens))")
            }
            guard loop.accepts(event.id) else { return }
            let completed = event.response?.status == "completed"
            let marker = completed ? CandidateOutput(raw).marker : .end
            current?.output = CandidateOutput(raw, finished: true)
            finish(interrupted: !completed)
            loop.responseDone(marker, now: now)
        default: break // Audio is never played or routed to SpeakEngine.
        }
    }
    private func finish(interrupted: Bool) {
        guard var paragraph = current else { return }
        paragraph.output = CandidateOutput(raw, finished: true)
        current = nil; raw = ""
        guard !paragraph.output.text.isEmpty else { return }
        if interrupted { retired.insert(paragraph.id) }
        paragraph.interrupted = interrupted
        paragraphs.append(paragraph); paragraphs = Array(paragraphs.suffix(30))
        history.answered(paragraph.output.text)
        gloss.enqueue([paragraph.output.text]); onParagraph?(paragraph)
        debugLog("assistant: paragraph chars=\(paragraph.output.text.count) interrupted=\(interrupted)")
    }
}
