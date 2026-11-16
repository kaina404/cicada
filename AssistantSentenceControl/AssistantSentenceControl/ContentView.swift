import AVFoundation
import SwiftUI
import VisionKit

struct ContentView: View {
    @State private var remote = RemoteAnswer()
    @State private var scanning = false
    @State private var pairingError = false
    @State private var cameraError = false
    @State private var showingScreen = false
    @State private var readingLine: CGFloat = 0
    @GestureState private var moving = false
    @GestureState private var pressing = false
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title2) private var scriptSize: CGFloat = 29

    private let ink = Color(red: 0.09, green: 0.10, blue: 0.11)
    private let muted = Color(red: 0.33, green: 0.36, blue: 0.40)
    private let ground = Color(red: 0.95, green: 0.96, blue: 0.97)
    private let accent = Color(red: 0.81, green: 0.24, blue: 0.09)

    var body: some View {
        VStack(spacing: 10) {
            header
            if showingScreen, remote.connection == .connected {
                screenPreview
            } else if remote.connection == .connected, remote.answer.windowID != nil {
                HStack(spacing: 10) {
                    reading
                    controls
                }
            } else {
                waiting
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .background(ground.ignoresSafeArea())
        .foregroundStyle(ink)
        .preferredColorScheme(.light)
        .onChange(of: phase) { _, phase in
            if phase == .active { remote.resume() } else { remote.suspend() }
        }
        .onChange(of: moving) { _, active in
            if !active { Task { remote.cancelGesture(.move) } }
        }
        .onChange(of: pressing) { _, active in
            if !active { Task { remote.cancelGesture(.hold) } }
        }
        .fullScreenCover(isPresented: $scanning) {
            PairingScanner(onCode: { link in pair(link); scanning = false },
                           onUnavailable: { scanning = false; cameraError = true })
                .ignoresSafeArea()
                .overlay(alignment: .topTrailing) {
                    Button("关闭") { scanning = false }
                        .buttonStyle(.borderedProminent).tint(ink).padding()
                }
        }
        .alert("配对码无效", isPresented: $pairingError) {
            Button("好", role: .cancel) {}
        } message: {
            Text("请在 Mac 的悬浮回答中重新生成配对码。")
        }
        .alert("暂时无法更新本机配对记录", isPresented: Binding(
            get: { remote.pairingStorageError },
            set: { if !$0 { remote.dismissPairingStorageError() } }
        )) {
            Button("好", role: .cancel) {}
        }
        .alert("无法重新生成", isPresented: Binding(
            get: { remote.refreshMessage != nil },
            set: { if !$0 { remote.dismissRefreshMessage() } }
        )) {
            Button("好", role: .cancel) { remote.dismissRefreshMessage() }
        } message: {
            Text(remote.refreshMessage ?? "")
        }
        .alert("相机不可用", isPresented: $cameraError) {
            Button("好", role: .cancel) {}
        } message: {
            Text("可以从 Mac 复制配对链接，再在此粘贴。")
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true; remote.resume() }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false; remote.suspend() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("悬浮回答").font(.headline)
            Spacer()
            if remote.connection == .connected {
                if !showingScreen, remote.answer.windowID != nil, let status = playbackStatus {
                    Text(status).font(.footnote).foregroundStyle(muted)
                }
                Button { remote.regenerate() } label: {
                    Label(remote.refreshing ? "正在请求…" : "重新生成", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered).tint(ink)
                .disabled(!remote.canRefreshAnswer)
                Button {
                    remote.finishHold()
                    remote.cancelGesture(.move)
                    showingScreen.toggle()
                } label: {
                    Label(showingScreen ? "悬浮回答" : "Mac 屏幕", systemImage: showingScreen ? "text.alignleft" : "display")
                }
                .buttonStyle(.bordered).tint(ink)
                Label("Mac 已连接", systemImage: "wifi").font(.subheadline).foregroundStyle(muted)
            }
            if remote.connection != .unpaired {
                Button("断开") { showingScreen = false; remote.disconnect() }
                    .buttonStyle(.bordered).tint(ink)
            }
        }
    }

    private var screenPreview: some View {
        GeometryReader { viewport in
            Group {
                switch remote.screen {
                case .image(let image):
                    Image(uiImage: image).resizable().scaledToFit()
                        .accessibilityLabel(Text("Mac 主屏幕实时画面"))
                case .waiting:
                    ProgressView("正在获取 Mac 画面").tint(.white)
                case .off:
                    Text("在 Mac 悬浮回答的手机菜单中开启屏幕共享。")
                case .unavailable:
                    Text("暂时无法获取 Mac 画面，请检查 Mac 的屏幕录制权限。")
                }
            }
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .frame(width: viewport.size.width, height: viewport.size.height)
        }
        .background(.black, in: RoundedRectangle(cornerRadius: 18))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .task { await remote.watchScreen() }
    }

    private var waiting: some View {
        VStack(spacing: 12) {
            Image(systemName: "macbook.and.iphone").font(.system(size: 36)).foregroundStyle(muted)
            switch remote.connection {
            case .unpaired:
                Text("连接到 Mac").font(.title2.bold())
                Text("在 Mac 悬浮回答底部点手机图标，生成配对码。")
                HStack {
                    Button("扫描配对码", action: openScanner).buttonStyle(.borderedProminent).tint(ink)
                    PasteButton(payloadType: String.self) { links in
                        if let text = links.first, let link = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                            pair(link)
                        } else {
                            pairingError = true
                        }
                    }.tint(ink)
                }
            case .connecting:
                ProgressView("正在连接 Mac")
            case .connected:
                Text("请在 Mac 打开悬浮回答").font(.title2.bold())
            case .offline:
                Text("正在重新连接 Mac").font(.title2.bold())
                Text("请确认两台设备连接同一个 Wi-Fi，且已允许本地网络访问。")
            case .expired:
                Text("配对已失效").font(.title2.bold())
                Button("重新配对") { remote.disconnect() }.buttonStyle(.borderedProminent).tint(ink)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
    }

    private var reading: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(remote.answer.sentences.enumerated()), id: \.offset) { index, sentence in
                            let active = remote.answer.currentSentence == index
                            Group {
                                if active {
                                    let answerID = remote.answer.answerID
                                    ReadingLyrics(sentence: sentence, word: remote.answer.word,
                                                  size: scriptSize, color: ink, accent: accent) { y in
                                        guard remote.answer.answerID == answerID, remote.answer.currentSentence == index else { return }
                                        readingLine = y
                                    }
                                } else {
                                    Text(sentence).font(.system(size: scriptSize))
                                        .foregroundStyle(index < (remote.answer.currentSentence ?? 0) ? muted : ink)
                                }
                            }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14).padding(.vertical, 5)
                                .background(active ? accent.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 8))
                                .overlay(alignment: .leading) {
                                    if active {
                                        Capsule().fill(accent).frame(width: 3).padding(.vertical, 5)
                                    }
                                }
                                .accessibilityAddTraits(active ? .isSelected : [])
                                .overlay(alignment: .topLeading) {
                                    if active {
                                        VStack(spacing: 0) {
                                            Color.clear.frame(height: readingLine + 5)
                                            Color.clear.frame(width: 1, height: 1).id("reading-line")
                                        }
                                        .allowsHitTesting(false)
                                        .accessibilityHidden(true)
                                    }
                                }
                                .id(index)
                        }
                    }
                    .padding(.horizontal, 14).padding(.top, 12)
                    .padding(.bottom, viewport.size.height)
                }
                .scrollDisabled(true)
                .scrollIndicators(.hidden)
                .onChange(of: remote.answer.currentSentence, initial: true) { _, index in
                    readingLine = 0
                    guard let index else { return }
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { proxy.scrollTo(index, anchor: .top) }
                }
                .onChange(of: remote.answer.answerID) { _, _ in
                    readingLine = 0
                    proxy.scrollTo(remote.answer.currentSentence ?? 0, anchor: .top)
                }
                .onChange(of: readingLine) { _, line in
                    if line == 0, let index = remote.answer.currentSentence {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { proxy.scrollTo(index, anchor: .top) }
                    } else {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { proxy.scrollTo("reading-line", anchor: .top) }
                    }
                }
            }
            .overlay {
                if remote.answer.sentences.isEmpty {
                    Text("正在等待回答").foregroundStyle(muted)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.white, in: RoundedRectangle(cornerRadius: 18))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 5)
                    .updating($moving) { _, state, _ in state = true }
                    .onChanged { remote.move($0.translation, in: viewport.size) }
                    .onEnded { remote.finishMove($0.translation, in: viewport.size) }
            )
            .accessibilityHint(Text("滑动移动 Mac 浮窗"))
        }
    }

    private var controls: some View {
        GeometryReader { column in
            let spacing: CGFloat = 8
            let height = max(0, (column.size.height - 2 * spacing) / 3)
            VStack(spacing: spacing) {
                sentenceButton("上一句", icon: "chevron.up", delta: -1,
                               enabled: remote.answer.canSelectSentence && (remote.answer.currentSentence ?? 0) > 0)
                    .frame(height: height)
                holdButton
                    .frame(height: height)
                sentenceButton("下一句", icon: "chevron.down", delta: 1,
                               enabled: remote.answer.canSelectSentence &&
                                   (remote.answer.currentSentence ?? 0) < remote.answer.sentences.count - 1)
                    .frame(height: height)
            }
        }
        .frame(width: 134)
    }

    private func sentenceButton(_ title: LocalizedStringKey, icon: String, delta: Int, enabled: Bool) -> some View {
        Button { remote.select(delta) } label: {
            controlLabel(title, icon: icon, foreground: ink, background: .white)
                .opacity(enabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var holdButton: some View {
        let enabled = remote.answer.canSelectSentence && remote.answer.playback != .headphones
        return controlLabel(remote.holding ? "松手暂停" : "按住播放",
                            icon: remote.holding ? "pause.fill" : "play.fill",
                            foreground: .white, background: enabled ? (remote.holding ? accent : ink) : muted)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($pressing) { _, state, _ in state = true }
                    .onChanged { _ in remote.startHold() }
                    .onEnded { _ in remote.finishHold() },
                isEnabled: enabled
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(Text("从连接 Mac 的耳机播放"))
    }

    private func controlLabel(_ title: LocalizedStringKey, icon: String, foreground: Color, background: Color) -> some View {
        Label(title, systemImage: icon)
            .font(.body.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(foreground)
            .background(background, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
    }

    private var playbackStatus: LocalizedStringKey? {
        switch remote.answer.playback {
        case .off: "请在 Mac 开启陪读"
        case .headphones: "请在 Mac 连接耳机"
        case .preparing: "正在准备音频"
        case .guiding: "Mac 耳机播放中"
        case .failed: "松手后重试"
        case .ended: "已读完"
        case .waiting: nil
        }
    }

    private func openScanner() {
        guard DataScannerViewController.isSupported else { cameraError = true; return }
        Task {
            let allowed = await AVCaptureDevice.requestAccess(for: .video)
            if allowed && DataScannerViewController.isAvailable { scanning = true }
            else { cameraError = true }
        }
    }

    private func pair(_ link: URL) { pairingError = !remote.connect(link) }
}
