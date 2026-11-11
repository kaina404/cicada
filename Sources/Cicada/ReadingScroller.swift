import AppKit
import SwiftUI

/// One handoff between sentences: the colours cross-fade and the list scrolls on the same
/// slow ease-in-out curve, so the eye can follow the new sentence up instead of hunting for it.
/// It settles within a second, leaving the sentence still while it is being read.
enum ReadingTransition {
    static let duration: Double = 0.9
    static let animation = Animation.timingCurve(0.45, 0, 0.25, 1, duration: duration)
    /// Close to `animation`; used where AppKit, not SwiftUI, runs the frames (smootherstep).
    static func ease(_ t: Double) -> Double { t * t * t * (t * (t * 6 - 15) + 10) }
}

/// SwiftUI's `scrollTo` on macOS ignores the animation's duration and finishes in about 0.2 s,
/// which reads as a jump. This drives the enclosing NSScrollView itself.
@MainActor final class ReadingScroller {
    weak var scrollView: NSScrollView?
    private var run: (from: CGFloat, to: CGFloat, start: CFTimeInterval)?
    private var last: CGFloat?
    private var timer: Timer?

    /// `restart` starts a fresh handoff; otherwise a moved target (a gloss arriving, a resize)
    /// bends the running curve so it neither jumps nor ends later.
    func scroll(to target: CGFloat, restart: Bool, animated: Bool) {
        guard let scrollView, let document = scrollView.documentView else { return }
        let clip = scrollView.contentView
        let y = min(max(0, target), max(0, document.frame.height - clip.bounds.height))
        let now = CACurrentMediaTime(), current = clip.bounds.minY
        guard animated, abs(y - current) > 0.5 else { stop(); set(y); return }
        if !restart, let run, timer != nil {
            let e = CGFloat(ReadingTransition.ease(min(1, (now - run.start) / ReadingTransition.duration)))
            self.run = e < 0.98 ? ((current - y * e) / (1 - e), y, run.start) : nil
            if self.run == nil { stop(); set(y) }
            return
        }
        run = (current, y, now)
        if timer == nil {
            let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.step() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        step()
    }
    private func step() {
        guard let run, let scrollView else { stop(); return }
        // The reader scrolled by hand: let go rather than fight them.
        if let last, abs(scrollView.contentView.bounds.minY - last) > 1 { stop(); return }
        let t = min(1, (CACurrentMediaTime() - run.start) / ReadingTransition.duration)
        set(run.from + (run.to - run.from) * CGFloat(ReadingTransition.ease(t)))
        if t >= 1 { stop() }
    }
    private func set(_ y: CGFloat) {
        guard let scrollView else { return }
        scrollView.contentView.scroll(to: NSPoint(x: scrollView.contentView.bounds.minX, y: y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        last = scrollView.contentView.bounds.minY
    }
    private func stop() { timer?.invalidate(); timer = nil; run = nil; last = nil }
}

/// Hands the enclosing NSScrollView of a SwiftUI ScrollView to a `ReadingScroller`.
struct ScrollViewFinder: NSViewRepresentable {
    let scroller: ReadingScroller
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { if let found = view.enclosingScrollView { scroller.scrollView = found } }
    }
}

/// Each sentence row's top, in the scroll content's coordinates.
struct ReadingRowTops: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}
