import Foundation
import NaturalLanguage

/// A separate lane: translation never holds up the local model's first token or next question.
@MainActor
final class AskGloss: ObservableObject {
    @Published private(set) var translations: [String: String] = [:]
    var enabled = true {
        didSet {
            guard enabled != oldValue else { return }
            generation = UUID()
            task?.cancel(); task = nil; queued = []; seen = Set(translations.keys)
        }
    }
    var onUpdate: (() -> Void)?
    private var task: Task<Void, Never>?
    private var queued: [String] = []
    private var seen: Set<String> = []
    typealias Translate = (String, String) async -> String?
    private let translate: Translate

    init(translate: @escaping Translate = { text, source in
        await TranslationService.appleOnly(text, source: source, target: "zh-CN")
    }) {
        self.translate = translate
    }
    private var generation = UUID()

    func enqueue(_ lines: [String]) {
        guard enabled else { return }
        for line in lines where !line.isEmpty && seen.insert(line).inserted { queued.append(line) }
        guard task == nil, !queued.isEmpty else { return }
        let id = generation
        task = Task { [weak self] in
            guard let self else { return }
            while !self.queued.isEmpty, !Task.isCancelled {
                let line = self.queued.removeFirst()
                let recognizer = NLLanguageRecognizer()
                let spoken = CoachPronunciation.spokenText(line)
                recognizer.processString(spoken)
                let source = recognizer.dominantLanguage?.rawValue ?? "en"
                if source.hasPrefix("zh") { continue }
                var translated = await self.translate(spoken, source)
                guard !Task.isCancelled, self.generation == id else { return }
                if translated == nil {
                    // A temporary failure must not disable this meeting's remaining glosses.
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                    guard self.generation == id else { return }
                    translated = await self.translate(spoken, source)
                }
                guard !Task.isCancelled, self.generation == id else { return }
                guard let translated else {
                    debugLog("ask: zh gloss unavailable")
                    self.seen.remove(line)
                    continue
                }
                self.translations[line] = translated
                self.onUpdate?()
            }
            if self.generation == id { self.task = nil }
        }
    }

    func clear() {
        generation = UUID()
        task?.cancel()
        task = nil
        queued = []
        seen = []
        translations = [:]
    }
}
