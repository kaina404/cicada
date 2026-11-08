import AVFoundation
import AudioToolbox
import CoreAudio

/// The microphone with the system's echo cancellation (VoiceProcessingIO): with speakers on, the
/// online meeting's voices reach the mic. The talk key would translate them and speak them back, and
/// 电脑和会议室 would write each remote sentence twice. Measured with a clip on the MacBook speakers
/// at 60 %: 38–39 of 43 words recognized from the bare mic, none through this.
///
/// One unit in the process, or none: the room (listening the whole meeting) and the talk key (each
/// press) share it as consumers, and it runs while anyone is attached.
///
/// The raw unit, because AVAudioEngine's voice processing fails ('bfmt') when the default input is
/// the virtual mic, which 同声传译 makes it. Making the unit takes ~1.8 s, so it is made ahead and
/// only started (~40 ms) and stopped per press; made but stopped, it doesn't hold the mic open, but
/// it does starve AVAudioEngine's input on the same mic (−56 dB peaks): it is let go of before the
/// plain mic is used.
/// AGC is off (it lifts the room's noise with the voice, which recognition likes less), and other
/// audio's ducking is set to its minimum: the meeting must stay audible while you talk.
final class VoiceMic: @unchecked Sendable {
    static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!

    private let currentOutput: () -> AudioObjectID?
    private let createUnit: ((AudioObjectID, AudioObjectID) -> AudioUnit?)?

    init(currentOutput: @escaping () -> AudioObjectID? = { SystemAudioTap.defaultOutputDevice() },
         createUnit: ((AudioObjectID, AudioObjectID) -> AudioUnit?)? = nil) {
        self.currentOutput = currentOutput
        self.createUnit = createUnit
    }

    private let queue = AudioLifecycle.queue
    private let lock = NSLock()
    private var unit: AudioUnit?
    /// The devices the unit was made for: another mic or output means making it again.
    private var builtFor: (input: AudioObjectID, output: AudioObjectID)?
    private var building = false
    private var running = false
    private var consumers: [String: (AVAudioPCMBuffer) -> Void] = [:]
    private var waiting: [(Bool) -> Void] = []
    private var scratch = [Float](repeating: 0, count: 8192)
    /// After a unit is made or let go of: audio already flowing in this process goes silent for good
    /// (measured: an output engine playing into BlackHole, and the system audio tap), and must be
    /// started anew.
    var onUnitChanged: (() -> Void)?

    deinit {
        if let unit {
            AudioOutputUnitStop(unit)
            AudioComponentInstanceDispose(unit)
        }
    }

    /// Whether anyone is attached (then nobody may use the plain mic, which the unit starves).
    var inUse: Bool { lock.withLock { !consumers.isEmpty } }

    /// Plain inputs reserve before any hardware work is queued. A prepared VoiceProcessingIO
    /// starves them even while stopped, so it must not exist for the lifetime of these leases.
    private var plainInputs: Set<UUID> = []
    private var rawID: UUID?
    private var resumeInput: AudioObjectID?
    // Only used on the hardware lane. Waiting for a press to end never blocks that lane.
    private var plainWaiting: [UUID: (Bool) -> Void] = [:]

    func acquirePlainInput(_ id: UUID, ready: @escaping (Bool) -> Void) {
        let reserved = lock.withLock { () -> Bool in
            guard rawID == nil || rawID == id else { return false }
            plainInputs.insert(id)
            return true
        }
        guard reserved else { queue.async { ready(false) }; return }
        queue.async { [self] in
            guard lock.withLock({ plainInputs.contains(id) }) else { return }
            plainWaiting[id] = ready
            grantPlainInputs()
        }
    }

    /// On the hardware lane, after the last echo consumer has stopped.
    private func grantPlainInputs() {
        let canGrant = lock.withLock { consumers.isEmpty && !plainInputs.isEmpty }
        guard canGrant else { return }
        disposeIdleUnit()
        let callbacks = plainWaiting
        plainWaiting = [:]
        for (id, ready) in callbacks where lock.withLock({ plainInputs.contains(id) }) { ready(true) }
    }

    /// The caller queues this after stopping its input, so a deferred build cannot starve it.
    func endPlainInput(_ id: UUID) {
        queue.async { [self] in
            plainWaiting.removeValue(forKey: id)
            let input = lock.withLock { () -> AudioObjectID? in
                guard plainInputs.remove(id) != nil else { return nil }
                if rawID == id { rawID = nil }
                guard plainInputs.isEmpty else { return nil }
                defer { resumeInput = nil }
                return resumeInput
            }
            if let input { prepare(input: input) }
        }
    }

    /// Voice cloning needs an exclusive reservation; meeting and press inputs may share plain IO.
    func beginRawRecording() async -> Bool {
        let id = UUID()
        let reserved = lock.withLock { () -> Bool in
            guard plainInputs.isEmpty, consumers.isEmpty else { return false }
            rawID = id
            plainInputs.insert(id)
            return true
        }
        guard reserved else { return false }
        await withCheckedContinuation { continuation in
            acquirePlainInput(id) { _ in continuation.resume() }
        }
        return true
    }

    func endRawRecording() {
        if let id = lock.withLock({ rawID }) { endPlainInput(id) }
    }

    func prepare(input: AudioObjectID, then: ((Bool) -> Void)? = nil) {
        guard input != 0, let output = currentOutput() else { then?(false); return }
        lock.lock()
        if !plainInputs.isEmpty {
            resumeInput = input
            lock.unlock()
            then?(false)
            return
        }
        let ready = builtFor.map { $0 == (input, output) } ?? false
        if ready { lock.unlock(); then?(true); return }
        if let then { waiting.append(then) }
        if building { lock.unlock(); return }
        building = true
        lock.unlock()
        queue.async { [self] in
            let t0 = Date()
            // A reservation may have arrived while this build was queued.
            let allowed = lock.withLock { plainInputs.isEmpty && !running }
            let made: AudioUnit?
            // Dispose before creating: two VoiceProcessingIO units must never overlap.
            if allowed { disposeIdleUnit() }
            if !allowed { made = nil }
            else if let createUnit { made = createUnit(input, output) }
            else { made = make(input: input, output: output) }
            let (ok, told) = lock.withLock { () -> (Bool, [(Bool) -> Void]) in
                var ok = false
                if !plainInputs.isEmpty { resumeInput = input }
                if let made, unit == nil, plainInputs.isEmpty {
                    unit = made; builtFor = (input, output); ok = true
                }
                building = false
                defer { waiting = [] }
                return (ok, waiting)
            }
            if let made, !ok { AudioComponentInstanceDispose(made) }
            debugLog(String(format: "voice mic: %@ in %.1f s (input %u, output %u)", ok ? "ready" : "deferred",
                            Date().timeIntervalSince(t0), input, output))
            if made != nil { onUnitChanged?() }
            told.forEach { $0(ok) }
            grantPlainInputs()
        }
    }

    /// Both start and stop run on the hardware lane. Callers discard late completion by identity.
    func attach(_ key: String, input: AudioObjectID, onAudio: @escaping (AVAudioPCMBuffer) -> Void,
                completion: @escaping (Bool) -> Void) {
        queue.async { [self] in
            guard let output = currentOutput() else { completion(false); return }
            lock.lock()
            guard plainInputs.isEmpty, let unit, let b = builtFor, b == (input, output) else {
                lock.unlock(); completion(false); return
            }
            consumers[key] = onAudio
            let first = !running
            running = true
            lock.unlock()
            guard first else { completion(true); return }
            let status = AudioOutputUnitStart(unit)
            if status != noErr {
                debugLog("voice mic: start failed \(status)")
                lock.withLock { running = false; consumers = [:]; builtFor = nil }
                completion(false)
                grantPlainInputs()
                return
            }
            debugLog("voice mic: started for \(key)")
            completion(true)
        }
    }

    func detach(_ key: String) {
        queue.async { [self] in
            lock.lock()
            guard consumers.removeValue(forKey: key) != nil else { lock.unlock(); return }
            guard consumers.isEmpty, running, let unit else { lock.unlock(); return }
            running = false
            lock.unlock()
            AudioOutputUnitStop(unit)
            debugLog("voice mic: stopped (\(key) was the last)")
            grantPlainInputs()
        }
    }

    /// Called only on the hardware lane; never dispose a unit under the render callback's lock.
    private func disposeIdleUnit() {
        let old: AudioUnit? = lock.withLock {
            guard !running, consumers.isEmpty, let old = unit else { return nil }
            unit = nil
            builtFor = nil
            return old
        }
        if let old {
            AudioComponentInstanceDispose(old)
            debugLog("voice mic: released")
            onUnitChanged?()
        }
    }

    func release() { queue.async { [self] in disposeIdleUnit() } }

    private func make(input: AudioObjectID, output: AudioObjectID) -> AudioUnit? {
        var desc = AudioComponentDescription(componentType: kAudioUnitType_Output, componentSubType: kAudioUnitSubType_VoiceProcessingIO,
                                             componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        guard let comp = AudioComponentFindNext(nil, &desc) else { return nil }
        var made: AudioUnit?
        guard AudioComponentInstanceNew(comp, &made) == noErr, let u = made else { return nil }
        func set<T>(_ property: AudioUnitPropertyID, _ scope: AudioUnitScope, _ element: AudioUnitElement, _ value: T) -> Bool {
            let status = withUnsafeBytes(of: value) {
                AudioUnitSetProperty(u, property, scope, element, $0.baseAddress, UInt32($0.count))
            }
            if status != noErr { debugLog("voice mic: property \(property) failed \(status)") }
            return status == noErr
        }
        // Element 1 is the mic, element 0 the output the echo is heard against.
        var ok = set(kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 1, input)
            && set(kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, output)
        _ = set(kAUVoiceIOProperty_VoiceProcessingEnableAGC, kAudioUnitScope_Global, 0, UInt32(0))
        _ = set(kAUVoiceIOProperty_OtherAudioDuckingConfiguration, kAudioUnitScope_Global, 0,
                AUVoiceIOOtherAudioDuckingConfiguration(mEnableAdvancedDucking: false, mDuckingLevel: .min))
        let asbd = Self.format.streamDescription.pointee
        ok = ok && set(kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, asbd)
            && set(kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, asbd)
        ok = ok && set(kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0,
                       AURenderCallbackStruct(inputProc: { ref, flags, ts, _, frames, _ in
                           Unmanaged<VoiceMic>.fromOpaque(ref).takeUnretainedValue().render(flags, ts, frames)
                       }, inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()))
        if ok, AudioUnitInitialize(u) == noErr { return u }
        AudioComponentInstanceDispose(u)
        return nil
    }

    /// On the real-time thread, as `SystemAudioTap.render`.
    private func render(_ flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>, _ ts: UnsafePointer<AudioTimeStamp>,
                        _ frames: UInt32) -> OSStatus {
        guard let unit, frames > 0, Int(frames) <= scratch.count else { return noErr }
        let status = scratch.withUnsafeMutableBufferPointer { p -> OSStatus in
            var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: frames * 4, mData: p.baseAddress))
            return AudioUnitRender(unit, flags, ts, 1, frames, &list)
        }
        let listeners = lock.withLock { Array(consumers.values) }
        guard status == noErr, !listeners.isEmpty, let out = AVAudioPCMBuffer(pcmFormat: Self.format, frameCapacity: frames),
              let dst = out.floatChannelData?[0] else { return status }
        out.frameLength = frames
        scratch.withUnsafeBufferPointer { dst.update(from: $0.baseAddress!, count: Int(frames)) }
        listeners.forEach { $0(out) }
        return noErr
    }
}

/// 会议室 heard through the echo-cancelling unit (电脑和会议室): an `AudioSource` like `RoomMic`, so the
/// rest of listening is unchanged. The unit is made on `start` (~1.8 s, the room is heard from then);
/// `onFailed` says it couldn't be, and the caller falls back to the plain mic. While `muted` (the
/// Mac reading aloud, the talk key held), silence goes on in its place, as with `RoomMic`.
final class EchoCancelledRoomMic: AudioSource, @unchecked Sendable {
    var onAudio: ((AVAudioPCMBuffer) -> Void)?
    var onFailed: (() -> Void)?
    private let mic: VoiceMic
    private let device: OutputDevice
    private let consumer = "room-" + UUID().uuidString
    private let lock = NSLock()
    private var _muted = false
    private var stopped = false
    var muted: Bool {
        get { lock.withLock { _muted } }
        set { lock.withLock { _muted = newValue } }
    }
    var deviceName: String { device.name }
    var deviceUID: String { device.uid }

    init(mic: VoiceMic, device: OutputDevice) {
        self.mic = mic
        self.device = device
    }

    func start() throws {
        mic.prepare(input: device.id) { [weak self] ok in
            guard let self, !self.lock.withLock({ self.stopped }) else { return }
            guard ok else {
                self.onFailed?()
                return
            }
            self.mic.attach(self.consumer, input: self.device.id, onAudio: { [weak self] buf in self?.deliver(buf) }) { [weak self] attached in
                guard let self else { return }
                if self.lock.withLock({ self.stopped }) {
                    if attached { self.mic.detach(self.consumer) }
                    return
                }
                if !attached {
                    debugLog("room mic: echo cancellation unavailable, plain mic instead")
                    self.onFailed?()
                } else {
                    debugLog("room mic started with echo cancellation: \(self.device.name)")
                }
            }
        }
    }

    func stop() {
        lock.withLock { stopped = true }
        mic.detach(consumer)
    }

    private func deliver(_ buf: AVAudioPCMBuffer) {
        if muted, let d = buf.floatChannelData?[0] { d.update(repeating: 0, count: Int(buf.frameLength)) }
        onAudio?(buf)
    }
}
