import SwiftUI
import UIKit

/// A copy of the app's night tokens. The report runs in its own process and
/// cannot see App/Theme, so the values are repeated here. Keep them in step
/// with Zen.swift.
enum ReportTheme {
    static let card = Color(reportLight: 0xFFFFFF, dark: 0x141A36)
    static let sand = Color(reportLight: 0xEFEDE9, dark: 0x1C2347)
    static let ink = Color(reportLight: 0x16171B, dark: 0xEEF0FF)
    static let inkSoft = Color(reportLight: 0x6B6D75, dark: 0xA9AED3)
    static let inkFaint = Color(reportLight: 0xA7A9B0, dark: 0x656C98)
    static let shu = Color(reportLight: 0x5B5FEF, dark: 0xA3A1FF)
    static let ai = Color(reportLight: 0x0EA5B7, dark: 0x7BD8FF)
    static let kin = Color(reportLight: 0xF08C2E, dark: 0xFFC477)
    static let line = Color(reportLight: 0xE6E4E0, dark: 0x252D58)

    static let accentGradient = LinearGradient(
        colors: [Color(reportLight: 0x6D6AF6, dark: 0xB7A6FF), Color(reportLight: 0x4D8DF7, dark: 0x7FA6FF)],
        startPoint: .top, endPoint: .bottom
    )

    static let radius: CGFloat = 24

    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension Color {
    /// Resolved per trait, so the report follows the app's night or day look.
    /// Named apart from the app's `init(light:dark:)` to make the copy obvious.
    init(reportLight light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex: UInt32 = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

extension View {
    /// The app's card: surface colour, large continuous corners, hairline edge.
    func reportCard(padding: CGFloat = 18) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ReportTheme.card, in: RoundedRectangle(cornerRadius: ReportTheme.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ReportTheme.radius, style: .continuous)
                    .strokeBorder(ReportTheme.line.opacity(0.6), lineWidth: 0.5)
            )
    }
}

/// Durations and weekday names in both languages.
enum ReportFormat {
    /// "3 h 20 min" or "3 Std. 20 Min.", minutes only below an hour.
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return tr("\(rest) min", "\(rest) Min.") }
        if rest == 0 { return tr("\(hours) h", "\(hours) Std.") }
        return tr("\(hours) h \(rest) min", "\(hours) Std. \(rest) Min.")
    }

    /// Short form above the bars. Whole hours only: a decimal point would
    /// differ per language and crowd a narrow column.
    static func short(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return tr("\(minutes)m", "\(minutes) Min") }
        let hours = Int((Double(minutes) / 60).rounded())
        return tr("\(hours)h", "\(hours) Std")
    }

    /// Two-letter weekday, the same letters the app uses on Today.
    static func weekday(_ date: Date, calendar: Calendar = .current) -> String {
        let en = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
        let de = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]
        let index = (calendar.component(.weekday, from: date) - 1 + 7) % 7
        return Loc.isGerman ? de[index] : en[index]
    }
}
