import Foundation
import AVFoundation
import CoreML
import Accelerate
enum Fbank {
    static let bins = 80
    static let frameLength = 400
    static let shift = 160
    private static let fftSize = 512

    private static let window: [Float] = (0..<frameLength).map {
        pow(0.5 - 0.5 * cos(2 * Float.pi * Float($0) / Float(frameLength - 1)), 0.85)
    }

    /// `bins` rows of `fftSize / 2 + 1` weights (the Nyquist column is always zero, as in Kaldi).
    private static let melBanks: [Float] = {
        func mel(_ f: Double) -> Double { 1127 * log(1 + f / 700) }
        let cols = fftSize / 2 + 1
        let lo = mel(20), hi = mel(8000), delta = (hi - lo) / Double(bins + 1)
        var w = [Float](repeating: 0, count: bins * cols)
        for m in 0..<bins {
            let left = lo + Double(m) * delta, center = left + delta, right = center + delta
            for k in 0..<(fftSize / 2) {
                let x = mel(Double(k) * 16000 / Double(fftSize))
                let v = min((x - left) / (center - left), (right - x) / (right - center))
                if v > 0 { w[m * cols + k] = Float(v) }
            }
        }
        return w
    }()

    private static let setup = vDSP_create_fftsetup(9, FFTRadix(kFFTRadix2))!

    /// Frames × `bins`, row-major. `samples` are 16 kHz mono in -1...1.
    static func compute(_ samples: [Float]) -> [Float] {
        guard samples.count >= frameLength else { return [] }
        let frames = 1 + (samples.count - frameLength) / shift
        let cols = fftSize / 2 + 1
        var out = [Float](repeating: 0, count: frames * bins)
        var frame = [Float](repeating: 0, count: fftSize)
        var re = [Float](repeating: 0, count: fftSize / 2), im = re
        var power = [Float](repeating: 0, count: cols)
        var mels = [Float](repeating: 0, count: bins)
        for f in 0..<frames {
            let start = f * shift
            for i in 0..<frameLength { frame[i] = samples[start + i] * 32768 }
            for i in frameLength..<fftSize { frame[i] = 0 }
            var mean: Float = 0
            vDSP_meanv(frame, 1, &mean, vDSP_Length(frameLength))
            for i in 0..<frameLength { frame[i] -= mean }
            for i in stride(from: frameLength - 1, to: 0, by: -1) { frame[i] -= 0.97 * frame[i - 1] }
            frame[0] -= 0.97 * frame[0]
            vDSP_vmul(frame, 1, window, 1, &frame, 1, vDSP_Length(frameLength))
            re.withUnsafeMutableBufferPointer { rp in
                im.withUnsafeMutableBufferPointer { ip in
                    var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    frame.withUnsafeBytes { raw in
                        vDSP_ctoz(raw.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(fftSize / 2))
                    }
                    vDSP_fft_zrip(setup, &split, 1, 9, FFTDirection(FFT_FORWARD))
                }
            }
            // vDSP's real FFT returns twice the true values, Nyquist packed into im[0].
            power[0] = re[0] * re[0] / 4
            power[cols - 1] = im[0] * im[0] / 4
            for k in 1..<(fftSize / 2) { power[k] = (re[k] * re[k] + im[k] * im[k]) / 4 }
            vDSP_mmul(melBanks, 1, power, 1, &mels, 1, vDSP_Length(bins), 1, vDSP_Length(cols))
            for b in 0..<bins { out[f * bins + b] = log(max(mels[b], .ulpOfOne)) }
        }
        return out
    }
}


final class Voiceprints {
 static let minSeconds = 0.5
 static let maxSeconds = 20.0
 let model: MLModel
 init(_ model: MLModel) { self.model = model }
    func embed(_ samples: [Float]) -> [Float]? {
        guard Double(samples.count) >= Self.minSeconds * 16000 else { return nil }
        let clip = samples.count > Int(Self.maxSeconds * 16000) ? Array(samples.prefix(Int(Self.maxSeconds * 16000))) : samples
        var feats = Fbank.compute(clip)
        let frames = feats.count / Fbank.bins
        guard frames >= 50 else { return nil }
        // Mean normalisation per bin over the clip, as in training.
        for b in 0..<Fbank.bins {
            var sum: Float = 0
            for f in 0..<frames { sum += feats[f * Fbank.bins + b] }
            let mean = sum / Float(frames)
            for f in 0..<frames { feats[f * Fbank.bins + b] -= mean }
        }
        guard let input = try? MLMultiArray(shape: [1, NSNumber(value: frames), NSNumber(value: Fbank.bins)], dataType: .float32) else { return nil }
        feats.withUnsafeBufferPointer { src in
            input.withUnsafeMutableBytes { dst, _ in
                dst.copyMemory(from: UnsafeRawBufferPointer(src))
            }
        }
        guard let out = try? model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["feats": input])),
              let embs = out.featureValue(for: "embs")?.multiArrayValue else { return nil }
        var v = (0..<embs.count).map { Float(truncating: embs[$0]) }
        var norm: Float = 0
        vDSP_svesq(v, 1, &norm, vDSP_Length(v.count))
        guard norm > 0 else { return nil }
        vDSP_vsdiv(v, 1, [norm.squareRoot()], &v, 1, vDSP_Length(v.count))
        return v
    }
}

let args = CommandLine.arguments
let config = MLModelConfiguration()
config.computeUnits = .cpuAndGPU
let model = try MLModel(contentsOf: URL(fileURLWithPath: args[1]), configuration: config)
let vp = Voiceprints(model)
let file = try AVAudioFile(forReading: URL(fileURLWithPath: args[2]))
let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
try file.read(into: buf)
let samples = Array(UnsafeBufferPointer(start: buf.floatChannelData![0], count: Int(buf.frameLength)))
func clip(_ start: Double, _ end: Double) -> [Float] {
 Array(samples[max(0,Int(start*16000))..<min(samples.count,Int(end*16000))])
}
func dot(_ a: [Float], _ b: [Float]) -> Float { zip(a,b).reduce(0) { $0 + $1.0 * $1.1 } }
func centroid(_ ranges: [(Double,Double)]) -> [Float] {
 let embs = ranges.compactMap { vp.embed(clip($0.0,$0.1)) }
 var c = [Float](repeating: 0, count: embs[0].count)
 for e in embs { for i in c.indices { c[i] += e[i] } }
 let norm = sqrt(dot(c,c));return c.map { $0/norm }
}
// Known alternating opening turns; long examples avoid gender inference from text.
let male = centroid([(0,1.5),(8.3,11.9),(23.2,28),(28.3,32.7),(32.8,40)])
let female = centroid([(1.7,3.4),(3.5,6.5),(20.9,23.2),(3180.2,3185.9)])
print("reference similarity: \(dot(male,female))")
FileManager.default.createFile(atPath: args[3], contents: nil)
let out = try FileHandle(forWritingTo: URL(fileURLWithPath: args[3]))
try out.write(contentsOf: Data("center,male,female,rms\n".utf8))
let duration = Double(samples.count)/16000
var center = 0.0
var index = 0
while center < duration {
 autoreleasepool {
  let audio = clip(max(0,center-0.8),min(duration,center+0.8))
  let rms = sqrt(audio.reduce(Float(0)) { $0 + $1*$1 }/Float(audio.count))
  let e = rms > 0.002 ? vp.embed(audio) : nil
  let m = e.map { dot($0,male) } ?? 0
  let f = e.map { dot($0,female) } ?? 0
  try! out.write(contentsOf: Data("\(center),\(m),\(f),\(rms)\n".utf8))
 }
 index += 1
 if index % 400 == 0 { print("classified \(Int(center)) / \(Int(duration)) s"); fflush(stdout) }
 center += 0.25
}
try out.close()
print("DONE")
