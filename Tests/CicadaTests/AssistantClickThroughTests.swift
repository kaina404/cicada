import AppKit
import Testing
@testable import Cicada

@MainActor
struct AssistantClickThroughTests {
    // Opt in: the WindowServer probe opens visible windows on the current Mac desktop.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CICADA_TEST_FLOAT_CLICKS"] == "1"))
    func systemRoutesScriptAndControlsToDifferentWindows() async throws {
        _ = NSApplication.shared
        let screen = try #require(NSScreen.main)
        let visible = screen.visibleFrame
        let area = NSRect(x: visible.midX - 340, y: visible.midY - 190, width: 680, height: 380)
        let behind = NSWindow(contentRect: area.insetBy(dx: -20, dy: -20),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        behind.orderFrontRegardless()
        defer { behind.orderOut(nil) }

        let model = AppModel()
        let controller = model.assistantWindow
        let defaults = UserDefaults.standard
        let previous = ["assistantClickThrough", "assistantOpacity", "assistantSizeLocked",
                        "NSWindow Frame CicadaAssistantFloat"].map { ($0, defaults.object(forKey: $0)) }
        defer {
            controller.hide()
            model.stopWatchControl()
            for (key, value) in previous { defaults.set(value, forKey: key) }
        }
        model.settings.assistantOpacity = 0.8
        model.settings.assistantSizeLocked = false
        model.settings.assistantClickThrough = false
        controller.show()
        let script = try #require(controller.remoteWindow)
        let controls = try #require(script.childWindows?.first)
        script.setFrame(area, display: true)
        let scriptPoint = NSPoint(x: area.midX, y: area.midY)
        let controlsPoint = NSPoint(x: area.midX, y: area.minY + 6)

        func hit(_ point: NSPoint) -> Int {
            NSWindow.windowNumber(at: point, belowWindowWithWindowNumber: 0)
        }
        try await Task.sleep(for: .milliseconds(200))
        #expect(hit(scriptPoint) == script.windowNumber)
        #expect(hit(controlsPoint) == controls.windowNumber)

        model.settings.assistantClickThrough = true
        try await Task.sleep(for: .milliseconds(100))
        #expect(hit(scriptPoint) == behind.windowNumber)
        #expect(hit(controlsPoint) == controls.windowNumber)
        #expect(!script.isKeyWindow && !controls.isKeyWindow)

        model.settings.assistantOpacity = 0
        try await Task.sleep(for: .milliseconds(100))
        #expect(hit(controlsPoint) == controls.windowNumber)

        let moved = area.offsetBy(dx: 40, dy: -20)
        script.setFrame(moved, display: true)
        try await Task.sleep(for: .milliseconds(100))
        #expect(script.frame.origin != area.origin)
        #expect(controls.frame.origin == script.frame.origin)
        #expect(controls.frame.width == script.frame.width)

        model.settings.assistantOpacity = 0.8
        model.settings.assistantClickThrough = false
        try await Task.sleep(for: .milliseconds(100))
        #expect(hit(scriptPoint) == script.windowNumber)

        controller.hide()
        #expect(!script.isVisible && !controls.isVisible)
    }
}
