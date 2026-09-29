import SwiftUI
import WidgetKit

/// The night palette from App/Theme/Zen.swift, dark side only. The widget
/// target cannot see App/, and Ma's widgets always wear the night look, the
/// same way the app does by default.
enum Night {
    static let paper = Color(rgb: 0x0A0E22)
    static let card = Color(rgb: 0x141A36)
    static let sky = Color(rgb: 0x1B1F4A)
    static let line = Color(rgb: 0x252D58)

    static let ink = Color(rgb: 0xEEF0FF)
    static let inkSoft = Color(rgb: 0xA9AED3)
    static let inkFaint = Color(rgb: 0x656C98)

    /// Focus: moonlit lavender, Zen.shu at night.
    static let shu = Color(rgb: 0xA3A1FF)
    /// Learning: Zen.ai at night.
    static let ai = Color(rgb: 0x7BD8FF)
    /// Resisted impulses and breaks: Zen.matcha at night.
    static let matcha = Color(rgb: 0x62E3B0)

    /// The app's background: night sky at the top, deep navy below.
    static var background: LinearGradient {
        LinearGradient(colors: [sky, paper], startPoint: .top, endPoint: .bottom)
    }

    /// Focus rounds glow lavender, breaks green, like in the app.
    static func tint(isBreak: Bool) -> Color {
        isBreak ? matcha : shu
    }

    static func symbol(isBreak: Bool) -> String {
        isBreak ? "cup.and.saucer.fill" : "timer"
    }
}

extension Color {
    /// Named rgb, not hex, so it never collides with Zen's Color(light:dark:)
    /// should a file ever end up in both targets.
    init(rgb: UInt32) {
        let red: Double = Double((rgb >> 16) & 0xFF) / 255
        let green: Double = Double((rgb >> 8) & 0xFF) / 255
        let blue: Double = Double(rgb & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}

/// Deep links the app already understands in AppModel.handle(url:).
enum MaLink: String {
    case today, focus, learn

    var url: URL {
        // The literal is always valid; the fallback only keeps the type non-optional.
        URL(string: "ma://\(rawValue)") ?? URL(fileURLWithPath: "/")
    }
}

/// A single progress ring, the widget cousin of the app's ProgressRing.
struct WidgetRing: View {
    let progress: Double
    let tint: Color
    let lineWidth: CGFloat

    var body: some View {
        let clamped: Double = min(1, max(0, progress))
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        ZStack {
            Circle()
                .stroke(tint.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(tint, style: style)
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
        }
        .padding(lineWidth / 2)
    }
}

/// Focus outside, learning in the middle, resisted impulses inside: the same
/// order as the rings on the Today screen.
struct TripleRings: View {
    let snapshot: MaSnapshot
    let size: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        let step: CGFloat = lineWidth * 2 + 4
        ZStack {
            WidgetRing(progress: snapshot.focusProgress, tint: Night.shu, lineWidth: lineWidth)
                .frame(width: size, height: size)
            WidgetRing(progress: snapshot.learnProgress, tint: Night.ai, lineWidth: lineWidth)
                .frame(width: size - step, height: size - step)
            WidgetRing(progress: snapshot.resistProgress, tint: Night.matcha, lineWidth: lineWidth)
                .frame(width: size - step * 2, height: size - step * 2)
        }
        .accessibilityHidden(true)
    }
}

/// One dot per round of the set: done rounds full, the running one bright,
/// the rest faint.
struct RoundDots: View {
    let round: Int
    let totalRounds: Int
    let isBreak: Bool
    var size: CGFloat = 7

    var body: some View {
        // A round can outrun the setting if it was lowered mid-set.
        let total: Int = max(1, max(totalRounds, round))
        HStack(spacing: size * 0.7) {
            ForEach(1...total, id: \.self) { index in
                Circle()
                    .fill(color(for: index))
                    .frame(width: size, height: size)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(tr("Round \(round) of \(total)", "Runde \(round) von \(total)")))
    }

    private func color(for index: Int) -> Color {
        let done: Bool = isBreak ? index <= round : index < round
        if done { return Night.shu }
        if !isBreak && index == round { return Night.shu.opacity(0.55) }
        return Night.inkFaint.opacity(0.45)
    }
}

extension View {
    /// Night gradient on the Home Screen. Lock Screen families get a clear
    /// background, the system draws its own material there.
    @ViewBuilder
    func nightBackground(for family: WidgetFamily) -> some View {
        switch family {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline:
            containerBackground(for: .widget) { Color.clear }
        default:
            containerBackground(for: .widget) { Night.background }
        }
    }
}
