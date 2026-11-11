import AppKit
import SwiftUI

/// TextKit lays out the original script once; only the clipped foreground changes per audio frame.
/// A token spanning a line break fills its fragments in reading order, without horizontal motion.
struct ShadowLyricsText: NSViewRepresentable {
    var text: String
    var fontSize: CGFloat
    var active: Bool
    var firstWord: Int
    var playback: ShadowPlayback
    var seek: (Int) -> Void

    func makeNSView(context: Context) -> LyricsTextView {
        let view = LyricsTextView()
        view.isEditable = false; view.isSelectable = true
        view.drawsBackground = false; view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.isHorizontallyResizable = false; view.isVerticallyResizable = false
        view.textContainer?.widthTracksTextView = false
        view.textContainer?.heightTracksTextView = false
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }
    func updateNSView(_ view: LyricsTextView, context: Context) {
        if view.string != text || view.font?.pointSize != fontSize {
            view.string = text; view.font = .systemFont(ofSize: fontSize)
            view.wordRanges = ShadowPlayback.displayRanges(text)
            view.setActive(active, animated: false)
        } else {
            // Only a reading handoff fades; a new script or font size appears at once.
            view.setActive(active, animated: view.window != nil)
        }
        view.firstWord = firstWord; view.playback = playback; view.seek = seek
        view.needsDisplay = true
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: LyricsTextView, context: Context) -> CGSize? {
        let width = max(1, proposal.width ?? 400)
        guard let container = nsView.textContainer, let manager = nsView.layoutManager else { return nil }
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        manager.ensureLayout(for: container)
        return CGSize(width: width, height: ceil(manager.usedRect(for: container).height) + 1)
    }
}

final class LyricsTextView: NSTextView {
    private(set) var active = false
    /// 0 = not being read, 1 = being read. Eased over `ReadingTransition.duration` so the
    /// sentence that was read dims while the next one brightens, in step with the scroll.
    private var emphasis: CGFloat = 0
    private var fade: (from: CGFloat, start: CFTimeInterval)?
    private var fadeTimer: Timer?
    var firstWord = 0
    var wordRanges: [NSRange] = []
    var playback = ShadowPlayback()
    var seek: ((Int) -> Void)?
    private var press: NSPoint?

    func setActive(_ active: Bool, animated: Bool) {
        let changed = active != self.active
        self.active = active
        guard animated else {
            fadeTimer?.invalidate(); fadeTimer = nil; fade = nil
            emphasis = active ? 1 : 0; applyEmphasis(); return
        }
        guard changed else { return }
        fade = (emphasis, CACurrentMediaTime())
        guard fadeTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.stepFade() }
        }
        RunLoop.main.add(timer, forMode: .common)
        fadeTimer = timer
        stepFade()
    }
    private func stepFade() {
        guard let fade else { return }
        let target: CGFloat = active ? 1 : 0
        let t = min(1, (CACurrentMediaTime() - fade.start) / ReadingTransition.duration)
        emphasis = fade.from + (target - fade.from) * ReadingTransition.ease(t)
        applyEmphasis()
        if t >= 1 { fadeTimer?.invalidate(); fadeTimer = nil; self.fade = nil }
    }
    private func applyEmphasis() {
        var color = NSColor(Palette.secondary)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let from = NSColor(Palette.secondary).usingColorSpace(.sRGB)
            let to = NSColor(Palette.ink).withAlphaComponent(0.55).usingColorSpace(.sRGB)
            if let from, let to {
                func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * emphasis }
                color = NSColor(srgbRed: mix(from.redComponent, to.redComponent),
                                green: mix(from.greenComponent, to.greenComponent),
                                blue: mix(from.blueComponent, to.blueComponent),
                                alpha: mix(from.alphaComponent, to.alphaComponent))
            }
        }
        textColor = color
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance(); applyEmphasis()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let manager = layoutManager, let container = textContainer else { return }
        for word in playback.words {
            let local = word.range.clamped(to: firstWord..<(firstWord + wordRanges.count))
            guard !local.isEmpty else { continue }
            let lower = wordRanges[local.lowerBound - firstWord].location
            let upper = NSMaxRange(wordRanges[local.upperBound - 1 - firstWord])
            let characters = NSRange(location: lower, length: upper - lower)
            let glyphs = manager.glyphRange(forCharacterRange: characters, actualCharacterRange: nil)
            var rects: [NSRect] = []
            manager.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                                            in: container) { rect, _ in rects.append(rect) }
            var remaining = rects.reduce(CGFloat(0)) { $0 + $1.width } * word.timing.progress(at: playback.seconds)
            guard remaining > 0 else { continue }
            manager.addTemporaryAttribute(.foregroundColor, value: NSColor(Palette.accent), forCharacterRange: characters)
            for rect in rects where remaining > 0 {
                var clip = rect.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
                clip.size.width = min(clip.width, remaining)
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(rect: clip).addClip()
                manager.drawGlyphs(forGlyphRange: glyphs, at: textContainerOrigin)
                NSGraphicsContext.restoreGraphicsState()
                remaining -= rect.width
            }
            manager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: characters)
        }
    }
    override func mouseDown(with event: NSEvent) {
        press = convert(event.locationInWindow, from: nil)
        super.mouseDown(with: event)
        // NSTextView tracks the whole selection gesture inside mouseDown. Only a plain click seeks.
        let end = convert(window?.mouseLocationOutsideOfEventStream ?? event.locationInWindow, from: nil)
        guard event.clickCount == 1, selectedRange().length == 0, let press,
              hypot(end.x - press.x, end.y - press.y) < 4,
              let manager = layoutManager, let container = textContainer else { return }
        let point = NSPoint(x: press.x - textContainerOrigin.x, y: press.y - textContainerOrigin.y)
        var fraction: CGFloat = 0
        let glyph = manager.glyphIndex(for: point, in: container, fractionOfDistanceThroughGlyph: &fraction)
        guard glyph < manager.numberOfGlyphs,
              manager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).contains(point) else { return }
        let character = manager.characterIndexForGlyph(at: glyph)
        if let index = wordRanges.firstIndex(where: { NSLocationInRange(character, $0) }) { seek?(firstWord + index) }
    }
}

