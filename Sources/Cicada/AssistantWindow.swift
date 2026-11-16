import AppKit
import Combine
import CoreImage.CIFilterBuiltins
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
    private static let frameAutosaveName = "CicadaAssistantFloat"
    private weak var model: AppModel?
    private var panel: AssistantPanel?
    private var footer: AssistantPanel?
    private let layout = AssistantFloatLayout()
    private var clickThroughSetting: AnyCancellable?
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
            let host = FirstClickHostingView(rootView: AssistantScriptView(
                engine: model.candidate, settings: model.settings, shadowReader: model.shadowReader, layout: layout))
            host.sizingOptions = []
            p.contentView = host
            // After contentView: installing the hosting view resets minSize to its zero fitting size,
            // which let a drag shrink the float to a 1-pt line that the autosave then kept.
            p.minSize = NSSize(width: 520, height: 260)
            p.setFrame(frame, display: false)
            p.setFrameAutosaveName(Self.frameAutosaveName)
            _ = p.setFrameUsingName(Self.frameAutosaveName)
            // A removed display must not strand the floating answer off screen, and a restored frame
            // skips minSize, so a line saved by older builds falls back to the default size.
            if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(p.frame) })
                || p.frame.width < p.minSize.width || p.frame.height < p.minSize.height {
                p.setFrame(frame, display: false)
            }
            p.setSizeLocked(model.settings.assistantSizeLocked)
            panel = p
            makeFooter(model: model, parent: p)
            clickThroughSetting = model.settings.$assistantClickThrough.removeDuplicates().sink { [weak p] on in
                p?.ignoresMouseEvents = on
            }
            NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: p, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.layoutFooter()
                    self?.scheduleBackdropCheck()
                }
            }
            NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: p, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.layoutFooter() }
            }
        }
        if let panel, let footer {
            layoutFooter()
            panel.orderFrontRegardless()
            if footer.parent == nil { panel.addChildWindow(footer, ordered: .above) }
            footer.orderFrontRegardless()
        }
        model.floatingAnswerVisibilityChanged()
        scheduleBackdropCheck()
    }

    func hide() {
        settle?.cancel()
        model?.shadowReader.setHeld(false)
        if let footer {
            panel?.removeChildWindow(footer)
            footer.orderOut(nil)
        }
        panel?.orderOut(nil)
        model?.floatingAnswerVisibilityChanged()
    }

    private func makeFooter(model: AppModel, parent: AssistantPanel) {
        // AppKit routes mouse input per window. Keep the controls in their own child window
        // so the script can pass through immediately, even before the cursor has moved.
        let p = AssistantPanel(contentRect: layout.footerFrame(in: parent.frame),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.identifier = NSUserInterfaceItemIdentifier("cicada.assistant.controls")
        p.title = L("悬浮回答")
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.level = parent.level
        p.collectionBehavior = parent.collectionBehavior
        p.sharingType = parent.sharingType
        let host = FirstClickHostingView(rootView: AssistantFloatingControls(
            engine: model.candidate, settings: model.settings, shadowReader: model.shadowReader, layout: layout,
            dragWindow: { [weak parent] in parent },
            pairPhone: { [weak model] in model?.pairPhoneForFloatingAnswer() },
            disconnectPhone: { [weak model] in model?.disconnectPhoneFromFloatingAnswer() == true },
            hasPhonePairing: { [weak model] in model?.hasPhonePairing == true },
            isPhoneScreenEnabled: { [weak model] in model?.isPhoneScreenEnabled == true },
            setPhoneScreenEnabled: { [weak model] in model?.setPhoneScreenEnabled($0) == true },
            toggleSizeLock: { [weak self] in self?.toggleSizeLock() },
            setHeight: { [weak self] in self?.setFooterHeight($0) },
            close: { [weak self] in self?.hide() }))
        host.sizingOptions = []
        p.contentView = host
        footer = p
    }

    private func setFooterHeight(_ height: CGFloat) {
        guard height > 0, height.isFinite, height != layout.footerHeight else { return }
        layout.footerHeight = height
        layoutFooter()
    }

    private func layoutFooter() {
        guard let panel, let footer else { return }
        let frame = layout.footerFrame(in: panel.frame)
        if footer.frame != frame { footer.setFrame(frame, display: true) }
    }

    private func toggleSizeLock() {
        guard let panel, let settings = model?.settings else { return }
        let locked = !settings.assistantSizeLocked
        panel.setSizeLocked(locked)
        if locked { panel.saveFrame(usingName: Self.frameAutosaveName) }
        settings.assistantSizeLocked = locked
    }

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
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        panel.appearance = appearance
        footer?.appearance = appearance
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
        let ownNumbers = Set(([panel] + (panel.childWindows ?? [])).map(\.windowNumber))
        let own = content.windows.filter { ownNumbers.contains(Int($0.windowID)) }
        let config = SCStreamConfiguration()
        config.sourceRect = rect.intersection(display.frame).offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
        config.width = 48; config.height = 32
        config.showsCursor = false
        let filter = SCContentFilter(display: display, excludingWindows: own)
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else { return nil }
        return AssistantAppearance.meanLuminance(image)
    }
    func setCapturable(_ on: Bool) {
        let sharing: NSWindow.SharingType = on ? .readOnly : .none
        panel?.sharingType = sharing
        footer?.sharingType = sharing
    }

    func logState() {
        guard let panel, let model else { debugLog("assistant float: not created"); return }
        debugLog("assistant float: visible=\(panel.isVisible) font=\(model.settings.assistantFontSize) opacity=\(model.settings.assistantOpacity) frame=\(panel.frame) key=\(panel.isKeyWindow) dark=\(panel.appearance?.name == .darkAqua) sharing=\(panel.sharingType.rawValue) scriptClickThrough=\(panel.ignoresMouseEvents) footer=\(String(describing: footer?.frame))")
    }
}

final class AssistantPanel: NSPanel {
    private var lockedSize: NSSize?

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func setSizeLocked(_ locked: Bool) {
        if locked {
            lockedSize = frame.size
            styleMask.remove(.resizable)
        } else {
            lockedSize = nil
            styleMask.insert(.resizable)
        }
    }

    // The style mask disables AppKit's resize handles. Frame changes can still move the panel.
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var frameRect = frameRect
        if let lockedSize { frameRect.size = lockedSize }
        super.setFrame(frameRect, display: flag)
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool, animate animateFlag: Bool) {
        var frameRect = frameRect
        if let lockedSize { frameRect.size = lockedSize }
        super.setFrame(frameRect, display: flag, animate: animateFlag)
    }

    override func setContentSize(_ size: NSSize) {
        guard lockedSize == nil else { return }
        super.setContentSize(size)
    }
}

@MainActor
private final class AssistantFloatLayout: ObservableObject {
    @Published var footerHeight: CGFloat = 95
    @Published var followsReading = true

    func footerFrame(in frame: NSRect) -> NSRect {
        NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: min(footerHeight, frame.height))
    }
}

private struct AssistantScriptView: View {
    let engine: InterviewCoach
    @ObservedObject var settings: AppSettings
    let shadowReader: ShadowReader
    @ObservedObject var layout: AssistantFloatLayout

    var body: some View {
        CandidateFeed(engine: engine, settings: settings, shadowReader: shadowReader, expanded: true,
                      fontSize: settings.assistantFontSize,
                      glossFontSize: max(10, min(14, settings.assistantFontSize * 0.375)),
                      floatingFollow: layout.followsReading)
            .padding(.top, 4)
            .padding(.bottom, layout.footerHeight)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 16).fill(Palette.surface.opacity(settings.assistantOpacity)))
    }
}

private struct AssistantDragHandle: NSViewRepresentable {
    weak var window: NSWindow?

    func makeNSView(context: Context) -> Handle {
        let view = Handle()
        view.target = window
        return view
    }

    func updateNSView(_ nsView: Handle, context: Context) { nsView.target = window }

    final class Handle: NSView {
        weak var target: NSWindow?
        private var start = NSPoint.zero
        private var origin = NSPoint.zero

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard let target else { return }
            start = NSEvent.mouseLocation
            origin = target.frame.origin
        }

        override func mouseDragged(with event: NSEvent) {
            let mouse = NSEvent.mouseLocation
            target?.setFrameOrigin(NSPoint(x: origin.x + mouse.x - start.x, y: origin.y + mouse.y - start.y))
        }
    }
}

private struct AssistantFloatingControls: View {
    @ObservedObject var engine: InterviewCoach
    @ObservedObject var settings: AppSettings
    let shadowReader: ShadowReader
    @ObservedObject var layout: AssistantFloatLayout
    let dragWindow: () -> NSWindow?
    let pairPhone: () -> URL?
    let disconnectPhone: () -> Bool
    let hasPhonePairing: () -> Bool
    let isPhoneScreenEnabled: () -> Bool
    let setPhoneScreenEnabled: (Bool) -> Bool
    let toggleSizeLock: () -> Void
    let setHeight: (CGFloat) -> Void
    let close: () -> Void
    @State private var pairingShown = false
    @State private var pairingURL: URL?
    @State private var pairingFailed = false
    @State private var disconnectFailed = false
    @State private var paired = false
    @State private var pairingImage: CGImage?
    @State private var screenEnabled = false
    @State private var screenFailed = false

    private var sizeLockLabel: Text {
        Text(settings.assistantSizeLocked ? "解锁大小" : "锁定大小")
    }

    var body: some View {
        VStack(spacing: 8) {
            CandidateFeedControls(engine: engine, settings: settings, shadowReader: shadowReader,
                                  followsReading: $layout.followsReading)
                .padding(.horizontal, 24)
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "hand.draw").accessibilityHidden(true)
                    Text("悬浮回答").fontWeight(.semibold)
                }
                .padding(.vertical, 6)
                .overlay(AssistantDragHandle(window: dragWindow()).accessibilityHidden(true))
                Spacer()
                if settings.notesCapturable {
                    Image(systemName: "eye")
                        .help(Text("共享中可见"))
                        .accessibilityLabel(Text("共享中可见"))
                }
                Toggle("稿件点击穿透", isOn: $settings.assistantClickThrough)
                    .toggleStyle(.checkbox)
                    .fixedSize()
                Button {
                    paired = hasPhonePairing()
                    screenEnabled = isPhoneScreenEnabled()
                    screenFailed = false
                    disconnectFailed = false
                    pairingShown = true
                } label: {
                    Image(systemName: "iphone").frame(width: 28, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("连接手机"))
                .help(Text("连接手机"))
                .popover(isPresented: $pairingShown) {
                    VStack(spacing: 12) {
                        if !screenEnabled, let pairingImage {
                            Image(decorative: pairingImage, scale: 1)
                                .interpolation(.none).resizable().scaledToFit()
                                .frame(width: 176, height: 176).padding(10).background(.white)
                            Text("同一 Wi-Fi 下，用系统相机扫码打开网页。")
                        }
                        if !screenEnabled, let pairingURL {
                            Button("复制配对链接") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(pairingURL.absoluteString, forType: .string)
                            }
                        }
                        if pairingFailed { Text("暂时无法生成配对码").foregroundStyle(Palette.secondary) }
                        Button {
                            pairingFailed = true
                            if let url = pairPhone() {
                                paired = true
                                screenEnabled = false
                                pairingFailed = false
                                pairingURL = url
                                pairingImage = nil
                                let filter = CIFilter.qrCodeGenerator()
                                filter.message = Data(url.absoluteString.utf8)
                                if let output = filter.outputImage {
                                    pairingImage = CIContext().createCGImage(output, from: output.extent)
                                }
                            }
                        } label: {
                            Text(paired ? "重新生成配对码" : "生成配对码")
                        }
                        if paired {
                            Button {
                                screenFailed = !setPhoneScreenEnabled(!screenEnabled)
                                screenEnabled = isPhoneScreenEnabled()
                                if screenEnabled { pairingShown = false }
                            } label: {
                                Text(screenEnabled ? "停止共享 Mac 屏幕" : "向手机共享 Mac 主屏幕")
                            }
                            if screenFailed {
                                Text("请在系统设置中允许 Cicada 录制屏幕。").foregroundStyle(Palette.secondary)
                            }
                            Button("断开手机") {
                                disconnectFailed = !disconnectPhone()
                                guard !disconnectFailed else { return }
                                paired = false
                                screenEnabled = false
                                pairingImage = nil
                                pairingURL = nil
                            }
                            if disconnectFailed { Text("暂时无法断开手机").foregroundStyle(Palette.secondary) }
                        }
                    }
                    .padding(16)
                }
                Button(action: toggleSizeLock) {
                    Image(systemName: settings.assistantSizeLocked ? "lock.fill" : "lock.open")
                        .frame(width: 28, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(sizeLockLabel)
                .help(sizeLockLabel)
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
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { ceil($0.size.height) } action: { setHeight($0) }
        // A fully transparent pixel is click-through at the WindowServer level. Leave a
        // faint tint so the control strip still owns mouse input at zero background opacity.
        .background(UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16)
            .fill(Palette.surface.opacity(0.04)))
    }
}
