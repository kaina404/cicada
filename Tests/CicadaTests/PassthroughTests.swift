import XCTest
@testable import Cicada

final class PassthroughTests: XCTestCase {
    private func write(_ b: PassthroughBuffer, _ v: Float, _ n: Int) {
        let x = [Float](repeating: v, count: n)
        x.withUnsafeBufferPointer { b.write($0) }
    }
    private func read(_ b: PassthroughBuffer, _ n: Int) -> [Float] {
        var x = [Float](repeating: 9, count: n)
        x.withUnsafeMutableBufferPointer { b.read(into: $0.baseAddress!, count: n) }
        return x
    }

    func testShutGateKeepsNothing() {
        let b = PassthroughBuffer()
        write(b, 0.5, 1600)
        XCTAssertEqual(b.buffered, 0)
        XCTAssertEqual(read(b, 256), [Float](repeating: 0, count: 256))
    }

    func testOpensWithARampNotAClick() {
        let b = PassthroughBuffer()
        b.isOpen = true
        write(b, 0.5, 1600)
        let out = read(b, 1600)
        XCTAssertEqual(out[0], 0.5 / Float(b.rampFrames), accuracy: 1e-6)
        for i in 1..<out.count { XCTAssertLessThanOrEqual(abs(out[i] - out[i - 1]), 0.5 / Float(b.rampFrames) + 1e-6) }
        XCTAssertEqual(out.last!, 0.5, accuracy: 1e-6)
    }

    func testShuttingFadesOutAndDropsWhatWasSaidMeanwhile() {
        let b = PassthroughBuffer()
        b.isOpen = true
        write(b, 0.5, 1600)
        _ = read(b, 400)
        b.isOpen = false
        let out = read(b, 400)
        for i in 1..<out.count { XCTAssertLessThanOrEqual(abs(out[i] - out[i - 1]), 0.5 / Float(b.rampFrames) + 1e-6) }
        XCTAssertEqual(out.last!, 0)
        XCTAssertEqual(b.buffered, 0)
        // Opened again later: none of the press's words come out.
        b.isOpen = true
        XCTAssertEqual(read(b, 400), [Float](repeating: 0, count: 400))
    }

    func testBacklogIsCapped() {
        let b = PassthroughBuffer()
        b.isOpen = true
        write(b, 0.1, b.maxFrames * 3)
        XCTAssertEqual(b.buffered, b.maxFrames)
    }

    func testWaitsToPrimeAfterRunningDry() {
        let b = PassthroughBuffer()
        b.isOpen = true
        write(b, 0.5, b.primeFrames - 10)
        XCTAssertEqual(read(b, 64), [Float](repeating: 0, count: 64))
        write(b, 0.5, 20)
        XCTAssertGreaterThan(read(b, 64)[63], 0)
    }

    @MainActor
    func testIdleModesExcludeEachOther() {
        let s = AppSettings()
        let (h, p) = (s.speakHandsFree, s.speakPassthrough)
        defer { s.speakHandsFree = h; s.speakPassthrough = p }
        s.speakHandsFree = true
        s.speakPassthrough = true
        XCTAssertFalse(s.speakHandsFree)
        s.speakHandsFree = true
        XCTAssertFalse(s.speakPassthrough)
    }
}
