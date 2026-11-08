import Foundation

/// CPU-only acoustic inference, isolated from the audio callback and MLX's GPU queue.
@MainActor
final class CoachAudioWorker {
    struct Event: Decodable {
        var kind: String
        var role: String?
        var now: Double?
        var voiced: Bool?
        var complete: Bool?
        var probability: Double?
    }
    var onEvent: ((Event) -> Void)?
    private var process: Process?
    private var input: FileHandle?
    private var run = UUID()
    private let writer = DispatchQueue(label: "cicada.coach.audio.write", qos: .userInitiated)
    private let reader = DispatchQueue(label: "cicada.coach.audio.read", qos: .utility)
    private var lastSent: [String: Double] = [:]
    private let capacity = DispatchSemaphore(value: 4)
    private var ready = false
    private var attempted = false
    static var scriptURL: URL? { Bundle.main.url(forResource: "audio_worker", withExtension: "py", subdirectory: "coach") }
    static var python: URL { VisionServer.executable.deletingLastPathComponent().appendingPathComponent("python") }

    static func prepareModels() async -> Bool {
        guard let script = scriptURL else { return false }
        let python = python
        return await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = python; process.arguments = [script.path, "--prepare"]
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            do { try process.run(); process.waitUntilExit(); return process.terminationStatus == 0 }
            catch { return false }
        }.value
    }

    func start() {
        guard !attempted else { return }
        attempted = true
        guard let script = Self.scriptURL else { return }
        let process = Process(); let output = Pipe(); let incoming = Pipe()
        process.executableURL = Self.python; process.arguments = ["-u", script.path]
        process.standardInput = incoming; process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let token = run
        do {
            try process.run(); self.process = process; input = incoming.fileHandleForWriting
            reader.async { [weak self] in
                var buffer = Data()
                while true {
                    let data = output.fileHandleForReading.availableData
                    if data.isEmpty { break }
                    buffer.append(data)
                    while let newline = buffer.firstIndex(of: 10) {
                        let line = Data(buffer[..<newline]); buffer.removeSubrange(...newline)
                        guard let event = try? JSONDecoder().decode(Event.self, from: line) else { continue }
                        Task { @MainActor [weak self] in
                            guard let self, self.run == token else { return }
                            if event.kind == "ready" { self.ready = true }
                            self.onEvent?(event)
                        }
                    }
                }
                Task { @MainActor [weak self] in
                    guard let self, self.run == token else { return }
                    self.ready = false
                    self.onEvent?(Event(kind: "unavailable"))
                }
            }
        } catch { onEvent?(Event(kind: "unavailable")) }
    }
    func send(_ pcm: Data, role: String, now: Double) {
        guard ready, process?.isRunning == true, let input,
              capacity.wait(timeout: .now()) == .success else { return }
        lastSent[role] = now
        let packet: [String: Any] = ["role": role, "now": now, "pcm": pcm.base64EncodedString()]
        guard var data = try? JSONSerialization.data(withJSONObject: packet) else { capacity.signal(); return }
        data.append(10)
        writer.async { [capacity] in
            defer { capacity.signal() }
            do { try input.write(contentsOf: data) } catch { /* EOF; reader reports worker failure. */ }
        }
    }
    /// Core Audio may stop delivering buffers in silence. Give VAD a clock on which pauses can finish.
    func tick(now: Double) {
        for role in ["interviewer", "candidate"] {
            if let last = lastSent[role], now - last >= 0.24 {
                send(Data(count: 8000), role: role, now: now)
            }
        }
    }
    func stop() {
        run = UUID(); ready = false; attempted = false; lastSent = [:]
        let previousInput = input; input = nil
        writer.async { try? previousInput?.close() }
        if process?.isRunning == true { process?.terminate() }
        process = nil
    }
}
