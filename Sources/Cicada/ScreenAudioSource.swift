import AppKit
import AVFoundation
import ScreenCaptureKit

/// Audio-only ScreenCaptureKit stream. The caller retains the process-tap fallback for missing permission.
final class ScreenAudioSource: NSObject, AudioSource, SCStreamOutput, SCStreamDelegate {
    var onAudio: ((AVAudioPCMBuffer) -> Void)?
    var onFailed: (() -> Void)?
    private var stream: SCStream?
    private var startup: Task<Void, Never>?
    private var run = UUID()
    private let queue = DispatchQueue(label: "cicada.screen.audio", qos: .userInitiated)

    func start() throws {
        let token = run
        startup = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard !Task.isCancelled, run == token, let display = content.displays.first else { return }
                let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
                let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
                let config = SCStreamConfiguration()
                config.capturesAudio = true; config.excludesCurrentProcessAudio = true
                config.sampleRate = 16000; config.channelCount = 1
                config.width = 2; config.height = 2
                config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
                let next = SCStream(filter: filter, configuration: config, delegate: self)
                try next.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
                stream = next
                try await next.startCapture()
                guard !Task.isCancelled, run == token else { try? await next.stopCapture(); return }
                debugLog("coach: ScreenCaptureKit system audio started")
            } catch {
                guard !Task.isCancelled, run == token else { return }
                onFailed?()
            }
        }
    }
    func stop() {
        run = UUID(); startup?.cancel(); startup = nil
        if let stream { Task { try? await stream.stopCapture() } }
        stream = nil
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, self.stream === stream else { return }
            self.onFailed?()
        }
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, CMSampleBufferDataIsReady(buffer),
              let description = CMSampleBufferGetFormatDescription(buffer) else { return }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(CMSampleBufferGetNumSamples(buffer))) else { return }
        pcm.frameLength = pcm.frameCapacity
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(buffer, at: 0, frameCount: Int32(pcm.frameLength), into: pcm.mutableAudioBufferList) == noErr else { return }
        onAudio?(pcm)
    }
}
