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
        if view.string != text || view.font?.pointSize != fontSize || view.active != active {
            view.string = text; view.font = .systemFont(ofSize: fontSize)
            view.textColor = active ? NSColor(Palette.ink).withAlphaComponent(0.55) : NSColor(Palette.secondary)
            view.active = active
            view.wordRanges = ShadowPlayback.displayRanges(text)
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
    var active = false
    var firstWord = 0
    var wordRanges: [NSRange] = []
    var playback = ShadowPlayback()
    var seek: ((Int) -> Void)?
    private var press: NSPoint?

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
