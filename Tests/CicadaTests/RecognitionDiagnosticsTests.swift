import AVFoundation
import Speech
import Testing
@testable import Cicada

@Suite struct RecognitionDiagnosticsTests {
    @Test func inputClosesBeforeFurtherAudioIsAccepted() async throws {
        guard #available(macOS 26, *) else { return }
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000,
                                               channels: 1, interleaved: false))
        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let input = RecognitionInput(format: format, continuation: continuation, role: "test")
        let source = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160))
        source.frameLength = 160
        input.append(source)
        input.close("test")
        input.close("duplicate")
        input.append(source)
        var count = 0
        for await _ in stream { count += 1 }
        #expect(count == 1)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CICADA_RECOGNITION_SMOKE_AUDIO"] != nil))
    func realAnalyzersWithReusedSource() async throws {
        guard #available(macOS 26, *),
              let path = ProcessInfo.processInfo.environment["CICADA_RECOGNITION_SMOKE_AUDIO"] else { return }
        let live = try await Analyzer.start("en-US", drafts: true, confidence: false)
        let record = try await RecordTrack.start("en-US", format: live.format)
        let tee = TeeStream(live: live, record: record)
        let reading = Task { () throws -> String in
            var text = ""
            for try await piece in live.results where piece.isFinal { text += piece.text }
            return text
        }
        let recording = Task { () throws -> Int in
            var count = 0
            for try await sentence in record.sentences { count += sentence.runs.count }
            return count
        }
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: path),
                                   commonFormat: live.format.commonFormat, interleaved: live.format.isInterleaved)
        let source = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096))
        let converter = PCMConverter()
        while file.framePosition < file.length {
            try file.read(into: source)
            if let buffer = converter.convert(source, to: live.format) {
                tee.append(buffer)
                // Reuse immediately, while both analyzers may still be reading their copies.
                for b in UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList) {
                    memset(b.mData, 0, Int(b.mDataByteSize))
                }
            }
        }
        await tee.finish()
        let text = try await reading.value
        let runs = try await recording.value
        #expect(text.lowercased().contains("android"))
        #expect(runs > 0)
    }

    @Test(arguments: [false, true]) func independentSamples(interleaved: Bool) throws {
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000,
                                               channels: 2, interleaved: interleaved))
        let source = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 320))
        source.frameLength = 160
        for b in UnsafeMutableAudioBufferListPointer(source.mutableAudioBufferList) {
            memset(b.mData, 0x2a, Int(b.mDataByteSize))
        }
        let live = try RecognitionBuffer.copy(source, format: format)
        let record = try RecognitionBuffer.copy(source, format: format)
        for b in UnsafeMutableAudioBufferListPointer(source.mutableAudioBufferList) {
            memset(b.mData, 0, Int(b.mDataByteSize))
        }
        #expect(live.frameLength == 160)
        #expect(live.frameCapacity == 160)
        for b in UnsafeMutableAudioBufferListPointer(live.mutableAudioBufferList) {
            #expect(b.mData?.load(as: UInt8.self) == 0x2a)
            memset(b.mData, 0, Int(b.mDataByteSize))
        }
        for b in UnsafeMutableAudioBufferListPointer(record.mutableAudioBufferList) {
            #expect(b.mData?.load(as: UInt8.self) == 0x2a)
        }
    }

    @Test func rejectsMalformedBuffers() throws {
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000,
                                               channels: 1, interleaved: false))
        let b = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160))
        #expect(throws: RecognitionBuffer.Invalid.empty) { try RecognitionBuffer.copy(b, format: format) }
        b.frameLength = 160
        let other = try #require(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000,
                                              channels: 1, interleaved: false))
        #expect(throws: RecognitionBuffer.Invalid.format) { try RecognitionBuffer.copy(b, format: other) }
        // AVAudioPCMBuffer normalizes its AudioBufferList on access. Exercise malformed
        // external descriptors directly rather than trying to corrupt Apple's managed list.
        let data = try #require(b.floatChannelData?[0])
        let truncated = AudioBuffer(mNumberChannels: 1, mDataByteSize: 1, mData: data)
        #expect(throws: RecognitionBuffer.Invalid.size) {
            try RecognitionBuffer.validate(truncated, channels: 1, bytes: 640)
        }
        let missing = AudioBuffer(mNumberChannels: 1, mDataByteSize: 640, mData: nil)
        #expect(throws: RecognitionBuffer.Invalid.size) {
            try RecognitionBuffer.validate(missing, channels: 1, bytes: 640)
        }
    }

    @Test func logsSurviveReopeningRotateAndStayPrivate() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = RecognitionDiagnosticLog(directory: directory, limit: 256)
        first.write("before restart")
        first.flush()
        let reopened = RecognitionDiagnosticLog(directory: directory, limit: 256)
        reopened.write("after restart")
        reopened.flush()
        let url = directory.appendingPathComponent("recognition.log")
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("before restart"))
        #expect(text.contains("after restart"))
        for i in 0..<30 { reopened.write("checkpoint block=\(i)") }
        reopened.flush()
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        #expect(files.count == 3)
        for file in files {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
            #expect((attributes[.size] as? NSNumber)?.intValue ?? 999 < 256)
        }
    }
}
