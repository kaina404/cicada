import Foundation

/// Accent-tolerant alignment of fast on-device drafts to the script, for display only.
/// Chinese-accented English often merges voicing (d/t, b/p, g/k, v/w/f, z/s), swaps l/r/n and
/// drops endings (-s, -ed, -th); the recognizer then hears a near word ("cotton" for "Kotlin")
/// or splits one ("jet pack"). Words are compared by spelling and by a coarse sound key, and a
/// move needs several such words in order, so one lucky match cannot jump the reader ahead.
enum FastReadingAlign {
    static let fillers: Set<String> = ["um", "uh", "er", "erm", "ah", "eh", "hmm", "mm", "uhm"]
    private static let weak: Set<String> = ["a", "an", "the", "i", "we", "it", "is", "are", "to", "of",
                                            "and", "or", "in", "on", "for", "so", "that", "this", "be"]

    /// Script word index just past the reader's latest heard word, or nil to stay put.
    static func advance(heard raw: [String], script: [String], cursor: Int) -> Int? {
        let heard = Array(raw.filter { !fillers.contains($0) }.suffix(16))
        guard heard.count >= 2, cursor >= 0, cursor < script.count else { return nil }
        // Reaching back a little lets a repeated phrase anchor without moving the cursor.
        let lower = max(0, cursor - 8), upper = min(script.count, cursor + 60)
        let window = Array(script[lower..<upper])
        let h = heard.count, s = window.count
        struct Cell { var score = 0.0; var hits = 0; var strong = 0; var sim = 0.0; var end = -1 }
        var grid = Array(repeating: Array(repeating: Cell(), count: s + 1), count: h + 1)
        for i in 1...h {
            for j in 1...s {
                var best = Cell()
                func take(_ from: Cell, _ add: Double, hit: Double?, end: Int?) {
                    guard from.score + add > best.score else { return }
                    best = from; best.score += add
                    if let hit {
                        best.hits += 1; best.sim += hit; best.end = end ?? best.end
                        if hit >= 0.9, !weak.contains(window[j - 1]) { best.strong += 1 }
                    }
                }
                let sim = similarity(heard[i - 1], window[j - 1])
                if sim >= 0.6 { take(grid[i - 1][j - 1], 2 * sim, hit: sim, end: j) }
                else { take(grid[i - 1][j - 1], -1, hit: nil, end: nil) }
                // Recognizer split one script word into two ("jet pack" → "jetpack").
                if i >= 2 {
                    let merged = similarity(heard[i - 2] + heard[i - 1], window[j - 1])
                    if merged >= 0.75 { take(grid[i - 2][j - 1], 2 * merged, hit: merged, end: j) }
                }
                // Recognizer merged two script words into one.
                if j >= 2 {
                    let merged = similarity(heard[i - 1], window[j - 2] + window[j - 1])
                    if merged >= 0.75 { take(grid[i - 1][j - 2], 2 * merged, hit: merged, end: j) }
                }
                take(grid[i - 1][j], -0.7, hit: nil, end: nil)   // repetition, filler, misheard extra word
                take(grid[i][j - 1], -0.7, hit: nil, end: nil)   // skipped or unheard script word
                grid[i][j] = best
            }
        }
        // The path must reach the newest heard words, or it describes old speech.
        var choices: [Cell] = []
        for i in max(1, h - 1)...h {
            for j in 1...s where grid[i][j].hits > 0 { choices.append(grid[i][j]) }
        }
        guard let best = choices.max(by: { $0.score < $1.score }), best.end > 0 else { return nil }
        let strongest = choices.filter { $0.score >= best.score * 0.9 && abs($0.end - best.end) > 3 }
        // Two near-equal places (a repeated phrase): keep the nearer one, never the farther.
        let pick = ([best] + strongest).min(by: { $0.end < $1.end }) ?? best
        let through = lower + pick.end
        guard through > cursor, pick.sim / Double(pick.hits) >= 0.7 else { return nil }
        let jump = through - cursor
        // Small steps near the cursor need two good words; longer jumps need more evidence.
        let enough = pick.hits >= 3 && pick.strong >= 2 || pick.hits >= 2 && pick.strong >= 1 && jump <= 4
        guard enough, jump <= max(6, pick.hits * 4) else { return nil }
        return through
    }

    /// 0…1. Spelling distance, endings dropped, then a coarse sound key for accent confusions.
    static func similarity(_ a: String, _ b: String) -> Double {
        if a == b { return 1 }
        if stem(a) == stem(b) { return 0.92 }
        let spelling = 1 - Double(distance(Array(a), Array(b))) / Double(max(a.count, b.count))
        let ka = soundKey(a), kb = soundKey(b)
        guard !ka.isEmpty, !kb.isEmpty else { return spelling }
        let sound = ka == kb ? 0.85 : 0.85 * (1 - Double(distance(ka, kb)) / Double(max(ka.count, kb.count)))
        // Very short words carry little sound evidence: "it"/"at" must not count as a match.
        let cap = min(a.count, b.count) <= 2 ? 0.5 : 1
        return min(cap, max(spelling, sound))
    }

    static func stem(_ w: String) -> String {
        for suffix in ["ing", "ed", "es", "s"] where w.count > suffix.count + 2 && w.hasSuffix(suffix) {
            return String(w.dropLast(suffix.count))
        }
        return w
    }

    /// Consonant classes that a heavy accent or the recognizer commonly blurs; vowels dropped.
    static func soundKey(_ word: String) -> [Character] {
        var w = stem(word)
        for (from, to) in [("th", "t"), ("ph", "f"), ("ck", "k"), ("sh", "s"), ("ch", "s"), ("wh", "w"), ("qu", "k")] {
            w = w.replacingOccurrences(of: from, with: to)
        }
        var key: [Character] = []
        for c in w {
            let mapped: Character? = switch c {
            case "b", "p": "P"
            case "d", "t": "T"
            case "g", "k", "c", "q": "K"
            case "v", "w", "f": "F"
            case "s", "z", "x", "j": "S"
            case "l", "r", "n": "L"
            case "m": "M"
            case "0"..."9": c
            default: nil
            }
            if let mapped, key.last != mapped { key.append(mapped) }
        }
        return key
    }

    static func distance<T: Equatable>(_ a: [T], _ b: [T]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var row = Array(0...b.count)
        for i in 1...a.count {
            var previous = row[0]; row[0] = i
            for j in 1...b.count {
                let current = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, previous + (a[i - 1] == b[j - 1] ? 0 : 1))
                previous = current
            }
        }
        return row[b.count]
    }
}
