import AppKit
import SwiftUI

// Tinted neutrals with one rose accent taken from the icon's hoodie. The accent is kept for the things you act on
// (send, selection, focus, links); surfaces stay quiet so the conversation is what you read.
enum Theme {
    static let accent = dynamic(light: 0xCF2D66, dark: 0xF25C8F)
    static let background = dynamic(light: 0xFFF8FA, dark: 0x1F171B)
    static let sidebar = dynamic(light: 0xF8E9EF, dark: 0x171114)
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x2A2226)
    static let border = dynamic(light: 0xE9D6DE, dark: 0x3C3237)
    static let userBubble = dynamic(light: 0xF6E1E9, dark: 0x382830)
    static let code = dynamic(light: 0xF8EEF2, dark: 0x140F11)
    static let codeHeader = dynamic(light: 0xEFE1E7, dark: 0x221A1E)

    // the width of the conversation column, about 70 characters of text
    static let columnWidth: CGFloat = 720

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
