import AppKit
import SwiftUI

/// Keep corrupt stored preferences from making the floating controls unreadable or unusable.
enum AssistantAppearance {
    static func fontSize(_ value: Double) -> Double { value.isFinite ? min(96, max(16, value)) : 32 }
    static func opacity(_ value: Double) -> Double { value.isFinite ? min(1, max(0, value)) : 0.8 }
}

@MainActor
final class AssistantWindowController {
    private weak var model: AppModel?
    private var panel: NSPanel?

    init(model: AppModel) { self.model = model }

    func show() {
        guard let model else { return }
        if panel == nil {
            let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
            let frame = NSRect(x: screen.midX - 360, y: screen.midY - 240,
                               width: min(720, screen.width), height: min(480, screen.height))
            let p = AssistantPanel(contentRect: frame,
                                   styleMask: [.borderless, .resizable, .nonactivatingPanel],
                                   backing: .buffered, defer: false)
            p.title = L("悬浮回答")
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.level = .floating
            p.isFloatingPanel = true
            p.hidesOnDeactivate = false
            p.isReleasedWhenClosed = false
            p.isMovableByWindowBackground = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.sharingType = model.settings.notesCapturable ? .readOnly : .none
            p.minSize = NSSize(width: 520, height: 260)
            let host = FirstClickHostingView(rootView: AssistantFloatingView(
                engine: model.candidate, settings: model.settings,
                close: { [weak self] in self?.hide() }))
            host.sizingOptions = []
            p.contentView = host
            p.setFrame(frame, display: false)
            p.setFrameAutosaveName("CicadaAssistantFloat")
            _ = p.setFrameUsingName("CicadaAssistantFloat")
            // A removed display must not strand the floating answer off screen.
            if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(p.frame) }) {
                p.setFrame(frame, display: false)
            }
            panel = p
        }
        panel?.orderFrontRegardless()
    }

    func hide() { panel?.orderOut(nil) }
    func setCapturable(_ on: Bool) { panel?.sharingType = on ? .readOnly : .none }

    func logState() {
        guard let panel, let model else { debugLog("assistant float: not created"); return }
        debugLog("assistant float: visible=\(panel.isVisible) font=\(model.settings.assistantFontSize) opacity=\(model.settings.assistantOpacity) frame=\(panel.frame) key=\(panel.isKeyWindow) sharing=\(panel.sharingType.rawValue)")
    }
}

private final class AssistantPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct AssistantFloatingView: View {
    @ObservedObject var engine: InterviewCoach
    @ObservedObject var settings: AppSettings
    let close: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "hand.draw").accessibilityHidden(true)
                Text("悬浮回答").fontWeight(.semibold)
                Spacer()
                if settings.notesCapturable {
                    Label("共享中可见", systemImage: "eye")
                }
                Button(action: close) {
                    Image(systemName: "xmark").frame(width: 28, height: 28).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(Text("关闭"))
            }
            .font(.system(size: 12)).foregroundStyle(Palette.secondary)
            .padding(.horizontal, 20).padding(.top, 10)
            HStack(spacing: 10) {
                Text("字号")
                Slider(value: $settings.assistantFontSize, in: 16...96, step: 1)
                    .accessibilityLabel(Text("字号"))
                Text("\(Int(settings.assistantFontSize))").monospacedDigit().frame(width: 26)
                Text("背景不透明度")
                Slider(value: $settings.assistantOpacity, in: 0...1, step: 0.01)
                    .accessibilityLabel(Text("背景不透明度"))
                Text("\(Int((settings.assistantOpacity * 100).rounded()))%").monospacedDigit().frame(width: 36)
            }
            .font(.system(size: 12)).foregroundStyle(Palette.ink).padding(.horizontal, 20)
            CandidateFeed(engine: engine, settings: settings, expanded: true,
                          fontSize: settings.assistantFontSize)
                .frame(maxHeight: .infinity)
        }
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Only the background fades; the script and controls retain their contrast.
        .background(RoundedRectangle(cornerRadius: 16).fill(Palette.surface.opacity(settings.assistantOpacity)))
    }
}
