import SwiftUI

/// Result an exercise reports back when it has been checked.
struct Outcome {
    var correct: Bool
    var typo = false
    var perCard: [String: Bool] = [:]
}

/// Dispatches to the view for each exercise kind. Every view owns its own
/// selection and its own "Prüfen" button, and goes quiet once `locked`.
struct ExerciseView: View {
    let exercise: Exercise
    let locked: Bool
    let onCheck: (Outcome) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Text(exercise.deck.symbol)
                    .font(.kanji(13, bold: true))
                    .foregroundStyle(Zen.shu)
                Text(exercise.instruction)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Zen.inkSoft)
            }
            switch exercise.kind {
            case .choice, .reverse, .cloze:
                ChoiceExercise(exercise: exercise, locked: locked, onCheck: onCheck)
            case .trueFalse:
                TrueFalseExercise(exercise: exercise, locked: locked, onCheck: onCheck)
            case .typeIn:
                TypeExercise(exercise: exercise, locked: locked, onCheck: onCheck)
            case .order:
                OrderExercise(exercise: exercise, locked: locked, onCheck: onCheck)
            case .pairs:
                PairsExercise(exercise: exercise, locked: locked, onCheck: onCheck)
            case .flash:
                FlashExercise(exercise: exercise, locked: locked, onCheck: onCheck)
            }
        }
    }
}

// MARK: - Prompt

struct PromptText: View {
    let text: String

    var body: some View {
        let cjk = ExerciseEngine.containsCJK(text)
        Text(text)
            .font(cjk ? .kanji(text.count <= 4 ? 64 : 30, bold: true) : .mincho(text.count > 60 ? 22 : 28, weight: .semibold))
            .foregroundStyle(Zen.ink)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
    }
}

struct CheckButton: View {
    var title = "Prüfen"
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(title) {
            Haptics.tap()
            action()
        }
        .buttonStyle(.ink)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .padding(.top, 8)
    }
}

// MARK: - Choice, reverse, cloze

struct ChoiceExercise: View {
    let exercise: Exercise
    let locked: Bool
    let onCheck: (Outcome) -> Void
    @State private var picked: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if exercise.kind == .cloze {
                Text(exercise.statement)
                    .font(.system(size: 15))
                    .foregroundStyle(Zen.inkSoft)
            }
            PromptText(text: exercise.prompt)
            VStack(spacing: 10) {
                ForEach(exercise.options, id: \.self) { option in
                    OptionRow(
                        text: option,
                        state: state(for: option)
                    ) {
                        guard !locked else { return }
                        Haptics.tap()
                        picked = option
                    }
                }
            }
            if !locked {
                CheckButton(enabled: picked != nil) {
                    onCheck(Outcome(correct: picked == exercise.solution))
                }
            }
        }
    }

    private func state(for option: String) -> OptionRow.Look {
        if locked {
            if option == exercise.solution { return .right }
            if option == picked { return .wrong }
            return .idle
        }
        return option == picked ? .picked : .idle
    }
}

struct OptionRow: View {
    enum Look { case idle, picked, right, wrong }
    let text: String
    let state: Look
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(text)
                    .font(ExerciseEngine.containsCJK(text) ? .kanji(20, bold: true) : .system(size: 17, weight: .medium))
                    .foregroundStyle(foreground)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                if state == .right {
                    Image(systemName: "checkmark").foregroundStyle(Zen.matcha)
                } else if state == .wrong {
                    Image(systemName: "xmark").foregroundStyle(Zen.shu)
                }
            }
            .padding(.vertical, 15)
            .padding(.horizontal, 18)
            .background(background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(border, lineWidth: state == .idle ? 1 : 2)
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: state)
    }

    private var foreground: Color {
        switch state {
        case .idle, .picked: Zen.ink
        case .right: Zen.matcha
        case .wrong: Zen.shu
        }
    }

    private var background: Color {
        switch state {
        case .picked: Zen.ink.opacity(0.06)
        case .right: Zen.matcha.opacity(0.12)
        case .wrong: Zen.shu.opacity(0.1)
        case .idle: Zen.card
        }
    }

    private var border: Color {
        switch state {
        case .idle: Zen.line
        case .picked: Zen.ink
        case .right: Zen.matcha
        case .wrong: Zen.shu
        }
    }
}

// MARK: - True or false

struct TrueFalseExercise: View {
    let exercise: Exercise
    let locked: Bool
    let onCheck: (Outcome) -> Void
    @State private var said: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PromptText(text: exercise.prompt)
            HStack(spacing: 10) {
                Image(systemName: "arrow.turn.down.right")
                    .foregroundStyle(Zen.inkFaint)
                Text(exercise.statement)
                    .font(ExerciseEngine.containsCJK(exercise.statement) ? .kanji(24, bold: true) : .mincho(22, weight: .medium))
                    .foregroundStyle(Zen.ink)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Zen.sand.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            HStack(spacing: 12) {
                answerButton(true, title: "Stimmt", symbol: "○")
                answerButton(false, title: "Stimmt nicht", symbol: "×")
            }
        }
    }

    private func answerButton(_ value: Bool, title: String, symbol: String) -> some View {
        let isRight = value == exercise.statementIsTrue
        let tint: Color = locked ? (isRight ? Zen.matcha : (said == value ? Zen.shu : Zen.inkFaint)) : Zen.ink
        return Button {
            guard !locked else { return }
            said = value
            Haptics.tap()
            onCheck(Outcome(correct: isRight))
        } label: {
            VStack(spacing: 6) {
                Text(symbol).font(.kanji(34, bold: true))
                Text(title).font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(Zen.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(locked && (isRight || said == value) ? tint : Zen.line, lineWidth: locked ? 2 : 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Typing

struct TypeExercise: View {
    let exercise: Exercise
    let locked: Bool
    let onCheck: (Outcome) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PromptText(text: exercise.prompt)
            TextField("Deine Antwort", text: $text)
                .font(.system(size: 20, weight: .medium))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused)
                .submitLabel(.done)
                .disabled(locked)
                .padding(16)
                .background(Zen.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(focused ? Zen.ink : Zen.line, lineWidth: focused ? 2 : 1))
                .onSubmit(check)
            if !locked {
                CheckButton(enabled: !text.trimmingCharacters(in: .whitespaces).isEmpty, action: check)
            }
        }
        .onAppear { focused = true }
    }

    private func check() {
        guard !locked, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        focused = false
        let verdict = Grader.check(text, against: exercise.card)
        onCheck(Outcome(correct: verdict != .wrong, typo: verdict == .typo))
    }
}

// MARK: - Word order

struct OrderExercise: View {
    let exercise: Exercise
    let locked: Bool
    let onCheck: (Outcome) -> Void
    /// Indices into `exercise.tiles`, so duplicate words stay distinct.
    @State private var placed: [Int] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PromptText(text: exercise.prompt)

            FlowLayout(spacing: 8) {
                ForEach(placed, id: \.self) { index in
                    Tile(text: exercise.tiles[index], style: .placed) {
                        guard !locked else { return }
                        Haptics.tap()
                        placed.removeAll { $0 == index }
                    }
                }
            }
            .frame(minHeight: 56, alignment: .topLeading)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .bottom) {
                VStack(spacing: 44) {
                    Rectangle().fill(Zen.line).frame(height: 1)
                    Rectangle().fill(Zen.line).frame(height: 1)
                }
                .padding(.bottom, 8)
            }

            FlowLayout(spacing: 8) {
                ForEach(exercise.tiles.indices, id: \.self) { index in
                    Tile(text: exercise.tiles[index], style: placed.contains(index) ? .ghost : .loose) {
                        guard !locked, !placed.contains(index) else { return }
                        Haptics.tap()
                        placed.append(index)
                    }
                }
            }

            if !locked {
                CheckButton(enabled: !placed.isEmpty) {
                    let built = placed.map { exercise.tiles[$0] }.joined(separator: " ")
                    onCheck(Outcome(correct: built == exercise.solution))
                }
            }
        }
    }
}

struct Tile: View {
    enum Style { case loose, placed, ghost }
    let text: String
    let style: Style
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(ExerciseEngine.containsCJK(text) ? .kanji(20, bold: true) : .system(size: 17, weight: .medium))
                .foregroundStyle(style == .ghost ? .clear : Zen.ink)
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(style == .ghost ? Zen.line.opacity(0.6) : Zen.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(style == .ghost ? .clear : Zen.line, lineWidth: 1)
                )
                .shadow(color: style == .ghost ? .clear : Zen.ink.opacity(0.08), radius: 0, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(style == .ghost)
    }
}

/// Left-to-right wrapping layout for tiles.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                y += row + spacing
                x = 0
                row = 0
            }
            x += size.width + spacing
            row = max(row, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += row + spacing
                x = bounds.minX
                row = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}

// MARK: - Pairs

struct PairsExercise: View {
    let exercise: Exercise
    let locked: Bool
    let onCheck: (Outcome) -> Void

    @State private var left: [Card] = []
    @State private var right: [Card] = []
    @State private var pickedLeft: String?
    @State private var pickedRight: String?
    @State private var matched: Set<String> = []
    @State private var missed: Set<String> = []
    @State private var flash: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tippe links und rechts, was zusammengehört.")
                .font(.system(size: 15))
                .foregroundStyle(Zen.inkSoft)
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 10) {
                    ForEach(left) { card in
                        pairButton(card.prompt, id: card.id, side: .left)
                    }
                }
                VStack(spacing: 10) {
                    ForEach(right) { card in
                        pairButton(card.answer, id: card.id, side: .right)
                    }
                }
            }
        }
        .onAppear {
            if left.isEmpty {
                left = exercise.pairCards
                right = exercise.pairCards.shuffled()
            }
        }
    }

    private enum Side { case left, right }

    private func pairButton(_ text: String, id: String, side: Side) -> some View {
        let done = matched.contains(id)
        let picked = side == .left ? pickedLeft == id : pickedRight == id
        let wrongFlash = flash == "\(side)-\(id)"
        return Button {
            guard !locked, !done else { return }
            Haptics.tap()
            if side == .left { pickedLeft = id } else { pickedRight = id }
            resolve()
        } label: {
            Text(text)
                .font(ExerciseEngine.containsCJK(text) ? .kanji(22, bold: true) : .system(size: 16, weight: .medium))
                .foregroundStyle(done ? Zen.matcha.opacity(0.6) : Zen.ink)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 54)
                .padding(.horizontal, 8)
                .background(done ? Zen.matcha.opacity(0.1) : (picked ? Zen.ink.opacity(0.07) : Zen.card), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(wrongFlash ? Zen.shu : (picked ? Zen.ink : Zen.line), lineWidth: picked || wrongFlash ? 2 : 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(done)
        .animation(.easeOut(duration: 0.2), value: done)
    }

    private func resolve() {
        guard let l = pickedLeft, let r = pickedRight else { return }
        pickedLeft = nil
        pickedRight = nil
        if l == r {
            matched.insert(l)
            if matched.count == exercise.pairCards.count {
                Haptics.success()
                var perCard: [String: Bool] = [:]
                for card in exercise.pairCards { perCard[card.id] = !missed.contains(card.id) }
                onCheck(Outcome(correct: missed.count <= 1, perCard: perCard))
            }
        } else {
            Haptics.warning()
            missed.insert(l)
            flash = "right-\(r)"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { flash = nil }
        }
    }
}

// MARK: - Flash card

struct FlashExercise: View {
    let exercise: Exercise
    let locked: Bool
    let onCheck: (Outcome) -> Void
    @State private var revealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PromptText(text: exercise.prompt)
            if revealed {
                Text(exercise.solution)
                    .font(.mincho(24, weight: .medium))
                    .foregroundStyle(Zen.ai)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                if !locked {
                    HStack(spacing: 12) {
                        Button("Wusste ich nicht") { onCheck(Outcome(correct: false)) }
                            .buttonStyle(.quiet)
                        Button("Gewusst") { onCheck(Outcome(correct: true)) }
                            .buttonStyle(.matcha)
                    }
                }
            } else {
                Button("Aufdecken") {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { revealed = true }
                }
                .buttonStyle(.ink)
            }
        }
    }
}
