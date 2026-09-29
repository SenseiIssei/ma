import FamilyControls
import SwiftUI

/// The pause between impulse and app: breathe, answer, then decide.
///
/// Deciding is the point. After the questions, "let it be" is offered as
/// prominently as "open", and choosing it is celebrated, not punished.
struct GateView: View {
    @Environment(AppModel.self) private var model
    let reason: GateReason

    private enum Stage { case breathe, quiz, decide, open, blocked }

    @State private var stage: Stage = .breathe
    @State private var session: QuizSession?
    @State private var inhale = false
    @State private var breaths = 0
    @State private var minutes = 5
    @State private var openUntil: Date?

    private var pending: PendingUnlock? {
        if case .unlock(let pending) = reason { return pending }
        return nil
    }

    private var policy: UnlockPolicy {
        pending.map { model.policy(for: $0) } ?? UnlockPolicy()
    }

    private var needed: Int {
        switch reason {
        case .unlock: return policy.questions
        case .disableRule, .stopFocus, .practice: return 3
        }
    }

    var body: some View {
        ZStack {
            WashiBackground()
            VStack(spacing: 0) {
                HStack {
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Zen.inkSoft)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Schließen")
                    Spacer()
                }
                .padding(.horizontal, 8)

                switch stage {
                case .breathe: breathe
                case .quiz: quiz
                case .decide: decide
                case .open: opened
                case .blocked: blocked
                }
            }
        }
        .onAppear {
            minutes = policy.minutes
            if pending != nil && !policy.allowed { stage = .blocked }
        }
    }

    // MARK: Stages

    private var subject: some View {
        Group {
            if let token = pending?.application {
                Label(token)
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 17, weight: .semibold))
            } else if let web = pending?.webDomain {
                Label(web)
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 17, weight: .semibold))
            } else {
                Text(subjectText)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Zen.ink)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(Zen.card, in: Capsule())
        .overlay(Capsule().strokeBorder(Zen.line))
    }

    private var subjectText: String {
        switch reason {
        case .unlock(let pending): return pending.displayName ?? "Eine Kategorie"
        case .disableRule(let id): return "Grenze \(model.rules.first { $0.id == id }?.name ?? "") ausschalten"
        case .stopFocus: return "Fokusrunde abbrechen"
        case .practice: return "Übung"
        }
    }

    private var breathe: some View {
        VStack(spacing: 28) {
            Spacer()
            subject
            BreathingEnso(inhale: inhale)
                .frame(width: 230, height: 230)
                .overlay(
                    Text(breaths % 2 == 0 ? "吸" : "吐")
                        .font(.kanji(44, bold: true))
                        .foregroundStyle(Zen.shu)
                        .contentTransition(.opacity)
                )
            Text(breaths % 2 == 0 ? "Atme ein" : "Atme aus")
                .font(.mincho(26, weight: .medium))
                .foregroundStyle(Zen.ink)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.6), value: breaths)
            Text("Einen Atemzug lang nichts wollen.")
                .font(.system(size: 15))
                .foregroundStyle(Zen.inkSoft)
            Spacer()
            VStack(spacing: 12) {
                Button(needed == 1 ? "Zur Frage" : "Zu den \(needed) Fragen") {
                    startQuiz()
                }
                .buttonStyle(.ink)
                .opacity(breaths >= 2 ? 1 : 0.3)
                .disabled(breaths < 2)
                if pending != nil {
                    Button("Ich lass es gut sein") { resist() }
                        .buttonStyle(.quiet)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 20)
        }
        .task {
            withAnimation(.easeInOut(duration: 4)) { inhale = true }
            while !Task.isCancelled && stage == .breathe {
                try? await Task.sleep(for: .seconds(4))
                breaths += 1
                withAnimation(.easeInOut(duration: 4)) { inhale.toggle() }
            }
        }
    }

    private var quiz: some View {
        Group {
            if let session {
                QuizView(session: session) {
                    finishQuiz()
                }
            }
        }
    }

    private var decide: some View {
        VStack(spacing: 24) {
            Spacer()
            Hanko(text: "決", size: 64)
            Text("Du hast es dir verdient.\nWillst du es noch?")
                .font(.mincho(28, weight: .semibold))
                .foregroundStyle(Zen.ink)
                .multilineTextAlignment(.center)
            subject
            if let session, !session.exercises.isEmpty {
                Text("\(session.correct) richtig, \(session.wrong) daneben")
                    .font(.system(size: 14))
                    .foregroundStyle(Zen.inkSoft)
            }
            HStack(spacing: 8) {
                ForEach(minuteOptions, id: \.self) { value in
                    Chip(title: "\(value) Min.", selected: minutes == value) { minutes = value }
                }
            }
            Spacer()
            VStack(spacing: 12) {
                Button("Für \(minutes) Minuten öffnen") { unlock() }
                    .buttonStyle(.shu)
                Button("Ich lass es doch") { resist() }
                    .buttonStyle(.matcha)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 20)
        }
        .padding(.horizontal, Zen.gutter)
    }

    private var minuteOptions: [Int] {
        let base = policy.minutes
        return Array(Set([max(1, base / 2), base].filter { $0 > 0 })).sorted()
    }

    private var opened: some View {
        VStack(spacing: 22) {
            Spacer()
            EnsoView(progress: 1, lineWidth: 14, color: Zen.matcha)
                .frame(width: 160, height: 160)
                .overlay(Text("開").font(.kanji(48, bold: true)).foregroundStyle(Zen.ink))
            Text("Offen bis \(openUntil?.formatted(date: .omitted, time: .shortened) ?? "")")
                .font(.mincho(26, weight: .semibold))
                .foregroundStyle(Zen.ink)
            Text("Danach schließt sich die Grenze von selbst wieder. Wechsle jetzt einfach zur App.")
                .font(.system(size: 15))
                .foregroundStyle(Zen.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            Spacer()
            VStack(spacing: 12) {
                if let name = pending?.displayName {
                    Button("Zu \(name)") {
                        model.open(appNamed: name)
                        close()
                    }
                    .buttonStyle(.ink)
                }
                Button("Schließen", action: close)
                    .buttonStyle(.quiet)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 20)
        }
    }

    private var blocked: some View {
        VStack(spacing: 22) {
            Spacer()
            Hanko(text: "結", size: 72)
            Text(policy.focusLocked ? "Fokus läuft" : "Kein Ausweg")
                .font(.mincho(30, weight: .semibold))
                .foregroundStyle(Zen.ink)
            Text(policy.focusLocked
                 ? "Während einer Fokusrunde öffnet Ma nichts. Die Runde endet von selbst, und dann ist alles wieder da."
                 : "Diese Grenze hast du ohne Ausweg gesetzt. Wenn du das ändern willst, geht das unter Grenzen.")
                .font(.system(size: 16))
                .foregroundStyle(Zen.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            Spacer()
            Button("Zurück zur Ruhe") { resist() }
                .buttonStyle(.ink)
                .padding(.horizontal, 28)
                .padding(.bottom, 20)
        }
    }

    // MARK: Flow

    private func startQuiz() {
        let session = QuizSession(mode: .gate(required: needed), store: model.decks)
        self.session = session
        withAnimation(.easeInOut) {
            stage = session.finished ? .decide : .quiz
        }
        if session.finished { finishQuiz() }
    }

    private func finishQuiz() {
        model.reload()
        switch reason {
        case .unlock:
            withAnimation(.easeInOut) { stage = .decide }
        case .disableRule, .stopFocus, .practice:
            Haptics.success()
            model.gatePassed(reason)
            model.gate = nil
        }
    }

    private func unlock() {
        guard let pending else { return }
        Haptics.success()
        model.grant(pending, minutes: minutes)
        openUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
        withAnimation(.easeInOut) { stage = .open }
    }

    private func resist() {
        Haptics.success()
        if let pending {
            model.resist(pending)
        }
        model.gate = nil
    }

    private func close() {
        if pending != nil && stage != .open {
            model.dismissPending()
        }
        model.gate = nil
    }
}
