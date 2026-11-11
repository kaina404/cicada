import Foundation

/// One inference at a time. User reading advances the script without cancelling its completion.
@MainActor
final class InterviewCoach: ObservableObject {
    enum State: String { case idle, setup, loading, ready, generating, failed }
    struct Paragraph: Identifiable {
        var id: String
        var output: CoachOutput
        var interrupted = false
    }
    typealias Stream = ([[String: Any]], String) -> AsyncThrowingStream<String, Error>
    @Published private(set) var state = State.idle
    @Published private(set) var current: Paragraph?
    @Published private(set) var paragraphs: [Paragraph] = []
    @Published private(set) var script = CoachScript(modelReading: true)
    @Published private(set) var readingFailed = false
    @Published private(set) var firstLatency: Double?
    @Published private(set) var firstSentenceLatency: Double?
    let gloss = AskGloss()
    let acoustic = CoachAudioWorker()
    let reading: CoachReading
    @Published private(set) var acousticReady = false
    private var acousticEndpoint: Double?
    private var acousticHoldUntil = -Double.infinity
    var onParagraph: ((Paragraph) -> Void)?
    var onEvent: ((CoachEvent) -> Void)?
    var onWillGenerate: (() -> Void)?
    private var task: Task<Void, Never>?
    private var prepare: (() async -> Bool)?
    private let stream: Stream
    var stage: InterviewStage = .general
    private var background = ""
    private var turns: [CoachTurn] = []
    private var seen: [String: String] = [:]
    private var drafts: [String: CoachTurn] = [:]
    private var lastSpeech: [String: String] = [:]
    private var frames: [CoachFrame] = []
    private var lastVoicedAt = -Double.infinity
    private var lastInterviewerAt = -Double.infinity
    private var lastInterviewerWords: [String] = []
    private var endpoint = Double.infinity
    private var dirty = false
    private var due = Double.infinity
    private var clock = 0.0
    private var revision = UUID()
    private var interviewerRevision = UUID()
    private var raw = ""
    private var generationStarted = Date()
    private var snapshotIDs: Set<String> = []
    private var speculative = false
    private var finishedSpeculation = false
    private var publishedCurrentAnswer = false
    private(set) var generationCount = 0
    private(set) var reviewCount = 0
    var responseID: String? { current?.id ?? paragraphs.last?.id }
    var frameCount: Int { frames.count }

    init(stream: Stream? = nil,
         readingInfer: @escaping CoachReading.Infer = CoachReading.infer) {
        let cloud = LingClient()
        self.stream = stream ?? { messages, model in
            CoachDeepSeekTest.enabled ? cloud.streamCoachTest(messages) : InterviewCoach.stream(messages, model)
        }
        reading = CoachReading(infer: readingInfer)
        acoustic.onEvent = { [weak self] event in self?.acousticEvent(event) }
        reading.onFailure = { [weak self] failed in self?.readingFailed = failed }
        reading.onProgress = { [weak self] id, through, transcript in
            guard let self, self.state != .idle, self.script.answerID == id else { return }
            let before = self.script.cursor
            self.script.advanceReading(to: through, answerID: id)
            if self.script.cursor > before { self.emit("readingProgress", text: transcript) }
        }
    }
    private func acousticEvent(_ event: CoachAudioWorker.Event) {
        if event.kind == "ready" { acousticReady = true; return }
        if event.kind == "unavailable" { acousticReady = false; return }
        guard let now = event.now, event.role == "interviewer", state != .idle else { return }
        if event.kind == "vad", event.voiced == true {
            lastVoicedAt = now; acousticEndpoint = nil
            endpoint = max(endpoint.isFinite ? endpoint : now, now + 0.45)
        }
        if event.kind == "endpoint" {
            if event.complete == true { acousticEndpoint = now; endpoint = now }
            else { acousticHoldUntil = now + 1.5; endpoint = max(endpoint, acousticHoldUntil) }
            emit(event.complete == true ? "semanticEnd" : "semanticHold")
        }
    }

    func start(background: String, available: Bool, prepare: @escaping () async -> Bool) {
        self.prepare = prepare
        if self.background != background {
            self.background = background
            if state != .idle { schedule(now: clock, delay: 0.3, cancel: true) }
        }
        guard state == .idle || state == .setup else { return }
        state = available ? .ready : .setup
        if available { acoustic.start() }
    }

    func speech(_ text: String, role: String, now: Double) {
        guard state != .idle, state != .setup, !text.isEmpty, lastSpeech[role] != text else { return }
        clock = now; lastSpeech[role] = text
        drafts[role] = CoachTurn(id: "draft-" + role, seconds: now, role: role, text: text)
        if role == "candidate" {
            // In the app this is the independent Gemma candidate transcript, shared with the record.
            return
        }
        acceptInterviewer(text, now: now)
    }
    func finalized(role: String) { drafts[role] = nil }

    func observe(lines: [TranscriptLine], now: Double) {
        guard state != .idle, state != .setup else { return }
        clock = now
        let spoken = CoachTurn.spoken(lines)
        let fresh = spoken.filter { seen[$0.id] != $0.text }
        turns = spoken
        for turn in fresh {
            let wasSeen = seen[turn.id] != nil
            seen[turn.id] = turn.text
            if turn.role == "candidate" {
                // Final ASR is the sole authority for committed content; revisions cannot rewrite it.
                guard !wasSeen else { continue }
                script.commit(id: turn.id, text: turn.text)
                emit("committed", text: turn.text)
            } else {
                // A final matching its draft confirms the endpoint without cancelling prepared text.
                if lastSpeech["interviewer"] != turn.text { acceptInterviewer(turn.text, now: now) }
                drafts["interviewer"] = nil
            }
        }
        // Keep bounded speech in the request, while complete originals live in SessionStore.
        turns = Array(turns.suffix(160))
    }

    private func acceptInterviewer(_ text: String, now: Double) {
        // A delayed copy of microphone speech is not a new interviewer turn.
        let words = CoachScript.words(text)
        guard !words.isEmpty else { return }
        // A line's timestamp is its start, not the arrival of its final ASR revision.
        // Long, hesitant reading and delayed channel copies routinely exceed 15 seconds.
        // Bound by candidate turns instead, including revisions and immutable first finals.
        let recent = turns.filter { $0.role == "candidate" }.suffix(8)
        let candidateTexts = recent.map(\.text) + script.committed.suffix(8).map(\.text)
            + [drafts["candidate"]?.text ?? ""]
        if words.count >= 4, candidateTexts.contains(where: {
            let other = CoachScript.words($0)
            let sharedPrefix = zip(words, other).prefix(while: { $0 == $1 }).count
            let extendsCandidate = sharedPrefix >= 6 &&
                Double(sharedPrefix) / Double(min(words.count, other.count)) >= 0.65
            return other == words || extendsCandidate || (words.count >= 8 && other.count >= 8 &&
                Double(Set(words).intersection(other).count) / Double(max(Set(words).count, Set(other).count)) >= 0.8)
        }) {
            emit("candidateEcho", text: text)
            return
        }
        // Draft/final punctuation and casing revisions do not change the question. In particular,
        // a late final must not cancel a useful answer that has already started streaming.
        guard words != lastInterviewerWords else { return }
        lastInterviewerWords = words
        interviewerRevision = UUID()
        lastInterviewerAt = now
        acousticEndpoint = nil
        endpoint = max(now + CoachEndpoint.delay(text), acousticHoldUntil)
        // Coalesce drafts. Once an answer is visible, finish it and review coverage before
        // touching the script; a new interviewer utterance alone cannot invalidate an answer.
        schedule(now: now, delay: 0.35, cancel: script.pending.isEmpty)
        emit("interviewerUpdate", text: text)
    }

    func appendAudio(_ pcm: Data, voiced: Bool, now: Double) {
        guard state != .idle, state != .setup else { return }
        clock = now
        // System PCM is only for turn detection; Apple transcripts feed answer generation.
        acoustic.send(pcm, role: "interviewer", now: now)
        if voiced {
            lastVoicedAt = now
            if !acousticReady, lastInterviewerAt.isFinite { endpoint = max(endpoint, now + 0.45) }
        }
    }

    func appendCandidateAudio(_ pcm: Data, voiced: Bool, now: Double) {
        guard state != .idle, state != .setup else { return }
        acoustic.send(pcm, role: "candidate", now: now)
        if !reading.usesTranscripts { reading.append(pcm, voiced: voiced, now: now) }
    }

    func picture(_ frame: CoachFrame) {
        guard state != .idle, state != .setup else { return }
        frames.append(frame); frames = Array(frames.suffix(3))
        // A selected page is context, not an interviewer request. OCR alone must not
        // start an answer before anyone asks; explicit screen-only analysis uses ask().
        if script.pending.isEmpty, current == nil,
           lastInterviewerAt.isFinite {
            dirty = true; due = max(clock + 0.3, lastInterviewerAt + 0.65)
        }
    }
    func clearPicture() {
        guard !frames.isEmpty else { return }
        // Reject in-flight results from the old screen, but never regenerate a reading script.
        frames = []
        if task != nil { invalidate(); dirty = false }
    }
    private func schedule(now: Double, delay: Double, cancel: Bool) {
        if cancel { invalidate() }
        dirty = true; due = now + delay
    }
    private func invalidate() {
        reading.pause()
        revision = UUID(); task?.cancel(); task = nil
        finish(interrupted: true)
        speculative = false; finishedSpeculation = false
        if state == .generating || state == .loading { state = .ready }
    }

    func tick(now: Double) {
        guard state != .idle, state != .setup else { return }
        clock = now
        acoustic.tick(now: now)
        if speculative, now >= endpoint {
            speculative = false; publish()
            if finishedSpeculation { finish(interrupted: false); state = .ready }
        }
        reading.tick(script: script, blocked: current != nil || (!CoachDeepSeekTest.enabled && (task != nil || dirty)), now: now)
        guard state == .ready, dirty, now >= due, task == nil else { return }
        guard now >= endpoint || !lastInterviewerAt.isFinite else { return }
        if script.pending.isEmpty { generate(speculate: false) }
        else { review() }
    }
    func ask() {
        guard state != .idle, state != .setup else { return }
        invalidate(); endpoint = clock; dirty = true; generate(speculate: false, refresh: true)
    }
    func retry() {
        if readingFailed { reading.retry() }
        guard state == .failed else { return }
        state = .ready
        if script.pending.isEmpty { ask() }
        else { dirty = true; due = clock; endpoint = clock }
    }
    private var evidence: [CoachTurn] {
        (turns + drafts.values.filter { draft in
            !turns.suffix(2).contains { $0.role == draft.role && $0.text == draft.text }
        }).sorted { $0.seconds < $1.seconds }
    }
    private func review() {
        let messages = CoachPrompt.reviewRequest(turns: evidence, background: background, frames: frames, script: script, stage: stage)
        let token = revision, input = interviewerRevision
        let committed = script.committed, cursor = script.cursor
        let started = Date()
        dirty = false; state = .generating; reviewCount += 1
        emit("review")
        task = Task { [weak self] in
            guard let self else { return }
            var replacing = false
            do {
                var response = ""
                var firstToken: Double?
                for try await piece in self.stream(messages, CoachPrompt.model) {
                    guard !Task.isCancelled, self.revision == token else { return }
                    if firstToken == nil { firstToken = Date().timeIntervalSince(started) }
                    response += piece
                    guard let update = try CoachReviewResponse.parse(response, finished: false),
                          update.decision.action == .replace, !update.answer.isEmpty else { continue }
                    if !replacing {
                        guard self.interviewerRevision == input else {
                            self.task = nil; self.state = .ready; self.emit("reviewSuperseded"); return
                        }
                        guard self.script.committed == committed, self.script.cursor == cursor else {
                            self.task = nil; self.state = .ready; self.dirty = true; self.due = self.clock
                            self.emit("reviewSuperseded"); return
                        }
                        replacing = true
                        self.reading.pause(); self.onWillGenerate?()
                        self.snapshotIDs = Set(self.script.committed.map(\.id))
                        self.publishedCurrentAnswer = false
                        self.speculative = false; self.finishedSpeculation = false
                        self.generationStarted = started
                        self.firstLatency = firstToken; self.firstSentenceLatency = nil
                        self.current = Paragraph(id: UUID().uuidString, output: CoachOutput(""))
                        self.generationCount += 1
                        self.emit("answerNeedsUpdate", text: update.decision.reason)
                        self.emit("generation")
                    }
                    self.raw = update.answer
                    self.current?.output = CoachOutput(update.answer)
                    self.current?.output.next = self.spokenAnswer(update.answer, finished: false)
                    self.publish()
                }
                guard !Task.isCancelled, self.revision == token else { return }
                self.task = nil; self.state = .ready
                if !replacing, self.interviewerRevision != input { self.emit("reviewSuperseded"); return }
                guard let update = try CoachReviewResponse.parse(response, finished: true) else {
                    throw URLError(.cannotParseResponse)
                }
                if update.decision.action == .keep {
                    self.emit("answerKept", text: update.decision.reason)
                } else {
                    guard replacing else {
                        self.dirty = true; self.due = self.clock; self.emit("reviewSuperseded"); return
                    }
                    self.current?.output = CoachOutput(update.answer)
                    self.current?.output.next = self.spokenAnswer(update.answer, finished: true)
                    self.publish(); self.finish(interrupted: false)
                    self.onEvent?(CoachEvent(kind: "latency", seconds: self.clock, answerID: self.script.answerID,
                        firstToken: self.firstLatency, firstSentence: self.firstSentenceLatency,
                        total: Date().timeIntervalSince(started)))
                }
            } catch {
                guard !Task.isCancelled, self.revision == token else { return }
                self.task = nil
                if replacing { self.finish(interrupted: true) }
                if self.interviewerRevision != input { self.state = .ready; return }
                self.state = .failed; self.emit("reviewFailure")
                debugLog("coach: answer update failed (\((error as NSError).code))")
            }
        }
    }

    private func generate(speculate: Bool, refresh: Bool = false) {
        let evidence = evidence
        // Background reloads can also schedule work before the first question.
        guard refresh || lastInterviewerAt.isFinite else { dirty = false; return }
        guard !evidence.isEmpty || !frames.isEmpty else { dirty = false; return }
        dirty = false; publishedCurrentAnswer = false
        onWillGenerate?()
        let token = revision
        let messages = CoachPrompt.request(turns: evidence, background: background, frames: frames, audio: nil, committed: script.spokenText, refresh: refresh, stage: stage)
        snapshotIDs = Set(script.committed.map(\.id))
        speculative = speculate; finishedSpeculation = false
        firstLatency = nil; firstSentenceLatency = nil
        let started = Date(); generationStarted = started
        state = .loading
        task = Task { [weak self] in
            guard let self else { return }
            guard await self.prepare?() == true else {
                guard !Task.isCancelled, self.revision == token else { return }
                self.state = .failed; self.task = nil; return
            }
            guard !Task.isCancelled, self.revision == token else { return }
            await CoachPronunciation.prepare()
            guard !Task.isCancelled, self.revision == token else { return }
            self.state = .generating; self.raw = ""
            self.current = Paragraph(id: UUID().uuidString, output: CoachOutput(""))
            self.generationCount += 1
            self.emit(speculate ? "speculation" : "generation")
            debugLog("coach: full answer turns=\(evidence.count) frames=\(self.frames.count) input=text_image speculative=\(speculate)")
            do {
                for try await piece in self.stream(messages, CoachPrompt.model) {
                    guard !Task.isCancelled, self.revision == token else { return }
                    if self.raw.isEmpty {
                        self.firstLatency = Date().timeIntervalSince(started)
                        debugLog("coach: pipeline_first_token_ms=\(Int((self.firstLatency ?? 0) * 1000)) provider=\(CoachDeepSeekTest.enabled ? "deepseek" : "local")")
                    }
                    self.raw += piece
                    self.current?.output = CoachOutput(self.raw)
                    if let answer = self.current?.output.next {
                        self.current?.output.next = self.spokenAnswer(answer, finished: false)
                    }
                    if !self.speculative { self.publish() }
                }
                guard !Task.isCancelled, self.revision == token else { return }
                guard !self.spokenAnswer(self.raw, finished: true).isEmpty else { throw URLError(.cannotParseResponse) }
                if self.current != nil {
                    self.current?.output = CoachOutput(self.raw)
                    self.current?.output.next = self.spokenAnswer(self.raw, finished: true)
                    if !self.speculative { self.publish() }
                }
                if self.speculative { self.finishedSpeculation = true }
                else { self.finish(interrupted: false); self.state = .ready }
                self.task = nil
                self.onEvent?(CoachEvent(kind: "latency", seconds: self.clock, answerID: self.script.answerID,
                    firstToken: self.firstLatency, firstSentence: self.firstSentenceLatency,
                    total: Date().timeIntervalSince(started)))
            } catch {
                guard !Task.isCancelled, self.revision == token else { return }
                self.finish(interrupted: true); self.state = .failed; self.task = nil
                self.emit("failure")
                debugLog("coach: answer inference failed (\((error as NSError).code))")
            }
        }
    }
    private func spokenAnswer(_ raw: String, finished: Bool) -> String {
        let answer = CoachOutput(raw).next
        let text = stage == .hr ? CoachHRAnswer.clean(answer, finished: finished) : answer
        return CoachPronunciation.annotate(text, finished: finished)
    }
    private func publish() {
        guard let current else { return }
        guard !current.output.next.isEmpty else { return }
        script.replacePending(current.output.next, since: snapshotIDs, newAnswer: !publishedCurrentAnswer)
        if !publishedCurrentAnswer { reading.begin(answerID: script.answerID) }
        publishedCurrentAnswer = true
        let sentences = script.sentences.filter { $0.last.map { ".!?".contains($0) } == true }
        gloss.enqueue(sentences)
        // Measure a usable, visible sentence, including speculative text held until the endpoint.
        if firstSentenceLatency == nil, let first = CoachScript.sentences(current.output.next).first,
           first.last.map({ ".!?".contains($0) }) == true {
            firstSentenceLatency = Date().timeIntervalSince(generationStarted)
            let end = lastVoicedAt.isFinite ? lastVoicedAt : lastInterviewerAt
            onEvent?(CoachEvent(kind: "visibleSentence", seconds: clock, answerID: script.answerID,
                firstToken: firstLatency, firstSentence: firstSentenceLatency,
                endpointToSentence: end.isFinite ? max(0, clock - end) : nil,
                transcriptToSentence: lastInterviewerAt.isFinite ? max(0, clock - lastInterviewerAt) : nil))
            debugLog(String(format: "coach: visible sentence inference=%.2fs since_text=%.2fs since_voice=%.2fs",
                            firstSentenceLatency ?? 0, lastInterviewerAt.isFinite ? max(0, clock - lastInterviewerAt) : -1,
                            end.isFinite ? max(0, clock - end) : -1))
        }
    }
    private func finish(interrupted: Bool) {
        guard var paragraph = current else { return }
        current = nil; raw = ""
        guard !paragraph.output.next.isEmpty, !speculative else { return }
        paragraph.interrupted = interrupted
        paragraphs.append(paragraph); paragraphs = Array(paragraphs.suffix(30))
        gloss.enqueue(script.sentences); onParagraph?(paragraph)
        emit(interrupted ? "cancelled" : "answer", text: paragraph.output.next)
    }
    private func emit(_ kind: String, text: String = "") {
        onEvent?(CoachEvent(kind: kind, seconds: clock, answerID: script.answerID, text: text))
    }
    func stop() {
        reading.stop()
        acoustic.stop(); acousticReady = false; acousticEndpoint = nil
        invalidate(); state = .idle; dirty = false; due = .infinity; endpoint = .infinity
        drafts = [:]; lastSpeech = [:]; frames = []; lastVoicedAt = -.infinity
        lastInterviewerAt = -.infinity
        lastInterviewerWords = []
    }
    func endMeeting() {
        stop(); turns = []; seen = [:]; paragraphs = []; current = nil; gloss.clear()
        script = CoachScript(modelReading: true); generationCount = 0; reviewCount = 0; firstLatency = nil; firstSentenceLatency = nil
    }

    nonisolated static func stream(_ messages: [[String: Any]], _ model: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let work = Task {
                do {
                    var request = URLRequest(url: VisionServer.base.appendingPathComponent("v1/chat/completions"), timeoutInterval: 120)
                    request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "messages": messages,
                        "stream": true, "temperature": 0, "max_tokens": 1600, "enable_thinking": false])
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let value = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        if value == "[DONE]" { break }
                        if let delta = AskPrompt.delta(value), !delta.isEmpty { continuation.yield(delta) }
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }
}
