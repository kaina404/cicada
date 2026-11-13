import Foundation

/// Optional fast follow (快速跟读): on-device English drafts of the candidate's microphone move a
/// display-only word cursor within a few hundred milliseconds. It never edits `CoachScript`, records
/// or answers; Gemma's slower reading progress stays the authority and the display shows the
/// further of the two. With the switch off nothing here runs and the microphone is not touched.
@MainActor
final class FastReadingFollow: ObservableObject {
    enum Status: String { case off, starting, on, unavailable }
    @Published private(set) var status = Status.off
    /// Script word index just past the last word heard, for `answerID` only.
    @Published private(set) var word: Int?
    private(set) var answerID = ""
    private var script: [String] = []
    private var finals: [String] = []
    private var draft: [String] = []
    private var recognition: ShadowRecognition?

    func update(enabled: Bool, script coach: CoachScript) {
        guard enabled else { if status != .off { stop() }; return }
        if recognition == nil, status != .unavailable { start() }
        if coach.answerID != answerID {
            answerID = coach.answerID; word = nil; finals = []; draft = []
        }
        script = CoachScript.words(coach.pending)
    }

    /// Microphone samples at 16 kHz mono, already on the main actor.
    func append(_ samples: [Float]) { recognition?.append(samples) }

    func stop() {
        recognition?.stop(); recognition = nil
        status = .off; word = nil; answerID = ""; script = []; finals = []; draft = []
    }

    /// Drafts replace each other until a final ends the line; keep only recent speech.
    func hear(_ text: String, final: Bool) {
        let words = CoachScript.words(text)
        if final { finals = Array((finals + words).suffix(24)); draft = [] } else { draft = words }
        guard !script.isEmpty else { return }
        let cursor = word ?? 0
        guard let through = FastReadingAlign.advance(heard: finals + draft, script: script, cursor: cursor) else { return }
        word = through
        debugLog("fast follow: word=\(through)/\(script.count) heard=\((finals + draft).suffix(8).joined(separator: " "))")
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
