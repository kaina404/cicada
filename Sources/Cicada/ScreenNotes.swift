import AppKit
import Foundation
import ScreenCaptureKit
import Vision

/// 识别共享屏幕: numbers on a shared slide are often shown, not said. While listening, the meeting
/// app's window (or the window or display picked in 设置 › 屏幕识别) is captured once a second; when
/// it turns to a new page and holds still, that page is read on the Mac (Vision for the exact text, a
/// local MLX model for what it means) and goes into the transcript as a "screen" line the notes read
/// like any other. Nothing leaves the Mac.
@MainActor
final class ScreenWatch: ObservableObject {
    /// What is captured: a window or display, and how the settings page names it.
    struct Target {
        var filter: SCContentFilter
        var label: String
        /// The window found by itself; nil for the user's pick.
        var windowID: CGWindowID?
    }

    /// A new page was read: the line, and its screenshot (JPEG) to keep with the meeting.
    var onPage: ((_ secondsIn: Double, _ text: String, _ jpeg: Data) -> Void)?

    /// The user's pick, until the app quits or the window closes; nil = find the meeting window.
    @Published private(set) var chosen: Target?
    /// What is watched now (the pick or the window found), and its latest frame, small, for the preview.
    @Published private(set) var current: String?
    @Published private(set) var preview: CGImage?
    @Published private(set) var isRunning = false

    private var task: Task<Void, Never>?
    let server = VisionServer()
    private lazy var pickerObserver = PickerObserver(watch: self)
    /// A page is being read (one at a time), and the text of the last page that became a line.
    private var reading = false
    private var lastText = ""

    /// A pick works without the Screen Recording permission (the system picker grants it);
    /// finding the meeting window by itself needs it.
    var needsPermission: Bool { chosen == nil && !CGPreflightScreenCaptureAccess() }

    func start(startedAt: Date, model: String) {
        stop()
        if needsPermission {
            // Asking opens System Settings once; capture starts with the next meeting.
            CGRequestScreenCaptureAccess()
            debugLog("screen: no screen recording permission, asked")
            return
        }
        isRunning = true
        if !model.isEmpty { server.start(model: model) }
        task = Task { [weak self] in await self?.run(startedAt: startedAt, model: model) }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
        server.stop()
    }

    private func run(startedAt: Date, model: String) async {
        var auto: Target?
        var lastLook = Date.distantPast
        var watched: String?
        var previous: [UInt8]?
        var steady = 0
        var failures = 0
        var lastRead: [UInt8]?
        reading = false
        lastText = ""
        debugLog("screen: watching (model \(model))")
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            // The meeting window can open, close or move to another app mid-meeting: look again every 10 s.
            if chosen == nil, auto == nil || Date().timeIntervalSince(lastLook) > 10 {
                lastLook = Date()
                let found = await Self.meetingTarget()
                if found?.windowID != auto?.windowID { auto = found }
            }
            guard let target = chosen ?? auto else { current = nil; continue }
            if target.label != watched {
                debugLog("screen: watching \(target.label)")
                watched = target.label
                current = target.label
                previous = nil
                steady = 0
            }
            guard let image = await Self.capture(target.filter) else {
                // The picked window closed: back to finding the meeting window.
                failures += 1
                if failures >= 3, chosen != nil {
                    debugLog("screen: the picked \(target.label) is gone, finding the meeting window")
                    chosen = nil
                }
                continue
            }
            failures = 0
            preview = Self.scaled(image, longSide: 640)
            let at = Date()
            let sig = Self.signature(image)
            if let p = previous, Self.difference(p, sig) < 0.015 { steady += 1 } else { steady = 0 }
            previous = sig
            // A page counts once it has held still for a second, and only if it differs from the last one read.
            guard steady == 1, !reading, lastRead.map({ Self.difference($0, sig) > 0.06 }) ?? true else { continue }
            lastRead = sig
            reading = true
            let secondsIn = max(0, at.timeIntervalSince(startedAt) - 1)
            Task.detached(priority: .utility) { [weak self] in
                let page = await Self.read(image, model: model)
                await self?.finish(page, secondsIn: secondsIn)
            }
        }
    }

    private func finish(_ page: Page?, secondsIn: Double) {
        reading = false
        guard isRunning, let page, Self.novel(page.ocr, after: lastText) else { return }
        lastText = page.ocr
        onPage?(secondsIn, page.line, page.jpeg)
    }

    /// The settings page's preview outside a meeting (in one, the watch keeps it fresh).
    func refreshPreview() async {
        guard !isRunning else { return }
        let target: Target? = if let chosen { chosen } else if CGPreflightScreenCaptureAccess() { await Self.meetingTarget() } else { nil }
        current = target?.label
        if let target, let image = await Self.capture(target.filter) { preview = Self.scaled(image, longSide: 640) } else { preview = nil }
    }

    // MARK: Picking a window or display

    /// The system's own picker, the one meeting apps show for sharing: any window or a whole display.
    func choose() {
        let picker = SCContentSharingPicker.shared
        var config = SCContentSharingPickerConfiguration()
        config.allowedPickerModes = [.singleWindow, .singleDisplay]
        if let me = Bundle.main.bundleIdentifier { config.excludedBundleIDs = [me] }
        picker.defaultConfiguration = config
        picker.add(pickerObserver)
        picker.isActive = true
        picker.present()
    }

    func useAutomatic() {
        chosen = nil
        current = nil
        preview = nil
        debugLog("screen: back to finding the meeting window")
    }

    fileprivate func picked(_ filter: SCContentFilter) {
        SCContentSharingPicker.shared.isActive = false
        chosen = Target(filter: filter, label: Self.label(filter), windowID: nil)
        preview = nil
        debugLog("screen: picked \(chosen!.label)")
    }

    fileprivate func pickEnded() { SCContentSharingPicker.shared.isActive = false }

    static func label(_ filter: SCContentFilter) -> String {
        if #available(macOS 15.2, *) {
            if let w = filter.includedWindows.first {
                return [w.owningApplication?.applicationName, w.title].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
            }
            if let d = filter.includedDisplays.first { return L("显示器 \(Int(d.width))×\(Int(d.height))") }
        }
        return filter.style == .display ? L("整个显示器") : L("你选的窗口")
    }

    // MARK: Finding and capturing the meeting window

    /// Meeting apps, and browsers when the tab is a meeting (by its title).
    static let apps: Set<String> = ["us.zoom.xos", "com.tencent.meeting", "com.tencent.tencentmeeting",
                                    "com.microsoft.teams2", "com.microsoft.teams", "com.electron.lark",
                                    "com.bytedance.macos.feishu", "com.alibaba.DingTalkMac", "Cisco-Systems.Spark",
                                    "com.cisco.webexmeetingsapp", "com.tencent.WeWorkMac"]
    static let browsers: Set<String> = ["com.google.Chrome", "com.apple.Safari", "com.microsoft.edgemac",
                                        "company.thebrowser.Browser", "org.mozilla.firefox", "com.brave.Browser"]
    static let meetingTitles = ["Meet -", "Google Meet", "meet.google.com", "Zoom", "Teams", "腾讯会议", "飞书会议", "Webex"]

    /// The largest meeting window on screen.
    static func meetingTarget() async -> Target? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) else { return nil }
        let w = content.windows.filter { w in
            guard w.frame.width >= 480, w.frame.height >= 320, let id = w.owningApplication?.bundleIdentifier else { return false }
            if apps.contains(id) { return true }
            let title = w.title ?? ""
            return browsers.contains(id) && meetingTitles.contains { title.contains($0) }
        }.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
        guard let w else { return nil }
        let label = [w.owningApplication?.applicationName, w.title].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
        return Target(filter: SCContentFilter(desktopIndependentWindow: w), label: label, windowID: w.windowID)
    }

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
    }

    /// nil when the window shows no page (people's video, the meeting app's controls).
    nonisolated static func read(_ image: CGImage, model: String) async -> Page? {
        let started = Date()
        let ocr = recognizeText(image)
        // A video grid or a toolbar reads as a few names and buttons.
        guard ocr.filter({ $0.isLetter || $0.isNumber }).count >= 20 else { return nil }
        guard let jpeg = jpeg(image, longSide: 1600) else { return nil }
        let meaning = model.isEmpty ? nil : await explain(jpeg, ocr: ocr, model: model)
        if meaning?.slide == false { return nil }
        let line = compose(ocr: ocr, meaning: meaning)
        debugLog("screen: page read in \(String(format: "%.1f", Date().timeIntervalSince(started))) s, \(ocr.count) chars, \(meaning == nil ? "text only" : "with meaning")")
        contentLog("SCREEN \(line)")
        return Page(ocr: ocr, line: line, jpeg: jpeg)
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

    func start(model: String) {
        guard process?.isRunning != true else { return }
        guard FileManager.default.isExecutableFile(atPath: Self.executable.path) else {
            debugLog("screen: no mlx-vlm at \(Self.executable.path), text only")
            return
        }
        let p = Process()
        p.executableURL = Self.executable
        p.arguments = ["--model", model, "--host", "127.0.0.1", "--port", "\(Self.port)"]
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
            try? await Task.sleep(for: .seconds(2))
        } while Date() < until && !Task.isCancelled
        return false
    }
}

/// The system picker reports on any thread; the watch hears it on the main one.
private final class PickerObserver: NSObject, SCContentSharingPickerObserver {
    weak var watch: ScreenWatch?
    init(watch: ScreenWatch) { self.watch = watch }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        Task { @MainActor in self.watch?.picked(filter) }
    }
    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor in self.watch?.pickEnded() }
    }
    func contentSharingPickerStartDidFailWithError(_ error: any Error) {
        debugLog("screen: picker failed \(error.localizedDescription)")
    }
}
