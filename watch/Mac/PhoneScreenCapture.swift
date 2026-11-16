import AppKit
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

/// Capture on demand. Concurrent polls share one snapshot and an idle phone costs no capture work.
@MainActor
final class PhoneScreenCapture {
    private var capture: Task<LANServer.ScreenFrame, Never>?
    private var lastCapture = -Double.infinity
    private var stopped = false
    private var privateWindowIDs: Set<CGWindowID> {
        Set(NSApp.windows.filter { $0.isVisible && $0.sharingType == .none }.compactMap {
            CGWindowID(exactly: $0.windowNumber)
        })
    }

    func stop() {
        stopped = true
        capture?.cancel()
    }

    func nextFrame() async -> LANServer.ScreenFrame {
        guard !stopped else { return .off }
        if let capture { return await capture.value }
        guard ProcessInfo.processInfo.systemUptime - lastCapture >= 0.125 else { return .waiting }
        let capture = Task { [weak self] in
            await self?.captureFrame() ?? .off
        }
        self.capture = capture
        let frame = await capture.value
        self.capture = nil
        guard !stopped else { return .off }
        lastCapture = ProcessInfo.processInfo.systemUptime
        return frame
    }

    private func captureFrame() async -> LANServer.ScreenFrame {
        guard !Task.isCancelled, CGPreflightScreenCaptureAccess() else { return .unavailable }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard !Task.isCancelled else { return .off }
            guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) else {
                return .unavailable
            }
            let privateIDs = privateWindowIDs
            let excluded = content.windows.filter { privateIDs.contains($0.windowID) }
            let filter = SCContentFilter(display: display, excludingWindows: excluded)
            let config = SCStreamConfiguration()
            let width = max(display.width, 1)
            let height = max(display.height, 1)
            let scale = min(1, 1440.0 / Double(max(width, height)))
            config.width = max(1, Int(Double(width) * scale))
            config.height = max(1, Int(Double(height) * scale))
            config.showsCursor = true
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            guard !Task.isCancelled else { return .off }
            guard let jpeg = await Self.encode(image) else { return .unavailable }
            // Discard an in-flight image if a previously shareable Cicada window became private.
            guard privateWindowIDs.isSubset(of: privateIDs) else { return .waiting }
            return .image(jpeg)
        } catch {
            return .unavailable
        }
    }

    private nonisolated static func encode(_ image: CGImage) async -> Data? {
        let data = NSMutableData()
        guard let encoder = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(encoder, image, [kCGImageDestinationLossyCompressionQuality: 0.68] as CFDictionary)
        return CGImageDestinationFinalize(encoder) ? data as Data : nil
    }
}
