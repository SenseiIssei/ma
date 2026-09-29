import SwiftUI
import UIKit

/// Washi paper, sumi ink, one vermilion seal. Everything else is space.
enum Zen {
    static let paper = Color(light: 0xF4EFE6, dark: 0x151412)
    static let card = Color(light: 0xFBF8F2, dark: 0x1E1C19)
    static let sand = Color(light: 0xE9E1D1, dark: 0x25221E)
    static let ink = Color(light: 0x1F1D1B, dark: 0xECE6DA)
    static let inkSoft = Color(light: 0x6B645C, dark: 0xA69E92)
    static let inkFaint = Color(light: 0xA9A196, dark: 0x6A645B)
    static let shu = Color(light: 0xC8412C, dark: 0xD9573F)
    static let matcha = Color(light: 0x66784A, dark: 0x9DB07A)
    static let ai = Color(light: 0x2E3A55, dark: 0x8E9CC0)
    static let kin = Color(light: 0xAE8537, dark: 0xD1AE63)
    static let stone = Color(light: 0x5A554F, dark: 0x8C857B)
    static let line = Color(light: 0xD9D0C0, dark: 0x302C27)

    static let radius: CGFloat = 22
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
    /// Serif for headings: New York, the closest thing iOS has to a brush.
    static func mincho(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// Kanji look best in Hiragino Mincho, which every iPhone ships with.
    static func kanji(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? "HiraMinProN-W6" : "HiraMinProN-W3", size: size)
    }
}

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}
