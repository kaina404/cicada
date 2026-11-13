import Foundation

/// Optional fast follow (快速跟读): on-device English drafts of the candidate's microphone move a
/// display-only word cursor within a few hundred milliseconds. It never edits `CoachScript`, records
/// or answers; Gemma's slower reading progress stays the authority and the display shows the
/// further of the two. With the switch off nothing here runs and the microphone is not touched.
@MainActor
final class FastReadingFollow: ObservableObject {
    enum Status: String { case off, starting, on, unavailable }
    @Published private(set) var status = Status.off
    /// Displayed script word index: just past the last word heard, plus `lead` seconds of reading,
    /// for `answerID` only.
    @Published private(set) var word: Int?
    /// Just past the last word actually heard; alignment continues from here, never from the lead.
    private(set) var heard: Int?
    private(set) var answerID = ""
    /// Recognition lags speech by about a second or two, so the reader is already further on.
    var lead = 0.0
    var now: () -> Double = { ProcessInfo.processInfo.systemUptime }
    private var pace: [(t: Double, word: Int)] = []
    private var sentenceEnds: [Int] = []
    private var script: [String] = []
    private var finals: [String] = []
    private var draft: [String] = []
    private var recognition: ShadowRecognition?

    func update(enabled: Bool, script coach: CoachScript, lead: Double = 0) {
        guard enabled else { if status != .off { stop() }; return }
        if recognition == nil, status != .unavailable { start() }
        if coach.answerID != answerID {
            answerID = coach.answerID; word = nil; heard = nil; finals = []; draft = []; pace = []
        }
        self.lead = lead
        script = CoachScript.words(coach.pending)
        var end = 0
        sentenceEnds = coach.sentences.map { end += CoachScript.words($0).count; return end }
    }

    /// The watch (or a tap) placed read-along elsewhere: drop this position and follow on from there.
    func move(to target: Int) {
        guard !answerID.isEmpty, word != target || heard != target else { return }
        heard = target; word = target; finals = []; draft = []; pace = []
        debugLog("fast follow: moved to word \(target)")
    }

    /// Microphone samples at 16 kHz mono, already on the main actor.
    func append(_ samples: [Float]) { recognition?.append(samples) }

    func stop() {
        recognition?.stop(); recognition = nil
        status = .off; word = nil; heard = nil; answerID = ""; script = []; finals = []; draft = []; pace = []
    }

    /// Drafts replace each other until a final ends the line; keep only recent speech.
    func hear(_ text: String, final: Bool) {
        let words = CoachScript.words(text)
        if final { finals = Array((finals + words).suffix(24)); draft = [] } else { draft = words }
        guard !script.isEmpty else { return }
        guard let through = FastReadingAlign.advance(heard: finals + draft, script: script, cursor: heard ?? 0) else { return }
        heard = through
        let ahead = leadWords(through)
        word = max(word ?? 0, ahead)
        debugLog("fast follow: word=\(word ?? through)/\(script.count) heard_word=\(through) heard=\((finals + draft).suffix(8).joined(separator: " "))")
    }

    /// `lead` seconds at the reader's recent pace, never past the end of the sentence being read:
    /// people pause between sentences, and the cursor must not run on into one not yet started.
    private func leadWords(_ through: Int) -> Int {
        let t = now()
        pace = pace.filter { t - $0.t <= 6 } + [(t, through)]
        guard lead > 0 else { return through }
        var rate = 2.5   // ~150 words a minute, a typical pace reading aloud
        if let first = pace.first, t - first.t >= 1.5 {
            rate = min(4, max(1.5, Double(through - first.word) / (t - first.t)))
        }
        let end = sentenceEnds.first { $0 >= through } ?? script.count
        return min(end, through + Int((rate * lead).rounded()))
    }

    private func start() {
        let recognition = ShadowRecognition()
        recognition.onText = { [weak self] text, final in self?.hear(text, final: final) }
        recognition.onReady = { [weak self] ready in self?.status = ready ? .on : .unavailable }
        self.recognition = recognition
        status = .starting
        recognition.start()
    }
}
