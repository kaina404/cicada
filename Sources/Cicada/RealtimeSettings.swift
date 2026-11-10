import AppKit
import SwiftUI

struct InterviewCoachSettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    @State private var status = ""
    @State private var testing = false
    @State private var checking: Task<Void, Never>?
    @State private var deepSeekKey = ""
    @State private var hasDeepSeekKey = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("面试教练").font(.system(size: 13, weight: .semibold))
            Text("DeepSeek 处理原文和截图，Gemma 在本机跟读")
                .font(.system(size: 12)).foregroundStyle(Palette.tertiary)
            SettingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(verbatim: "DeepSeek Flash · Gemma 4 E4B").font(.system(size: 13))
                    HStack {
                        SecureField(hasDeepSeekKey ? L("已保存 DeepSeek key") : "DeepSeek key", text: $deepSeekKey)
                        Button("保存") {
                            if AIKey.save(deepSeekKey.trimmingCharacters(in: .whitespacesAndNewlines), "deepseek") {
                                hasDeepSeekKey = true; deepSeekKey = ""
                            } else { status = L("Key 保存失败") }
                        }.disabled(deepSeekKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Toggle("面试教练", isOn: $settings.continuousAssistant)
                    Toggle("陪读", isOn: $settings.shadowReading)
                    Button("候选人麦克风") { model.openSettings(.speak) }
                    Text("Kokoro 本机合成，按住手表播放，松开暂停")
                        .font(.system(size: 11)).foregroundStyle(Palette.tertiary)
                    HStack {
                        Button("检查本机模型") { test() }.disabled(testing)
                        Button("安装语音检测") { installAudio() }.disabled(testing)
                        Text(status).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                    }
                    Divider()
                    HStack {
                        Text("面试资料").font(.system(size: 13))
                        Spacer()
                        Button("打开资料文件夹") { openKnowledge() }
                    }
                    Text("简历、项目、预制回答和目标公司，开始听时重新读取")
                        .font(.system(size: 11)).foregroundStyle(Palette.tertiary)
                }.textFieldStyle(.roundedBorder).padding(14)
            }
        }
        .onAppear {
            hasDeepSeekKey = AIKey.read("deepseek") != nil
        }
        .onDisappear { checking?.cancel(); model.candidateBackgroundChanged() }
    }
    /// The files are edited in the user's own editor; the app only makes sure they exist.
    private func openKnowledge() {
        do { try Knowledge.prepareFolder(); NSWorkspace.shared.open(Knowledge.folder) }
        catch { status = L("资料文件夹创建失败") }
    }
    private func installAudio() {
        testing = true; status = L("正在准备语音检测…")
        checking = Task {
            defer { testing = false }
            let ready = await CoachAudioWorker.prepareModels()
            guard !Task.isCancelled else { return }
            status = ready ? L("语音检测已就绪") : L("语音检测安装失败，请重试")
            if ready { model.candidate.acoustic.stop(); model.candidate.acoustic.start() }
        }
    }
    private func test() {
        guard VisionServer.available(model: CoachPrompt.model) else {
            status = L("本机未安装 mlx-vlm"); return
        }
        testing = true; status = L("正在准备本机 Gemma…")
        checking = Task {
            defer { testing = false }
            if !(await VisionServer.waitReady(seconds: 0)) { model.screen.server.start(model: CoachPrompt.model) }
            let ready = await VisionServer.waitReady(seconds: 90)
            guard !Task.isCancelled else { return }
            status = ready ? L("本机模型已就绪") : L("本机模型未能启动，请重试")
        }
    }
}
