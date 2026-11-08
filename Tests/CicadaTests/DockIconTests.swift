import AppKit
import Testing
@testable import Cicada

@Suite @MainActor struct DockIconTests {
    @Test func liveIndicatorAppearsAndClears() {
        _ = NSApplication.shared
        DockIcon.show(live: false)
        let idle = (NSApp.dockTile.contentView as? NSImageView)?.image?.tiffRepresentation
        #expect(idle != nil)
        DockIcon.show(live: true)
        #expect(DockIcon.live)
        let live = (NSApp.dockTile.contentView as? NSImageView)?.image?.tiffRepresentation
        #expect(live != nil)
        #expect(live != idle)
        DockIcon.show(live: false)
        #expect(!DockIcon.live)
        #expect((NSApp.dockTile.contentView as? NSImageView)?.image?.tiffRepresentation == idle)
    }
}
