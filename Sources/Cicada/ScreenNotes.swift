import AppKit
import Foundation
import ScreenCaptureKit
import Vision

/// 识别共享屏幕: numbers on a shared slide are often shown, not said. While listening, the meeting
/// window or display explicitly picked for this meeting is captured once a second; when
/// it turns to a new page and holds still, that page is read on the Mac (Vision for the exact text, a
/// local MLX model for what it means) and goes into the transcript as a "screen" line the notes read
/// like any other. OCR, page records and interview keyframes stay local.
@MainActor
final class ScreenWatch: ObservableObject {
    /// What this meeting captures and displays beside its notes.
    struct Target {
        var filter: SCContentFilter
        var label: String
        /// Window identity when available; nil for a display.
        var windowID: CGWindowID?
    }

    /// A new page was read: the line, and its screenshot (JPEG) to keep with the meeting.
    var onPage: ((_ secondsIn: Double, _ text: String, _ jpeg: Data) -> Void)?

    var onRealtimePage: ((Data) -> Void)?
    var onKeyframe: ((CoachFrame) -> Void)?
    var onKeyframesCleared: (() -> Void)?

    /// The pick belongs only to the current meeting; nil means no screen capture.
    @Published private(set) var meetingID: String?
    @Published private(set) var chosen: Target?
    /// The current selection and its latest thumbnail.
    @Published private(set) var current: String?
    @Published private(set) var preview: CGImage?
    @Published private(set) var isRunning = false
    @Published private(set) var previewUnavailable = false

    private let captureImage: @MainActor (SCContentFilter) async -> CGImage?
    private var previewInFlight = false
    private var pickerID: UUID?
    private var pickerObserver: PickerObserver?
    var onSelectionChanged: (() -> Void)?

    init(captureImage: @escaping @MainActor (SCContentFilter) async -> CGImage? = ScreenWatch.capture) {
        self.captureImage = captureImage
    }

    private var task: Task<Void, Never>?
    let server = VisionServer()
    /// A page is being read (one at a time), and the text of the last page that became a line.
    private var readTask: Task<Void, Never>?
    private var readID = UUID()
    private var runID = UUID()
    private var retryRead = false
    private var targetRevision = UUID()
    var isAsking: (() -> Bool)?
    private(set) var latestImage: AskPrompt.Image?
    private(set) var pageImage: AskPrompt.Image?
    private(set) var isSlide = false
    private(set) var captureCount = 0
    private var lastText = ""

    func beginMeeting(_ id: String) {
        endMeeting()
        meetingID = id
    }

    func endMeeting() {
        meetingID = nil
        clearSelection()
    }

    func start(startedAt: Date, model: String) {
        stop(clearPage: false)
        guard meetingID != nil, chosen != nil else { return }
        isRunning = true
        if !model.isEmpty { server.start(model: model) }
        task = Task { [weak self] in await self?.run(startedAt: startedAt, model: model) }
    }

    /// Leaves the model running: 会中问答 answers with it too. The app stops it when the meeting ends.
    func stop(clearPage: Bool = true) {
        task?.cancel()
        task = nil
        isRunning = false
        runID = UUID()
        interruptForQuestion()
        retryRead = false
        latestImage = nil
        onKeyframesCleared?()
        if clearPage { pageImage = nil }
        isSlide = false
    }

    /// Cancelling the owning task also cancels URLSession's in-flight local model request.
    func interruptForQuestion() {
        readID = UUID()
        if readTask != nil {
            retryRead = true
            debugLog("screen: read cancelled")
        }
        readTask?.cancel()
        readTask = nil
    }

    private func run(startedAt: Date, model: String) async {
        var watched: String?
        var watchedWindow: CGWindowID?
        var previous: [UInt8]?
        var steady = 0
        var failures = 0
        var lastRead: [UInt8]?
        let generation = runID
        var policy = ScreenReadPolicy()
        var keyframes = CoachKeyframePolicy()
        var frameRevision = targetRevision
        lastText = ""
        debugLog("screen: watching (model \(model))")
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, generation == runID else { return }
            guard meetingID != nil, let target = chosen else { return }
            if target.label != watched || target.windowID != watchedWindow {
                debugLog("screen: watching \(target.label)")
                watched = target.label
                watchedWindow = target.windowID
                current = target.label
                previous = nil
                lastRead = nil
                lastText = ""
                latestImage = nil
                isSlide = false
                interruptForQuestion()
                policy = ScreenReadPolicy()
                keyframes = CoachKeyframePolicy(); onKeyframesCleared?()
                steady = 0
            }
            let revision = targetRevision
            if frameRevision != revision {
                keyframes = CoachKeyframePolicy(); frameRevision = revision
            }
            captureCount += 1
            let image = await captureImage(target.filter)
            guard !Task.isCancelled, generation == runID, revision == targetRevision else { return }
            guard let image else {
                failures += 1
                preview = nil
                previewUnavailable = true
                latestImage = nil
                pageImage = nil
                onKeyframesCleared?()
                if failures >= 3 {
                    debugLog("screen: selected capture unavailable, stopped")
                    stop()
                    return
                }
                continue
            }
            failures = 0
            let at = Date()
            let prepared = await Task.detached(priority: .utility) {
                (Self.signature(image), Self.scaled(image, longSide: 640), Self.askImage(image, at: at))
            }.value
            guard !Task.isCancelled, generation == runID else { return }
            guard revision == targetRevision else { continue }
            let sig = prepared.0
            previewUnavailable = false
            preview = prepared.1
            latestImage = prepared.2
            let difference = previous.map { Self.difference($0, sig) } ?? 1
            if difference < 0.015 { steady += 1 } else { steady = 0 }
            previous = sig
            if onKeyframe != nil {
                let accepted = keyframes
                let result = await Task.detached(priority: .utility) { () -> (CoachKeyframePolicy, Data?, String) in
                    var policy = accepted
                    let ocr = Self.recognizeText(image)
                    let fingerprint = Self.coachSignature(image)
                    let changed = policy.accept(fingerprint: fingerprint, text: ocr, at: at.timeIntervalSinceReferenceDate)
                    return (policy, changed ? RealtimeMedia.jpeg(image) : nil, ocr)
                }.value
                guard !Task.isCancelled, generation == runID, revision == targetRevision else { continue }
                keyframes = result.0
                if let jpeg = result.1 {
                    onKeyframe?(CoachFrame(jpeg: jpeg, seconds: max(0, at.timeIntervalSince(startedAt)), ocr: result.2))
                    debugLog("coach: screen keyframe bytes=\(jpeg.count)")
                }
            }
            let trigger = policy.next(now: at.timeIntervalSinceReferenceDate, difference: retryRead ? 1 : difference, steady: steady,
                                      fromRead: lastRead.map { Self.difference($0, sig) } ?? 1,
                                      busy: isAsking?() ?? false, reading: readTask != nil)
            guard trigger != .none else { continue }
            if trigger == .fallback { debugLog("screen: fallback ocr") }
            retryRead = false
            lastRead = sig
            let secondsIn = max(0, at.timeIntervalSince(startedAt) - 1)
            let id = UUID()
            readID = id
            let previousText = lastText
            readTask = Task.detached(priority: .utility) { [weak self] in
                let ocr = Self.recognizeText(image)
                let eligible = ocr.filter { $0.isLetter || $0.isNumber }.count >= 20
                guard !Task.isCancelled else { return }
                await self?.classified(eligible, id: id)
                guard ScreenReadPolicy.shouldRead(ocr: ocr, previous: previousText), !Task.isCancelled else {
                    await self?.finish(nil, secondsIn: secondsIn, at: at, id: id)
                    return
                }
                if trigger == .fallback { debugLog("screen: fallback read") }
                let page = await Self.read(image, model: model, ocr: ocr)
                guard !Task.isCancelled else { return }
                if page == nil { await self?.classified(false, id: id) }
                await self?.finish(page, secondsIn: secondsIn, at: at, id: id)
            }
        }
    }

    private func classified(_ slide: Bool, id: UUID) {
        guard readID == id, isRunning else { return }
        isSlide = slide
    }

    private func finish(_ page: Page?, secondsIn: Double, at: Date, id: UUID) {
        guard readID == id, isRunning else { return }
        readTask = nil
        guard let page else { return }
        isSlide = true
        lastText = page.ocr
        pageImage = page.askImage
        pageImage?.capturedAt = at
        onPage?(secondsIn, page.line, page.jpeg)
        onRealtimePage?(page.jpeg)
    }

    /// Only the live meeting may request a preview; finishing invalidates any in-flight capture.
    func refreshPreview() async {
        guard meetingID != nil, let target = chosen, !isRunning, !previewInFlight else { return }
        previewInFlight = true
        defer { previewInFlight = false }
        let revision = targetRevision
        guard !Task.isCancelled, !isRunning, revision == targetRevision else { return }
        current = target.label
        captureCount += 1
        let image = await captureImage(target.filter)
        // A picker change or meeting start must not let an older capture replace the new target.
        guard !Task.isCancelled, !isRunning, revision == targetRevision else { return }
        preview = image.flatMap { Self.scaled($0, longSide: 640) }
        previewUnavailable = image == nil
    }

    // MARK: Picking a window or display

    /// The system's own picker, the one meeting apps show for sharing: any window or a whole display.
    func choose() {
        guard let meetingID else { return }
        closePicker()
        let picker = SCContentSharingPicker.shared
        var config = SCContentSharingPickerConfiguration()
        config.allowedPickerModes = [.singleWindow, .singleDisplay]
        if let me = Bundle.main.bundleIdentifier { config.excludedBundleIDs = [me] }
        picker.defaultConfiguration = config
        let id = UUID()
        let observer = PickerObserver(watch: self, meetingID: meetingID, pickerID: id)
        pickerID = id
        pickerObserver = observer
        picker.add(observer)
        picker.isActive = true
        picker.present()
    }

    func clearSelection() {
        closePicker()
        stop()
        invalidateImages()
        chosen = nil
        current = nil
        preview = nil
        onSelectionChanged?()
        debugLog("screen: selection cleared")
    }

    func picked(_ filter: SCContentFilter, meetingID: String, pickerID: UUID? = nil) {
        guard self.meetingID == meetingID, pickerID == nil || self.pickerID == pickerID else { return }
        closePicker()
        invalidateImages()
        chosen = Target(filter: filter, label: Self.label(filter), windowID: nil)
        current = chosen?.label
        preview = nil
        pageImage = nil
        onSelectionChanged?()
        debugLog("screen: picked \(chosen?.label ?? "")")
    }

    private func closePicker() {
        if let pickerObserver {
            SCContentSharingPicker.shared.remove(pickerObserver)
            SCContentSharingPicker.shared.isActive = false
        }
        pickerObserver = nil
        pickerID = nil
    }

    private func invalidateImages() {
        previewUnavailable = false
        targetRevision = UUID()
        onKeyframesCleared?()
        interruptForQuestion()
        retryRead = true
        latestImage = nil
        isSlide = false
        lastText = ""
    }

    fileprivate func pickEnded(meetingID: String, pickerID: UUID) {
        guard self.meetingID == meetingID, self.pickerID == pickerID else { return }
        closePicker()
    }

    static func label(_ filter: SCContentFilter) -> String {
        if #available(macOS 15.2, *) {
            if let w = filter.includedWindows.first {
                return [w.owningApplication?.applicationName, w.title].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
            }
            if let d = filter.includedDisplays.first { return L("显示器 \(Int(d.width))×\(Int(d.height))") }
        }
        return filter.style == .display ? L("整个显示器") : L("你选的窗口")
    }

    // MARK: Capturing the selected window or display

    /// Full resolution: small table text is lost when the window is scaled down.
    static func capture(_ filter: SCContentFilter) async -> CGImage? {
        let config = SCStreamConfiguration()
        config.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
        config.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
        config.showsCursor = false
        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    nonisolated static func scaled(_ image: CGImage, longSide: Int) -> CGImage? {
        let scale = min(1, Double(longSide) / Double(max(image.width, image.height)))
        let w = Int(Double(image.width) * scale), h = Int(Double(image.height) * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    // MARK: Page changes

    nonisolated static let side = 32

    /// A 32×32 grey thumbnail: enough to tell a new page from a moving cursor or a video tile.
    nonisolated static func signature(_ image: CGImage) -> [UInt8] {
        var px = [UInt8](repeating: 0, count: side * side)
        px.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        return px
    }

    /// A finer grid preserves localized code edits that disappear in a 32×32 page thumbnail.
    nonisolated static func coachSignature(_ image: CGImage) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: 128 * 72)
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: 128, height: 72, bitsPerComponent: 8,
                                          bytesPerRow: 128, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0) else { return }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: 128, height: 72))
        }
        return pixels
    }

    /// Mean difference, 0 (same) to 1.
    nonisolated static func difference(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 1 }
        let sum = zip(a, b).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
        return Double(sum) / Double(a.count) / 255
    }

    /// The same page read again (a video tile changed under it): not a new line.
    nonisolated static func novel(_ text: String, after last: String) -> Bool {
        let a = Set(text.split(whereSeparator: \.isWhitespace)), b = Set(last.split(whereSeparator: \.isWhitespace))
        guard !a.isEmpty else { return false }
        return Double(a.intersection(b).count) / Double(a.union(b).count) < 0.8
    }

    // MARK: Reading a page

    struct Page {
        var ocr: String
        var line: String
        var jpeg: Data
        var askImage: AskPrompt.Image?
    }

    /// nil when the window shows no page (people's video, the meeting app's controls).
    nonisolated static func read(_ image: CGImage, model: String, ocr supplied: String? = nil) async -> Page? {
        let started = Date()
        let ocr = supplied ?? recognizeText(image)
        // A video grid or a toolbar reads as a few names and buttons.
        guard ocr.filter({ $0.isLetter || $0.isNumber }).count >= 20 else { return nil }
        guard let jpeg = jpeg(image, longSide: 1600) else { return nil }
        let meaning = model.isEmpty ? nil : await explain(jpeg, ocr: ocr, model: model)
        if Task.isCancelled || meaning?.slide == false { return nil }
        let line = compose(ocr: ocr, meaning: meaning)
        debugLog("screen: page read in \(String(format: "%.1f", Date().timeIntervalSince(started))) s, \(ocr.count) chars, \(meaning == nil ? "text only" : "with meaning")")
        contentLog("SCREEN \(line)")
        return Page(ocr: ocr, line: line, jpeg: jpeg, askImage: askImage(image, at: started))
    }

    /// Vision, on the Mac: the exact text, row by row. Language correction stays off: it "fixes" numbers.
    nonisolated static func recognizeText(_ image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US", "zh-Hans", "zh-Hant", "ja-JP", "ko-KR"]
        try? VNImageRequestHandler(cgImage: image).perform([request])
        let boxes = (request.results ?? []).compactMap { o in o.topCandidates(1).first.map { (o.boundingBox, $0.string) } }
        return rows(boxes.map { (y: $0.0.midY, h: $0.0.height, x: $0.0.minX, text: $0.1) })
    }

    /// Text boxes into reading order: a row is the boxes whose middles are within half a line of each other.
    nonisolated static func rows(_ boxes: [(y: Double, h: Double, x: Double, text: String)]) -> String {
        var rows: [[(y: Double, h: Double, x: Double, text: String)]] = []
        for b in boxes.sorted(by: { $0.y > $1.y }) {
            if let last = rows.last?.first, abs(last.y - b.y) < max(last.h, b.h) / 2 {
                rows[rows.count - 1].append(b)
            } else {
                rows.append([b])
            }
        }
        return rows.map { $0.sorted { $0.x < $1.x }.map(\.text).joined(separator: "  ") }.joined(separator: "\n")
    }

    struct Meaning: Decodable {
        var slide: Bool?
        var title: String?
        var meaning: String?
        var uncertain: String?
    }

    /// The local model reads the page's structure; its numbers are checked against the OCR text.
    /// nil when the model server isn't there or never got ready: the line keeps the text alone.
    nonisolated static func explain(_ jpeg: Data, ocr: String, model: String) async -> Meaning? {
        // The first page of a meeting can come while the model is still loading.
        guard await VisionServer.waitReady(seconds: 90) else {
            debugLog("screen: model server not ready, text only")
            return nil
        }
        let language = Locale(identifier: "en").localizedString(forLanguageCode: Locale.preferredLanguages.first ?? "zh") ?? "Chinese"
        let prompt = """
        This screenshot is a page shared on screen in a meeting (a slide, table, chart or document), or just a meeting app's video and controls.
        Its text, read exactly by OCR, row by row:
        \(ocr.prefix(3000))

        Return JSON only: {"slide": false if it shows only people's video, a meeting app's controls or an empty desktop, else true,
         "title": "the page's title exactly as written, or null",
         "meaning": "1-3 sentences in \(language): what the page shows and its point; which number belongs to which item; the trend of any chart",
         "uncertain": "what you could not read or are unsure of, or null"}
        Rules: keep English technical terms and names as written. Use only numbers that appear in the OCR text and copy them exactly as written ($1.28M, (1,284), YoY +12.3%, +45 bps, Q3 FY26): never round, convert currencies or units (not $1.28M as 128万美元), or compute. If a chart has no number labels, give no numbers for it, only the trend.
        """
        let body: [String: Any] = [
            "model": model, "stream": false, "temperature": 0, "max_tokens": 500, "enable_thinking": false,
            "messages": [["role": "user", "content": [
                ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(jpeg.base64EncodedString())"]],
                ["type": "text", "text": prompt],
            ]]],
        ]
        var req = URLRequest(url: VisionServer.base.appendingPathComponent("v1/chat/completions"), timeoutInterval: 120)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let reply = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let content = ((reply["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String,
                  let meaning = parseMeaning(content) else {
                debugLog("screen: \(model) gave no usable answer (\((response as? HTTPURLResponse)?.statusCode ?? 0))")
                return nil
            }
            return meaning
        } catch {
            debugLog("screen: \(model) unreachable: \(error.localizedDescription)")
            return nil
        }
    }

    /// The reply's JSON object, also when the model wraps it in a ```json fence or a sentence.
    nonisolated static func parseMeaning(_ content: String) -> Meaning? {
        guard let open = content.firstIndex(of: "{"), let close = content.lastIndex(of: "}"), open < close else { return nil }
        return try? JSONDecoder().decode(Meaning.self, from: Data(content[open...close].utf8))
    }

    /// Numbers in the model's reading that the OCR text doesn't show: the model made them up or misread them.
    nonisolated static func unverified(_ text: String, ocr: String) -> [String] {
        func numbers(_ s: String) -> [String] {
            // Not the digits of a label like Q3 or FY26: those are words, and copied as they are.
            let re = try! NSRegularExpression(pattern: "(?<![A-Za-z\\d.,])\\d[\\d,.]*")
            return re.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { Range($0.range, in: s).map { String(s[$0]) } }
                .map { $0.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
        }
        let seen = Set(numbers(ocr))
        var out: [String] = []
        for n in numbers(text) where !seen.contains(n) && !out.contains(n) { out.append(n) }
        return out
    }

    /// The line the notes read: the model's reading first, then the exact text it must take numbers from.
    nonisolated static func compose(ocr: String, meaning: Meaning?) -> String {
        var parts: [String] = []
        if let m = meaning {
            let title = m.title.map { "《\($0)》" } ?? ""
            let text = m.meaning ?? ""
            if !(title + text).isEmpty { parts.append("含义：\(title)\(text)") }
            var unsure = m.uncertain.map { [$0] } ?? []
            let wrong = unverified(title + text, ocr: ocr)
            if !wrong.isEmpty { unsure.append("原文里没有 \(wrong.joined(separator: "、"))") }
            if !unsure.isEmpty { parts.append("不确定：\(unsure.joined(separator: "；"))") }
        }
        let flat = ocr.split(separator: "\n").joined(separator: " / ")
        parts.append("原文：\(flat.count > 1500 ? String(flat.prefix(1500)) + "…" : flat)")
        return parts.joined(separator: "\n")
    }

    nonisolated static func askImage(_ image: CGImage, at: Date) -> AskPrompt.Image? {
        guard let small = scaled(image, longSide: 1280),
              let data = NSBitmapImageRep(cgImage: small).representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { return nil }
        return AskPrompt.Image(jpeg: data, width: small.width, height: small.height, capturedAt: at)
    }

    nonisolated static func jpeg(_ image: CGImage, longSide: Int) -> Data? {
        guard let small = scaled(image, longSide: longSide) else { return nil }
        return NSBitmapImageRep(cgImage: small).representation(using: .jpeg, properties: [.compressionFactor: 0.8])
    }
}

/// mlx-vlm's server (`pip install mlx-vlm` into ~/.cicada-mlx), run by Cicada while it reads the
/// screen: the model stays loaded between pages, and its memory comes back when the meeting ends.
/// It listens on this Mac only: its own default would open it to the whole network.
@MainActor
final class VisionServer {
    nonisolated static let port = 18765
    nonisolated static let base = URL(string: "http://127.0.0.1:\(port)")!
    nonisolated static let executable = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".cicada-mlx/bin/mlx_vlm.server")
    nonisolated static let log = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cicada-mlx.log")

    private var process: Process?

    var isRunning: Bool { process?.isRunning == true }

    /// mlx-vlm is installed and a model is named: 会中问答 and the screen's meaning can work.
    nonisolated static func available(model: String) -> Bool {
        !model.isEmpty && FileManager.default.isExecutableFile(atPath: executable.path)
    }

    func start(model: String) {
        guard process?.isRunning != true else { return }
        guard FileManager.default.isExecutableFile(atPath: Self.executable.path) else {
            debugLog("screen: no mlx-vlm at \(Self.executable.path), text only")
            return
        }
        let p = Process()
        p.executableURL = Self.executable
        p.arguments = ["--model", model, "--host", "127.0.0.1", "--port", "\(Self.port)"]
        // Prefix caching in memory only: assistant tasks share the meeting's prefix, and meeting
        // content must never be written to the server's disk cache.
        var env = ProcessInfo.processInfo.environment
        env["APC_ENABLED"] = "1"
        env["APC_DISK_ENABLED"] = "0"
        env["APC_MEMORY_MAX_GB"] = "2"
        // Gemma's sliding-window layers resume only from checkpoints: at the default 2048 tokens a
        // 1.4k-token request reused just the system prompt (first token 1.27s); every 256 tokens it
        // reuses the meeting background too (0.68s, measured on Gemma 4 E4B, M4 Pro).
        env["APC_CHECKPOINT_INTERVAL_TOKENS"] = "256"
        env["APC_CHECKPOINT_ENTRIES"] = "8"
        p.environment = env
        FileManager.default.createFile(atPath: Self.log.path, contents: nil)
        let out = try? FileHandle(forWritingTo: Self.log)
        p.standardOutput = out
        p.standardError = out
        do {
            try p.run()
            process = p
            debugLog("screen: started mlx-vlm \(model) (pid \(p.processIdentifier), log \(Self.log.path))")
        } catch {
            debugLog("screen: mlx-vlm didn't start: \(error.localizedDescription)")
        }
    }

    func stop() {
        guard let p = process else { return }
        process = nil
        if p.isRunning { p.terminate() }
    }

    /// Up and its model loaded; polled while a meeting's first page waits for it.
    nonisolated static func waitReady(seconds: Double) async -> Bool {
        let until = Date().addingTimeInterval(seconds)
        repeat {
            var req = URLRequest(url: base.appendingPathComponent("health"), timeoutInterval: 2)
            req.httpMethod = "GET"
            if let (data, response) = try? await URLSession.shared.data(for: req), (response as? HTTPURLResponse)?.statusCode == 200,
               let health = try? JSONSerialization.jsonObject(with: data) as? [String: Any], health["loaded_model"] is String {
                return true
            }
            guard Date() < until, !Task.isCancelled else { return false }
            try? await Task.sleep(for: .seconds(2))
        } while Date() < until && !Task.isCancelled
        return false
    }
}

/// The system picker reports on any thread; the watch hears it on the main one.
private final class PickerObserver: NSObject, SCContentSharingPickerObserver {
    weak var watch: ScreenWatch?
    let meetingID: String
    let pickerID: UUID
    init(watch: ScreenWatch, meetingID: String, pickerID: UUID) {
        self.watch = watch
        self.meetingID = meetingID
        self.pickerID = pickerID
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        Task { @MainActor in self.watch?.picked(filter, meetingID: self.meetingID, pickerID: self.pickerID) }
    }
    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor in self.watch?.pickEnded(meetingID: self.meetingID, pickerID: self.pickerID) }
    }
    func contentSharingPickerStartDidFailWithError(_ error: any Error) {
        debugLog("screen: picker failed \(error.localizedDescription)")
        Task { @MainActor in self.watch?.pickEnded(meetingID: self.meetingID, pickerID: self.pickerID) }
    }
}

/// Cheap detection keeps checking moving screens without monopolizing the shared model.
struct ScreenReadPolicy {
    enum Trigger { case none, stable, fallback }
    private var lastCheck: Double?
    private var changed = false

    mutating func next(now: Double, difference: Double, steady: Int, fromRead: Double,
                       busy: Bool, reading: Bool) -> Trigger {
        if lastCheck == nil { lastCheck = now }
        if difference > 0.015 { changed = true }
        guard !busy, !reading else { return .none }
        let trigger: Trigger
        if steady == 1 && fromRead > 0.06 { trigger = .stable }
        else if now - (lastCheck ?? now) >= 5 && changed { trigger = .fallback }
        else { return .none }
        lastCheck = now
        changed = false
        return trigger
    }

    static func shouldRead(ocr: String, previous: String) -> Bool {
        ocr.filter { $0.isLetter || $0.isNumber }.count >= 20 && ScreenWatch.novel(ocr, after: previous)
    }
}
