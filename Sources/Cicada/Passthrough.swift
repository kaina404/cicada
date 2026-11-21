import Foundation

/// 原声直通's audio between the echo-cancelled mic (`micQueue`) and the output engine's render
/// thread: a short FIFO with a gate. The gate shuts the moment the talk key is pressed and opens
/// only after the translation has played, so the room never hears my own words and their
/// translation over each other. Gate changes ramp over `rampFrames` (a hard cut is a click), and a
/// shut gate throws what it held away: words said during a press must not come out after it.
/// Pure (no audio objects), for the tests.
final class PassthroughBuffer: @unchecked Sendable {
    /// 16 kHz: `VoiceMic.format`.
    let rate: Double
    /// Held at most (older audio is dropped): the mic and the output run on different clocks, and
    /// a backlog would be heard as delay.
    let maxFrames: Int
    /// Buffered before playing starts again after running dry, so a late mic block isn't a gap each time.
    let primeFrames: Int
    /// 20 ms.
    let rampFrames: Int

    private let lock = NSLock()
    private var fifo: [Float] = []
    private var head = 0
    private var gain: Float = 0
    private var open = false
    private var primed = false
    /// Debug (`passState`): what went out since the last look, split by the gate.
    private var openSquares = 0.0, openFrames = 0, shutPeak: Float = 0, shutFrames = 0

    init(rate: Double = 16_000, maxSeconds: Double = 0.2, primeSeconds: Double = 0.03, rampSeconds: Double = 0.02) {
        self.rate = rate
        maxFrames = Int(rate * maxSeconds)
        primeFrames = Int(rate * primeSeconds)
        rampFrames = max(1, Int(rate * rampSeconds))
    }

    var isOpen: Bool {
        get { lock.withLock { open } }
        set { lock.withLock { open = newValue } }
    }

    var buffered: Int { lock.withLock { fifo.count - head } }

    /// From the mic. Nothing is kept while the gate is shut.
    func write(_ samples: UnsafeBufferPointer<Float>) {
        lock.withLock {
            guard open else { return }
            fifo.append(contentsOf: samples)
            let over = fifo.count - head - maxFrames
            if over > 0 { head += over }
            if head > 4096 { fifo.removeFirst(head); head = 0 }
        }
    }

    /// Since the last call: the open gate's RMS in dBFS and seconds, the shut gate's peak and seconds.
    func takeStats() -> (openDB: Double, openSeconds: Double, shutPeak: Float, shutSeconds: Double) {
        lock.withLock {
            defer { openSquares = 0; openFrames = 0; shutPeak = 0; shutFrames = 0 }
            let rms = openFrames > 0 ? (openSquares / Double(openFrames)).squareRoot() : 0
            return (20 * log10(max(rms, 1e-9)), Double(openFrames) / rate, shutPeak, Double(shutFrames) / rate)
        }
    }

    /// From the render thread: fills `out` with `count` frames, silence where there is nothing to play.
    func read(into out: UnsafeMutablePointer<Float>, count: Int) {
        lock.withLock {
            let target: Float = open ? 1 : 0
            let step = 1 / Float(rampFrames)
            if fifo.count - head >= primeFrames { primed = true }
            for i in 0..<count {
                if gain < target { gain = min(target, gain + step) } else if gain > target { gain = max(target, gain - step) }
                var s: Float = 0
                if primed, head < fifo.count { s = fifo[head]; head += 1 } else { primed = false }
                out[i] = s * gain
                if open { openSquares += Double(out[i] * out[i]); openFrames += 1 } else if gain == 0 { shutPeak = max(shutPeak, abs(out[i])); shutFrames += 1 }
            }
            // Shut and faded out: what is left was said during the press.
            if !open, gain == 0 { fifo.removeAll(keepingCapacity: true); head = 0; primed = false }
        }
    }
}
