import SwiftUI

// MARK: - Mood face

extension Mood {
    var tint: Color {
        switch self {
        case .low: Zen.negative
        case .meh: Zen.kin
        case .okay: Zen.ai
        case .good: Zen.shu
        case .great: Zen.matcha
        }
    }
}

/// A face drawn from two dots and a curve. Drawn rather than an emoji so it
/// matches the rest of the app in both colour schemes.
struct MoodFace: View {
    let mood: Mood
    var size: CGFloat = 44
    var selected = true

    var body: some View {
        let tint: Color = selected ? mood.tint : Zen.inkFaint
        let line: CGFloat = max(1.5, size * 0.07)
        ZStack {
            Circle().fill(tint.opacity(selected ? 0.16 : 0.10))
            MoodEyes().fill(tint)
            MoodMouth(curve: mood.curve)
                .stroke(tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(mood.title)
    }
}

private struct MoodEyes: Shape {
    func path(in rect: CGRect) -> Path {
        let r: CGFloat = rect.width * 0.055
        let y: CGFloat = rect.height * 0.40
        var path = Path()
        for x in [rect.width * 0.36, rect.width * 0.64] {
            path.addEllipse(in: CGRect(x: rect.minX + x - r, y: rect.minY + y - r, width: r * 2, height: r * 2))
        }
        return path
    }
}

private struct MoodMouth: Shape {
    var curve: Double

    var animatableData: Double {
        get { curve }
        set { curve = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let bend = CGFloat(curve)
        // A frown sits a little lower so the face does not look surprised.
        let y: CGFloat = rect.minY + rect.height * (0.64 - bend * 0.04)
        let left = CGPoint(x: rect.minX + rect.width * 0.32, y: y)
        let right = CGPoint(x: rect.minX + rect.width * 0.68, y: y)
        let control = CGPoint(x: rect.midX, y: y + bend * rect.height * 0.18)
        var path = Path()
        path.move(to: left)
        path.addQuadCurve(to: right, control: control)
        return path
    }
}

struct MoodPicker: View {
    @Binding var mood: Mood?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Mood.allCases) { option in
                let isOn: Bool = mood == option
                Button {
                    Haptics.tap()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { mood = option }
                } label: {
                    VStack(spacing: 8) {
                        MoodFace(mood: option, size: 50, selected: mood == nil || isOn)
                            .scaleEffect(isOn ? 1.12 : 1)
                            .accessibilityHidden(true)
                        Text(option.title)
                            .scaledFont(size: 12, weight: isOn ? .semibold : .medium)
                            .foregroundStyle(isOn ? Zen.ink : Zen.inkSoft)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        // Five faces in one row: past this size the names would not fit.
        .dynamicTypeSize(...denseTypeLimit)
    }
}

// MARK: - Morning

struct MorningCheckInView: View {
    @Environment(DayStore.self) private var day
    @Environment(\.dismiss) private var dismiss
    @State private var mood: Mood?
    @State private var intention = ""
    @FocusState private var typing: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Illustration(name: "IllustrationMorning", height: 150)

                    VStack(alignment: .leading, spacing: 16) {
                        Text(tr("How do you feel?", "Wie fühlst du dich?"))
                            .displayFont(24)
                            .foregroundStyle(Zen.ink)
                        MoodPicker(mood: $mood)
                    }
                    .zenCard(padding: 20)

                    VStack(alignment: .leading, spacing: 12) {
                        Text(tr("One intention for today", "Ein Vorsatz für heute"))
                            .displayFont(24)
                            .foregroundStyle(Zen.ink)
                        Text(tr("Small and concrete works best.", "Klein und konkret klappt am besten."))
                            .scaledFont(size: 15)
                            .foregroundStyle(Zen.inkSoft)
                        TextField(tr("e.g. Take a walk at lunch", "z. B. Mittags eine Runde gehen"), text: $intention, axis: .vertical)
                            .lineLimit(1...3)
                            .scaledFont(size: 17)
                            .focused($typing)
                            .submitLabel(.done)
                            .padding(14)
                            .background(Zen.sand, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .onChange(of: intention) { _, text in
                                if text.contains("\n") {
                                    intention = text.replacingOccurrences(of: "\n", with: "")
                                    typing = false
                                }
                            }
                    }
                    .zenCard(padding: 20)

                    Button(tr("Start the day", "Tag beginnen")) {
                        guard let mood else { return }
                        day.saveMorning(mood: mood, intention: intention)
                        Haptics.success()
                        dismiss()
                    }
                    .buttonStyle(.primary)
                    .disabled(mood == nil)
                    .opacity(mood == nil ? 0.5 : 1)
                }
                .padding(.horizontal, Zen.gutter)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppBackground())
            .navigationTitle(tr("Morning", "Morgen"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Close", "Schließen")) { dismiss() }
                }
            }
            .onAppear {
                mood = day.today.morning?.mood
                intention = day.today.morning?.intention ?? ""
            }
        }
    }
}

// MARK: - Evening

struct EveningReflectionView: View {
    @Environment(DayStore.self) private var day
    @Environment(\.dismiss) private var dismiss
    @State private var wentWell = ""
    @State private var learned = ""
    @State private var letGo = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Illustration(name: "IllustrationEvening", height: 150)

                    if let intention = day.intention {
                        HStack(alignment: .top, spacing: 12) {
                            IconBadge(systemName: "scope", tint: Zen.shu, size: 36)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(tr("This morning you set out to", "Heute Morgen hattest du vor"))
                                    .scaledFont(size: 13, weight: .medium)
                                    .foregroundStyle(Zen.inkSoft)
                                Text(intention)
                                    .scaledFont(size: 17, weight: .semibold)
                                    .foregroundStyle(Zen.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .zenCard()
                    }

                    prompt(icon: "sparkles", tint: Zen.matcha,
                           title: tr("What went well?", "Was lief gut?"),
                           placeholder: tr("Even something small", "Auch etwas Kleines"),
                           text: $wentWell)
                    prompt(icon: "lightbulb", tint: Zen.kin,
                           title: tr("What did you learn?", "Was hast du gelernt?"),
                           placeholder: tr("About the world or yourself", "Über die Welt oder dich"),
                           text: $learned)
                    prompt(icon: "wind", tint: Zen.ai,
                           title: tr("What will you let go?", "Was lässt du los?"),
                           placeholder: tr("It can stay in today", "Es darf im Heute bleiben"),
                           text: $letGo)

                    Button(tr("Close the day", "Tag abschließen")) {
                        let reflection = EveningReflection(wentWell: wentWell, learned: learned, letGo: letGo)
                        day.saveEvening(reflection)
                        Haptics.success()
                        dismiss()
                    }
                    .buttonStyle(.primary)
                }
                .padding(.horizontal, Zen.gutter)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppBackground())
            .navigationTitle(tr("Evening", "Abend"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Close", "Schließen")) { dismiss() }
                }
            }
            .onAppear {
                let saved = day.today.evening
                wentWell = saved?.wentWell ?? ""
                learned = saved?.learned ?? ""
                letGo = saved?.letGo ?? ""
            }
        }
    }

    private func prompt(icon: String, tint: Color, title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                IconBadge(systemName: icon, tint: tint, size: 32)
                Text(title)
                    .displayFont(19, weight: .semibold)
                    .foregroundStyle(Zen.ink)
            }
            TextField(placeholder, text: text, axis: .vertical)
                .lineLimit(2...5)
                .scaledFont(size: 16)
                .padding(14)
                .background(Zen.sand, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .zenCard()
    }
}
