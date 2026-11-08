import Foundation

struct CoachKeyframePolicy {
    private var last: [UInt8]?
    private var text = ""
    private var sentAt = -Double.infinity

    mutating func accept(fingerprint: [UInt8], text: String, at time: Double) -> Bool {
        guard time - sentAt >= 2 else { return false }
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
        guard changed else { return false }
        last = fingerprint; self.text = normalized; sentAt = time
        return true
    }
}
