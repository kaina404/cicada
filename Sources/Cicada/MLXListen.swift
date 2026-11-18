import AVFoundation
import Foundation

/// 本机 Qwen3-ASR + Hy-MT2 (MLX), the assistant's other recognizer for the meeting's side: one
/// warm child (`Resources/coach/mlx_listen_worker.py` in `~/.cicada-mlx`) hears the audio and
/// translates into Chinese. Kept running between meetings while the switch is on, so a meeting never
/// waits for the ~3 s load. All state lives on `queue`; only the private pipes carry meeting text.
final class MLXListen: @unchecked Sendable {
    static let shared = MLXListen()

    static let models = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cicada-mlx/models")
    /// The same runtime as mlx-vlm and the coach's audio worker.
    static let python = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cicada-mlx/bin/python")
    static var script: URL? {
        if let bundled = Bundle.main.url(forResource: "mlx_listen_worker", withExtension: "py", subdirectory: "coach") {
            return bundled
        }
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/coach/mlx_listen_worker.py")
        return FileManager.default.fileExists(atPath: source.path) ? source : nil
    }
    /// The runtime, both models and the script are on this Mac.
    static var installed: Bool {
        let fm = FileManager.default
        return fm.isExecutableFile(atPath: python.path) && script != nil
            && ["qwen3-asr-1.7b-8bit", "hy-mt2-1.8b-8bit"].allSatisfy {
                fm.fileExists(atPath: models.appendingPathComponent($0).appendingPathComponent("config.json").path)
            }
    }

    private let queue = DispatchQueue(label: "com.wquguru.cicada.mlxlisten", qos: .userInitiated)
    private var process: Process?
    private var input: FileHandle?
    private var run = UUID()
    private var sink: AsyncThrowingStream<Recognition.Piece, Error>.Continuation?
    private var owner: ObjectIdentifier?
    private var asks: [Int: CheckedContinuation<String?, Never>] = [:]
    private var nextAsk = 0

    /// Starts the child if it isn't running (models load and warm in the background).
    func warmUp() { queue.async { self.startLocked() } }

    /// Shuts the child down (the switch turned off): its ~5 GB go back to the Mac.
    func stop() {
        queue.async {
            self.run = UUID()
            try? self.input?.close(); self.input = nil
            if self.process?.isRunning == true { self.process?.terminate() }
            self.process = nil
            self.failLocked()
        }
    }

    /// Lines heard from now on go to `sink`, in `language` (a BCP-47 code; nil lets Qwen tell).
    fileprivate func bind(_ stream: MLXStream, _ sink: AsyncThrowingStream<Recognition.Piece, Error>.Continuation,
                          language: String?) {
        queue.async {
            self.startLocked()
            self.sink?.finish()
            self.sink = sink; self.owner = ObjectIdentifier(stream)
            self.writeLocked(["reset": language ?? ""])
        }
    }

    /// `stream` is done; a newer stream that took over meanwhile keeps listening.
    fileprivate func unbind(_ stream: MLXStream) {
        queue.async {
            guard self.owner == ObjectIdentifier(stream) else { return }
            self.sink?.finish(); self.sink = nil; self.owner = nil
        }
    }

    /// Only the bound stream's audio and cuts reach the worker.
    fileprivate func send(_ value: [String: Any], from stream: MLXStream) {
        queue.async { if self.owner == ObjectIdentifier(stream) { self.writeLocked(value) } }
    }

    /// Hy-MT2's Chinese for `text`; nil when the worker is gone. A sentence waits ahead of drafts,
    /// and a newer draft replaces one still waiting (that one comes back nil).
    func translate(_ text: String, sentence: Bool) async -> String? {
        await withCheckedContinuation { continuation in
            queue.async {
                guard self.process?.isRunning == true else { continuation.resume(returning: nil); return }
                self.nextAsk += 1
                let id = self.nextAsk
                self.asks[id] = continuation
                self.writeLocked(["translate": text, "id": id, "sentence": sentence])
                self.queue.asyncAfter(deadline: .now() + 20) { self.asks.removeValue(forKey: id)?.resume(returning: nil) }
            }
        }
    }

    // MARK: - On `queue`

    private func startLocked() {
        guard process?.isRunning != true, let script = Self.script, Self.installed else { return }
        let p = Process(), incoming = Pipe(), outgoing = Pipe()
        p.executableURL = Self.python
        p.arguments = ["-u", script.path]
        var environment = HubMirror.environment()
        environment["TOKENIZERS_PARALLELISM"] = "false"
        p.environment = environment
        p.standardInput = incoming; p.standardOutput = outgoing; p.standardError = FileHandle.nullDevice
        // A worker that died must not take the app with it through SIGPIPE on the next write.
        _ = fcntl(incoming.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        let token = UUID()
        run = token
        do { try p.run() } catch {
            debugLog("mlx listen: worker didn't start: \(error.localizedDescription)")
            return
        }
        process = p; input = incoming.fileHandleForWriting
        debugLog("mlx listen: worker started (pid \(p.processIdentifier))")
        let started = Date()
        let output = outgoing.fileHandleForReading
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var buffer = Data()
            while true {
                let chunk = output.availableData
                if chunk.isEmpty { break }
                buffer.append(chunk)
                while let end = buffer.firstIndex(of: 10) {
                    let line = Data(buffer[..<end]); buffer.removeSubrange(...end)
                    self?.queue.async {
                        guard let self, self.run == token else { return }
                        self.receiveLocked(line, started: started)
                    }
                }
            }
            self?.queue.async {
                guard let self, self.run == token else { return }
                debugLog("mlx listen: worker exited")
                self.process = nil; self.input = nil
                self.failLocked()
            }
        }
    }

    private func receiveLocked(_ data: Data, started: Date) {
        guard let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let event = MLXListenEvent(value) {
            switch event {
            case .ready:
                debugLog(String(format: "mlx listen: Qwen3-ASR + Hy-MT2 warm after %.1f s", Date().timeIntervalSince(started)))
            case .heard(let piece):
                sink?.yield(piece)
            case .translated(let id, let zh):
                asks.removeValue(forKey: id)?.resume(returning: zh)
            }
        }
    }

    private func writeLocked(_ value: [String: Any]) {
        guard let input, var data = try? JSONSerialization.data(withJSONObject: value) else { return }
        data.append(10)
        do { try input.write(contentsOf: data) } catch { debugLog("mlx listen: write failed") }
    }

    private func failLocked() {
        let pending = asks.values; asks.removeAll()
        pending.forEach { $0.resume(returning: nil) }
        sink?.finish(throwing: MLXListenError.workerGone)
        sink = nil; owner = nil
    }
}

enum MLXListenError: Error { case workerGone }

/// One line from the worker (pure, for tests).
enum MLXListenEvent {
    case ready
    case heard(Recognition.Piece)
    case translated(id: Int, zh: String?)

    init?(_ value: [String: Any]) {
        if value["ready"] as? Bool == true { self = .ready; return }
        if let id = value["id"] as? Int {
            let zh = (value["zh"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            self = .translated(id: id, zh: zh?.isEmpty == false ? zh : nil)
            return
        }
        let start = value["start"] as? Double ?? 0, end = value["end"] as? Double ?? 0
        guard start.isFinite, end.isFinite else { return nil }
        if let text = value["final"] as? String {
            self = .heard(Recognition.Piece(text: text, isFinal: true, start: start, end: max(start, end), confidence: nil))
        } else if let text = value["draft"] as? String {
            self = .heard(Recognition.Piece(text: text, isFinal: false, start: start, end: max(start, end), confidence: nil))
        } else {
            return nil
        }
    }
}

/// The meeting heard by `MLXListen` as a `RecognitionStream`: drafts as Qwen revises them, a line
/// finished at a pause or when the engine cuts it (`finalize`).
final class MLXStream: RecognitionStream, @unchecked Sendable {
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    let results: AsyncThrowingStream<Recognition.Piece, Error>
    private let continuation: AsyncThrowingStream<Recognition.Piece, Error>.Continuation
    private let worker: MLXListen

    init(language: String?, worker: MLXListen = .shared) {
        self.worker = worker
        (results, continuation) = AsyncThrowingStream.makeStream()
        worker.bind(self, continuation, language: language)
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData, buffer.frameLength > 0 else { return }
        let data = Data(bytes: channel[0], count: Int(buffer.frameLength) * MemoryLayout<Float>.size)
        worker.send(["audio": data.base64EncodedString()], from: self)
    }

    func finalize(through seconds: Double) async throws { worker.send(["cut": true], from: self) }

    func finish() async {
        worker.send(["cut": true], from: self)
        // The last line comes back within a decode (~0.3 s).
        try? await Task.sleep(for: .milliseconds(600))
        worker.unbind(self)
    }

    func cancel() async { worker.unbind(self) }
}
