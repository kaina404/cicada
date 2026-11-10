import AppKit
import SwiftUI
import Testing
@testable import Cicada

@MainActor
struct AssistantVolumeUITests {
    @Test func volumeControls() async throws {
        guard let directory = ProcessInfo.processInfo.environment["CICADA_TEST_VOLUME_UI"] else { return }
        _ = NSApplication.shared
        let settings = AppSettings()
        let old = settings.shadowReading
        settings.shadowReading = true
        defer { settings.shadowReading = old }
        let reader = ShadowReader(audio: ShadowReaderTests.Driver(), automatic: false)
        let coach = InterviewCoach()
        let window = NSWindow(contentRect: NSRect(x: 100, y: 150, width: 640, height: 490),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Assistant Volume Check"
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        let language = ProcessInfo.processInfo.environment["CICADA_TEST_VOLUME_LANGUAGE"] ?? "en"
        let host = NSHostingView(rootView: CandidateFeed(engine: coach, settings: settings,
            shadowReader: reader, expanded: true).padding(20)
            .environment(\.locale, Locale(identifier: language)).environment(\.colorScheme, .light).background(Color.white))
        host.sizingOptions = []
        window.contentView = host
        window.setContentSize(NSSize(width: 640, height: 490))
        window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(300))
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to:
            URL(fileURLWithPath: directory).appendingPathComponent("volume-\(language).png"))
        if let seconds = ProcessInfo.processInfo.environment["CICADA_TEST_VOLUME_HOLD"].flatMap(Double.init) {
            try await Task.sleep(for: .seconds(seconds))
        }
    }
}
