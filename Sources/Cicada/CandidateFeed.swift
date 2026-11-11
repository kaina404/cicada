import SwiftUI
import Combine

struct CandidateFeed: View {
    @ObservedObject var engine: InterviewCoach
    @ObservedObject var settings: AppSettings
    @ObservedObject private var gloss: AskGloss
    var shadowReader: ShadowReader?
    var expanded = false
    var compactHeight: CGFloat = 250
    var microphoneName = ""
    var micOn = false
    var onMic: (() -> Void)?
    var onMicrophoneSettings: (() -> Void)?
    var onFloat: (() -> Void)?
    var fontSize: CGFloat = 20
    var glossFontSize: CGFloat?
    @State private var controlsExpanded = false
    @State private var followsReading = true
    @State private var playback = ShadowPlayback()
    @State private var scrollAnswerID: String?
    @State private var scrolledSentence: Int?
    @State private var rowTops: [Int: CGFloat] = [:]
    @State private var scroller = ReadingScroller()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(engine: InterviewCoach, settings: AppSettings, shadowReader: ShadowReader? = nil, expanded: Bool = false,
         compactHeight: CGFloat = 250, microphoneName: String = "", micOn: Bool = false,
         onMic: (() -> Void)? = nil, onMicrophoneSettings: (() -> Void)? = nil, onFloat: (() -> Void)? = nil, fontSize: CGFloat = 20, glossFontSize: CGFloat? = nil) {
        self.engine = engine; self.settings = settings; self.gloss = engine.gloss; self.shadowReader = shadowReader
        self.expanded = expanded; self.compactHeight = compactHeight
        self.microphoneName = microphoneName; self.micOn = micOn; self.onMic = onMic
        self.onMicrophoneSettings = onMicrophoneSettings; self.onFloat = onFloat; self.fontSize = fontSize
        self.glossFontSize = glossFontSize
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button { controlsExpanded.toggle() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: controlsExpanded ? "chevron.down" : "chevron.right")
                        Text("面试教练")
                    }.font(.system(size: 11, weight: .semibold)).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(Text(controlsExpanded ? "收起" : "展开"))
                Spacer()
                if let onFloat {
                    Button(action: onFloat) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }.buttonStyle(.plain).help("放大悬浮回答").accessibilityLabel(Text("放大悬浮回答"))
                }
                Button("跟随朗读") { followsReading.toggle() }
                    .buttonStyle(.plain).foregroundStyle(followsReading ? Palette.accent : Palette.secondary)
                if engine.state == .failed || engine.readingFailed {
                    Button("重试") { engine.retry() }.buttonStyle(.plain)
                }
            }
            if controlsExpanded {
                Picker("面试阶段", selection: $settings.interviewStage) {
                    ForEach(InterviewStage.allCases) { stage in
                        Text(verbatim: stage.title).tag(stage)
                    }
                }
                .pickerStyle(.segmented).font(.system(size: 12))
                HStack(spacing: 8) {
                    Toggle("陪读", isOn: $settings.shadowReading).toggleStyle(.checkbox).fixedSize()
                    if settings.shadowReading, let shadowReader { ShadowStatus(reader: shadowReader, settings: settings) }
                }.font(.system(size: 11))
                Text(status).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                if CoachDeepSeekTest.enabled {
                    Text(verbatim: "DeepSeek V4.1 Flash · " + L("文本和截图发送云端") +
                         (engine.firstLatency.map { String(format: " · TTFT %.2fs", $0) } ?? ""))
                        .font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                }
                if !microphoneName.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            if let onMicrophoneSettings {
                                Button(action: onMicrophoneSettings) {
                                    Label {
                                        Text(verbatim: microphoneName).lineLimit(1).truncationMode(.middle)
                                    } icon: { Image(systemName: "mic") }
                                }
                                .help("选择候选人麦克风")
                                .accessibilityLabel(Text("选择候选人麦克风"))
                            } else {
                                Text(verbatim: microphoneName).lineLimit(2)
                            }
                            if let onMic {
                                Button(micOn ? L("关闭麦克风") : L("打开麦克风"), action: onMic)
                                    .fixedSize()
                            }
                        }
                        if !micOn { Text("尚未听取候选人回答") }
                    }
                    .font(.system(size: 11))

                }
            }
            GeometryReader { viewport in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(Array(engine.script.sentences.enumerated()), id: \.offset) { index, sentence in
                                VStack(alignment: .leading, spacing: 5) {
                                    if settings.shadowReading, let shadowReader {
                                        ShadowLyricsText(text: sentence, fontSize: fontSize,
                                            active: index == followedSentence, firstWord: firstWord(in: index),
                                            playback: playback.answerID == engine.script.answerID ? playback : ShadowPlayback(),
                                            seek: { shadowReader.seek(to: $0) })
                                    } else {
                                        Text(sentence).font(.system(size: fontSize))
                                            .foregroundStyle(index < engine.script.currentSentence ? Palette.secondary : Palette.ink).textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .animation(reduceMotion ? nil : ReadingTransition.animation, value: engine.script.currentSentence)
                                    }
                                    if settings.askGloss, let text = gloss.translations[sentence] {
                                        // Keep the gloss compact even when the floating English script is enlarged.
                                        Text(text).font(.system(size: glossFontSize ?? max(11, min(18, fontSize * 0.5)))).foregroundStyle(Palette.secondary)
                                    }
                                }
                                .padding(8)
                                .background(index == followedSentence ? Palette.accent.opacity(0.09) : .clear,
                                            in: RoundedRectangle(cornerRadius: 7))
                                .animation(ReadingTransition.animation, value: index == followedSentence)
                                .background(GeometryReader { row in
                                    Color.clear.preference(key: ReadingRowTops.self,
                                        value: [index: row.frame(in: .named(Self.readingSpace)).minY])
                                })
                            }
                            if !engine.script.committed.isEmpty {
                                Text("已经说出").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                                Text(engine.script.spokenText).font(.system(size: max(16, fontSize * 0.8))).foregroundStyle(Palette.secondary)
                                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .coordinateSpace(name: Self.readingSpace)
                        .background(ScrollViewFinder(scroller: scroller))
                        // Leave enough scroll range to place even the last sentence at the top.
                        .padding(.bottom, max(0, viewport.size.height - 24))
                    }
                    // Keep a fixed margin above the current sentence, even at large font sizes.
                    .padding(.top, 24)
                    .onPreferenceChange(ReadingRowTops.self) { rowTops = $0 }
                    .task(id: ReadingScrollRequest(answerID: engine.script.answerID,
                        sentence: followedSentence, sentenceCount: engine.script.sentences.count,
                        translations: gloss.translations, size: viewport.size, fontSize: fontSize,
                        follows: followsReading, target: rowTops[followedSentence])) {
                        guard followsReading else { return }
                        // Coalesce sentence, gloss and layout updates before scrolling. A layout
                        // correction must retarget the same animation rather than snap to its end.
                        do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
                        guard !Task.isCancelled else { return }
                        guard let target = rowTops[followedSentence] else { return }
                        let newAnswer = scrollAnswerID != engine.script.answerID
                        let handoff = scrolledSentence != followedSentence
                        scrollAnswerID = engine.script.answerID; scrolledSentence = followedSentence
                        // Slow and eased at both ends: a sudden jump makes the reader lose their place.
                        scroller.scroll(to: target, restart: handoff, animated: !(reduceMotion || newAnswer))
                    }
            }.frame(height: expanded ? nil : compactHeight)
                .frame(maxHeight: expanded ? .infinity : compactHeight)
                .task(id: settings.askGloss) {
                    if settings.askGloss { gloss.enqueue(engine.script.sentences) }
                }
        }.onChange(of: settings.interviewStage) { _, stage in engine.stage = stage }
        .onReceive(shadowReader.map { $0.$playback.eraseToAnyPublisher() } ?? Just(ShadowPlayback()).eraseToAnyPublisher()) {
            playback = $0
        }.foregroundStyle(Palette.tertiary).padding(.horizontal, 24).padding(.bottom, 8)
    }
    private static let readingSpace = "readingContent"
    private func firstWord(in sentence: Int) -> Int {
        engine.script.sentences.prefix(sentence).reduce(0) { $0 + CoachScript.words($1).count }
    }
    private var followedSentence: Int {
        guard settings.shadowReading else { return engine.script.currentSentence }
        guard playback.answerID == engine.script.answerID else { return 0 }
        let word = playback.currentWord ?? playback.words.first?.range.lowerBound ?? 0
        var end = 0
        for (index, sentence) in engine.script.sentences.enumerated() {
            end += CoachScript.words(sentence).count
            if word < end { return index }
        }
        return max(0, engine.script.sentences.count - 1)
    }
    private var status: String {
        if CoachDeepSeekTest.enabled {
            switch engine.state {
            case .idle: return L("已暂停")
            case .setup, .failed: return L("请检查 AI 服务设置")
            case .loading, .generating: return L("正在生成完整英文回答…")
            case .ready: return L("正在听双方发言 · Gemma 识别与跟读")
            }
        }
        return switch engine.state {
        case .idle: L("已暂停")
        case .setup: L("本机 Gemma 未就绪，请查看 AI 服务设置")
        case .loading: L("正在准备本机 Gemma…")
        case .ready: engine.readingFailed ? L("本机跟读识别暂不可用，稿件已保留") : L("正在听双方发言 · Gemma 识别与跟读")
        case .generating: L("正在生成完整英文回答…")
        case .failed: L("本机模型未能回答，请重试")
        }
    }
}

/// A passive debug image; the live view keeps native controls and text selection.
struct CoachSnapshot: View {
    let engine: InterviewCoach
    let microphoneName: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("面试教练").font(.headline)
            Text(microphoneName).font(.caption)
            ForEach(Array(engine.script.sentences.prefix(5).enumerated()), id: \.offset) { index, sentence in
                Text(sentence).font(.system(size: 18)).fixedSize(horizontal: false, vertical: true)
                    .padding(4).background(index == engine.script.currentSentence ? Palette.accent.opacity(0.09) : .clear)
            }
            if !engine.script.spokenText.isEmpty {
                Text(engine.script.spokenText).font(.system(size: 14)).foregroundStyle(Palette.secondary)
            }
            Spacer(minLength: 0)
        }.padding().frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(Palette.ink)
    }
}

private struct ShadowStatus: View {
    @ObservedObject var reader: ShadowReader
    @ObservedObject var settings: AppSettings
    @State private var volumeShown = false
    var body: some View {
        HStack {
            Text(reader.label).foregroundStyle(Palette.tertiary).fixedSize(horizontal: false, vertical: true)
            Picker("播放速度", selection: Binding(get: { reader.rate }, set: { reader.setRate($0) })) {
                Text(verbatim: "0.75×").tag(Float(0.75))
                Text(verbatim: "1×").tag(Float(1))
                Text(verbatim: "1.25×").tag(Float(1.25))
            }.labelsHidden().frame(width: 78).accessibilityLabel(Text("播放速度"))
            Button { volumeShown.toggle() } label: {
                Image(systemName: settings.shadowVolume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain).help("陪读音量").accessibilityLabel(Text("陪读音量"))
            .accessibilityValue(Text(verbatim: "\(Int((settings.shadowVolume * 100).rounded()))%"))
            .popover(isPresented: $volumeShown) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("陪读音量")
                        Spacer()
                        Text(verbatim: "\(Int((settings.shadowVolume * 100).rounded()))%")
                            .monospacedDigit()
                    }
                    Slider(value: $settings.shadowVolume, in: 0...1, step: 0.01)
                        .accessibilityLabel(Text("陪读音量"))
                }.font(.system(size: 12)).padding(16).frame(width: 220)
            }
        }
    }
}

/// Playback time changes do not request scrolling; only the sentence or its layout does.
private struct ReadingScrollRequest: Equatable {
    var answerID: String
    var sentence: Int
    var sentenceCount: Int
    var translations: [String: String]
    var size: CGSize
    var fontSize: CGFloat
    var follows: Bool
    var target: CGFloat?
}
