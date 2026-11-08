import Testing
@testable import Cicada

struct AssistantAppearanceTests {
    @Test func storedAppearanceRemainsUsable() {
        #expect(AssistantAppearance.fontSize(-10) == 16)
        #expect(AssistantAppearance.fontSize(120) == 96)
        #expect(AssistantAppearance.fontSize(48) == 48)
        #expect(AssistantAppearance.fontSize(.nan) == 32)
        #expect(AssistantAppearance.opacity(-1) == 0)
        #expect(AssistantAppearance.opacity(2) == 1)
        #expect(AssistantAppearance.opacity(0.42) == 0.42)
        #expect(AssistantAppearance.opacity(.infinity) == 0.8)
    }
}
