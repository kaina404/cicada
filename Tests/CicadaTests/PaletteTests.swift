import AppKit
import SwiftUI
import Testing
@testable import Cicada

@Suite @MainActor struct PaletteTests {
    private func resolved(_ color: Color, _ name: NSAppearance.Name) throws -> NSColor {
        let appearance = try #require(NSAppearance(named: name))
        var result: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            result = NSColor(color).usingColorSpace(.sRGB)
        }
        return try #require(result)
    }

    private func luminance(_ c: NSColor) -> Double {
        func linear(_ v: CGFloat) -> Double {
            let x = Double(v)
            return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(c.redComponent) + 0.7152 * linear(c.greenComponent) + 0.0722 * linear(c.blueComponent)
    }

    @Test func textRemainsReadableInBothAppearances() throws {
        let backgrounds = [Palette.surface, Palette.ground, Palette.fill, Palette.raised, Palette.accentPale, Palette.accentWash]
        let text = [Palette.ink, Palette.body, Palette.secondary, Palette.tertiary]
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for background in backgrounds {
                let bg = luminance(try resolved(background, appearance))
                for foreground in text {
                    let fg = luminance(try resolved(foreground, appearance))
                    #expect((max(bg, fg) + 0.05) / (min(bg, fg) + 0.05) >= 4.5)
                }
            }
            for (foreground, background) in [(Palette.accentInk, Palette.accentPale), (Palette.ok, Palette.okPale),
                                              (Palette.error, Palette.errorPale), (Palette.body, Palette.mark)] {
                let fg = luminance(try resolved(foreground, appearance))
                let bg = luminance(try resolved(background, appearance))
                #expect((max(bg, fg) + 0.05) / (min(bg, fg) + 0.05) >= 4.5)
            }
            for n in 1...4 {
                let fg = luminance(try resolved(SpeakerColor.ink(n), appearance))
                let bg = luminance(try resolved(Palette.surface, appearance))
                #expect((max(bg, fg) + 0.05) / (min(bg, fg) + 0.05) >= 4.5)
            }
        }
    }

    @Test func sameDynamicColourResolvesAgainAfterAppearanceChanges() throws {
        let surface = Palette.surface
        let light = try resolved(surface, .aqua)
        let dark = try resolved(surface, .darkAqua)
        #expect(luminance(light) > 0.95)
        #expect(luminance(dark) < 0.05)
        #expect(try resolved(surface, .aqua) == light)
        #expect(try resolved(Palette.strong, .aqua) == resolved(Palette.strong, .darkAqua))
    }
}
