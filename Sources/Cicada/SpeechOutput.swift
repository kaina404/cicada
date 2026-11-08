@preconcurrency import AVFoundation
import CoreAudio

/// The speech engine and all of its device operations stay off the main thread. Pending buffers
/// survive a hardware configuration change; callbacks from the replaced engine are ignored.
final class SpeechOutput: @unchecked Sendable {
    private let queue = AudioLifecycle.queue
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var observer: NSObjectProtocol?
    private var format: AVAudioFormat?
    private var device: OutputDevice?
    private var revision = AudioRevision()
    private struct Pending {
        let id = UUID()
        let buffer: AVAudioPCMBuffer
        var completion: (() -> Void)?
    }
    private var pending: [Pending] = []
    private var rebuildScheduled = false
    private let operationTimeout: TimeInterval

    init(operationTimeout: TimeInterval = 8) { self.operationTimeout = operationTimeout }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        let engine = engine
        queue.async { engine?.stop() }
    }

    func prepare(format: AVAudioFormat, device: OutputDevice?) async -> Bool {
        await enqueue([], format: format, device: device)
    }

    func enqueue(_ buffers: [AVAudioPCMBuffer], format: AVAudioFormat, device: OutputDevice?) async -> Bool {
        let once = Once()
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + operationTimeout) {
                once.run { continuation.resume(returning: false) }
            }
            queue.async { [self] in
                guard !once.hasRun else { return }
                do {
                    if engine == nil || self.format != format || self.device?.uid != device?.uid {
                        reset()
                        self.format = format
                        self.device = device
                        try makeEngine()
                    }
                    guard let engine, let player else { once.run { continuation.resume(returning: false) }; return }
                    if !engine.isRunning { try engine.start() }
                    guard !once.hasRun else { reset(); return }
                    for buffer in buffers {
                        let item = Pending(buffer: buffer)
                        pending.append(item)
                        schedule(item)
                    }
                    if !buffers.isEmpty, !player.isPlaying { player.play() }
                    once.run { continuation.resume(returning: true) }
                } catch {
                    debugLog("voice output failed: \(error)")
                    once.run { continuation.resume(returning: false) }
                }
            }
        }
    }

    /// A separate timer can finish even if Core Audio itself is stuck on the hardware lane.
    func drain(_ tail: AVAudioPCMBuffer, limit: TimeInterval) async -> Bool {
        let once = Once()
        let played = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            queue.async { [self] in
                guard !once.hasRun else { return }
                guard let player else { once.run { continuation.resume(returning: false) }; return }
                let item = Pending(buffer: tail, completion: { once.run { continuation.resume(returning: true) } })
                pending.append(item)
                schedule(item)
                if !player.isPlaying { player.play() }
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + limit) {
                once.run { continuation.resume(returning: false) }
            }
        }
        if !played {
            debugLog("voice output stalled, resetting")
            queue.async { [self] in reset() }
        }
        return played
    }

    func stop() { queue.async { [self] in reset() } }

    func rebuild() { queue.async { [self] in scheduleRebuild() } }

    private func scheduleRebuild() {
        guard !rebuildScheduled else { return }
        rebuildScheduled = true
        queue.asyncAfter(deadline: .now() + 0.2) { [self] in
            rebuildScheduled = false
            guard format != nil else { return }
            do {
                try makeEngine()
                debugLog("voice output: rebuilt after audio configuration changed")
            } catch { debugLog("voice output rebuild failed: \(error)") }
        }
    }

    private func makeEngine() throws {
        revision.advance()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        player?.stop()
        engine?.stop()
        player = nil
        engine = nil
        guard let format else { return }
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        self.engine = engine
        self.player = player
        engine.attach(player)
        if let device, let unit = engine.outputNode.audioUnit {
            var id = device.id
            let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                             &id, UInt32(MemoryLayout<AudioObjectID>.size))
            guard status == noErr else { throw NSError(domain: "SpeechOutput", code: Int(status)) }
        }
        engine.connect(player, to: engine.mainMixerNode, format: format)
        try engine.start()
        let current = revision.value
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
            guard let self else { return }
            self.queue.async { [weak self] in
                guard let self, self.revision.accepts(current), self.engine?.isRunning == false else { return }
                self.scheduleRebuild()
            }
        }
        for item in pending { schedule(item) }
        if !pending.isEmpty { player.play() }
    }

    private func schedule(_ item: Pending) {
        let current = revision.value
        player?.scheduleBuffer(item.buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            guard let self else { return }
            self.queue.async { [weak self] in
                guard let self, self.revision.accepts(current),
                      let index = self.pending.firstIndex(where: { $0.id == item.id }) else { return }
                self.pending.remove(at: index)
                item.completion?()
            }
        }
    }

    private func reset() {
        revision.advance()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        player?.stop()
        engine?.stop()
        player = nil
        engine = nil
        pending = []
        format = nil
        device = nil
    }
}
