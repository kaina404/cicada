import AppKit
import ScreenCaptureKit
import SwiftUI

/// Keep corrupt stored preferences from making the floating controls unreadable or unusable.
enum AssistantAppearance {
    static func fontSize(_ value: Double) -> Double { value.isFinite ? min(96, max(16, value)) : 32 }
    static func opacity(_ value: Double) -> Double { value.isFinite ? min(1, max(0, value)) : 0.8 }

    /// A dead band around mid-grey keeps a busy backdrop from flipping the float back and forth.
    static func prefersDark(_ luminance: Double, current: Bool) -> Bool {
        luminance < 0.42 ? true : luminance > 0.58 ? false : current
    }

    static func meanLuminance(_ image: CGImage) -> Double? {
        let w = image.width, h = image.height
        guard w > 0, h > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                                space: CGColorSpaceCreateDeviceRGB(),
                                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let data = ctx.data else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let px = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var sum = 0.0
        for i in 0..<(w * h) {
            sum += 0.2126 * Double(px[i * 4]) + 0.7152 * Double(px[i * 4 + 1]) + 0.0722 * Double(px[i * 4 + 2])
        }
        return sum / Double(w * h) / 255
    }
}

@MainActor
final class AssistantWindowController {
    private weak var model: AppModel?
    private var panel: NSPanel?
    private var settle: Task<Void, Never>?

    init(model: AppModel) { self.model = model }

    var remoteWindow: NSWindow? { panel }

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
            p.identifier = NSUserInterfaceItemIdentifier("cicada.assistant")
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
            let host = FirstClickHostingView(rootView: AssistantFloatingView(
                engine: model.candidate, settings: model.settings, shadowReader: model.shadowReader,
                close: { [weak self] in self?.hide() }))
            host.sizingOptions = []
            p.contentView = host
            // After contentView: installing the hosting view resets minSize to its zero fitting size,
            // which let a drag shrink the float to a 1-pt line that the autosave then kept.
            p.minSize = NSSize(width: 520, height: 260)
            p.setFrame(frame, display: false)
            p.setFrameAutosaveName("CicadaAssistantFloat")
            _ = p.setFrameUsingName("CicadaAssistantFloat")
            // A removed display must not strand the floating answer off screen, and a restored frame
            // skips minSize, so a line saved by older builds falls back to the default size.
            if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(p.frame) })
                || p.frame.width < p.minSize.width || p.frame.height < p.minSize.height {
                p.setFrame(frame, display: false)
            }
            panel = p
            NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: p, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleBackdropCheck() }
            }
        }
        panel?.orderFrontRegardless()
        scheduleBackdropCheck()
    }

    func hide() { settle?.cancel(); model?.shadowReader.setHeld(false); panel?.orderOut(nil) }

    /// With a see-through background the text can land on anything; once the float has rested for
    /// a moment, switch its light/dark appearance to the screen beneath so the adaptive ink contrasts.
    private func scheduleBackdropCheck() {
        settle?.cancel()
        settle = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            await self?.matchBackdrop()
        }
    }

    func matchBackdrop() async {
        // Only with existing Screen Recording permission: moving a window must never raise a prompt.
        guard let panel, panel.isVisible, CGPreflightScreenCaptureAccess(),
              let luminance = await Self.backdropLuminance(behind: panel), !Task.isCancelled else { return }
        let dark = AssistantAppearance.prefersDark(luminance, current: panel.appearance?.name == .darkAqua)
        panel.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        debugLog("assistant float: backdrop luminance=\(String(format: "%.2f", luminance)) dark=\(dark)")
    }

    /// Mean luminance (0–1) of what the screen shows under the panel, the panel itself excluded.
    private static func backdropLuminance(behind panel: NSWindow) async -> Double? {
        guard let primary = NSScreen.screens.first,
              let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else { return nil }
        // AppKit puts the origin bottom-left; ScreenCaptureKit uses top-left global coordinates.
        let f = panel.frame
        let rect = CGRect(x: f.minX, y: primary.frame.maxY - f.maxY, width: f.width, height: f.height)
        guard let display = content.displays.first(where: { $0.frame.contains(CGPoint(x: rect.midX, y: rect.midY)) })
                ?? content.displays.first(where: { $0.frame.intersects(rect) }) else { return nil }
        let own = content.windows.filter { $0.windowID == CGWindowID(panel.windowNumber) }
        let config = SCStreamConfiguration()
        config.sourceRect = rect.intersection(display.frame).offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
        config.width = 48; config.height = 32
        config.showsCursor = false
        let filter = SCContentFilter(display: display, excludingWindows: own)
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else { return nil }
        return AssistantAppearance.meanLuminance(image)
    }
    func setCapturable(_ on: Bool) { panel?.sharingType = on ? .readOnly : .none }

    func logState() {
        guard let panel, let model else { debugLog("assistant float: not created"); return }
        debugLog("assistant float: visible=\(panel.isVisible) font=\(model.settings.assistantFontSize) opacity=\(model.settings.assistantOpacity) frame=\(panel.frame) key=\(panel.isKeyWindow) dark=\(panel.appearance?.name == .darkAqua) sharing=\(panel.sharingType.rawValue)")
    }
}

private final class AssistantPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct AssistantFloatingView: View {
    @ObservedObject var engine: InterviewCoach
    @ObservedObject var settings: AppSettings
    let shadowReader: ShadowReader
    let close: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            CandidateFeed(engine: engine, settings: settings, shadowReader: shadowReader, expanded: true,
                          fontSize: settings.assistantFontSize,
                          glossFontSize: max(10, min(14, settings.assistantFontSize * 0.375)),
                          controlsAtBottom: true)
                .frame(maxHeight: .infinity)
                .padding(.top, 4)
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
            .padding(.horizontal, 20)
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
        }
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Only the background fades; the script and controls retain their contrast.
        .background(RoundedRectangle(cornerRadius: 16).fill(Palette.surface.opacity(settings.assistantOpacity)))
    }
}
