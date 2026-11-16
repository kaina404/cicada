import SwiftUI
import UIKit

/// TextKit provides the same glyph positions for the highlight and the scroll target.
struct ReadingLyrics: UIViewRepresentable {
    let sentence: String
    let word: FloatingAnswerState.ReadingWord?
    let size: CGFloat
    let color: Color
    let accent: Color
    let lineChanged: (CGFloat) -> Void

    func makeUIView(context: Context) -> ReadingLyricsView {
        let view = ReadingLyricsView()
        view.isOpaque = false
        view.backgroundColor = .clear
        view.isAccessibilityElement = true
        return view
    }

    func updateUIView(_ view: ReadingLyricsView, context: Context) {
        view.update(sentence: sentence, word: word, size: size, color: UIColor(color),
                    accent: UIColor(accent), lineChanged: lineChanged)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ReadingLyricsView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        return CGSize(width: width, height: uiView.measure(width: width))
    }
}

final class ReadingLyricsView: UIView {
    private let text = NSTextStorage()
    private let layout = NSLayoutManager()
    private let container = NSTextContainer(size: .zero)
    private let accentText = NSTextStorage()
    private let accentLayout = NSLayoutManager()
    private let accentContainer = NSTextContainer(size: .zero)
    private var word: FloatingAnswerState.ReadingWord?
    private var color = UIColor.label
    private var accent = UIColor.systemOrange
    private var font = UIFont.systemFont(ofSize: 29, weight: .semibold)
    private var reportedLine: CGFloat?
    private var lineChanged: ((CGFloat) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        text.addLayoutManager(layout)
        accentContainer.lineFragmentPadding = 0
        accentLayout.addTextContainer(accentContainer)
        accentText.addLayoutManager(accentLayout)
    }

    required init?(coder: NSCoder) { nil }

    func update(sentence: String, word: FloatingAnswerState.ReadingWord?, size: CGFloat,
                color: UIColor, accent: UIColor, lineChanged: @escaping (CGFloat) -> Void) {
        let font = UIFont.systemFont(ofSize: size, weight: .semibold)
        if text.string != sentence || self.font != font || self.color != color || self.accent != accent {
            self.font = font
            self.color = color
            text.setAttributedString(NSAttributedString(string: sentence, attributes: [.font: font, .foregroundColor: color]))
            accentText.setAttributedString(NSAttributedString(string: sentence, attributes: [.font: font, .foregroundColor: accent]))
            accessibilityLabel = sentence
            invalidateIntrinsicContentSize()
        }
        self.word = word
        self.accent = accent
        self.lineChanged = lineChanged
        setNeedsLayout()
        setNeedsDisplay()
    }

    func measure(width: CGFloat) -> CGFloat {
        let size = CGSize(width: width, height: .greatestFiniteMagnitude)
        if container.size != size {
            container.size = size
            accentContainer.size = size
        }
        layout.ensureLayout(for: container)
        return ceil(layout.usedRect(for: container).height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }
        _ = measure(width: bounds.width)
        let y = activeGlyphs.map { layout.lineFragmentRect(forGlyphAt: $0.location, effectiveRange: nil).minY } ?? 0
        guard reportedLine != y else { return }
        reportedLine = y
        // Report geometry outside SwiftUI's layout pass and drop stale callbacks.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.reportedLine == y else { return }
            self.lineChanged?(y)
        }
    }

    private var activeGlyphs: NSRange? {
        guard let word, word.range(in: text.string) != nil else { return nil }
        let glyphs = layout.glyphRange(forCharacterRange: NSRange(location: word.location, length: word.length),
                                       actualCharacterRange: nil)
        return glyphs.length > 0 ? glyphs : nil
    }

    override func draw(_ rect: CGRect) {
        guard bounds.width > 0 else { return }
        _ = measure(width: bounds.width)
        let allGlyphs = layout.glyphRange(for: container)
        layout.drawGlyphs(forGlyphRange: allGlyphs, at: .zero)
        guard let word, let active = activeGlyphs, let context = UIGraphicsGetCurrentContext() else { return }
        if word.fillsPrefix, word.location > 0 {
            let prefix = accentLayout.glyphRange(forCharacterRange: NSRange(location: 0, length: word.location),
                                                actualCharacterRange: nil)
            accentLayout.drawGlyphs(forGlyphRange: prefix, at: .zero)
        }
        let progress = word.progress.isFinite ? min(1, max(0, word.progress)) : 0
        guard progress > 0 else { return }
        var fragments: [CGRect] = []
        layout.enumerateEnclosingRects(forGlyphRange: active, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                                      in: container) { rect, _ in fragments.append(rect) }
        var remaining = fragments.reduce(CGFloat.zero) { $0 + $1.width } * progress
        for fragment in fragments where remaining > 0 {
            var clip = fragment
            clip.size.width = min(clip.width, remaining)
            context.saveGState()
            context.clip(to: clip)
            accentLayout.drawGlyphs(forGlyphRange: active, at: .zero)
            context.restoreGState()
            remaining -= fragment.width
        }
    }

}
