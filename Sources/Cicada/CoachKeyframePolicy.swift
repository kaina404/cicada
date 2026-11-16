import Foundation

struct CoachKeyframePolicy {
    enum Kind { case changed, refresh }
    /// An unchanged screen is still re-captured, so a request never carries a picture older than 5 s.
    /// The capture loop ticks a little over once a second, so 4 s here lands at 4–5 s in practice.
    static let maxInterval = 4.0
    private var last: [UInt8]?
    private var text = ""
    private var sentAt = -Double.infinity

    mutating func accept(fingerprint: [UInt8], text: String, at time: Double) -> Kind? {
        guard time - sentAt >= 2 else { return nil }
        let normalized = String(text.filter { !$0.isWhitespace })
        let changed: Bool
        if let last, last.count == fingerprint.count, !last.isEmpty {
            let difference = zip(last, fingerprint).map { abs(Int($0) - Int($1)) }
            let mean = Double(difference.reduce(0, +)) / Double(last.count) / 255
            let changedPixels = difference.filter { $0 > 25 }.count
            // OCR is an additional change signal, never an eligibility gate for pictures/diagrams.
            changed = mean >= 0.015 || Double(changedPixels) / Double(last.count) >= 0.04
                || normalized != self.text && max(normalized.count, self.text.count) >= 8
        } else { changed = true }
        guard changed || time - sentAt >= Self.maxInterval else { return nil }
        last = fingerprint; self.text = normalized; sentAt = time
        return changed ? .changed : .refresh
    }
}
