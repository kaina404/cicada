import AppKit
import SwiftUI

/// 设置 › 屏幕识别: what is read off the screen (the meeting window found by itself, or a window or
/// display picked with the system picker), what it looks like now, and the local model.
struct ScreenSettings: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var screen: ScreenWatch

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsCard {
                SettingsRow(title: screen.chosen?.label ?? L("自动找会议窗口"),
                            detail: screen.chosen == nil ? L("Zoom、腾讯会议、Teams、飞书，或浏览器里的会议") : L("这个窗口关掉后改回自动")) {
                    HStack(spacing: 8) {
                        if screen.chosen != nil { SoftButton(L("改回自动")) { screen.useAutomatic() } }
                        SoftButton(L("选择窗口或屏幕…")) { screen.choose() }
                    }
                }
                if screen.needsPermission {
                    SettingsRow(title: L("需要屏幕录制权限"), detail: L("自动找会议窗口要用；自己选的窗口不用")) {
                        SoftButton(L("打开系统设置")) {
                            CGRequestScreenCaptureAccess()
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                        }
                    }
                }
                preview
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
        // Outside a meeting the preview is taken here; in one the watch keeps it fresh.
        .task {
            while !Task.isCancelled {
                await screen.refreshPreview()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if screen.isRunning { Circle().fill(Palette.accent).frame(width: 6, height: 6) }
                Text(screen.isRunning ? L("正在识别") : L("预览")).font(.system(size: 13)).foregroundStyle(Palette.ink)
                if let current = screen.current {
                    Text(current).font(.system(size: 11)).foregroundStyle(Palette.tertiary).lineLimit(1)
                }
            }
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Palette.fill)
                if let image = screen.preview {
                    Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6)).padding(6)
                } else {
                    Text(screen.needsPermission ? L("给了权限才能看到") : L("没找到会议窗口，选一个窗口或屏幕"))
                        .font(.system(size: 12)).foregroundStyle(Palette.tertiary)
                }
            }
            .frame(height: 260)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
}
