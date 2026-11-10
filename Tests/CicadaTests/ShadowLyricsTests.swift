import AppKit
import SwiftUI
import Testing
@testable import Cicada

@MainActor
struct ShadowLyricsTests {
    @Test func fixedGlyphPositionsWhileColorAdvances() throws {
        let text = "I build reliable Android applications with offline queues and end-to-end delivery."
        let view = LyricsTextView(frame: NSRect(x: 0, y: 0, width: 310, height: 220))
        view.string = text; view.font = .systemFont(ofSize: 28)
        view.textColor = .gray; view.drawsBackground = false; view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.containerSize = NSSize(width: 310, height: 10000)
        view.wordRanges = ShadowPlayback.displayRanges(text)
        let manager = try #require(view.layoutManager), container = try #require(view.textContainer)
        manager.ensureLayout(for: container)
        let positions = view.wordRanges.map { manager.boundingRect(forGlyphRange: manager.glyphRange(forCharacterRange: $0, actualCharacterRange: nil), in: container) }
        view.playback = ShadowPlayback(seconds: 2.5, words: [
            .init(range: 0..<1, timing: .init(text: "I", start: 0, end: 1)),
            .init(range: 1..<2, timing: .init(text: "build", start: 2, end: 3))])
        // Exercise native drawing, including a partial word and natural line wrapping.
        let image = NSImage(size: view.bounds.size)
        image.lockFocus(); view.draw(view.bounds); image.unlockFocus()
        view.playback.seconds = 0.5
        image.lockFocus(); view.draw(view.bounds); image.unlockFocus()
        #expect(positions == view.wordRanges.map { manager.boundingRect(forGlyphRange: manager.glyphRange(forCharacterRange: $0, actualCharacterRange: nil), in: container) })
        #expect(manager.usedRect(for: container).height > 60)
    }

    @Test func liveCandidateFeedSnapshot() async throws {
        guard let directory = ProcessInfo.processInfo.environment["CICADA_TEST_SHADOW_UI"] else { return }
        _ = NSApplication.shared
        let text = "I build reliable Android applications. I store messages locally and retry safely after reconnecting. I own delivery from the client to the backend. I use stable client identifiers for safe retries. WorkManager resumes the queue after a restart. Room preserves pending operations across process death. I track delivery latency and failures. I would validate these choices against ActAI requirements."
        let coach = InterviewCoach(stream: { _, _ in AsyncThrowingStream { $0.yield(text); $0.finish() } })
        coach.gloss.enabled = false
        coach.start(background: "ActAI Android interview", available: true, prepare: { true })
        defer { coach.endMeeting() }
        coach.speech("How do you design reliable offline sending on Android?", role: "interviewer", now: 0)
        coach.ask()
        for _ in 0..<200 where coach.script.pending.isEmpty || coach.state != .ready { try await Task.sleep(for: .milliseconds(10)) }
        try #require(!coach.script.pending.isEmpty)
        let audio = ShadowReaderTests.Driver(), settings = AppSettings()
        let old = settings.shadowReading, oldGloss = settings.askGloss
        settings.shadowReading = true; settings.askGloss = false
        defer { settings.shadowReading = old; settings.askGloss = oldGloss }
        let synth = ShadowSynthesizer()
        try #require(await synth.warmUp())
        let pcm = await synth.make("I build reliable Android applications.")
        let reader = ShadowReader(audio: audio, synthesize: { _ in pcm },
            headphones: { OutputDevice(id: 123, uid: "test", name: "Test headphones") }, automatic: false)
        reader.update(enabled: true, script: coach.script, finished: true)
        for _ in 0..<100 { await Task.yield(); reader.tick() }
        audio.state.seconds = pcm.words.first(where: { $0.text.lowercased() == "android" }).map { ($0.start + $0.end) / 2 } ?? 0.7
        reader.tick()
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 640, height: 490),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua)
        let host = NSHostingView(rootView: CandidateFeed(engine: coach, settings: settings,
            shadowReader: reader, expanded: true, fontSize: 28).padding(.top, 16).background(Palette.surface).environment(\.colorScheme, .light))
        host.sizingOptions = []
        window.contentView = host
        window.setContentSize(NSSize(width: 640, height: 490))
        window.orderFront(nil)
        defer { window.close(); reader.stop() }
        try await Task.sleep(for: .milliseconds(250))
        let content = try #require(window.contentView)
        content.layoutSubtreeIfNeeded()
        let bitmap = try #require(content.bitmapImageRepForCachingDisplay(in: content.bounds))
        content.cacheDisplay(in: content.bounds, to: bitmap)
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: directory).appendingPathComponent("assistant-audio-fill.png"))
        func scrollViews(in view: NSView) -> [NSScrollView] {
            (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
        }
        let scroll = try #require(scrollViews(in: content).first)
        let initialY = scroll.contentView.bounds.minY
        reader.selectSentence(offset: 7)
        for _ in 0..<40 { reader.tick(); try await Task.sleep(for: .milliseconds(10)) }
        #expect(scroll.contentView.bounds.minY > initialY + 20)
        #expect(abs(scroll.contentView.bounds.minX) < 0.1)
        #expect(!audio.playing)
        let selectedBitmap = try #require(content.bitmapImageRepForCachingDisplay(in: content.bounds))
        content.cacheDisplay(in: content.bounds, to: selectedBitmap)
        try #require(selectedBitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: directory).appendingPathComponent("assistant-selected-sentence.png"))
    }
}
