import AppKit
import SwiftUI

/// Screen model preferences; the live meeting owns selection and capture.
struct ScreenSettings: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("画面在每场会议的纪要窗口中选择，可跳过")
                .font(.system(size: 12)).foregroundStyle(Palette.tertiary)
            SettingsCard {
                SettingsRow(title: L("面试教练"), detail: L("DeepSeek 处理原文和截图，Gemma 在本机跟读")) {
                    Toggle("面试教练", isOn: $settings.continuousAssistant).labelsHidden().toggleStyle(.switch).tint(Palette.ink)
                }
                SettingsRow(title: L("显示中文对照"), detail: L("使用已安装的苹果翻译语言包"), divider: false) {
                    Toggle("显示中文对照", isOn: $settings.askGloss).labelsHidden().toggleStyle(.switch).tint(Palette.ink)
                }
            }
            SettingsCard {
                // A Hugging Face name is long ("mlx-community/gemma-4-E4B-it-qat-4bit"): the field gets the whole row.
                VStack(alignment: .leading, spacing: 6) {
                    Text("看懂画面的本地模型").font(.system(size: 13)).foregroundStyle(Palette.ink)
                    TextField("", text: $settings.screenModel).textFieldStyle(.roundedBorder)
                    Text("mlx-vlm 的模型名，留空只读文字").font(.system(size: 11)).foregroundStyle(Palette.tertiary)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                Divider().padding(.leading, 16)
                SettingsRow(title: L("mlx-vlm"),
                            detail: FileManager.default.isExecutableFile(atPath: VisionServer.executable.path)
                                ? L("已装在 ~/.cicada-mlx") : L("没装：只读文字，不解释画面"), divider: false) {
                    EmptyView()
                }
            }
        }
    }
}

/// Optional screen input belongs to this live meeting, alongside its notes.
struct ScreenStrip: View {
    @ObservedObject var screen: ScreenWatch
    var compact = false

    var body: some View {
        if screen.meetingID != nil {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if !compact {
                        Text("会议画面（可选）").font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                        Spacer(minLength: 0)
                    }
                    SoftButton(screen.chosen == nil ? L("选择画面…") : L("更换画面…")) { screen.choose() }
                    if screen.chosen != nil {
                        SoftButton(L("停止读取")) { screen.clearSelection() }
                    }
                }
                if let chosen = screen.chosen, !compact {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6).fill(Palette.fill)
                            if let image = screen.preview {
                                Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 4)).padding(2)
                            } else {
                                Image(systemName: "rectangle.dashed").foregroundStyle(Palette.tertiary)
                            }
                        }
                        .frame(width: 96, height: 54)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(chosen.label).font(.system(size: 12)).foregroundStyle(Palette.ink).lineLimit(2)
                            Text(screen.previewUnavailable ? L("暂时无法读取所选画面，请重新选择")
                                 : screen.preview == nil ? L("正在获取所选画面…") : L("结束会议后停止读取"))
                                .font(.system(size: 11)).foregroundStyle(Palette.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else if screen.chosen == nil, !compact {
                    Text("不选也可记录；声音来源不变").font(.system(size: 11)).foregroundStyle(Palette.tertiary)
                }
            }
        }
    }
}
