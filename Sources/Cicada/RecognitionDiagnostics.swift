import AVFoundation
import Speech
import os

/// Technical breadcrumbs survive relaunches; never pass transcript text, audio or error userInfo.
/// File work stays off audio callbacks. Three 1 MB files bound disk usage.
final class RecognitionDiagnosticLog: @unchecked Sendable {
    static let shared = RecognitionDiagnosticLog(directory: FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs/\(DevBuild.supportFolder)/Recognition", isDirectory: true))
    private let queue = DispatchQueue(label: "cicada.recognition.diagnostics", qos: .utility)
    private let directory: URL
    private let limit: Int
    private let fallback = Logger(subsystem: "com.wquguru.cicada", category: "recognition-diagnostics")

    init(directory: URL, limit: Int = 1_048_576) {
        self.directory = directory
        self.limit = limit
    }

    func write(_ event: String) {
        let line = "\(Date()) pid=\(ProcessInfo.processInfo.processIdentifier) \(event)\n"
        queue.async { [self] in
            do {
                let fm = FileManager.default
                try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                                       attributes: [.posixPermissions: 0o700])
                let url = directory.appendingPathComponent("recognition.log")
                let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
                if size + line.utf8.count > limit {
                    let oldest = directory.appendingPathComponent("recognition.2.log")
                    if fm.fileExists(atPath: oldest.path) { try fm.removeItem(at: oldest) }
                    let previous = directory.appendingPathComponent("recognition.1.log")
                    if fm.fileExists(atPath: previous.path) { try fm.moveItem(at: previous, to: oldest) }
                    if fm.fileExists(atPath: url.path) { try fm.moveItem(at: url, to: previous) }
                }
                if !fm.fileExists(atPath: url.path) {
                    guard fm.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                        throw CocoaError(.fileWriteUnknown)
                    }
                }
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(line.utf8))
            } catch {
                fallback.error("Local diagnostic write failed: \((error as NSError).code)")
            }
        }
    }

    /// Tests only: never wait for disk from an audio callback.
    func flush() { queue.sync {} }
}

enum RecognitionBuffer {
    enum Invalid: String, Error { case empty, format, layout, size, allocation }

    static func validate(_ buffer: AudioBuffer, channels: AVAudioChannelCount, bytes: UInt64) throws {
        guard buffer.mData != nil, buffer.mNumberChannels == channels,
              UInt64(buffer.mDataByteSize) >= bytes else { throw Invalid.size }
    }

    /// Each analyzer owns its samples, even when a caller reuses a file/converter buffer or
    /// TeeStream sends the same block to two independent SpeechAnalyzers.
    static func copy(_ source: AVAudioPCMBuffer, format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        guard source.frameLength > 0, source.frameLength <= source.frameCapacity else { throw Invalid.empty }
        guard source.format == format, format.sampleRate.isFinite, format.sampleRate > 0,
              format.channelCount > 0 else { throw Invalid.format }
        let bytes = UInt64(source.frameLength) * UInt64(format.streamDescription.pointee.mBytesPerFrame)
        guard bytes > 0, bytes <= UInt64(UInt32.max) else { throw Invalid.size }
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: source.audioBufferList))
        let expected = format.isInterleaved ? 1 : Int(format.channelCount)
        guard buffers.count == expected else { throw Invalid.layout }
        for b in buffers {
            try validate(b, channels: format.isInterleaved ? format.channelCount : 1, bytes: bytes)
        }
        guard let result = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: source.frameLength) else { throw Invalid.allocation }
        result.frameLength = source.frameLength
        let destination = UnsafeMutableAudioBufferListPointer(result.mutableAudioBufferList)
        for (src, dst) in zip(buffers, destination) {
            guard let from = src.mData, let to = dst.mData, UInt64(dst.mDataByteSize) >= bytes else { throw Invalid.size }
            memcpy(to, from, Int(bytes))
        }
        return result
    }
}

@available(macOS 26, *)
final class RecognitionInput: @unchecked Sendable {
    let id = UUID().uuidString
    private let format: AVAudioFormat
    private let continuation: AsyncStream<AnalyzerInput>.Continuation
    private let lock = NSLock()
    private var closed = false
    private var blocks = 0
    private var rejected = 0
    private var lastCheckpoint = Date.distantPast

    init(format: AVAudioFormat, continuation: AsyncStream<AnalyzerInput>.Continuation, role: String) {
        self.format = format
        self.continuation = continuation
        event("created role=\(role) os=\(ProcessInfo.processInfo.operatingSystemVersionString) rate=\(format.sampleRate) channels=\(format.channelCount) pcm=\(format.commonFormat.rawValue)")
    }

    func event(_ name: String) { RecognitionDiagnosticLog.shared.write("stream=\(id) \(name)") }
    func error(_ stage: String, _ error: Error) {
        let ns = error as NSError
        // localizedDescription/userInfo may contain meeting content or service credentials.
        event("error stage=\(stage) domain=\(ns.domain) code=\(ns.code)")
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.withLock {
            guard !closed else { return }
            do {
                let owned = try RecognitionBuffer.copy(buffer, format: format)
                blocks += 1
                if Date().timeIntervalSince(lastCheckpoint) >= 5 {
                    lastCheckpoint = Date()
                    event("audio block=\(blocks) frames=\(buffer.frameLength) capacity=\(buffer.frameCapacity) rejected=\(rejected)")
                }
                if case .terminated = continuation.yield(AnalyzerInput(buffer: owned)) {
                    closed = true
                    event("input terminated block=\(blocks)")
                }
            } catch {
                rejected += 1
                // A broken source must not flood disk or the diagnostic queue on every callback.
                if rejected == 1 || rejected.isMultiple(of: 250) {
                    event("buffer rejected reason=\((error as? RecognitionBuffer.Invalid)?.rawValue ?? "unknown") count=\(rejected) frames=\(buffer.frameLength) capacity=\(buffer.frameCapacity)")
                }
            }
        }
    }

    func close(_ reason: String) {
        lock.withLock {
            guard !closed else { return }
            closed = true
            event("input closed reason=\(reason) blocks=\(blocks) rejected=\(rejected)")
            continuation.finish()
        }
    }
}
