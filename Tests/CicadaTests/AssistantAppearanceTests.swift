import CoreGraphics
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

    @Test func backdropPicksReadableAppearance() {
        #expect(AssistantAppearance.prefersDark(0.1, current: false))
        #expect(!AssistantAppearance.prefersDark(0.9, current: true))
        // Mid-grey keeps whatever the float already shows.
        #expect(AssistantAppearance.prefersDark(0.5, current: true))
        #expect(!AssistantAppearance.prefersDark(0.5, current: false))
    }

    @Test func meanLuminanceOfSolidImages() throws {
        func solid(_ v: CGFloat) throws -> CGImage {
            let ctx = try #require(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
            ctx.setFillColor(red: v, green: v, blue: v, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
            return try #require(ctx.makeImage())
        }
        #expect(try #require(AssistantAppearance.meanLuminance(try solid(0))) < 0.01)
        #expect(try #require(AssistantAppearance.meanLuminance(try solid(1))) > 0.99)
    }
}
