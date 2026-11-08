import AppKit
import SwiftUI

enum Palette {
    /// Dynamic AppKit colours follow each window's appearance, including changes while open.
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: adaptiveNS(light, dark))
    }

    static func adaptiveNS(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        }
    }

    static let surface = adaptive(0xFFFFFF, 0x22252B)
    static let canvas = adaptive(0xF6F7F9, 0x191B20)
    /// Fixed dark surfaces with white labels, e.g. listening pills and primary buttons.
    static let strong = Color(red: 0.08, green: 0.09, blue: 0.11)
    static let ink = adaptive(0x14171C, 0xF1F2F5)
    static let ground = adaptive(0xF3F4F6, 0x191B20)
    static let line = adaptive(0xE4E6EA, 0x383C45)
    static let secondary = adaptive(0x5A5F6B, 0xBDC2CD)
    static let tertiary = adaptive(0x686D7C, 0xA3AABB)
    /// Body text in the records window: darker than the greys, lighter than headings.
    static let body = adaptive(0x3D414A, 0xD2D6DF)
    /// Times you can click to jump to the original, and the numbers that order notes: the logo's
    /// orange as ink, so text stays in the brand's family while the bright accent stays "live".
    static let link = adaptive(0xB23B14, 0xFFAC8C)
    /// Highlighter behind numbers and dates in the conclusions.
    static let mark = adaptive(0xFFE7A3, 0x655020)
    static let accent = Color(red: 0.91, green: 0.33, blue: 0.17)
    static let accentInk = adaptive(0xB23B14, 0xFFAC8C)
    static let accentPale = adaptive(0xFCEDE7, 0x422C25)
    /// Controls, chips, search fields.
    static let fill = adaptive(0xF2F3F5, 0x2C3038)
    /// Emphasis blocks (summary, setting cards).
    static let raised = adaptive(0xF5F6F8, 0x282C33)
    /// Current row while something is live.
    static let accentWash = adaptive(0xFFFAF8, 0x32241F)
    static let ok = adaptive(0x1F7A45, 0x80D9A3)
    static let okPale = adaptive(0xE7F5EC, 0x20392B)
    static let error = adaptive(0xB42318, 0xFF9C8E)
    static let errorPale = adaptive(0xFDECEA, 0x442A29)
    /// Headings over placeholder shapes while notes are being written.
    static let placeholder = adaptive(0xB8BDC6, 0x606979)
}
