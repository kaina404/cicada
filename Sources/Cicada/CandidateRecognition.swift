import AVFoundation
import Foundation
import NaturalLanguage

/// The candidate channel uses local Gemma for drafts and final records, independently of the script.
final class CandidateRecognition: RecognitionStream, @unchecked Sendable {
    let format: AVAudioFormat
    let results: AsyncThrowingStream<Recognition.Piece, Error>
    private let input: AsyncStream<[Float]>.Continuation
    private let consumer: Task<Void, Never>
    private let worker: CandidateTranscriber

    @MainActor init(infer: CoachReading.Infer? = nil) {
        format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        let output = AsyncThrowingStream<Recognition.Piece, Error>.makeStream()
        results = output.stream
        let packets = AsyncStream<[Float]>.makeStream()
        input = packets.continuation
        let server = VisionServer()
        let recognize: CoachReading.Infer = infer ?? { messages in
            if !(await VisionServer.waitReady(seconds: 0)) {
                server.start(model: CoachPrompt.model)
                guard await VisionServer.waitReady(seconds: 90) else { throw URLError(.cannotConnectToHost) }
            }
            return try await CoachReading.infer(messages)
        }
        let worker = CandidateTranscriber(infer: recognize, output: output.continuation)
        self.worker = worker
        consumer = Task { @MainActor in
            for await samples in packets.stream { worker.append(samples) }
        }
    }
    func append(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData else { return }
        input.yield(Array(UnsafeBufferPointer(start: channel[0], count: Int(buffer.frameLength))))
    }
    func finalize(through seconds: Double) async throws { await worker.flush() }
    func finish() async {
        input.finish(); await consumer.value
        await worker.finish()
    }
    func cancel() async {
        input.finish(); consumer.cancel(); await consumer.value
        await worker.cancel()
    }
}

@MainActor
final class CandidateTranscriber {
    private struct Clip {
        var id: Int
        var samples: [Float]
        var start: Double
        var end: Double
    }
    private let infer: CoachReading.Infer
    private let output: AsyncThrowingStream<Recognition.Piece, Error>.Continuation
    private var samples: [Float] = []
    private var queued: [Clip] = []
    private var clock = 0.0
    private var start = 0.0
    private var silence = 0.0
    private var voiced = false
    private var id = 0
    private var processed = 0
    private var stopped = false
    private var task: Task<Void, Never>?

    init(infer: @escaping CoachReading.Infer, output: AsyncThrowingStream<Recognition.Piece, Error>.Continuation) {
        self.infer = infer; self.output = output
    }
    func append(_ audio: [Float]) {
        guard !stopped, !audio.isEmpty else { return }
        let duration = Double(audio.count) / 16000
        let speech = audio.reduce(Float(0)) { $0 + $1 * $1 } / Float(audio.count) > 0.000025
        clock += duration
        if samples.isEmpty { start = clock - duration }
        // Keep a little leading silence, but never submit silence-only clips to the model.
        samples.append(contentsOf: audio)
        if speech { voiced = true; silence = 0 } else { silence += duration }
        if !voiced, samples.count > 3200 {
            samples = Array(samples.suffix(3200)); start = clock - Double(samples.count) / 16000
        }
        if voiced, silence >= 0.6 || samples.count >= 192000 { flush() }
        if queued.reduce(0, { $0 + $1.samples.count }) > 960000 {
            fail(URLError(.dataLengthExceedsMaximum)); return
        }
        pump()
    }
    func flush() {
        guard !stopped, voiced, !samples.isEmpty else { return }
        queued.append(Clip(id: id, samples: samples, start: start, end: clock))
        id += 1; samples = []; voiced = false; silence = 0; processed = 0
        pump()
    }
    private func pump() {
        guard !stopped, task == nil else { return }
        let final = !queued.isEmpty
        guard final || voiced && samples.count - processed >= 32000 else { return }
        let clip = final ? queued.removeFirst() : Clip(id: id, samples: samples, start: start, end: clock)
        if !final { processed = samples.count }
        task = Task { [weak self] in
            guard let self else { return }
            do {
                var buffer = CoachAudioBuffer()
                buffer.append(RealtimeMedia.pcm(clip.samples), endingAt: Double(clip.samples.count) / 16000)
                let messages = CoachReadingPrompt.transcribe(wav: buffer.wav)
                var text = ""
                for attempt in 0..<3 {
                    do { text = try await self.infer(messages); break }
                    catch {
                        if Task.isCancelled || attempt == 2 { throw error }
                        try await Task.sleep(for: .seconds(1))
                    }
                }
                guard !self.stopped, !Task.isCancelled else { return }
                text = text.trimmingCharacters(in: .whitespacesAndNewlines)
                // A delayed draft from a sealed clip must not overwrite a later utterance.
                if final || clip.id == self.id {
                    self.output.yield(Recognition.Piece(text: text, isFinal: final,
                                                       start: clip.start, end: clip.end, confidence: nil,
                                                       language: Self.language(text)))
                }
                self.task = nil; self.pump()
            } catch {
                guard !self.stopped, !Task.isCancelled else { return }
                self.fail(error)
            }
        }
    }
    private static func language(_ text: String) -> String {
        let language = NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue ?? "en"
        return language == "zh-Hans" || language == "zh-Hant" ? "zh-CN" : language
    }
    func finish() async {
        flush()
        while let running = task { await running.value }
        stopped = true; output.finish()
    }
    func cancel() {
        stopped = true; task?.cancel(); task = nil; samples = []; queued = []; output.finish()
    }
    private func fail(_ error: Error) {
        stopped = true; task?.cancel(); samples = []; queued = []; task = nil; output.finish(throwing: error)
    }
}
