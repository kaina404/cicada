import AppKit
import SwiftUI
import Testing
@testable import Cicada

@MainActor
struct CandidateFeedScrollTests {
    @Test func currentSentenceStaysNearTop() async throws {
        guard let directory = ProcessInfo.processInfo.environment["CICADA_TEST_FEED_SCROLL"] else { return }
        _ = NSApplication.shared
        let sentences = [
            "I build reliable Android applications.",
            "I store pending messages in Room before sending them to the server.",
            "Each message has a stable identifier so retries do not create duplicates.",
            "WorkManager resumes the queue after a process restart.",
            "The interface shows whether a message is pending, sent, or failed.",
            "I test slow networks and reconnects with the backend team.",
            "I measure failures and delivery latency to find the next improvement.",
            "I would validate this approach against the requirements for ActAI."
        ]
        let text = sentences.joined(separator: " ")
        let coach = InterviewCoach(stream: { _, _ in AsyncThrowingStream { $0.yield(text); $0.finish() } })
        coach.gloss.enabled = false
        coach.start(background: "ActAI Android interview", available: true, prepare: { true })
        defer { coach.endMeeting() }
        coach.speech("How would you build reliable offline messages on Android?", role: "interviewer", now: 0)
        coach.ask()
        for _ in 0..<200 where coach.script.pending.isEmpty || coach.state != .ready {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(coach.script.sentences.count == sentences.count)
        let settings = AppSettings()
        let oldReading = settings.shadowReading, oldGloss = settings.askGloss
        settings.shadowReading = true; settings.askGloss = false
        defer { settings.shadowReading = oldReading; settings.askGloss = oldGloss }
        let audio = ShadowReaderTests.Driver()
        let reader = ShadowReader(audio: audio, synthesize: { _ in
            KokoroWorker.decode(["rate": 24000, "pcm": Data(repeating: 0, count: 96000).base64EncodedString()])
        }, headphones: { OutputDevice(id: 123, uid: "test", name: "Test headphones") }, automatic: false)
        reader.update(enabled: true, script: coach.script, finished: true)
        for _ in 0..<30 { await Task.yield(); reader.tick() }
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 640, height: 490),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        let host = NSHostingView(rootView: CandidateFeed(engine: coach, settings: settings,
            shadowReader: reader, expanded: true, fontSize: 28)
            .padding(.top, 16).background(Palette.surface)
            .environment(\.locale, Locale(identifier: "en")))
        host.sizingOptions = []
        window.contentView = host
        window.setContentSize(NSSize(width: 640, height: 490))
        window.orderFront(nil)
        defer { window.close(); reader.stop() }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        func check(_ index: Int, name: String) async throws -> CGFloat {
            try await Task.sleep(for: .milliseconds(400))
            host.layoutSubtreeIfNeeded()
            let views = descendants(host)
            let scroll = try #require(views.compactMap { $0 as? NSScrollView }.first)
            let lyrics = views.compactMap { $0 as? LyricsTextView }
            let row = try #require(lyrics.first { $0.string == coach.script.sentences[index] })
            let rect = row.convert(row.bounds, to: scroll.contentView)
            let distance = rect.minY - scroll.contentView.bounds.minY
            #expect(abs(distance - 8) < 2, "Selected sentence should start at the top padding, not the middle: \(distance)")
            #expect(!audio.playing, "Navigating sentences must remain paused")
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to:
                URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
            return scroll.contentView.bounds.minY
        }
        let initial = try await check(0, name: "first")
        #expect(abs(initial) < 1)
        let scroll = try #require(descendants(host).compactMap { $0 as? NSScrollView }.first)
        reader.selectSentence(offset: 3)
        var samples: [Double] = []
        for sample in 0..<24 {
            if sample == 4 { window.setContentSize(NSSize(width: 640, height: 491)) }
            samples.append(scroll.contentView.bounds.minY)
            try await Task.sleep(for: .milliseconds(16))
        }
        let steps = zip(samples, samples.dropFirst()).map { abs($1 - $0) }
        let distance = (samples.last ?? 0) - initial
        #expect(samples.filter { $0 > initial + 1 && $0 < distance - 1 }.count >= 6,
                "Scrolling should pass through intermediate positions")
        #expect((steps.max() ?? 0) < distance * 0.4,
                "A layout change must not snap an in-flight scroll to its endpoint")
        print("SCROLL_TRAJECTORY distance=\(distance) max_step=\(steps.max() ?? 0) samples=\(samples)")
        let middle = try await check(3, name: "middle")
        #expect(middle > initial + 30)
        // Rapid Crown navigation must land on the latest selection, without queued scrolls.
        reader.selectSentence(offset: 1)
        try await Task.sleep(for: .milliseconds(60))
        reader.selectSentence(offset: 1)
        try await Task.sleep(for: .milliseconds(60))
        reader.selectSentence(offset: -1)
        _ = try await check(4, name: "rapid-navigation")
        reader.selectSentence(offset: 20)
        let last = try await check(7, name: "last")
        #expect(last > middle)
        reader.selectSentence(offset: -20)
        let returned = try await check(0, name: "returned-first")
        #expect(abs(returned) < 1)
    }
}
