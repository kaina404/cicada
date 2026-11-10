import AVFoundation
import Combine
import Foundation

@MainActor
protocol ShadowAudioDriving: AnyObject {
    var state: ShadowAudioState { get }
    func load(_ clip: ShadowClip, device: OutputDevice)
    func control(playing: Bool, rate: Float)
    func stop()
    func setVolume(_ value: Double)
    func seek(seconds: Double)
}
extension ShadowAudio: ShadowAudioDriving {}

/// Press-to-listen: microphone observations never move or control this private audio queue.
@MainActor
final class ShadowReader: ObservableObject {
    enum Status: String { case off, headphones, preparing, guiding, waiting, failed, ended }
    @Published private(set) var status = Status.off
    @Published private(set) var playback = ShadowPlayback()
    @Published private(set) var rate: Float = 1
    func setRate(_ value: Float) {
        guard [Float(0.75), 1, 1.25].contains(value) else { return }
        rate = value; tick()
    }
    func setVolume(_ value: Double) { audio.setVolume(ShadowVolume.clamped(value)) }

    func seek(to word: Int) {
        guard enabled, word >= 0, word < plan.words.count else { return }
        if let target = playback.words.first(where: { $0.range.contains(word) }), clip != nil {
            audio.seek(seconds: target.timing.start)
        } else {
            let output = device
            resetPlayback(); device = output
            plan.seek(to: word)
            playback = ShadowPlayback(answerID: plan.answerID, anchorWord: word)
            tick()
        }
    }
    /// Selection is independent of microphone evidence. Selecting always pauses and cancels stale work.
    func selectSentence(offset: Int) {
        guard enabled, offset != 0,
              let word = plan.sentenceStart(at: playback.currentWord ?? plan.cursor, offset: offset) else { return }
        setHeld(false)
        let output = device
        resetPlayback(); device = output
        plan.seek(to: word)
        playback = ShadowPlayback(answerID: plan.answerID, anchorWord: word)
        tick()
    }

    /// A tap plays only the selected sentence; crown selection remains paused.
    func playSentence(offset: Int) {
        selectSentence(offset: offset)
        guard enabled, !plan.words.isEmpty, headphones() != nil else { return }
        retryPlayback()
        tick()
        sentencePlaying = true
        tick()
    }

    private func retryPlayback() {
        guard failed else { return }
        failed = false
        resetPlayback()
        playback = ShadowPlayback(answerID: plan.answerID, anchorWord: plan.cursor)
        prepareWarmUp()
        tick()
    }

    private func prepareWarmUp() {
        guard !warmed, !failed, warming == nil else { return }
        warming = Task { [weak self] in
            guard let self else { return }
            let ready = await self.warmUp()
            guard !Task.isCancelled else { return }
            self.warming = nil; self.warmed = ready
            if !ready { self.markFailed(); return }
            self.tick()
        }
    }

    private(set) var plan = ShadowPlan()
    private let audio: ShadowAudioDriving
    private let synthesize: (String) async -> ShadowClip
    private let warmUp: () async -> Bool
    private let cancelSynthesis: () -> Void
    private let headphones: () -> OutputDevice?
    private let now: () -> Double
    private var timer: Timer?
    private var work: Task<Void, Never>?
    private var warming: Task<Void, Never>?
    private var revision = UUID()
    private var enabled = false
    private var warmed = false
    private var held = false
    private var sentencePlaying = false
    private var needsRelease = false
    private var lastHold = -Double.infinity
    private var device: OutputDevice?
    private var clip: (id: UUID, end: Int)?
    private var prepared: (start: Int, end: Int, clip: ShadowClip)?
    private var failed = false
    private let automatic: Bool
    static let holdLease = 0.5

    init(audio: ShadowAudioDriving? = nil, synthesize: ((String) async -> ShadowClip)? = nil,
         warmUp: (() async -> Bool)? = nil, cancelSynthesis: (() -> Void)? = nil,
         headphones: @escaping () -> OutputDevice? = AudioDevices.shadowHeadphones,
         now: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }, automatic: Bool = true) {
        let synth = ShadowSynthesizer()
        self.audio = audio ?? ShadowAudio()
        self.synthesize = synthesize ?? { await synth.make($0) }
        self.warmUp = warmUp ?? (synthesize == nil ? { await synth.warmUp() } : { true })
        self.cancelSynthesis = cancelSynthesis ?? { synth.cancel() }
        self.headphones = headphones; self.now = now; self.automatic = automatic
    }

    deinit { timer?.invalidate() }

    func update(enabled: Bool, script: CoachScript, finished: Bool) {
        guard enabled else { if self.enabled { stop() }; return }
        self.enabled = true
        if automatic, timer == nil {
            let timer = Timer(timeInterval: 0.025, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            self.timer = timer; RunLoop.main.add(timer, forMode: .common)
        }
        let changed = plan.update(id: script.answerID, text: script.pending, finished: finished)
        if changed {
            if held { needsRelease = true }
            resetPlayback(); held = false; lastHold = -.infinity; failed = false
        }
        prepareWarmUp()
        tick()
    }

    /// Each live touch heartbeat renews a short lease. Release pauses synchronously at the driver boundary.
    func setHeld(_ pressed: Bool) {
        guard enabled else { return }
        if !pressed {
            sentencePlaying = false
            held = false; needsRelease = false; lastHold = -.infinity
            audio.control(playing: false, rate: rate)
            tick(); return
        }
        // A disconnected headset never falls back to speakers, and reconnect requires a new press.
        guard !needsRelease else { return }
        guard headphones() != nil else { needsRelease = true; held = false; tick(); return }
        retryPlayback()
        sentencePlaying = false
        held = true; lastHold = now(); tick()
    }

    func stop() {
        enabled = false; held = false; needsRelease = false; lastHold = -.infinity
        timer?.invalidate(); timer = nil
        warming?.cancel(); warming = nil
        resetPlayback(); plan = ShadowPlan(); status = .off
    }

    func tick() {
        guard enabled else { return }
        if held, now() - lastHold >= Self.holdLease { held = false; needsRelease = true }
        guard let current = headphones() else {
            if held || device != nil { needsRelease = true }
            if device != nil || clip != nil { resetPlayback() }
            held = false; status = .headphones; return
        }
        if device?.uid != current.uid {
            if device != nil || held { needsRelease = true }
            resetPlayback(); device = current; held = false
        }
        guard !failed else { held = false; audio.control(playing: false, rate: rate); status = .failed; return }
        guard warmed else { status = .preparing; return }
        if let playing = clip {
            let state = audio.state
            // The driver loads on another queue: its snapshot may still belong to the old clip.
            guard state.clipID == playing.id else { status = .preparing; return }
            if state.failed { debugLog("shadow: audio driver failed"); markFailed(); return }
            if playback.seconds != state.seconds { playback.seconds = state.seconds }
            if state.ended {
                let single = sentencePlaying
                sentencePlaying = false
                plan.advance(to: playing.end); clip = nil
                if single { held = false }
                audio.control(playing: false, rate: rate)
            } else {
                audio.control(playing: held || sentencePlaying, rate: rate)
                status = held || sentencePlaying ? .guiding : .waiting
                if prepared == nil, work == nil { prepare(from: playing.end) }
                return
            }
        }
        if let ready = prepared, ready.start == plan.cursor {
            prepared = nil; clip = (ready.clip.id, ready.end)
            playback = ShadowPlayback(answerID: plan.answerID, anchorWord: ready.start, words:
                ShadowPlayback.align(ready.clip.words, to: plan.words, startingAt: ready.start))
            audio.load(ready.clip, device: current)
            // Loading schedules PCM without starting it. A release during synthesis stays paused.
            status = held || sentencePlaying ? .preparing : .waiting
            return
        }
        if work == nil { prepare(from: plan.cursor) }
        status = plan.cursor == plan.words.count && !plan.words.isEmpty ? .ended : (held || sentencePlaying ? .preparing : .waiting)
    }

    private func prepare(from start: Int) {
        guard work == nil, let phrase = plan.phrase(from: start) else { return }
        let token = revision
        work = Task { [weak self] in
            guard let self else { return }
            let result = await self.synthesize(phrase.text)
            guard !Task.isCancelled, self.revision == token, self.enabled else { return }
            self.work = nil
            guard !result.buffers.isEmpty, result.duration > 0 else { debugLog("shadow: synthesis returned no audio"); self.markFailed(); return }
            self.prepared = (start, phrase.end, result)
            self.tick()
        }
    }

    private func markFailed() {
        if held { needsRelease = true }
        resetPlayback()
        held = false; failed = true; status = .failed
    }

    private func resetPlayback() {
        sentencePlaying = false
        revision = UUID(); work?.cancel(); work = nil; cancelSynthesis()
        audio.stop(); clip = nil; prepared = nil; device = nil; playback = ShadowPlayback()
    }

    var label: String {
        switch status {
        case .off: L("陪读已关闭")
        case .headphones: L("请将系统声音输出切到耳机")
        case .preparing: L("正在准备 Kokoro 语音")
        case .guiding: L("正在陪读")
        case .waiting: L("按住手表播放，松开暂停")
        case .failed: L("语音暂不可用，请松手后重新按住")
        case .ended: L("回答已播放完")
        }
    }
}
