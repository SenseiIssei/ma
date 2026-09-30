import SwiftUI

/// Runs a QuizSession: progress on top, the exercise in the middle, and the
/// verdict sliding up from the bottom with the note that explains it.
/// Teaching cards skip the verdict and move straight on.
struct QuizView: View {
    @Bindable var session: QuizSession
    var onFinished: () -> Void

    @State private var outcome: Outcome?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Slides in from the side, or just fades with Reduce Motion.
    private var exerciseTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .opacity
        )
    }

    private var bannerTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, Zen.gutter)
                .padding(.top, 8)

            if let exercise = session.current {
                ScrollView {
                    ExerciseView(exercise: exercise, locked: outcome != nil) { result in
                        handle(result, for: exercise)
                    }
                    .id(exercise.id)
                    .padding(.horizontal, Zen.gutter)
                    .padding(.top, 24)
                    .padding(.bottom, 200)
                    .transition(exerciseTransition)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .overlay(alignment: .bottom) {
            if let outcome, let exercise = session.current {
                FeedbackBanner(outcome: outcome, exercise: exercise) {
                    next()
                }
                .transition(bannerTransition)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.9), value: outcome != nil)
    }

    private func handle(_ result: Outcome, for exercise: Exercise) {
        if exercise.kind == .teach {
            // Nothing to judge: mark it introduced and go on.
            session.grade(exercise, correct: true)
            next()
            return
        }
        outcome = result
        session.grade(exercise, correct: result.correct, perCard: result.perCard)
        if result.correct { Haptics.success() } else { Haptics.warning() }
        announce(result, for: exercise)
    }

    /// The banner appears without moving VoiceOver focus, so say the verdict.
    private func announce(_ result: Outcome, for exercise: Exercise) {
        let text: String
        if result.typo {
            text = tr("Almost, small typo. Correct: \(exercise.card.answer)", "Fast, kleiner Tippfehler. Richtig: \(exercise.card.answer)")
        } else if result.correct {
            text = tr("Correct", "Richtig")
        } else if exercise.kind == .pairs {
            text = tr("Not quite", "Nicht ganz")
        } else {
            text = tr("Not quite. Correct: \(exercise.card.answer)", "Nicht ganz. Richtig: \(exercise.card.answer)")
        }
        AccessibilityNotification.Announcement(text).post()
    }

    private func next() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
            outcome = nil
            session.advance()
        }
        if session.finished { onFinished() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            InkProgress(value: session.progress, color: Zen.matcha, height: 10)
                .accessibilityMeter(tr("Progress", "Fortschritt"), value: session.progress.formatted(.percent.precision(.fractionLength(0))))
            if case .gate = session.mode {
                if session.current?.kind == .teach {
                    Label(tr("Learn this card first, the question comes next.", "Lern zuerst diese Karte, dann kommt die Frage."), systemImage: "lightbulb")
                        .scaledFont(size: 13, weight: .medium)
                        .foregroundStyle(Zen.inkSoft)
                } else {
                    Text(tr("\(session.correct) of \(session.needed) right", "\(session.correct) von \(session.needed) richtig"))
                        .scaledFont(size: 13, weight: .medium)
                        .foregroundStyle(Zen.inkSoft)
                        .contentTransition(.numericText())
                }
            }
        }
    }
}

/// Green or red sheet after an answer: the verdict, the right answer if it
/// was missed, the explanation, and one big button to go on.
struct FeedbackBanner: View {
    let outcome: Outcome
    let exercise: Exercise
    let next: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: outcome.correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .scaledFont(size: 30, weight: .semibold)
                    .foregroundStyle(tint)
                    .symbolEffect(.bounce, value: outcome.correct)
                    .symbolEffectsRemoved(reduceMotion)
                    .accessibilityHidden(true)
                Text(title)
                    .displayFont(24)
                    .foregroundStyle(tint)
                Spacer(minLength: 0)
            }
            if !outcome.correct || outcome.typo {
                if exercise.kind == .pairs {
                    Text(tr("Have another look at the pairs, they will come back soon.", "Schau dir die Paare nochmal an, sie kommen bald wieder."))
                        .scaledFont(size: 16, weight: .medium)
                        .foregroundStyle(Zen.ink)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("Correct:", "Richtig:"))
                            .scaledFont(size: 14, weight: .semibold)
                            .foregroundStyle(tint)
                        Text(exercise.card.answer)
                            .cardFont(for: exercise.card.answer, kanji: 22, bold: true, size: 18, weight: .bold, design: .rounded)
                            .foregroundStyle(Zen.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let note = exercise.card.note, !note.isEmpty, exercise.kind != .pairs {
                Text(note)
                    .scaledFont(size: 15)
                    .foregroundStyle(Zen.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // After a miss is when an extra explanation helps most. Pairs touch
            // several cards at once, so there is no single card to explain.
            if showsExplainMore {
                ExplainMorePanel(deck: exercise.deck, card: exercise.card, afterMistake: true, maxTextHeight: 200)
            }
            Button(tr("Continue", "Weiter"), action: next)
                .buttonStyle(outcome.correct ? InkButtonStyle(kind: .matcha) : InkButtonStyle(kind: .negative))
                .padding(.top, 4)
        }
        .padding(Zen.gutter)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                    .fill(Zen.card)
                UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                    .fill(tint.opacity(0.14))
            }
            .shadow(color: Color.black.opacity(0.10), radius: 20, y: -4)
            .ignoresSafeArea(edges: .bottom)
        )
    }

    private var tint: Color { outcome.correct ? Zen.matcha : Zen.negative }

    private var showsExplainMore: Bool {
        !outcome.correct && exercise.kind != .pairs && MaAI.offersInline
    }

    private var title: String {
        if outcome.typo { return tr("Almost, small typo", "Fast, kleiner Tippfehler") }
        if outcome.correct {
            let words = Loc.isGerman ? ["Richtig!", "Genau so!", "Sehr gut!", "Stimmt!"] : ["Correct!", "Exactly!", "Well done!", "Right!"]
            return words[abs(exercise.id.hashValue % words.count)]
        }
        return tr("Not quite", "Nicht ganz")
    }
}
