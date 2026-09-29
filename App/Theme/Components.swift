import SwiftUI

// MARK: - Paper

/// Faint fibres over the paper colour, drawn once and cached as a bitmap.
struct WashiBackground: View {
    var body: some View {
        ZStack {
            Zen.paper
            Canvas { ctx, size in
                var rng = SeededRandom(seed: 7)
                let count = Int(size.width * size.height / 900)
                for _ in 0..<count {
                    let x = rng.next() * size.width
                    let y = rng.next() * size.height
                    let length = 4 + rng.next() * 14
                    let angle = rng.next() * .pi
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: x + cos(angle) * length, y: y + sin(angle) * length))
                    ctx.stroke(path, with: .color(Zen.inkFaint.opacity(0.07 + rng.next() * 0.06)), lineWidth: 0.6)
                }
            }
            .drawingGroup()
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

/// Deterministic randomness, so textures and gardens look the same on
/// every redraw instead of shimmering.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }

    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
}

// MARK: - Cards and headings

struct ZenCardModifier: ViewModifier {
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Zen.card, in: RoundedRectangle(cornerRadius: Zen.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Zen.radius, style: .continuous)
                    .strokeBorder(Zen.line, lineWidth: 0.8)
            )
    }
}

extension View {
    func zenCard(padding: CGFloat = 18) -> some View {
        modifier(ZenCardModifier(padding: padding))
    }
}

struct SectionHeader<Trailing: View>: View {
    let kanji: String
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(kanji)
                .font(.kanji(15, bold: true))
                .foregroundStyle(Zen.shu)
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(Zen.inkSoft)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 4)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(kanji: String, title: String) {
        self.init(kanji: kanji, title: title) { EmptyView() }
    }
}

// MARK: - Seal

/// The red hanko stamp. Slightly rotated, slightly uneven, like a real one.
struct Hanko: View {
    let text: String
    var size: CGFloat = 44
    var color: Color = Zen.shu

    var body: some View {
        Text(text)
            .font(.kanji(size * 0.52, bold: true))
            .foregroundStyle(Zen.paper)
            .frame(width: size, height: size)
            .background(color, in: RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.16, style: .continuous)
                    .strokeBorder(Zen.paper.opacity(0.55), lineWidth: 1)
                    .padding(size * 0.08)
            )
            .rotationEffect(.degrees(-3))
    }
}

// MARK: - Buttons

struct InkButtonStyle: ButtonStyle {
    enum Kind { case ink, shu, quiet, matcha }
    var kind: Kind = .ink
    var fullWidth = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.vertical, 15)
            .padding(.horizontal, 22)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(background, in: Capsule())
            .overlay(Capsule().strokeBorder(kind == .quiet ? Zen.line : .clear, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .ink: Zen.paper
        case .shu, .matcha: Color.white
        case .quiet: Zen.ink
        }
    }

    private var background: Color {
        switch kind {
        case .ink: Zen.ink
        case .shu: Zen.shu
        case .matcha: Zen.matcha
        case .quiet: Zen.card
        }
    }
}

extension ButtonStyle where Self == InkButtonStyle {
    static var ink: InkButtonStyle { InkButtonStyle(kind: .ink) }
    static var shu: InkButtonStyle { InkButtonStyle(kind: .shu) }
    static var quiet: InkButtonStyle { InkButtonStyle(kind: .quiet) }
    static var matcha: InkButtonStyle { InkButtonStyle(kind: .matcha) }
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
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(selected ? Zen.paper : Zen.ink)
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .background(selected ? Zen.ink : Zen.card, in: Capsule())
                .overlay(Capsule().strokeBorder(selected ? .clear : Zen.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Progress

struct InkProgress: View {
    var value: Double
    var color: Color = Zen.ink
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Zen.line)
                Capsule()
                    .fill(color)
                    .frame(width: max(height, geo.size.width * min(1, max(0, value))))
            }
        }
        .frame(height: height)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: value)
    }
}

/// A big number with a kanji label, used in the stat rows.
struct StatStone: View {
    let kanji: String
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(kanji)
                .font(.kanji(13, bold: true))
                .foregroundStyle(Zen.shu)
            Text(value)
                .font(.mincho(28, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Zen.ink)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Zen.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
