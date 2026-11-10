import AVFoundation
import Foundation

/// A persistent child owns Kokoro and its isolated runtime. Only private pipes carry answer text/PCM.
@MainActor
final class KokoroWorker {
    private var process: Process?
    private var input: FileHandle?
    private var ready = false
    private var starting = false
    private var generation = UUID()
    private var waiting: [CheckedContinuation<Bool, Never>] = []
    private var requests: [String: CheckedContinuation<ShadowClip, Never>] = [:]

    deinit { if process?.isRunning == true { process?.terminate() } }

    func warmUp() async -> Bool {
        if ready { return true }
        return await withCheckedContinuation { continuation in
            waiting.append(continuation)
            if !starting { start() }
        }
    }

    func make(_ text: String) async -> ShadowClip {
        guard await warmUp(), !Task.isCancelled else { return ShadowClip(buffers: []) }
        let id = UUID().uuidString
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                requests[id] = continuation
                do {
                    var data = try JSONSerialization.data(withJSONObject: ["id": id, "text": text])
                    data.append(10)
                    try input?.write(contentsOf: data)
                } catch { finish(id, clip: ShadowClip(buffers: [])) }
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(45))
                    self?.finish(id, clip: ShadowClip(buffers: []))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(id, clip: ShadowClip(buffers: [])) }
        }
    }

    func cancel() {
        let pending = requests.values; requests.removeAll()
        for continuation in pending { continuation.resume(returning: ShadowClip(buffers: [])) }
    }

    private func start() {
        starting = true
        let token = UUID(); generation = token
        let home = FileManager.default.homeDirectoryForCurrentUser
        let python = home.appendingPathComponent(".cicada-mlx/bin/python")
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("coach/kokoro_worker.py")
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/coach/kokoro_worker.py")
        let script = bundled.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil } ?? source
        guard FileManager.default.isExecutableFile(atPath: python.path) else { fail(); return }
        let p = Process(), incoming = Pipe(), outgoing = Pipe()
        p.executableURL = python; p.arguments = ["-u", script.path]
        var environment = ProcessInfo.processInfo.environment
        environment["TOKENIZERS_PARALLELISM"] = "false"
        p.environment = environment
        p.standardInput = incoming; p.standardOutput = outgoing; p.standardError = FileHandle.nullDevice
        process = p; input = incoming.fileHandleForWriting
        do { try p.run() } catch { fail(); return }
        let output = outgoing.fileHandleForReading
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var buffer = Data()
            while true {
                let chunk = output.availableData
                if chunk.isEmpty { break }
                buffer.append(chunk)
                while let end = buffer.firstIndex(of: 10) {
                    let line = Data(buffer[..<end]); buffer.removeSubrange(...end)
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == token else { return }
                        self.receive(line)
                    }
                }
            }
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.fail()
            }
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(900))
            guard let self, self.generation == token, !self.ready else { return }
            self.fail()
        }
    }

    private func receive(_ data: Data) {
        guard let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { fail(); return }
        if value["ready"] as? Bool == true {
            ready = true; starting = false
            let pending = waiting; waiting.removeAll()
            pending.forEach { $0.resume(returning: true) }
            debugLog("shadow: Kokoro-82M warmed (local CPU, af_heart)")
        } else if let id = value["id"] as? String {
            finish(id, clip: Self.decode(value))
        } else { fail() }
    }

    static func decode(_ value: [String: Any]) -> ShadowClip {
        guard value["rate"] as? Int == 24000, let encoded = value["pcm"] as? String,
              let data = Data(base64Encoded: encoded), !data.isEmpty, data.count % 4 == 0,
              data.count <= 24000 * 4 * 120,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24000, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(data.count / 4)),
              let channel = buffer.floatChannelData?[0] else { return ShadowClip(buffers: []) }
        buffer.frameLength = buffer.frameCapacity
        data.copyBytes(to: UnsafeMutableRawBufferPointer(start: channel, count: data.count))
        guard (0..<Int(buffer.frameLength)).allSatisfy({ channel[$0].isFinite }) else { return ShadowClip(buffers: []) }
        let duration = Double(buffer.frameLength) / 24000
        let raw = value["words"] as? [[String: Any]] ?? []
        var words: [ShadowWordTiming] = []
        for item in raw {
            guard let text = item["text"] as? String, let start = item["start"] as? Double,
                  let end = item["end"] as? Double, start.isFinite, end.isFinite,
                  start >= 0, end >= start, end <= duration + 0.05,
                  start >= (words.last?.start ?? 0) else {
                // Audio remains usable, but malformed alignment must never invent progress.
                return ShadowClip(buffers: [buffer])
            }
            words.append(ShadowWordTiming(text: text, start: start, end: min(end, duration)))
        }
        return ShadowClip(buffers: [buffer], words: words)
    }

    private func finish(_ id: String, clip: ShadowClip) { requests.removeValue(forKey: id)?.resume(returning: clip) }
    private func fail() {
        generation = UUID(); ready = false; starting = false
        try? input?.close(); input = nil
        if process?.isRunning == true { process?.terminate() }; process = nil
        let pending = waiting; waiting.removeAll(); pending.forEach { $0.resume(returning: false) }
        cancel()
        debugLog("shadow: Kokoro unavailable; no system-voice fallback")
    }
}
