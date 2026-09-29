import SwiftUI

/// Runs a QuizSession: progress on top, the exercise in the middle, and the
/// verdict sliding up from the bottom with the note that explains it.
struct QuizView: View {
    @Bindable var session: QuizSession
    var onFinished: () -> Void

    @State private var outcome: Outcome?

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, Zen.gutter)
                .padding(.top, 8)

            if let exercise = session.current {
                ScrollView {
                    ExerciseView(exercise: exercise, locked: outcome != nil) { result in
                        outcome = result
                        session.grade(exercise, correct: result.correct, perCard: result.perCard)
                        if result.correct { Haptics.success() } else { Haptics.warning() }
                    }
                    .id(exercise.id)
                    .padding(.horizontal, Zen.gutter)
                    .padding(.top, 24)
                    .padding(.bottom, 180)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .overlay(alignment: .bottom) {
            if let outcome, let exercise = session.current {
                FeedbackBanner(outcome: outcome, exercise: exercise) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                        self.outcome = nil
                        session.advance()
                    }
                    if session.finished { onFinished() }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.9), value: outcome != nil)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            InkProgress(value: session.progress, color: Zen.shu, height: 8)
            if case .gate = session.mode {
                Text("\(session.correct) von \(session.needed) richtig")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Zen.inkSoft)
                    .contentTransition(.numericText())
            }
        }
    }
}

struct FeedbackBanner: View {
    let outcome: Outcome
    let exercise: Exercise
    let next: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Hanko(text: outcome.correct ? "良" : "惜", size: 34, color: tint)
                Text(title)
                    .font(.mincho(22, weight: .semibold))
                    .foregroundStyle(tint)
            }
            if !outcome.correct || outcome.typo {
                if exercise.kind == .pairs {
                    Text("Schau dir die Paare nochmal an, sie kommen bald wieder.")
                        .font(.system(size: 16))
                        .foregroundStyle(Zen.ink)
                } else {
                    Text("Richtig: \(Text(exercise.card.answer).bold().foregroundStyle(Zen.ink))")
                        .font(.system(size: 17))
                        .foregroundStyle(Zen.inkSoft)
                }
            }
            if let note = exercise.card.note, !note.isEmpty, exercise.kind != .pairs {
                Text(note)
                    .font(.system(size: 15))
                    .foregroundStyle(Zen.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Weiter", action: next)
                .buttonStyle(outcome.correct ? InkButtonStyle(kind: .matcha) : InkButtonStyle(kind: .shu))
                .padding(.top, 4)
        }
        .padding(Zen.gutter)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                .fill(Zen.card)
                .shadow(color: Zen.ink.opacity(0.12), radius: 20, y: -4)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var tint: Color { outcome.correct ? Zen.matcha : Zen.shu }

    private var title: String {
        if outcome.typo { return "Fast, kleiner Tippfehler" }
        if outcome.correct {
            let words = ["Richtig", "Genau so", "Sehr gut", "Stimmt"]
            return words[abs(exercise.id.hashValue % words.count)]
        }
        return "Noch nicht"
    }
}
