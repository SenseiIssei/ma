import SwiftUI

/// The night side of Zen (App/Theme/Zen.swift), as plain literals: the watch
/// is always dark, so there is no light variant to switch between.
enum Night {
    // Surfaces
    static let paper = Color(hex: 0x0A0E22)
    static let card = Color(hex: 0x141A36)
    static let sand = Color(hex: 0x1C2347)
    static let sky = Color(hex: 0x1B1F4A)
    static let line = Color(hex: 0x252D58)

    // Text
    static let ink = Color(hex: 0xEEF0FF)
    static let inkSoft = Color(hex: 0xA9AED3)
    static let inkFaint = Color(hex: 0x656C98)

    // Colour, same roles as in the app
    /// Moonlit lavender, the accent and the focus ring.
    static let shu = Color(hex: 0xA3A1FF)
    /// Right answers, breathing, done.
    static let matcha = Color(hex: 0x62E3B0)
    /// Ending something early.
    static let negative = Color(hex: 0xFF7F8A)
    /// Streaks.
    static let kin = Color(hex: 0xFFC477)
    /// Learning.
    static let ai = Color(hex: 0x7BD8FF)

    static let accentGradient = LinearGradient(
        colors: [Color(hex: 0xB7A6FF), Color(hex: 0x7FA6FF)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// The sky fading into the night, behind every screen.
    static let background = LinearGradient(
        colors: [sky, paper],
        startPoint: .top, endPoint: .bottom
    )
}

extension Color {
    init(hex: UInt32) {
        let red: Double = Double((hex >> 16) & 0xFF) / 255
        let green: Double = Double((hex >> 8) & 0xFF) / 255
        let blue: Double = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}

/// A big, calm button: a tinted card with an icon and a line of text.
struct NightButtonStyle: ButtonStyle {
    var tint: Color = Night.shu
    var filled = false

    func makeBody(configuration: Configuration) -> some View {
        let fill: Color = filled ? tint : Night.card
        let text: Color = filled ? Night.paper : Night.ink
        return configuration.label
            .font(.system(.headline, design: .rounded))
            .foregroundStyle(text)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 10)
            .background(fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(tint.opacity(filled ? 0 : 0.35), lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

/// One ring of the day, like ProgressRing in the app.
struct NightRing: View {
    var progress: Double
    var tint: Color
    var lineWidth: CGFloat = 9

    var body: some View {
        let shown: Double = min(1, max(0, progress))
        ZStack {
            Circle()
                .stroke(tint.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
    }
}
