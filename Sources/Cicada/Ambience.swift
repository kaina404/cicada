import AVFoundation
import Foundation

/// 环境底噪 for 千问实时翻译: a few seconds of my quiet room, made into a loop that plays under the
/// translated voice the whole time a meeting is listened to, so the virtual mic sounds like a mic in
/// a room and not like a studio voice cut out of digital silence. `ambience.wav` (24 kHz mono float,
/// the live voice's format) under Application Support; never leaves the Mac except into the meeting.
enum Ambience {
    static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24_000, channels: 1, interleaved: false)!
    /// Posted after a new loop is saved or removed: the speak engine loads it again.
    static let changed = Notification.Name("AmbienceChanged")

    static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(DevBuild.supportFolder).appendingPathComponent("ambience.wav")
    }
    static var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    static func save(_ samples: [Float]) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: url)
        guard let buf = buffer(samples) else { return }
        // Closed (its header written) before anyone is told to read it.
        do {
            let f = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            try f.write(from: buf)
        }
        NotificationCenter.default.post(name: changed, object: nil)
    }

    static func remove() {
        try? FileManager.default.removeItem(at: url)
        NotificationCenter.default.post(name: changed, object: nil)
    }

    static func load() -> AVAudioPCMBuffer? {
        guard let f = try? AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false),
              f.processingFormat == format,
              let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(f.length)),
              (try? f.read(into: buf)) != nil, buf.frameLength > 0 else { return nil }
        return buf
    }

    static func buffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty, let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return nil }
        buf.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buf.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        return buf
    }

    /// The slider (0–1) as a gain on the loop, which is saved at `AmbienceLoop.level`: ±12 dB around it.
    static func gain(_ volume: Double) -> Float { Float(pow(10, (volume - 0.5) * 24 / 20)) }
}

/// Turns a recording of the room into a loop nobody hears the seam of. Pure, for the tests.
enum AmbienceLoop {
    static let rate = 24_000.0
    /// The loop's loudness, ≈ −50 dBFS RMS: a quiet room through a laptop mic.
    static let level: Float = 0.00316
    /// Shorter than this after the knocks are cut out: the room was too busy to loop.
    static let minSeconds = 4.0
    static let window = 1_200 // 50 ms

    enum Failure: Error, Equatable { case tooShort, silent }

    static func make(_ input: [Float]) -> Result<[Float], Failure> {
        // The first half second has the click that started it; the end the hand going to stop it.
        let start = Int(rate * 0.5), end = input.count - Int(rate * 0.3)
        guard end - start > Int(rate * minSeconds) else { return .failure(.tooShort) }
        var x = highPass(Array(input[start..<end]))
        x = steady(x)
        guard Double(x.count) >= rate * minSeconds else { return .failure(.tooShort) }
        x = seamless(x, fade: min(Int(rate * 1.5), x.count / 4))
        let r = rms(x)
        guard r > 1e-6 else { return .failure(.silent) }
        // A lone sample far over the rest (a codec glitch: −20 dBFS in a −50 dBFS room through
        // AirPods) is a tick every time the loop comes round; noise stays within ~4.5× its RMS.
        let g = level / r, cap = level * 6
        return .success(x.map { max(-cap, min(cap, $0 * g)) })
    }

    /// First-order high-pass at 80 Hz: the DC offset and the desk's rumble.
    static func highPass(_ x: [Float]) -> [Float] {
        let rc = 1 / (2 * Float.pi * 80), dt = 1 / Float(rate), a = rc / (rc + dt)
        var y = [Float](repeating: 0, count: x.count)
        for i in 1..<x.count { y[i] = a * (y[i - 1] + x[i] - x[i - 1]) }
        return y
    }

    /// Only the 50 ms windows within 6 dB of the median: a key or a cup heard once in a loop is
    /// heard again every few seconds. What is left is joined with 10 ms crossfades.
    static func steady(_ x: [Float]) -> [Float] {
        let n = x.count / window
        guard n > 0 else { return [] }
        let levels = (0..<n).map { rms(x[($0 * window)..<(($0 + 1) * window)]) }
        let line = levels.sorted()[n / 2] * 2
        var out: [Float] = []
        var joined = true
        let fade = 240
        for i in 0..<n {
            guard levels[i] <= line else { joined = false; continue }
            let w = x[(i * window)..<((i + 1) * window)]
            if !joined, out.count >= fade {
                // Equal-power, the two sides being unrelated noise.
                for k in 0..<fade {
                    let t = Float(k) / Float(fade) * .pi / 2
                    let j = out.count - fade + k
                    out[j] = out[j] * cos(t) + w[w.startIndex + k] * sin(t)
                }
                out.append(contentsOf: w.dropFirst(fade))
            } else {
                out.append(contentsOf: w)
            }
            joined = true
        }
        return out
    }

    /// The last `fade` samples crossfaded into the first: playing the result in a loop, its end runs
    /// straight on into its start (sample n−1 is followed by what came after it in the recording).
    static func seamless(_ x: [Float], fade: Int) -> [Float] {
        guard fade > 0, x.count > 2 * fade else { return x }
        var y = Array(x[0..<(x.count - fade)])
        for i in 0..<fade {
            let t = Float(i) / Float(fade) * .pi / 2
            y[i] = x[x.count - fade + i] * cos(t) + x[i] * sin(t)
        }
        return y
    }

    static func rms<C: Collection>(_ x: C) -> Float where C.Element == Float {
        guard !x.isEmpty else { return 0 }
        return (x.reduce(0) { $0 + $1 * $1 } / Float(x.count)).squareRoot()
    }
}

/// Records the room for `AmbienceLoop` from the mic the talk key uses, and keeps it only when nobody
/// spoke in it: a voice in the loop would be untranslated speech played into the meeting.
@MainActor
final class AmbienceRecorder: ObservableObject {
    enum Phase: Equatable { case idle, recording, failed(String), saved }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var seconds = 0.0
    static let length = 15.0

    private var mic: RoomMic?
    private var timer: Timer?
    private let store = Samples()

    /// Filled from the mic's thread.
    private final class Samples: @unchecked Sendable {
        let lock = NSLock()
        var loop: [Float] = []
        var speech: [Int16] = []
        let toLoop = PCMConverter(), toSpeech = PCMConverter()
        static let speechFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false)!
        func add(_ b: AVAudioPCMBuffer) {
            lock.withLock {
                if let o = toLoop.convert(b, to: Ambience.format) {
                    loop.append(contentsOf: UnsafeBufferPointer(start: o.floatChannelData![0], count: Int(o.frameLength)))
                }
                if let o = toSpeech.convert(b, to: Self.speechFormat) {
                    speech.append(contentsOf: UnsafeBufferPointer(start: o.int16ChannelData![0], count: Int(o.frameLength)))
                }
            }
        }
        func take() -> ([Float], [Int16]) { lock.withLock { defer { loop = []; speech = [] }; return (loop, speech) } }
    }

    func start(device: OutputDevice?, voiceMic: VoiceMic) {
        cancel()
        guard let device, !device.isVirtualMic else { phase = .failed(L("没有可用的麦克风")); return }
        if voiceMic.inUse { phase = .failed(L("请先关闭会议麦克风并松开说话键，再录制")); return }
        voiceMic.release()
        _ = store.take()
        let mic = RoomMic(device: device)
        let store = store
        mic.onAudio = { store.add($0) }
        do { try mic.start() } catch {
            phase = .failed(L("无法打开麦克风：\(error.localizedDescription)"))
            return
        }
        self.mic = mic
        seconds = 0
        phase = .recording
        let began = Date()
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.seconds = Date().timeIntervalSince(began)
                if self.seconds >= Self.length { self.finish() }
            }
        }
        timer = t
        RunLoop.main.add(t, forMode: .common)
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        mic?.stop()
        mic = nil
        if phase == .recording { phase = .idle }
    }

    private func finish() {
        cancel()
        let (loop, speech) = store.take()
        let measure = PressSpeech.measure(speech)
        debugLog("ambience: recorded \(String(format: "%.1f", Double(loop.count) / AmbienceLoop.rate)) s, \(measure.summary)")
        if measure.spoken {
            phase = .failed(L("录到了说话或较响的声音，请保持安静重录"))
            return
        }
        switch AmbienceLoop.make(loop) {
        case .success(let samples):
            do {
                try Ambience.save(samples)
                debugLog("ambience: saved a \(String(format: "%.1f", Double(samples.count) / AmbienceLoop.rate)) s loop")
                phase = .saved
            } catch {
                phase = .failed(L("没保存：\(error.localizedDescription)"))
            }
        case .failure(.silent):
            phase = .failed(L("麦克风没收到声音，请检查麦克风权限"))
        case .failure(.tooShort):
            phase = .failed(L("环境太吵，请换个安静的时候重录"))
        }
    }
}
