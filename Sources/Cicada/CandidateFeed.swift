import SwiftUI

struct CandidateFeed: View {
    @ObservedObject var engine: InterviewCoach
    @ObservedObject var settings: AppSettings
    @ObservedObject private var gloss: AskGloss
    var expanded = false
    var compactHeight: CGFloat = 250
    var microphoneName = ""
    var micOn = false
    var onMic: (() -> Void)?
    var onMicrophoneSettings: (() -> Void)?
    var onFloat: (() -> Void)?
    var fontSize: CGFloat = 20
    @State private var followsReading = true

    init(engine: InterviewCoach, settings: AppSettings, expanded: Bool = false,
         compactHeight: CGFloat = 250, microphoneName: String = "", micOn: Bool = false,
         onMic: (() -> Void)? = nil, onMicrophoneSettings: (() -> Void)? = nil, onFloat: (() -> Void)? = nil, fontSize: CGFloat = 20) {
        self.engine = engine; self.settings = settings; self.gloss = engine.gloss
        self.expanded = expanded; self.compactHeight = compactHeight
        self.microphoneName = microphoneName; self.micOn = micOn; self.onMic = onMic
        self.onMicrophoneSettings = onMicrophoneSettings; self.onFloat = onFloat; self.fontSize = fontSize
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("面试教练").font(.system(size: 11, weight: .semibold))
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
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(engine.script.sentences.enumerated()), id: \.offset) { index, sentence in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(sentence).font(.system(size: fontSize))
                                    .foregroundStyle(index < engine.script.currentSentence ? Palette.secondary : Palette.ink).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if settings.askGloss, let text = gloss.translations[sentence] {
                                    Text(text).font(.system(size: max(13, fontSize * 0.7))).foregroundStyle(Palette.secondary)
                                }
                            }
                            .padding(8)
                            .background(index == engine.script.currentSentence ? Palette.accent.opacity(0.09) : .clear,
                                        in: RoundedRectangle(cornerRadius: 7))
                            .id(index)
                        }
                        if !engine.script.committed.isEmpty {
                            Text("已经说出").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                            Text(engine.script.spokenText).font(.system(size: max(16, fontSize * 0.8))).foregroundStyle(Palette.secondary)
                                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                .onAppear {
                    if followsReading { proxy.scrollTo(engine.script.currentSentence, anchor: .center) }
                }
                .onChange(of: engine.script.currentSentence) { _, index in
                    if followsReading { proxy.scrollTo(index, anchor: .center) }
                }
                .onChange(of: engine.script.answerID) { _, _ in
                    if followsReading { proxy.scrollTo(engine.script.currentSentence, anchor: .center) }
                }
                .onChange(of: followsReading) { _, follows in
                    if follows { proxy.scrollTo(engine.script.currentSentence, anchor: .center) }
                }
            }.frame(maxHeight: expanded ? .infinity : compactHeight)
                .task(id: settings.askGloss) {
                    if settings.askGloss { gloss.enqueue(engine.script.sentences) }
                }
        }.foregroundStyle(Palette.tertiary).padding(.horizontal, 24).padding(.bottom, 8)
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
