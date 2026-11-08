import Foundation

/// 会中问答: a key (or 问 in the notes window) answers what was just asked in the meeting, from the
/// last five minutes of the transcript and the shared screen, with the local model that already reads the
/// screen (`VisionServer`, Gemma). Nothing leaves the Mac, so it doesn't go through `LingClient`,
/// which is for the AI services a key pays for. AppModel saves completed answers in the meeting.
@MainActor
final class AskEngine: ObservableObject {
    enum State: Equatable {
        case idle
        /// The model is being loaded (the first question of a meeting without 屏幕识别).
        case loading
        case answering
        case done
        case failed(String)
    }

    @Published private(set) var state = State.idle
    /// The question as the model understood it, which is often not what speech recognition heard.
    @Published private(set) var understood = ""
    @Published private(set) var points: [String] = []
    @Published private(set) var suggestions: [String] = []
    let gloss = AskGloss()

    private var task: Task<Void, Never>?
    private var omitNextImage = false

    var isBusy: Bool { state == .loading || state == .answering }

    /// A new question replaces the one being answered: it is the one the user wants now.
    func ask(_ prompt: AskPrompt.Request, model: String, server: VisionServer, onFirst: (() -> Void)? = nil, completion: ((AskPrompt.Reply, String) -> Void)? = nil) {
        task?.cancel()
        var prompt = prompt
        if omitNextImage {
            prompt.image = nil
            omitNextImage = false
            debugLog("ask: image omitted because previous first token exceeded 2s")
        }
        understood = ""
        points = []
        suggestions = []
        state = .answering
        let started = Date()
        task = Task { [weak self] in
            if !server.isRunning, !(await VisionServer.waitReady(seconds: 0)) {
                self?.state = .loading
                server.start(model: model)
            }
            // The first load reads the weights from disk; afterwards this answers at once.
            guard await VisionServer.waitReady(seconds: 90) else {
                if !Task.isCancelled { self?.state = .failed(L("本机模型没有启动")) }
                return
            }
            guard !Task.isCancelled else { return }
            self?.state = .answering
            var text = ""
            var first: Double?
            do {
                for try await piece in AskEngine.stream(prompt, model: model) {
                    guard !Task.isCancelled, let self else { return }
                    if first == nil {
                        first = Date().timeIntervalSince(started)
                        // Only an image makes the next one wait: a slow plan update is no reason to drop the screen.
                        self.omitNextImage = prompt.image != nil && AskPrompt.omitImageNextTime(first: first)
                        onFirst?()
                    }
                    text += piece
                    let parsed = AskPrompt.parse(text)
                    self.understood = parsed.understood
                    self.points = parsed.points
                    self.suggestions = parsed.suggestions
                    self.gloss.enqueue(AskPrompt.completeLines(text))
                }
            } catch {
                guard !Task.isCancelled else { return }
                debugLog("ask: failed \(error.localizedDescription)")
                self?.state = .failed(L("本机模型没有回答"))
                return
            }
            guard !Task.isCancelled, let self else { return }
            debugLog(String(format: "ask: answered first=%.2fs total=%.2fs understood=%@ points=%d image=%@ ctx=%d",
                            first ?? -1, Date().timeIntervalSince(started), self.understood, self.points.count, prompt.image?.size ?? "none", prompt.user.count))
            self.gloss.enqueue(AskPrompt.completeLines(text, finished: true))
            self.state = self.points.isEmpty && self.understood.isEmpty ? .failed(L("本机模型没有回答")) : .done
            completion?(AskPrompt.parse(text), text)
        }
    }

    func displayCompleted(_ reply: AskPrompt.Reply) {
        understood = reply.understood
        points = reply.points
        suggestions = reply.suggestions
    }

    /// Why there is no answer, in the card.
    func explain(_ why: String) {
        dismiss()
        state = .failed(why)
    }

    func dismiss() {
        task?.cancel()
        task = nil
        state = .idle
        understood = ""
        points = []
        suggestions = []
    }

    func endMeeting() {
        dismiss()
        omitNextImage = false
        gloss.clear()
    }

    /// The reply's text as it streams from mlx-vlm's OpenAI-style server (server-sent events).
    nonisolated static func stream(_ prompt: AskPrompt.Request, model: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let work = Task {
                let body: [String: Any] = [
                    "model": model, "stream": true, "temperature": 0, "max_tokens": 400, "enable_thinking": false,
                    "messages": prompt.messages,
                ]
                var req = URLRequest(url: VisionServer.base.appendingPathComponent("v1/chat/completions"), timeoutInterval: 60)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try? JSONSerialization.data(withJSONObject: body)
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: req)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let data = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if data == "[DONE]" { break }
                        if let piece = AskPrompt.delta(data), !piece.isEmpty { continuation.yield(piece) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }
}

/// What the model is told, and how its reply is read: pure, so the tests can pin both.
enum AskPrompt {
    struct Request: Equatable {
        var system: String
        var user: String
        var image: Image?

        var messages: [[String: Any]] {
            let content: Any
            if let image {
                content = [
                    ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(image.jpeg.base64EncodedString())"]],
                    ["type": "text", "text": user],
                ] as [[String: Any]]
            } else { content = user }
            return [["role": "system", "content": system], ["role": "user", "content": content]]
        }
    }

    struct Image: Equatable {
        var jpeg: Data
        var width: Int
        var height: Int
        var capturedAt: Date
        var size: String { "\(width)x\(height)" }
    }

    struct Answer: Equatable {
        var understood: String
        var points: [String]
    }

    static func history(_ lines: [TranscriptLine]) -> [Answer] {
        lines.filter(\.isAI).suffix(3).map {
            let reply = parse($0.src)
            return Answer(understood: reply.understood, points: reply.points)
        }
    }

    static func transcript(_ reply: Reply, translated: [String: String]? = nil) -> String? {
        let rows = [("Q: ", reply.understood)] + reply.points.map { ("- ", $0) } + reply.suggestions.map { ("> ", $0) }
        let present = rows.filter { !$0.1.isEmpty }
        guard !present.isEmpty else { return nil }
        if let translated {
            guard present.allSatisfy({ translated[$0.1] != nil }) else { return nil }
            return present.map { $0.0 + translated[$0.1]! }.joined(separator: "\n")
        }
        return present.map { $0.0 + $0.1 }.joined(separator: "\n")
    }

    static func recordTime(trigger: Double, last: Double?) -> Double { max(trigger, last ?? 0) }

    static func selectImage(enabled: Bool, latest: Image?, isSlide: Bool, page: Image?, now: Date) -> Image? {
        guard enabled else { return nil }
        if let latest, isSlide, (0...2).contains(now.timeIntervalSince(latest.capturedAt)) { return latest }
        if let page, (0...300).contains(now.timeIntervalSince(page.capturedAt)) { return page }
        return nil
    }

    static func omitImageNextTime(first: Double?) -> Bool { (first ?? 0) > 2 }

    static func isUncertain(_ point: String) -> Bool {
        let lower = point.lowercased()
        return ["不确定：", "不确定:", "uncertain:", "uncertain：", "不確か：", "不明：", "불확실:"].contains { lower.hasPrefix($0) }
    }

    /// How far back the background reaches, and what counts as "just asked".
    static let background: Double = 300
    static let speechLimit = 4000
    static let question: Double = 20

    /// The last five minutes of the meeting, split into what was said before and what was just asked.
    /// `partial` is the sentence still being recognized: the key is often pressed before it ends.
    static func request(lines: [TranscriptLine], now: Double, partial: String, topics: [String] = [], notes: MeetingNotes? = nil, previousAnswers: [Answer] = [], image: Image? = nil) -> Request {
        let spoken = lines.filter { $0.isSpoken && !$0.src.isEmpty }
        // The question: the other side's last lines within `question` seconds, at least their last one.
        var asked: [TranscriptLine] = []
        for line in spoken.reversed() {
            if line.speaker == "me" { if asked.isEmpty { continue } else { break } }
            if !asked.isEmpty, now - line.t > question { break }
            asked.insert(line, at: 0)
        }
        let askedIDs = Set(asked.map(\.id))
        // The window starts on a whole minute, so consecutive requests share their prefix for the
        // model server's cache; it still never reaches back more than `background`.
        let from = (ceil((now - background) / 60) * 60)
        // Notes, terms and pages first, speech last: speech grows at its end every few seconds, the notes
        // change about once a minute, so the model server's cache covers everything but the newest lines.
        var speech = spoken.filter { $0.t >= from && $0.t <= now && !askedIDs.contains($0.id) }.map {
            (minute: floor($0.t / 60), text: ($0.speaker == "me" ? "Me: " : "Them: ") + $0.src)
        }
        func size() -> Int { speech.reduce(0) { $0 + $1.text.count } + max(0, speech.count - 1) }
        // Over the limit, whole oldest minutes go first, so the start moves at most once a minute.
        while size() > speechLimit, let first = speech.first?.minute, speech.contains(where: { $0.minute != first }) {
            speech.removeAll { $0.minute == first }
        }
        while size() > speechLimit { speech.removeFirst() }
        var back: [String] = []
        if let notes {
            let summary = ([notes.summary] + notes.topics.suffix(3).map { $0.title + ": " + $0.summary }
                           + notes.conclusions.map(\.text)).filter { !$0.isEmpty }.joined(separator: "\n")
            if !summary.isEmpty { back.append("Notes: " + String(summary.prefix(800))) }
            let terms = notes.terms.map { $0.name + ($0.heard.isEmpty ? "" : " (heard: " + $0.heard.joined(separator: ", ") + ")") }
            if !terms.isEmpty { back.append("Terms: " + String(terms.joined(separator: "; ").prefix(800))) }
        } else if !topics.isEmpty { back.append("Topics so far: " + topics.suffix(6).joined(separator: "; ")) }
        // A clock time, not "n min ago", which would change the text every minute.
        for screen in lines.filter({ $0.isScreen && $0.t >= from && $0.t <= now }).suffix(3) {
            back.append(String(format: "Screen at %02d:%02d: ", Int(screen.t) / 60, Int(screen.t) % 60) + screenText(screen.src))
        }
        back += speech.map(\.text)
        var q = asked.map { "Them: " + $0.src }
        let tail = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty, !(asked.last?.src.hasSuffix(tail) ?? false) { q.append("Them: " + tail) }
        var user = "<background>\n\(back.joined(separator: "\n"))\n</background>\n<question>\n\(q.joined(separator: "\n"))\n</question>"
        if !previousAnswers.isEmpty {
            let history = previousAnswers.suffix(3).map {
                "Q: " + String($0.understood.prefix(300)) + "\n" + $0.points.prefix(3).map { "- " + String($0.prefix(400)) }.joined(separator: "\n")
            }.joined(separator: "\n")
            user += "\n<previous_answers>\n\(history)\n</previous_answers>"
        }
        return Request(system: Copilot.system, user: user, image: image)
    }

    /// Keep exact OCR alongside the meaning so image answers have a source for numbers.
    static func screenText(_ src: String) -> String {
        let rows = src.components(separatedBy: "\n")
        let meaning = rows.first { $0.hasPrefix("含义：") }
        let ocr = rows.first { $0.hasPrefix("原文：") }
        if let ocr {
            let lead = meaning.map { String($0.prefix(100)) + "\n" } ?? ""
            let room = 300 - lead.count
            if ocr.count <= room { return lead + ocr }
            // Browser chrome can precede the shared table: retain exact text at both ends.
            let head = min(50, room / 3)
            return lead + String(ocr.prefix(head)) + " … " + String(ocr.suffix(room - head - 3))
        }
        return String(src.prefix(300))
    }

    /// The reply so far: "Q: …" then "- …" points. Read again as each piece arrives, so a line
    /// still being written shows as it grows. Models number or star their points despite the
    /// format, and sometimes repeat the question's label in the notes' language.
    struct Reply: Equatable {
        var understood = ""
        var points: [String] = []
        var suggestions: [String] = []
    }

    /// Only terminated lines may be translated; flush the last line when generation finishes.
    static func completeLines(_ text: String, finished: Bool = false) -> [String] {
        var lines = text.components(separatedBy: "\n")
        if !finished { lines.removeLast() }
        let reply = parse(lines.joined(separator: "\n"))
        return ([reply.understood] + reply.points + reply.suggestions).filter { !$0.isEmpty }
    }

    static func parse(_ text: String) -> Reply {
        var understood = ""
        var points: [String] = []
        var suggestions: [String] = []
        for raw in text.components(separatedBy: "\n") {
            // Markdown bold around a label ("**Q:**") would hide it.
            let line = raw.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if let q = strip(line, labels: ["Q:", "Q：", "理解为：", "理解为:"]) {
                understood = q
            } else if let advice = strip(line, labels: ["> "]) {
                if suggestions.count < 2 { suggestions.append(advice) }
            } else if let p = point(line) {
                if points.count < 3 { points.append(p) }
            } else if understood.isEmpty, points.isEmpty {
                understood = line
            } else if !suggestions.isEmpty {
                suggestions[suggestions.count - 1] += " " + line
            } else if !points.isEmpty {
                // A point wrapped onto a second line.
                points[points.count - 1] += " " + line
            }
        }
        return Reply(understood: understood, points: points, suggestions: suggestions)
    }

    private static func strip(_ line: String, labels: [String]) -> String? {
        for label in labels where line.hasPrefix(label) {
            return line.dropFirst(label.count).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func point(_ line: String) -> String? {
        for mark in ["- ", "* ", "• ", "・"] where line.hasPrefix(mark) {
            return line.dropFirst(mark.count).trimmingCharacters(in: .whitespaces)
        }
        // "1." / "1、" / "1)"
        if let first = line.first, first.isNumber, line.count > 2 {
            let second = line[line.index(after: line.startIndex)]
            if [".", "、", ")", "）"].contains(second) {
                return line.dropFirst(2).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    /// One server-sent event's text, or nil for one without any (the role, the finish reason).
    static func delta(_ json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choice = (obj["choices"] as? [[String: Any]])?.first,
              let delta = choice["delta"] as? [String: Any] else { return nil }
        return delta["content"] as? String
    }
}
