@preconcurrency import AVFoundation
import CoreAudio

struct ShadowClip: @unchecked Sendable {
    let id = UUID()
    var buffers: [AVAudioPCMBuffer]
    var words: [ShadowWordTiming] = []
    var duration: Double { buffers.reduce(0) { $0 + Double($1.frameLength) / $1.format.sampleRate } }
}

/// Kokoro is loaded and warmed before the first press; synthesis never routes to interpreting.
@MainActor
final class ShadowSynthesizer {
    private let worker = KokoroWorker()
    func warmUp() async -> Bool { await worker.warmUp() }
    func make(_ text: String) async -> ShadowClip { await worker.make(text) }
    func cancel() { worker.cancel() }
}

enum ShadowVolume {
    static let initial = 0.55
    static func clamped(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : initial
    }
}

struct ShadowAudioState: Sendable { var clipID: UUID?; var seconds = 0.0; var ended = false; var failed = false }

/// A bounded phrase, explicitly pinned to headphones. Hardware work never waits on the UI.
final class ShadowAudio: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.wquguru.cicada.shadow.audio", qos: .userInitiated)
    private var volume = Float(ShadowVolume.initial)
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var pitch: AVAudioUnitTimePitch?
    private var format: AVAudioFormat?
    private var deviceUID: String?
    private var clipID: UUID?
    private var playedSeconds = 0.0
    private var source: ShadowClip?
    private var offset = 0.0
    private var ended = false
    private var failed = false
    private var revision = UUID()
    private let lock = NSLock()
    private var snapshot = ShadowAudioState()
    var state: ShadowAudioState { lock.withLock { snapshot } }

    func load(_ clip: ShadowClip, device: OutputDevice) {
        queue.async { [self] in
            guard let first = clip.buffers.first else { clipID = clip.id; failed = true; publish(); return }
            do {
                if engine == nil || format != first.format || deviceUID != device.uid {
                    reset()
                    let engine = AVAudioEngine(), player = AVAudioPlayerNode(), pitch = AVAudioUnitTimePitch()
                    self.engine = engine; self.player = player; self.pitch = pitch
                    format = first.format; deviceUID = device.uid
                    engine.attach(player); engine.attach(pitch)
                    guard let unit = engine.outputNode.audioUnit else { throw URLError(.cannotOpenFile) }
                    var id = device.id
                    let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                                     &id, UInt32(MemoryLayout<AudioObjectID>.size))
                    guard status == noErr else { throw NSError(domain: "ShadowAudio", code: Int(status)) }
                    engine.connect(player, to: pitch, format: first.format)
                    engine.connect(pitch, to: engine.mainMixerNode, format: first.format)
                    engine.mainMixerNode.outputVolume = volume
                }
                guard let player, let engine else { throw URLError(.cannotOpenFile) }
                source = clip; offset = 0
                revision = UUID(); player.stop(); playedSeconds = 0; ended = false; failed = false; clipID = clip.id
                let token = revision
                for (index, buffer) in clip.buffers.enumerated() {
                    player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                        guard index == clip.buffers.count - 1 else { return }
                        self?.queue.async { [weak self] in
                            guard let self, self.revision == token else { return }
                            self.playedSeconds = clip.duration; self.ended = true; self.publish()
                        }
                    }
                }
                if !engine.isRunning { try engine.start() }
                publish()
            } catch {
                let error = error as NSError
                debugLog("shadow: audio load failed domain=\(error.domain) code=\(error.code)")
                reset(); clipID = clip.id; failed = true; publish()
            }
        }
    }

    func setVolume(_ value: Double) {
        queue.async { [self] in
            volume = Float(ShadowVolume.clamped(value))
            engine?.mainMixerNode.outputVolume = volume
        }
    }

    func control(playing: Bool, rate: Float) {
        queue.async { [self] in
            if let engine, !engine.isRunning { failed = true }
            publish() // Capture render time before pause makes playerTime unavailable.
            if pitch?.rate != rate { pitch?.rate = rate }
            if playing && !failed { if player?.isPlaying == false { player?.play() } }
            else { player?.pause() }
            publish()
        }
    }
    func seek(seconds: Double) {
        queue.async { [self] in
            guard seconds.isFinite, let source, let player else { return }
            let resume = player.isPlaying
            revision = UUID(); let token = revision
            player.stop(); offset = min(source.duration, max(0, seconds)); playedSeconds = offset
            ended = offset >= source.duration
            var skipped = offset
            for (index, original) in source.buffers.enumerated() {
                let duration = Double(original.frameLength) / original.format.sampleRate
                if skipped >= duration { skipped -= duration; continue }
                let start = AVAudioFrameCount(skipped * original.format.sampleRate)
                skipped = 0
                let count = original.frameLength - start
                guard let buffer = AVAudioPCMBuffer(pcmFormat: original.format, frameCapacity: count),
                      let input = original.floatChannelData, let output = buffer.floatChannelData else {
                    failed = true; publish(); return
                }
                buffer.frameLength = count
                for channel in 0..<Int(original.format.channelCount) {
                    output[channel].update(from: input[channel].advanced(by: Int(start)), count: Int(count))
                }
                player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                    guard index == source.buffers.count - 1 else { return }
                    self?.queue.async { [weak self] in
                        guard let self, self.revision == token else { return }
                        self.playedSeconds = source.duration; self.ended = true; self.publish()
                    }
                }
            }
            if resume && !ended && !failed { player.play() }
            publish()
        }
    }
    func stop() { queue.async { [self] in reset(); publish() } }
    private func reset() {
        revision = UUID(); player?.stop(); engine?.stop()
        player = nil; engine = nil; pitch = nil; format = nil; deviceUID = nil; clipID = nil; source = nil; offset = 0; playedSeconds = 0; ended = false; failed = false
    }
    private func publish() {
        let time = player?.lastRenderTime.flatMap { player?.playerTime(forNodeTime: $0) }
        if let time { playedSeconds = max(playedSeconds, offset + Double(time.sampleTime) / time.sampleRate) }
        lock.withLock { snapshot = ShadowAudioState(clipID: clipID, seconds: playedSeconds, ended: ended, failed: failed) }
    }
}

extension AudioDevices {
    // Bluetooth transport alone also admits room speakers. When the driver doesn't identify a
    // headphone terminal, require an explicit headset name rather than guessing from transport.
    static func shadowHeadsetName(_ name: String) -> Bool {
        let name = name.lowercased()
        return ["airpods", "headphone", "headset", "earbud", "耳机", "耳機"].contains { name.contains($0) }
    }

    /// Recognizable Bluetooth headsets and hardware headphone terminals/jacks. No speaker fallback.
    static func shadowHeadphones() -> OutputDevice? {
        guard let device = defaultOutput, !device.isVirtualMic else { return nil }
        let transport = transport(device.id)
        if transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE,
           shadowHeadsetName(device.name) { return device }
        var streamsAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var streamSize: UInt32 = 0
        if AudioObjectGetPropertyDataSize(device.id, &streamsAddress, 0, nil, &streamSize) == noErr, streamSize > 0 {
            var streams = [AudioObjectID](repeating: 0, count: Int(streamSize) / MemoryLayout<AudioObjectID>.size)
            if AudioObjectGetPropertyData(device.id, &streamsAddress, 0, nil, &streamSize, &streams) == noErr {
                for stream in streams {
                    var terminal: UInt32 = 0, size = UInt32(MemoryLayout<UInt32>.size)
                    var address = AudioObjectPropertyAddress(mSelector: kAudioStreamPropertyTerminalType,
                        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
                    if AudioObjectGetPropertyData(stream, &address, 0, nil, &size, &terminal) == noErr,
                       terminal == kAudioStreamTerminalTypeHeadphones { return device }
                }
            }
        }
        var source: UInt32 = 0, size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDataSource,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        if AudioObjectGetPropertyData(device.id, &address, 0, nil, &size, &source) == noErr, source == 0x6864706e { return device }
        return nil
    }
}
