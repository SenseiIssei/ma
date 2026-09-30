import SwiftUI

// MARK: - Background

/// A night sky: deep navy fading up into violet, a soft moon glow in the
/// top corner and a scatter of faint stars. In light mode only the glow
/// stays. `WashiBackground` is the old name and stays as an alias.
struct AppBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Zen.sky, Zen.paper], startPoint: .top, endPoint: .center)
            RadialGradient(
                colors: [Zen.shu.opacity(scheme == .dark ? 0.22 : 0.10), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 380
            )
            .frame(height: 460)
            if scheme == .dark {
                StarField()
                    .frame(height: 420)
                    .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .bottom))
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

/// Faint, fixed stars. Seeded, so they never jump between redraws.
struct StarField: View {
    var count = 70

    var body: some View {
        Canvas { ctx, size in
            var rng = SeededRandom(seed: 42)
            for _ in 0..<count {
                let x = CGFloat(rng.next()) * size.width
                let y = CGFloat(rng.next()) * size.height
                let r = CGFloat(0.4 + rng.next() * 1.1)
                let alpha = 0.18 + rng.next() * 0.5
                ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(Color.white.opacity(alpha)))
            }
        }
        .drawingGroup()
    }
}

typealias WashiBackground = AppBackground

/// Deterministic randomness, so drawings look the same on every redraw.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }

    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
}

// MARK: - Cards

struct ZenCardModifier: ViewModifier {
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Zen.card, in: RoundedRectangle(cornerRadius: Zen.radius, style: .continuous))
            .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 4)
            .overlay(
                RoundedRectangle(cornerRadius: Zen.radius, style: .continuous)
                    .strokeBorder(Zen.line.opacity(0.6), lineWidth: 0.5)
            )
    }
}

extension View {
    /// The standard card: white surface, soft shadow, large corner radius.
    func zenCard(padding: CGFloat = 18) -> some View {
        modifier(ZenCardModifier(padding: padding))
    }

    func card(padding: CGFloat = 18) -> some View {
        modifier(ZenCardModifier(padding: padding))
    }
}

// MARK: - Headings

/// Small section heading with an SF Symbol.
struct SectionHeader<Trailing: View>: View {
    let icon: String?
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    init(icon: String? = nil, title: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.icon = icon
        self.title = title
        self.trailing = trailing
    }

    /// Old signature. The kanji is ignored; the heading is plain now.
    init(kanji: String, title: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.init(icon: nil, title: title, trailing: trailing)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .scaledFont(size: 13, weight: .semibold)
                    .foregroundStyle(Zen.shu)
                    .accessibilityHidden(true)
            }
            Text(title)
                .scaledFont(size: 20, weight: .bold, design: .rounded)
                .foregroundStyle(Zen.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 2)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(icon: String? = nil, title: String) {
        self.init(icon: icon, title: title) { EmptyView() }
    }

    init(kanji: String, title: String) {
        self.init(icon: nil, title: title) { EmptyView() }
    }
}

// MARK: - Icons

/// Rounded square with an SF Symbol, the app's replacement for seals.
struct IconBadge: View {
    let systemName: String
    var tint: Color = Zen.shu
    var size: CGFloat = 44
    var filled = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(filled ? Color.white : tint)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .fill(filled ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.13)))
            )
            // Always sits next to a text that says the same. Icon-only
            // buttons built from it carry their own label.
            .accessibilityHidden(true)
    }
}

/// Old seal. Renders the first character in a tinted rounded square, used
/// only where a deck's own symbol is content (e.g. a Japanese deck).
struct Hanko: View {
    let text: String
    var size: CGFloat = 44
    var color: Color = Zen.shu

    var body: some View {
        Text(text)
            .font(.system(size: size * 0.46, weight: .semibold, design: .rounded))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .fill(color.opacity(0.13))
            )
            // The deck title next to it is what VoiceOver should read.
            .accessibilityHidden(true)
    }
}

// MARK: - Illustrations

/// A generated illustration from the asset catalog, clipped to a card.
struct Illustration: View {
    let name: String
    var height: CGFloat = 200
    var corner: CGFloat = Zen.radius

    var body: some View {
        Image(name)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - Buttons

struct InkButtonStyle: ButtonStyle {
    enum Kind { case ink, shu, quiet, matcha, negative }
    var kind: Kind = .ink
    var fullWidth = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaledFont(size: 17, weight: .semibold, design: .rounded)
            .foregroundStyle(foreground)
            .padding(.vertical, 16)
            .padding(.horizontal, 22)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(kind == .quiet ? Zen.line : .clear, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .ink: Zen.paper
        case .shu, .matcha, .negative: Color.white
        case .quiet: Zen.ink
        }
    }

    private var background: AnyShapeStyle {
        switch kind {
        case .ink: AnyShapeStyle(Zen.ink)
        case .shu: AnyShapeStyle(Zen.accentGradient)
        case .matcha: AnyShapeStyle(Zen.matcha)
        case .negative: AnyShapeStyle(Zen.negative)
        case .quiet: AnyShapeStyle(Zen.card)
        }
    }
}

extension ButtonStyle where Self == InkButtonStyle {
    static var ink: InkButtonStyle { InkButtonStyle(kind: .ink) }
    /// Primary action in the accent gradient.
    static var shu: InkButtonStyle { InkButtonStyle(kind: .shu) }
    static var primary: InkButtonStyle { InkButtonStyle(kind: .shu) }
    static var quiet: InkButtonStyle { InkButtonStyle(kind: .quiet) }
    static var matcha: InkButtonStyle { InkButtonStyle(kind: .matcha) }
    static var destructive: InkButtonStyle { InkButtonStyle(kind: .negative) }
}

/// Small pill used for choices like minutes or weekdays.
struct Chip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Text(title)
                .scaledFont(size: 15, weight: .semibold, design: .rounded)
                .foregroundStyle(selected ? Color.white : Zen.ink)
                .padding(.vertical, 9)
                .padding(.horizontal, 15)
                .background(selected ? AnyShapeStyle(Zen.shu) : AnyShapeStyle(Zen.sand), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Progress

extension View {
    /// Reads a ring, bar or timer as one element, e.g. "Focus, 12 of 25 minutes".
    func accessibilityMeter(_ label: String, value: String) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(value)
    }
}

/// Dense, fixed-size content like ring centres and timers stops growing here,
/// so big numbers stay inside their circle.
let denseTypeLimit: DynamicTypeSize = .accessibility3

/// A spoken name for an SF Symbol in pickers where the symbol is the whole
/// choice: "figure.walk" becomes "figure walk". Plain, but better than silence.
func spokenSymbolName(_ symbol: String) -> String {
    let words: [Substring] = symbol.split(separator: ".").filter { $0 != "fill" }
    return words.joined(separator: " ")
}

/// Words for VoiceOver where the screen shows a clock like "12:34", which
/// would otherwise be read as a time of day.
enum Spoken {
    static func duration(_ seconds: TimeInterval) -> String {
        let total: Int = max(0, Int(seconds.rounded(.up)))
        let hours: Int = total / 3600
        let minutes: Int = (total % 3600) / 60
        let secs: Int = total % 60
        var parts: [String] = []
        if hours > 0 {
            parts.append(hours == 1 ? tr("1 hour", "1 Stunde") : tr("\(hours) hours", "\(hours) Stunden"))
        }
        if minutes > 0 {
            parts.append(minutes == 1 ? tr("1 minute", "1 Minute") : tr("\(minutes) minutes", "\(minutes) Minuten"))
        }
        if secs > 0 && hours == 0 {
            parts.append(secs == 1 ? tr("1 second", "1 Sekunde") : tr("\(secs) seconds", "\(secs) Sekunden"))
        }
        if parts.isEmpty { return tr("0 seconds", "0 Sekunden") }
        return parts.joined(separator: " ")
    }
}

struct InkProgress: View {
    var value: Double
    var color: Color = Zen.shu
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Zen.sand)
                Capsule()
                    .fill(color)
                    .frame(width: max(height, geo.size.width * min(1, max(0, value))))
            }
        }
        .frame(height: height)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: value)
    }
}

/// Clean circular progress with a rounded cap.
struct ProgressRing: View, Animatable {
    var progress: Double
    var lineWidth: CGFloat = 14
    var tint: Color = Zen.shu
    var track: Color = Zen.sand

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
    }
}

/// A number with an icon and a label, used in stat rows.
struct StatTile: View {
    let icon: String
    let value: String
    let label: String
    var tint: Color = Zen.shu

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .scaledFont(size: 14, weight: .semibold)
                .foregroundStyle(tint)
            Text(value)
                .displayFont(26)
                .monospacedDigit()
                .foregroundStyle(Zen.ink)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .scaledFont(size: 12, weight: .medium)
                .foregroundStyle(Zen.inkSoft)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // One element: "Resisted, 7" instead of three stops.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

/// Old stat signature; maps onto StatTile with a neutral icon.
struct StatStone: View {
    let kanji: String
    let value: String
    let label: String

    var body: some View {
        StatTile(icon: "circle.fill", value: value, label: label)
    }
}
