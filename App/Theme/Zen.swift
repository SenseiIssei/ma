import SwiftUI
import UIKit

/// Design tokens. Calm, modern, one accent. The names are kept from the
/// first design so every view keeps compiling while it is restyled:
/// `paper` is the background, `ink` the text, `shu` the accent.
enum Zen {
    // Surfaces
    static let paper = Color(light: 0xF6F5F3, dark: 0x0E0F12)
    static let card = Color(light: 0xFFFFFF, dark: 0x191A1F)
    static let sand = Color(light: 0xEFEDE9, dark: 0x23252B)

    // Text
    static let ink = Color(light: 0x16171B, dark: 0xF3F3F5)
    static let inkSoft = Color(light: 0x6B6D75, dark: 0xA3A5AE)
    static let inkFaint = Color(light: 0xA7A9B0, dark: 0x6A6C75)

    // Colour
    /// Primary accent: a calm indigo.
    static let shu = Color(light: 0x5B5FEF, dark: 0x8286FF)
    static let accent = shu
    /// Success, "right", focus done.
    static let matcha = Color(light: 0x22A06B, dark: 0x3DD68C)
    /// Errors, "wrong", destructive.
    static let negative = Color(light: 0xE5484D, dark: 0xFF6369)
    /// Streaks and warmth.
    static let kin = Color(light: 0xF08C2E, dark: 0xFFA94D)
    /// Secondary tint for learning.
    static let ai = Color(light: 0x0EA5B7, dark: 0x3CCFE0)
    static let stone = Color(light: 0x8A8C94, dark: 0x8A8C94)
    static let line = Color(light: 0xE6E4E0, dark: 0x2A2C33)

    static let accentGradient = LinearGradient(
        colors: [Color(light: 0x6D6AF6, dark: 0x8C89FF), Color(light: 0x4D8DF7, dark: 0x6AA6FF)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static let radius: CGFloat = 24
    static let gutter: CGFloat = 20
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Font {
    /// Headlines and big numbers: SF Pro Rounded, bold and friendly.
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// Kept for older call sites; now the same as `display`.
    static func mincho(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight == .regular ? .semibold : weight, design: .rounded)
    }

    /// Japanese learning content (kana, kanji in cards). Only for content,
    /// never for decoration.
    static func kanji(_ size: CGFloat, bold: Bool = false) -> Font {
        .system(size: size, weight: bold ? .semibold : .regular)
    }
}

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}
