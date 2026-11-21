import Foundation
import Testing
@testable import Cicada

@Suite struct AmbienceLoopTests {
    /// Deterministic white noise at `amplitude`.
    private func noise(_ seconds: Double, amplitude: Float = 0.01, seed: UInt64 = 1) -> [Float] {
        var g = SplitMix(seed)
        return (0..<Int(seconds * AmbienceLoop.rate)).map { _ in Float.random(in: -amplitude...amplitude, using: &g) }
    }

    @Test func loopsAtTheTargetLevel() throws {
        let loop = try AmbienceLoop.make(noise(10)).get()
        #expect(abs(AmbienceLoop.rms(loop) - AmbienceLoop.level) < 0.0002)
        #expect(Double(loop.count) / AmbienceLoop.rate > 6)
    }

    /// Played back to back, the step across the seam is no bigger than the steps inside the loop.
    @Test func seamIsInaudible() throws {
        let loop = try AmbienceLoop.make(noise(10)).get()
        let steps = zip(loop, loop.dropFirst()).map { abs($1 - $0) }
        let typical = steps.sorted()[steps.count * 99 / 100]
        #expect(abs(loop[0] - loop[loop.count - 1]) <= typical)
        // The edges are as loud as the middle: no dip or bump where it wraps.
        let edge = AmbienceLoop.rms(loop.prefix(2_400) + loop.suffix(2_400))
        #expect(abs(edge - AmbienceLoop.level) / AmbienceLoop.level < 0.3)
    }

    @Test func dropsAKnock() throws {
        var x = noise(10)
        let at = Int(5 * AmbienceLoop.rate)
        for i in at..<(at + 1_200) { x[i] = i % 2 == 0 ? 0.5 : -0.5 }
        let loop = try AmbienceLoop.make(x).get()
        #expect(loop.allSatisfy { abs($0) < 0.02 })
    }

    @Test func capsALoneSpike() throws {
        var x = noise(10)
        x[Int(5 * AmbienceLoop.rate)] = 0.3
        let loop = try AmbienceLoop.make(x).get()
        #expect(loop.allSatisfy { abs($0) <= AmbienceLoop.level * 6 })
    }

    @Test func rejectsSilenceAndShortClips() {
        #expect(AmbienceLoop.make([Float](repeating: 0, count: 240_000)) == .failure(.silent))
        #expect(AmbienceLoop.make(noise(3)) == .failure(.tooShort))
    }

    @Test func gainIsCenteredOnTheSavedLevel() {
        #expect(abs(Ambience.gain(0.5) - 1) < 0.0001)
        #expect(Ambience.gain(1) > 3.9 && Ambience.gain(0) < 0.26)
    }
}

private struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    init(_ seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
