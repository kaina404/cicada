@preconcurrency import AVFoundation
import Foundation

/// Optional fast, local-only drafts for display-only reading follow (`FastReadingFollow`).
/// Gemma still owns records and coach progress.
@MainActor
final class ShadowRecognition {
    var onText: ((String, Bool) -> Void)?
    /// False when the on-device English model is missing or this Mac cannot run it.
    var onReady: ((Bool) -> Void)?
    private var task: Task<Void, Never>?
    private var stream: RecognitionStream?
    private let feeder = ShadowRecognitionFeed()
    private var token = UUID()
    private var attempted = false

    func start() {
        guard !attempted else { return }
        attempted = true
        // Never take over the legacy recognizer or silently route candidate audio to a service.
        guard #available(macOS 26, *), !Recognition.cloudOnly, !Recognition.legacy, Recognition.host == nil else { onReady?(false); return }
        let token = token
        task = Task { [weak self] in
            guard case .installed = await Recognition.status("en-US") else { self?.onReady?(false); return }
            do {
                let stream = try await Recognition.start("en-US", drafts: true)
                guard let self, self.token == token, !Task.isCancelled else { await stream.cancel(); return }
                self.stream = stream
                self.onReady?(true)
                for try await piece in stream.results {
                    guard self.token == token, !Task.isCancelled else { break }
                    self.onText?(piece.text, piece.isFinal)
                }
                await stream.cancel()
            } catch {
                // Model-based progress remains available when fast drafts are unavailable.
                if self?.token == token { self?.onReady?(false) }
            }
        }
    }
    func append(_ samples: [Float]) {
        guard let stream, !samples.isEmpty else { return }
        feeder.append(samples, to: stream)
    }

    func stop() {
        token = UUID(); task?.cancel(); task = nil; attempted = false
        let stream = stream; self.stream = nil
        if let stream { Task { await stream.cancel() } }
        feeder.reset()
    }
}

/// Converter state belongs exclusively to this serial lane, including resets after cancellation.
private final class ShadowRecognitionFeed: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.wquguru.cicada.shadow.recognition", qos: .userInitiated)
    private var converter = PCMConverter()
    func append(_ samples: [Float], to stream: RecognitionStream) {
        queue.async { [self] in
            guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
                  let channel = buffer.floatChannelData?[0] else { return }
            buffer.frameLength = buffer.frameCapacity
            samples.withUnsafeBufferPointer { if let base = $0.baseAddress { channel.update(from: base, count: samples.count) } }
            if let converted = converter.convert(buffer, to: stream.format) { stream.append(converted) }
        }
    }
    func reset() { queue.async { [self] in converter = PCMConverter() } }
}
