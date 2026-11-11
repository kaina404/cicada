import AVFoundation
import Foundation
import Testing
@testable import Cicada

struct ShadowPlanTests {
    @Test func bluetoothTransportDoesNotImplyHeadphones() {
        #expect(AudioDevices.shadowHeadsetName("Xiaohui’s AirPods Pro"))
        #expect(!AudioDevices.shadowHeadsetName("Living Room Speaker"))
        // Never into a virtual mic or a multi-output device that may feed the meeting.
        #expect(AudioDevices.shadowTransportAllowed(kAudioDeviceTransportTypeBluetooth))
        #expect(AudioDevices.shadowTransportAllowed(kAudioDeviceTransportTypeBuiltIn))
        #expect(!AudioDevices.shadowTransportAllowed(kAudioDeviceTransportTypeVirtual))
        #expect(!AudioDevices.shadowTransportAllowed(kAudioDeviceTransportTypeAggregate))
        #expect(!AudioDevices.shadowTransportAllowed(kAudioDeviceTransportTypeAutoAggregate))
        #expect(!AudioDevices.shadowTransportAllowed(kAudioDeviceTransportTypeAirPlay))
    }
    @Test func sentenceNavigationIgnoresDecimalsAndDoesNotSplitLongSentences() {
        var plan = ShadowPlan()
        let long = Array(repeating: "word", count: 55).joined(separator: " ")
        _ = plan.update(id: "one", text: "Target 0.5 seconds. Next sentence! " + long + ".", finished: true)
        #expect(plan.sentenceStarts == [0, 4, 6])
        #expect(plan.sentenceStart(at: 2, offset: -1) == 0)
        #expect(plan.sentenceStart(at: 4, offset: 1) == 6)
        #expect(plan.sentenceStart(at: 6, offset: 20) == 6)
        #expect(plan.phrase(from: 6)?.end == 61)
    }
    @Test func streamingAndReplacement() {
        var plan = ShadowPlan()
        _ = plan.update(id: "one", text: "We store messages. Then retr", finished: false)
        #expect(plan.words == ["we", "store", "messages"])
        plan.advance(to: 3)
        _ = plan.update(id: "one", text: "We store messages. Then retry safely.", finished: true)
        #expect(plan.cursor == 3)
        #expect(plan.phrase(from: 3)?.text == "Then retry safely.")
        _ = plan.update(id: "two", text: "A different answer", finished: true)
        #expect(plan.cursor == 0)
    }
    @Test func decimalAndIPA() {
        var plan = ShadowPlan()
        _ = plan.update(id: "one", text: "The target is 0.5 seconds and", finished: false)
        #expect(plan.words.isEmpty)
        _ = plan.update(id: "two", text: "We persist /pəˈsɪst/ each message.", finished: true)
        #expect(plan.phrase(from: 0)?.text == "We persist  each message.")
    }
}

@MainActor
struct ShadowReaderTests {
    final class Driver: ShadowAudioDriving {
        var state = ShadowAudioState()
        var delayedLoad = false
        var pendingClipID: UUID?
        var loads = 0
        var stops = 0
        var playing = false
        var volume = ShadowVolume.initial
        func setVolume(_ value: Double) { volume = value }
        var rate: Float = 1
        var device: OutputDevice?
        func load(_ clip: ShadowClip, device: OutputDevice) {
            loads += 1; self.device = device
            if delayedLoad { pendingClipID = clip.id }
            else { state = ShadowAudioState(clipID: clip.id) }
        }
        func control(playing: Bool, rate: Float) { self.playing = playing; self.rate = rate }
        func seek(seconds: Double) { state.seconds = seconds; state.ended = false }
        func stop() { stops += 1; playing = false; state = ShadowAudioState() }
    }
    final class Environment {
        var clock = 0.0
        var device: OutputDevice? = OutputDevice(id: 123, uid: "headphones", name: "Test AirPods")
    }
    private func clip() -> ShadowClip {
        let pcm = Data(repeating: 0, count: 24000 * 4)
        return KokoroWorker.decode(["rate": 24000, "pcm": pcm.base64EncodedString()])
    }
    private func script(_ text: String) -> CoachScript {
        var script = CoachScript(modelReading: true)
        script.replacePending(text, since: [], newAnswer: true)
        return script
    }
    private func settle(_ reader: ShadowReader) async {
        for _ in 0..<30 { await Task.yield(); reader.tick() }
    }
    @Test func volumePersistsIncludingMute() {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "shadowVolume")
        defer {
            if let previous { defaults.set(previous, forKey: "shadowVolume") }
            else { defaults.removeObject(forKey: "shadowVolume") }
        }
        let settings = AppSettings()
        settings.shadowVolume = 0.85
        #expect(AppSettings().shadowVolume == 0.85)
        settings.shadowVolume = 0
        #expect(AppSettings().shadowVolume == 0)
    }
    @Test func volumeClampsAndReachesDriverWhilePausedOrPlaying() {
        let audio = Driver()
        let reader = ShadowReader(audio: audio, automatic: false)
        reader.setVolume(1)
        #expect(audio.volume == 1)
        audio.playing = true
        reader.setVolume(0.8)
        #expect(audio.volume == 0.8 && audio.playing)
        reader.setVolume(-1)
        #expect(audio.volume == 0)
        reader.setVolume(2)
        #expect(audio.volume == 1)
        reader.setVolume(.nan)
        #expect(audio.volume == ShadowVolume.initial)
        reader.setVolume(.infinity)
        #expect(audio.volume == ShadowVolume.initial)
    }
    @Test func preloadsSilentlyAndHoldResumesSamePCMWithoutMicrophone() async {
        let audio = Driver(), env = Environment(), pcm = clip()
        let reader = ShadowReader(audio: audio, synthesize: { _ in pcm }, headphones: { env.device },
                                  now: { env.clock }, automatic: false)
        let answer = script("We store messages locally.")
        reader.update(enabled: true, script: answer, finished: true)
        await settle(reader)
        #expect(audio.loads == 1 && !audio.playing)
        reader.setHeld(true)
        #expect(audio.playing)
        audio.state.seconds = 0.4
        reader.setHeld(false)
        #expect(!audio.playing)
        #expect(audio.state.seconds == 0.4)
        reader.setHeld(true)
        #expect(audio.playing && audio.loads == 1 && audio.state.seconds == 0.4)
        #expect(answer.cursor == 0)
        reader.stop()
    }
    @Test func sentenceSelectionPausesSkipsBacktracksAndResumes() async {
        let audio = Driver(), env = Environment(), pcm = clip()
        let reader = ShadowReader(audio: audio, synthesize: { _ in pcm }, headphones: { env.device },
                                  now: { env.clock }, automatic: false)
        reader.update(enabled: true, script: script("First sentence. Second sentence. Third sentence."), finished: true)
        await settle(reader); reader.setHeld(true)
        reader.selectSentence(offset: 1)
        #expect(!audio.playing && reader.playback.anchorWord == 2)
        reader.selectSentence(offset: 1) // rapid crown selection cancels previous synthesis
        await settle(reader)
        #expect(reader.plan.cursor == 4 && !audio.playing)
        reader.selectSentence(offset: -1); await settle(reader)
        #expect(reader.plan.cursor == 2 && !audio.playing)
        reader.setHeld(true); audio.state.seconds = 0.4; reader.setHeld(false)
        let loads = audio.loads
        reader.setHeld(true)
        #expect(audio.playing && audio.state.seconds == 0.4 && audio.loads == loads)
        reader.selectSentence(offset: -20); await settle(reader)
        #expect(reader.plan.cursor == 0 && !audio.playing)
        reader.stop()
    }
    @Test func tapsPlaySelectedSentenceWithoutHoldAndStopAtItsEnd() async {
        let audio = Driver(), env = Environment(), pcm = clip()
        let reader = ShadowReader(audio: audio, synthesize: { _ in pcm }, headphones: { env.device },
                                  now: { env.clock }, automatic: false)
        reader.update(enabled: true, script: script("First sentence. Second sentence. Third sentence."), finished: true)
        await settle(reader)
        reader.playSentence(offset: 1); await settle(reader)
        #expect(audio.playing && reader.playback.anchorWord == 2)
        env.clock = 2; reader.tick()
        #expect(audio.playing, "Tap playback does not require hold heartbeats")
        audio.state.ended = true; reader.tick(); await settle(reader)
        #expect(!audio.playing, "A tap plays only one sentence")
        reader.playSentence(offset: -1); await settle(reader)
        #expect(audio.playing && reader.playback.anchorWord == 2)
        reader.setHeld(false)
        #expect(!audio.playing)
        reader.playSentence(offset: -1); await settle(reader)
        #expect(audio.playing && reader.playback.anchorWord == 0)
        env.device = nil; reader.tick()
        #expect(!audio.playing && reader.status == .headphones)
        reader.stop()
    }

    @Test func newPressRecoversDriverAndSynthesisFailures() async {
        let audio = Driver(), env = Environment(), pcm = clip()
        var failSynthesis = true
        let reader = ShadowReader(audio: audio, synthesize: { _ in
            failSynthesis ? ShadowClip(buffers: []) : pcm
        }, headphones: { env.device }, now: { env.clock }, automatic: false)
        reader.update(enabled: true, script: script("First sentence."), finished: true)
        await settle(reader)
        #expect(reader.status == .failed)
        failSynthesis = false
        reader.setHeld(true); await settle(reader)
        #expect(audio.playing && reader.status == .guiding)
        audio.state.failed = true; reader.tick()
        #expect(reader.status == .failed && !audio.playing)
        reader.setHeld(true); await settle(reader)
        #expect(!audio.playing, "A failed live hold requires release before retry")
        reader.setHeld(false); reader.setHeld(true); await settle(reader)
        #expect(audio.playing && reader.status == .guiding)
        audio.state.failed = true; reader.tick()
        reader.playSentence(offset: -1); await settle(reader)
        #expect(audio.playing, "Tap can recover a failed player too")
        reader.stop()
    }

    @Test func staleDriverFailureDuringAsynchronousLoadCannotPoisonNewClip() async {
        let audio = Driver(), env = Environment(), pcm = clip()
        let reader = ShadowReader(audio: audio, synthesize: { _ in pcm }, headphones: { env.device },
                                  now: { env.clock }, automatic: false)
        reader.update(enabled: true, script: script("First sentence. Second sentence."), finished: true)
        await settle(reader)
        audio.delayedLoad = true
        reader.playSentence(offset: 1); await settle(reader)
        audio.state = ShadowAudioState(clipID: UUID(), failed: true)
        reader.tick()
        #expect(reader.status == .preparing, "Ignore a stale error while the selected clip loads")
        audio.state = ShadowAudioState(clipID: audio.pendingClipID)
        reader.tick()
        #expect(audio.playing && reader.status == .guiding)
        reader.stop()
    }

    @Test func leaseExpiryCannotResumeUntilNewTouch() async {
        let audio = Driver(), env = Environment(), pcm = clip()
        let reader = ShadowReader(audio: audio, synthesize: { _ in pcm }, headphones: { env.device }, now: { env.clock }, automatic: false)
        reader.update(enabled: true, script: script("We store messages."), finished: true)
        await settle(reader); reader.setHeld(true)
        env.clock = 0.3; reader.setHeld(true)
        env.clock = 0.6; reader.tick(); #expect(audio.playing)
        env.clock = 0.81; reader.tick(); #expect(!audio.playing)
        reader.setHeld(true); #expect(!audio.playing)
        reader.setHeld(false); reader.setHeld(true); #expect(audio.playing)
        reader.stop()
    }
    @Test func releaseDuringSynthesisAndReplacementRejectLateAudio() async {
        let audio = Driver(), env = Environment(), pcm = clip()
        var complete: CheckedContinuation<ShadowClip, Never>?
        let reader = ShadowReader(audio: audio, synthesize: { _ in await withCheckedContinuation { complete = $0 } },
            headphones: { env.device }, now: { env.clock }, automatic: false)
        reader.update(enabled: true, script: script("We store messages."), finished: true)
        await settle(reader); reader.setHeld(true); reader.setHeld(false)
        complete?.resume(returning: pcm); await settle(reader)
        #expect(audio.loads == 1 && !audio.playing)
        reader.setHeld(true); #expect(audio.playing)
        reader.update(enabled: true, script: script("A different answer."), finished: true)
        #expect(!audio.playing)
        await settle(reader); reader.setHeld(true)
        complete?.resume(returning: pcm); await settle(reader)
        #expect(!audio.playing) // continuous hold across replacement cannot start new answer
        reader.setHeld(false); reader.setHeld(true); #expect(audio.playing)
        reader.stop()
    }
    @Test func completedPhrasesAdvanceWhileHeldWithoutReadingEvidence() async {
        let audio = Driver(), env = Environment(), pcm = clip()
        let reader = ShadowReader(audio: audio, synthesize: { _ in pcm }, headphones: { env.device }, automatic: false)
        reader.update(enabled: true, script: script("Store messages. Retry safely."), finished: true)
        await settle(reader); reader.setHeld(true); await settle(reader)
        audio.state.ended = true; reader.tick(); await settle(reader)
        #expect(audio.loads == 2 && audio.playing)
        #expect(reader.plan.cursor == 2)
        audio.state.ended = true; reader.tick()
        #expect(reader.status == .ended && !audio.playing)
        reader.stop()
    }
    @Test func disconnectAndDisableNeverPlayLateAudioOrFallback() async {
        let audio = Driver(), env = Environment(), pcm = clip()
        let reader = ShadowReader(audio: audio, synthesize: { _ in pcm }, headphones: { env.device }, automatic: false)
        reader.update(enabled: true, script: script("We store messages."), finished: true)
        await settle(reader); reader.setHeld(true)
        env.device = nil; reader.tick()
        #expect(!audio.playing && reader.status == .headphones)
        env.device = OutputDevice(id: 124, uid: "other-headphones", name: "Other AirPods")
        reader.setHeld(true); await settle(reader); #expect(!audio.playing)
        reader.setHeld(false); reader.setHeld(true); #expect(audio.playing)
        reader.stop(); #expect(!audio.playing && reader.status == .off)
    }
    @Test func cancellationDoesNotLoadOldSynthesis() async {
        let audio = Driver(), env = Environment(), pcm = clip()
        var complete: CheckedContinuation<ShadowClip, Never>?
        let reader = ShadowReader(audio: audio, synthesize: { _ in await withCheckedContinuation { complete = $0 } },
            headphones: { env.device }, automatic: false)
        reader.update(enabled: true, script: script("We store messages."), finished: true)
        await settle(reader); reader.stop(); complete?.resume(returning: pcm); await settle(reader)
        #expect(audio.loads == 0 && reader.status == .off)
    }
    @Test func invalidPCMIsRejected() {
        #expect(KokoroWorker.decode(["rate": 16000, "pcm": Data(repeating: 0, count: 16).base64EncodedString()]).buffers.isEmpty)
        #expect(KokoroWorker.decode(["rate": 24000, "pcm": "bad"]).buffers.isEmpty)
    }
    @Test func audioProgressPauseSeekAndRateStaySeparateFromSpokenEvidence() async {
        let audio = Driver(), env = Environment()
        var pcm = clip()
        pcm.words = [ShadowWordTiming(text: "Store", start: 0, end: 0.3),
                     ShadowWordTiming(text: "messages", start: 0.4, end: 0.8)]
        let answer = script("Store messages. Retry safely.")
        let reader = ShadowReader(audio: audio, synthesize: { _ in pcm }, headphones: { env.device },
                                  now: { env.clock }, automatic: false)
        reader.update(enabled: true, script: answer, finished: true)
        await settle(reader)
        reader.setHeld(true); audio.state.seconds = 0.6; reader.tick()
        #expect(abs(reader.playback.progress(for: 1) - 0.5) < 0.001)
        reader.setRate(1.25)
        #expect(audio.rate == 1.25 && reader.playback.seconds == 0.6)
        reader.setHeld(false); reader.tick()
        #expect(!audio.playing && reader.playback.seconds == 0.6)
        reader.seek(to: 0); reader.tick()
        #expect(reader.playback.seconds == 0 && !audio.playing && audio.loads == 1)
        reader.setHeld(true); reader.setRate(0.75)
        #expect(audio.playing && audio.rate == 0.75)
        #expect(answer.cursor == 0 && answer.committed.isEmpty)
        reader.seek(to: 2); await settle(reader)
        #expect(reader.plan.cursor == 2 && audio.loads == 2)
        reader.stop()
        #expect(reader.playback.words.isEmpty)
    }
    @Test func actualHeadphonesReaderHoldAndTapPlayback() async throws {
        guard ProcessInfo.processInfo.environment["CICADA_TEST_SHADOW_PLAYBACK"] == "1" else { return }
        _ = try #require(AudioDevices.shadowHeadphones())
        let reader = ShadowReader()
        defer { reader.stop() }
        reader.update(enabled: true, script: script("I build Android applications. I test offline message delivery."), finished: true)
        for _ in 0..<600 {
            if reader.status == .waiting, !reader.playback.words.isEmpty { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(reader.status == .waiting && !reader.playback.words.isEmpty)
        for _ in 0..<8 {
            reader.setHeld(true)
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(reader.status == .guiding && reader.playback.seconds > 0.2)
        reader.setHeld(false)
        try await Task.sleep(for: .milliseconds(100))
        let paused = reader.playback.seconds
        try await Task.sleep(for: .milliseconds(250))
        #expect(abs(reader.playback.seconds - paused) < 0.08)
        reader.playSentence(offset: 1)
        for _ in 0..<200 {
            if reader.status == .guiding, reader.playback.seconds > 0.2 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(reader.status == .guiding && reader.playback.anchorWord == 4 && reader.playback.seconds > 0.2)
        reader.playSentence(offset: -1)
        for _ in 0..<200 {
            if reader.status == .guiding, reader.playback.seconds > 0.2 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(reader.status == .guiding && reader.playback.anchorWord == 0 && reader.playback.seconds > 0.2)
        reader.setHeld(false)
        #expect(reader.status == .waiting)
    }

    @Test func actualHeadphonesPauseAndResume() async throws {
        guard ProcessInfo.processInfo.environment["CICADA_TEST_SHADOW_PLAYBACK"] == "1" else { return }
        let device = try #require(AudioDevices.shadowHeadphones())
        let synth = ShadowSynthesizer()
        #expect(await synth.warmUp())
        let pcm = await synth.make("We store messages locally and retry safely after reconnecting.")
        let audio = ShadowAudio()
        audio.load(pcm, device: device)
        for _ in 0..<100 {
            if audio.state.clipID == pcm.id { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(!audio.state.failed && audio.state.clipID == pcm.id)
        audio.control(playing: true, rate: 1)
        try await Task.sleep(for: .milliseconds(850))
        audio.control(playing: false, rate: 1)
        try await Task.sleep(for: .milliseconds(80))
        let paused = audio.state.seconds
        try await Task.sleep(for: .milliseconds(350))
        audio.control(playing: false, rate: 1)
        try await Task.sleep(for: .milliseconds(50))
        #expect(abs(audio.state.seconds - paused) < 0.05)
        audio.control(playing: true, rate: 1)
        try await Task.sleep(for: .milliseconds(600))
        audio.control(playing: false, rate: 1)
        try await Task.sleep(for: .milliseconds(50))
        #expect(audio.state.seconds > paused + 0.3)
        #expect(!audio.state.failed)
        audio.seek(seconds: 0.25)
        try await Task.sleep(for: .milliseconds(80))
        #expect(abs(audio.state.seconds - 0.25) < 0.06)
        audio.control(playing: true, rate: 0.75)
        try await Task.sleep(for: .milliseconds(600))
        audio.control(playing: false, rate: 0.75)
        try await Task.sleep(for: .milliseconds(80))
        let slow = audio.state.seconds
        #expect(slow > 0.5 && slow < 0.9)
        audio.seek(seconds: 0.25)
        try await Task.sleep(for: .milliseconds(80))
        audio.control(playing: true, rate: 1.25)
        try await Task.sleep(for: .milliseconds(600))
        audio.control(playing: false, rate: 1.25)
        try await Task.sleep(for: .milliseconds(80))
        #expect(audio.state.seconds > slow + 0.12)
        #expect(audio.state.seconds < 1.2)
        print("Slow clock: \(slow); fast clock: \(audio.state.seconds)")
        print("Headphones: \(device.name); paused PCM seconds: \(paused); resumed seconds: \(audio.state.seconds)")
        audio.stop()
    }
    @Test func localTTSProducesAudioWithoutPlayingIt() async throws {
        guard ProcessInfo.processInfo.environment["CICADA_TEST_SHADOW_TTS"] == "1" else { return }
        let synth = ShadowSynthesizer()
        #expect(await synth.warmUp())
        let start = Date()
        let pcm = await synth.make("We store messages locally and retry safely.")
        #expect(!pcm.buffers.isEmpty && pcm.duration > 1)
        #expect(!pcm.words.isEmpty)
        let alignment = ShadowPlayback.align(pcm.words, to: CoachScript.words("We store messages locally and retry safely."), startingAt: 0)
        #expect(alignment.last?.range.upperBound == 7)
        print("Kokoro warm synthesis: \(Date().timeIntervalSince(start)) seconds; audio: \(pcm.duration) seconds")
        let second = await synth.make("Then we sync changes after the connection recovers.")
        #expect(!second.buffers.isEmpty)
        for sample in ["I've shipped end-to-end Android apps with Room, WorkManager and APIs.",
                       "My target is 0.5 seconds, with a 99.9 percent success rate."] {
            let result = await synth.make(sample)
            let expected = CoachScript.words(sample)
            #expect(!result.words.isEmpty)
            #expect(ShadowPlayback.align(result.words, to: expected, startingAt: 0).last?.range.upperBound == expected.count)
        }
    }
}
