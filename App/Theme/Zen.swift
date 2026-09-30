import SwiftUI
import UIKit

/// Design tokens. The dark side is the heart of it: a calm night, deep
/// navy and violet, moonlit lavender as the accent. The app runs dark by
/// default; the light side stays for people who choose "System".
/// The names are kept from the first design so every view keeps compiling:
/// `paper` is the background, `ink` the text, `shu` the accent.
enum Zen {
    // Surfaces
    static let paper = Color(light: 0xF6F5F3, dark: 0x0A0E22)
    static let card = Color(light: 0xFFFFFF, dark: 0x141A36)
    static let sand = Color(light: 0xEFEDE9, dark: 0x1C2347)

    // Text
    static let ink = Color(light: 0x16171B, dark: 0xEEF0FF)
    static let inkSoft = Color(light: 0x6B6D75, dark: 0xA9AED3)
    static let inkFaint = Color(light: 0xA7A9B0, dark: 0x656C98)

    // Colour
    /// Primary accent: indigo by day, moonlit lavender by night.
    static let shu = Color(light: 0x5B5FEF, dark: 0xA3A1FF)
    static let accent = shu
    /// Success, "right", focus done.
    static let matcha = Color(light: 0x22A06B, dark: 0x62E3B0)
    /// Errors, "wrong", destructive.
    static let negative = Color(light: 0xE5484D, dark: 0xFF7F8A)
    /// Streaks and warmth, like a lamp in the window.
    static let kin = Color(light: 0xF08C2E, dark: 0xFFC477)
    /// Secondary tint for learning.
    static let ai = Color(light: 0x0EA5B7, dark: 0x7BD8FF)
    static let stone = Color(light: 0x8A8C94, dark: 0x7A80A8)
    static let line = Color(light: 0xE6E4E0, dark: 0x252D58)
    /// The night sky at the top of the background.
    static let sky = Color(light: 0xE9E8FF, dark: 0x1B1F4A)

    static let accentGradient = LinearGradient(
        colors: [Color(light: 0x6D6AF6, dark: 0xB7A6FF), Color(light: 0x4D8DF7, dark: 0x7FA6FF)],
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

// MARK: - Dynamic Type

extension Font.TextStyle {
    /// The text style a fixed design size grows with. Picked by size so a
    /// caption grows like a caption and a big number like a title.
    static func matching(_ size: CGFloat) -> Font.TextStyle {
        if size <= 12 { return .caption }
        if size <= 13 { return .footnote }
        if size <= 15 { return .subheadline }
        if size <= 17 { return .body }
        if size <= 20 { return .title3 }
        if size <= 28 { return .title2 }
        return .largeTitle
    }

    var uiKit: UIFont.TextStyle {
        switch self {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .callout: return .callout
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        default: return .body
        }
    }
}

/// A system font that scales with Dynamic Type. `@ScaledMetric` reads the
/// environment, so the size follows a text size change while the app runs.
struct ScaledFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design

    init(size: CGFloat, weight: Font.Weight, design: Font.Design) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: Font.TextStyle.matching(size))
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}

extension View {
    /// Like `.font(.system(size:weight:design:))`, but grows with the text size.
    func scaledFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(ScaledFont(size: size, weight: weight, design: design))
    }

    /// Scaling form of `Font.display`.
    func displayFont(_ size: CGFloat, weight: Font.Weight = .bold) -> some View {
        modifier(ScaledFont(size: size, weight: weight, design: .rounded))
    }

    /// Scaling form of `Font.mincho`.
    func minchoFont(_ size: CGFloat, weight: Font.Weight = .regular) -> some View {
        let resolved: Font.Weight = weight == .regular ? .semibold : weight
        return modifier(ScaledFont(size: size, weight: resolved, design: .rounded))
    }

    /// Scaling form of `Font.kanji`.
    func kanjiFont(_ size: CGFloat, bold: Bool = false) -> some View {
        modifier(ScaledFont(size: size, weight: bold ? .semibold : .regular, design: .default))
    }
}

extension Font {
    /// The size scaled for the current text size. Read once when the view
    /// is built; prefer the `.scaledFont` family where a view allows it.
    static func scaledSize(_ size: CGFloat) -> CGFloat {
        let style: UIFont.TextStyle = Font.TextStyle.matching(size).uiKit
        return UIFontMetrics(forTextStyle: style).scaledValue(for: size)
    }

    /// Headlines and big numbers: SF Pro Rounded, bold and friendly.
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: scaledSize(size), weight: weight, design: .rounded)
    }

    /// Kept for older call sites; now the same as `display`.
    static func mincho(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: scaledSize(size), weight: weight == .regular ? .semibold : weight, design: .rounded)
    }

    /// Japanese learning content (kana, kanji in cards). Only for content,
    /// never for decoration.
    static func kanji(_ size: CGFloat, bold: Bool = false) -> Font {
        .system(size: scaledSize(size), weight: bold ? .semibold : .regular)
    }
}

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}
