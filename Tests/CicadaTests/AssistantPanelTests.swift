import AppKit
import Testing
@testable import Cicada

@MainActor
struct AssistantPanelTests {
    @Test func sizeLockKeepsCurrentDimensionsWhileAllowingMoves() {
        _ = NSApplication.shared
        let original = NSRect(x: 100, y: 100, width: 720, height: 480)
        let panel = AssistantPanel(contentRect: original,
                                   styleMask: [.borderless, .resizable, .nonactivatingPanel],
                                   backing: .buffered, defer: false)
        panel.minSize = NSSize(width: 520, height: 260)
        let resized = NSRect(x: 140, y: 150, width: 800, height: 600)

        panel.setSizeLocked(true)
        #expect(!panel.styleMask.contains(.resizable))
        #expect(panel.frame == original)

        panel.setFrame(resized, display: false)
        #expect(panel.frame.origin == resized.origin)
        #expect(panel.frame.size == original.size)

        panel.setFrame(original.insetBy(dx: 60, dy: 60), display: false, animate: true)
        panel.setContentSize(resized.size)
        #expect(panel.frame.size == original.size)

        panel.setFrameOrigin(original.origin)
        #expect(panel.frame == original)

        panel.setSizeLocked(false)
        #expect(panel.styleMask.contains(.resizable))
        #expect(panel.minSize == NSSize(width: 520, height: 260))
        panel.setFrame(resized, display: false)
        #expect(panel.frame == resized)
    }
}
